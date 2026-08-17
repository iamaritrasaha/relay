use std::{
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};

use anyhow::{Context as _, Result, bail};
use iroh::endpoint::{RecvStream, SendStream};
use localsend::crypto::{
    relay_identity::RelayIdentity,
    relay_identity_proof::{
        PROOF_LEN, RelayIdentityProofV1, RelayProofRole, create_relay_identity_proof,
        verify_relay_identity_proof,
    },
};
use rand::RngCore;
use rcgen::{CertificateParams, KeyPair};
use rustls::{
    ClientConfig, DigitallySignedStruct, DistinguishedName, Error, RootCertStore, ServerConfig,
    SignatureScheme,
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::WebPkiSupportedAlgorithms,
    pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime},
    server::danger::{ClientCertVerified, ClientCertVerifier},
};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio_rustls::{TlsAcceptor, TlsConnector};

const NONCE_LEN: usize = 32;
#[cfg(test)]
pub const RELAY_PROOF_BYTES: usize = PROOF_LEN;
const AUTH_OK: u8 = 0xa1;

pub struct IrohBiStream {
    send: SendStream,
    recv: RecvStream,
}

impl IrohBiStream {
    pub fn new(send: SendStream, recv: RecvStream) -> Self {
        Self { send, recv }
    }

    pub fn reset_send(&mut self) -> Result<()> {
        self.send
            .reset(0_u8.into())
            .context("reset Iroh QUIC send stream")
    }
}

impl AsyncRead for IrohBiStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.recv).poll_read(cx, buf)
    }
}

impl AsyncWrite for IrohBiStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.send)
            .poll_write(cx, buf)
            .map(|result| result.map_err(std::io::Error::other))
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.send).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.send).poll_shutdown(cx)
    }
}

pub struct RelayPeer {
    pub identity: Arc<RelayIdentity>,
    pub relay_id: String,
    cert_fingerprint: [u8; 32],
}

impl RelayPeer {
    fn new(identity: RelayIdentity, cert: &CertificateDer<'static>) -> Result<Self> {
        Ok(Self {
            relay_id: identity.relay_id().context("derive RelayId")?,
            identity: Arc::new(identity),
            cert_fingerprint: Sha256::digest(cert.as_ref()).into(),
        })
    }
}

/// A proof-only endpoint identity. Each instance owns an independent self-signed certificate.
/// TLS proves certificate-key possession only; RelayIdentityProofV1 authorizes the peer identity.
#[derive(Clone)]
pub struct InnerTlsPeer {
    connector: TlsConnector,
    acceptor: TlsAcceptor,
    pub relay: Arc<RelayPeer>,
}

impl InnerTlsPeer {
    pub fn new(dns_name: &str) -> Result<Self> {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let key = KeyPair::generate().context("generate independent inner TLS key")?;
        let params = CertificateParams::new(vec![dns_name.to_owned()])
            .context("create independent inner TLS certificate parameters")?;
        let certificate = params
            .self_signed(&key)
            .context("self-sign independent inner TLS certificate")?;
        let cert_der = CertificateDer::from(certificate.der().to_vec());
        let key_der = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key.serialize_der()));

        let algorithms = rustls::crypto::ring::default_provider().signature_verification_algorithms;
        let (server_signature_verifier, client_signature_verifier) =
            signature_verifiers(&cert_der)?;
        let client_config = ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PermissiveServerVerifier {
                algorithms,
                signature_verifier: server_signature_verifier,
            }))
            .with_client_auth_cert(vec![cert_der.clone()], key_der.clone_key())
            .context("configure independent inner TLS client")?;
        let server_config = ServerConfig::builder()
            .with_client_cert_verifier(Arc::new(PermissiveClientVerifier {
                algorithms,
                signature_verifier: client_signature_verifier,
            }))
            .with_single_cert(vec![cert_der.clone()], key_der)
            .context("configure independent inner TLS server")?;

        Ok(Self {
            connector: TlsConnector::from(Arc::new(client_config)),
            acceptor: TlsAcceptor::from(Arc::new(server_config)),
            relay: Arc::new(RelayPeer::new(RelayIdentity::generate(), &cert_der)?),
        })
    }

    pub async fn connect(
        &self,
        stream: IrohBiStream,
    ) -> Result<tokio_rustls::client::TlsStream<IrohBiStream>> {
        let name = ServerName::try_from("relay-anywhere-ra2a.invalid")
            .context("parse proof TLS server name")?;
        self.connector
            .connect(name, stream)
            .await
            .context("inner TLS client handshake")
    }

    pub async fn accept(
        &self,
        stream: IrohBiStream,
    ) -> Result<tokio_rustls::server::TlsStream<IrohBiStream>> {
        self.acceptor
            .accept(stream)
            .await
            .context("inner TLS server handshake")
    }
}

/// Deliberately omits chain and hostname trust in this isolated harness while preserving
/// CertificateVerify signature checks. The observed leaf is bound by RelayIdentityProofV1.
#[derive(Debug)]
struct PermissiveServerVerifier {
    algorithms: WebPkiSupportedAlgorithms,
    signature_verifier: Arc<dyn ServerCertVerifier>,
}

impl ServerCertVerifier for PermissiveServerVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, Error> {
        self.signature_verifier
            .verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, Error> {
        self.signature_verifier
            .verify_tls13_signature(message, cert, dss)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

#[derive(Debug)]
struct PermissiveClientVerifier {
    algorithms: WebPkiSupportedAlgorithms,
    signature_verifier: Arc<dyn ClientCertVerifier>,
}

impl ClientCertVerifier for PermissiveClientVerifier {
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }

    fn verify_client_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _now: UnixTime,
    ) -> std::result::Result<ClientCertVerified, Error> {
        Ok(ClientCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, Error> {
        self.signature_verifier
            .verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, Error> {
        self.signature_verifier
            .verify_tls13_signature(message, cert, dss)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

fn signature_verifiers(
    local_cert: &CertificateDer<'static>,
) -> Result<(Arc<dyn ServerCertVerifier>, Arc<dyn ClientCertVerifier>)> {
    let mut roots = RootCertStore::empty();
    roots
        .add(local_cert.clone())
        .context("create local-only proof TLS root")?;
    let server = rustls::client::WebPkiServerVerifier::builder(Arc::new(roots.clone()))
        .build()
        .context("build proof TLS server signature verifier")?;
    let client = rustls::server::WebPkiClientVerifier::builder(Arc::new(roots))
        .build()
        .context("build proof TLS client signature verifier")?;
    Ok((server, client))
}

pub fn client_peer_certificate_fingerprint(
    stream: &tokio_rustls::client::TlsStream<IrohBiStream>,
) -> Result<[u8; 32]> {
    peer_certificate_fingerprint(stream.get_ref().1.peer_certificates())
}

pub fn server_peer_certificate_fingerprint(
    stream: &tokio_rustls::server::TlsStream<IrohBiStream>,
) -> Result<[u8; 32]> {
    peer_certificate_fingerprint(stream.get_ref().1.peer_certificates())
}

fn peer_certificate_fingerprint(certificates: Option<&[CertificateDer<'_>]>) -> Result<[u8; 32]> {
    let leaf = certificates
        .and_then(|certs| certs.first())
        .context("inner TLS peer did not present a certificate")?;
    Ok(Sha256::digest(leaf.as_ref()).into())
}

pub async fn authenticate_client<S>(
    stream: &mut S,
    own: &RelayPeer,
    expected_server_relay_id: &str,
    observed_server_cert_fingerprint: [u8; 32],
) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut server_nonce = [0_u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut server_nonce);
    stream
        .write_all(&server_nonce)
        .await
        .context("send server challenge")?;
    stream.flush().await.context("flush server challenge")?;

    let mut server_proof_bytes = [0_u8; PROOF_LEN];
    stream
        .read_exact(&mut server_proof_bytes)
        .await
        .context("read server Relay proof")?;
    let server_proof =
        RelayIdentityProofV1::decode(&server_proof_bytes).context("decode server Relay proof")?;
    if server_proof.nonce != server_nonce {
        bail!("server Relay proof challenge mismatch");
    }
    let verified_server = verify_relay_identity_proof(
        &server_proof,
        RelayProofRole::Server,
        observed_server_cert_fingerprint,
    )
    .context("verify server Relay proof")?;
    if verified_server != expected_server_relay_id {
        bail!("authoritative RelayId mismatch");
    }

    let mut client_nonce = [0_u8; NONCE_LEN];
    stream
        .read_exact(&mut client_nonce)
        .await
        .context("read client challenge")?;
    let client_proof = create_relay_identity_proof(
        &own.identity,
        RelayProofRole::Client,
        client_nonce,
        own.cert_fingerprint,
    )
    .context("create client Relay proof")?;
    stream
        .write_all(&client_proof.encode())
        .await
        .context("send client Relay proof")?;
    stream.flush().await.context("flush client Relay proof")?;
    if stream
        .read_u8()
        .await
        .context("read authentication result")?
        != AUTH_OK
    {
        bail!("server rejected Relay authentication");
    }
    Ok(())
}

pub async fn authenticate_server<S>(
    stream: &mut S,
    own: &RelayPeer,
    expected_client_relay_id: &str,
    observed_client_cert_fingerprint: [u8; 32],
) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    authenticate_server_with_encoded_proof(
        stream,
        own,
        expected_client_relay_id,
        observed_client_cert_fingerprint,
        None,
    )
    .await
}

async fn authenticate_server_with_encoded_proof<S>(
    stream: &mut S,
    own: &RelayPeer,
    expected_client_relay_id: &str,
    observed_client_cert_fingerprint: [u8; 32],
    #[cfg(test)] behavior: Option<TestServerProofBehavior>,
    #[cfg(not(test))] _behavior: Option<()>,
) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut server_nonce = [0_u8; NONCE_LEN];
    stream
        .read_exact(&mut server_nonce)
        .await
        .context("read server challenge")?;
    #[cfg(test)]
    let binding = if matches!(
        behavior,
        Some(TestServerProofBehavior::WrongCertificateBinding)
    ) {
        [0x5a; 32]
    } else {
        own.cert_fingerprint
    };
    #[cfg(not(test))]
    let binding = own.cert_fingerprint;
    let proof =
        create_relay_identity_proof(&own.identity, RelayProofRole::Server, server_nonce, binding)
            .context("create server Relay proof")?;
    let encoded = proof.encode();
    #[cfg(test)]
    let mut encoded = encoded;
    #[cfg(test)]
    if let Some(behavior) = behavior {
        match behavior {
            TestServerProofBehavior::CorruptSignature => encoded[PROOF_LEN - 1] ^= 1,
            TestServerProofBehavior::WrongCertificateBinding => {}
            TestServerProofBehavior::Capture(capture) => {
                *capture.lock().expect("capture lock") = Some(encoded)
            }
            TestServerProofBehavior::Replay(replay) => encoded = replay,
        }
    }
    stream
        .write_all(&encoded)
        .await
        .context("send server Relay proof")?;

    let mut client_nonce = [0_u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut client_nonce);
    stream
        .write_all(&client_nonce)
        .await
        .context("send client challenge")?;
    stream
        .flush()
        .await
        .context("flush authentication challenges")?;
    let mut client_proof_bytes = [0_u8; PROOF_LEN];
    stream
        .read_exact(&mut client_proof_bytes)
        .await
        .context("read client Relay proof")?;
    let client_proof =
        RelayIdentityProofV1::decode(&client_proof_bytes).context("decode client Relay proof")?;
    if client_proof.nonce != client_nonce {
        bail!("client Relay proof challenge mismatch");
    }
    let verified_client = verify_relay_identity_proof(
        &client_proof,
        RelayProofRole::Client,
        observed_client_cert_fingerprint,
    )
    .context("verify client Relay proof")?;
    if verified_client != expected_client_relay_id {
        bail!("authoritative client RelayId mismatch");
    }
    stream
        .write_u8(AUTH_OK)
        .await
        .context("send authentication success")?;
    stream
        .flush()
        .await
        .context("flush authentication success")?;
    Ok(())
}

#[cfg(test)]
#[derive(Clone, Debug)]
pub enum TestServerProofBehavior {
    CorruptSignature,
    WrongCertificateBinding,
    Capture(Arc<std::sync::Mutex<Option<[u8; PROOF_LEN]>>>),
    Replay([u8; PROOF_LEN]),
}

#[cfg(test)]
pub async fn authenticate_server_for_test<S>(
    stream: &mut S,
    own: &RelayPeer,
    expected_client_relay_id: &str,
    observed_client_cert_fingerprint: [u8; 32],
    behavior: TestServerProofBehavior,
) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    authenticate_server_with_encoded_proof(
        stream,
        own,
        expected_client_relay_id,
        observed_client_cert_fingerprint,
        Some(behavior),
    )
    .await
}
