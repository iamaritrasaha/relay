use std::borrow::Cow;

use reqwest::StatusCode;

use crate::crypto::cert::fingerprint_digest_from_cert_der;
use crate::crypto::nonce::generate_nonce_32;
use crate::crypto::relay_identity::RelayIdentity;
use crate::crypto::relay_identity_proof::{
    create_relay_identity_proof, verify_relay_identity_proof, RelayProofRole,
};
use crate::http::client::{cert_fingerprint_digest_from_res, scoped_host};
use crate::http::dto_relay::{
    RelayChallengeV1Dto, RelayPairChallengeRequestV1Dto, RelayPairChallengeResponseV1Dto,
    RelayPairCompleteRequestV1Dto, RelayPairCompleteResponseV1Dto, RelayProofV1Dto,
};
use crate::model::discovery::ProtocolType;
use crate::relay::{verification_code, RelayId, RelayLanPairingOutcome, RelayPeerAuth};

/// What the initiator needs in order to pair over the LAN.
///
/// The Relay identity is local key material. The certificate PEM is this
/// device's own mTLS client certificate, so the Client-role proof is bound to
/// the certificate the peer will actually observe.
pub struct RelayLanPairingRequest<'a> {
    pub identity: &'a RelayIdentity,
    pub client_certificate_pem: &'a str,
    pub alias: &'a str,
    /// The identity the user targeted, when there is one. A mismatch is a hard
    /// failure; it is never downgraded to "pair with whoever answered".
    pub expected_relay_id: Option<&'a RelayId>,
}

/// Progress of a LAN pairing attempt.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RelayLanPairingEvent {
    /// Both identities are proven and both nonces are known, so the code can be
    /// shown while the remote user decides. Emitted before the request that
    /// asks them, never after.
    VerificationCode {
        code: String,
        remote_relay_id: String,
    },
    /// Terminal result.
    Outcome(RelayLanPairingOutcome),
}

pub(super) async fn authenticate_relay_server(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
) -> RelayPeerAuth {
    authenticate_relay_server_with_nonce(client, protocol, ip, port)
        .await
        .0
}

/// Runs the Server-role proof and also reports the nonce it used, which the
/// pairing transcript needs.
async fn authenticate_relay_server_with_nonce(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
) -> (RelayPeerAuth, [u8; 32]) {
    if protocol != ProtocolType::Https {
        return (RelayPeerAuth::NotAttempted, [0_u8; 32]);
    }

    let nonce = generate_nonce_32();
    (
        authenticate_relay_server_inner(client, protocol, ip, port, nonce).await,
        nonce,
    )
}

async fn authenticate_relay_server_inner(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
    nonce: [u8; 32],
) -> RelayPeerAuth {
    let response = match client
        .post(relay_proof_url(protocol, ip, port))
        .header("Content-Type", "application/json")
        .json(&RelayChallengeV1Dto::new(nonce))
        .send()
        .await
    {
        Ok(response) => response,
        Err(err) => {
            tracing::warn!("Relay proof request failed: {err:#}");
            return RelayPeerAuth::TransportUnauthenticated;
        }
    };

    match relay_status(response.status()) {
        Some(auth) => auth,
        None => authenticate_success_response(response, nonce).await,
    }
}

async fn authenticate_success_response(
    response: reqwest::Response,
    nonce: [u8; 32],
) -> RelayPeerAuth {
    let observed_tls_fingerprint =
        match tls_fingerprint_or_transport(cert_fingerprint_digest_from_res(&response)) {
            Ok(fingerprint) => fingerprint,
            Err(auth) => return auth,
        };

    let body = match response.bytes().await {
        Ok(body) => body,
        Err(_) => return RelayPeerAuth::Malformed,
    };
    let dto = match parse_proof_bytes(&body) {
        Ok(dto) => dto,
        Err(auth) => return auth,
    };
    authenticate_proof(dto, nonce, observed_tls_fingerprint)
}

fn relay_status(status: StatusCode) -> Option<RelayPeerAuth> {
    match status {
        StatusCode::OK => None,
        StatusCode::NOT_FOUND | StatusCode::METHOD_NOT_ALLOWED => Some(RelayPeerAuth::Unsupported),
        StatusCode::SERVICE_UNAVAILABLE => Some(RelayPeerAuth::SignerUnavailable),
        _ => Some(RelayPeerAuth::Malformed),
    }
}

fn tls_fingerprint_or_transport(
    fingerprint: anyhow::Result<[u8; 32]>,
) -> Result<[u8; 32], RelayPeerAuth> {
    fingerprint.map_err(|err| {
        tracing::warn!("Relay proof response has no authenticated TLS certificate: {err:#}");
        RelayPeerAuth::TransportUnauthenticated
    })
}

fn parse_proof_bytes(bytes: &[u8]) -> Result<RelayProofV1Dto, RelayPeerAuth> {
    serde_json::from_slice(bytes).map_err(|_| RelayPeerAuth::Malformed)
}

fn authenticate_proof(
    dto: RelayProofV1Dto,
    nonce: [u8; 32],
    observed_tls_fingerprint: [u8; 32],
) -> RelayPeerAuth {
    let proof = dto.proof();
    if proof.role != RelayProofRole::Server {
        return RelayPeerAuth::RoleMismatch;
    }
    if proof.nonce != nonce {
        return RelayPeerAuth::ChallengeMismatch;
    }
    match verify_relay_identity_proof(proof, RelayProofRole::Server, observed_tls_fingerprint) {
        Ok(relay_id) => match crate::relay::RelayId::from_verified_hex(&relay_id) {
            Ok(proven) => RelayPeerAuth::Authenticated {
                relay_id: proven.as_hex(),
                tls_fingerprint: observed_tls_fingerprint,
            },
            Err(_) => RelayPeerAuth::CryptoInvalid,
        },
        Err(_) => RelayPeerAuth::CryptoInvalid,
    }
}

/// Drives the initiator half of the mutual LAN pairing handshake.
///
/// The order is deliberate and cannot be reordered by the peer:
///
/// 1. prove *their* identity (Server-role proof over the pinned certificate),
/// 2. take a single-use nonce *they* chose,
/// 3. prove *our* identity to it (Client-role proof over our own certificate),
/// 4. and only then ask their user.
///
/// Step 3 is unreachable without step 2, and step 2 is unreachable without a
/// live mTLS connection, so neither side can be paired by a device that merely
/// answered on the right address.
pub(super) async fn pair_with_relay_server(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
    request: RelayLanPairingRequest<'_>,
    events: &tokio::sync::mpsc::Sender<RelayLanPairingEvent>,
) -> RelayLanPairingOutcome {
    let outcome = pair_inner(client, protocol, ip, port, request, events).await;
    let _ = events
        .send(RelayLanPairingEvent::Outcome(outcome.clone()))
        .await;
    outcome
}

async fn pair_inner(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
    request: RelayLanPairingRequest<'_>,
    events: &tokio::sync::mpsc::Sender<RelayLanPairingEvent>,
) -> RelayLanPairingOutcome {
    if protocol != ProtocolType::Https {
        // Pairing has no meaning without the certificate the proofs bind to.
        return RelayLanPairingOutcome::Unsupported;
    }

    let Ok(local_relay_id) = request
        .identity
        .relay_id()
        .and_then(|hex| RelayId::from_expected_canonical_hex(&hex))
    else {
        return RelayLanPairingOutcome::AuthenticationFailed;
    };
    let Some(own_cert_fingerprint) = client_certificate_fingerprint(request.client_certificate_pem)
    else {
        return RelayLanPairingOutcome::AuthenticationFailed;
    };

    let (auth, client_nonce) =
        authenticate_relay_server_with_nonce(client, protocol, ip, port).await;
    let remote_relay_id = match auth {
        RelayPeerAuth::Authenticated { relay_id, .. } => {
            match RelayId::from_expected_canonical_hex(&relay_id) {
                Ok(proven) => proven,
                Err(_) => return RelayLanPairingOutcome::AuthenticationFailed,
            }
        }
        RelayPeerAuth::Unsupported | RelayPeerAuth::SignerUnavailable => {
            return RelayLanPairingOutcome::Unsupported
        }
        RelayPeerAuth::NotAttempted | RelayPeerAuth::TransportUnauthenticated => {
            return RelayLanPairingOutcome::TransportFailed
        }
        RelayPeerAuth::Malformed
        | RelayPeerAuth::RoleMismatch
        | RelayPeerAuth::ChallengeMismatch
        | RelayPeerAuth::CryptoInvalid => return RelayLanPairingOutcome::AuthenticationFailed,
    };
    if let Some(expected) = request.expected_relay_id {
        if expected != &remote_relay_id {
            return RelayLanPairingOutcome::AuthenticationFailed;
        }
    }

    let server_nonce = match pair_challenge(client, protocol, ip, port, client_nonce).await {
        Ok(nonce) => nonce,
        Err(outcome) => return outcome,
    };

    let proof = match create_relay_identity_proof(
        request.identity,
        RelayProofRole::Client,
        server_nonce,
        own_cert_fingerprint,
    ) {
        Ok(proof) => proof,
        Err(_) => return RelayLanPairingOutcome::AuthenticationFailed,
    };

    let code = verification_code(
        &server_nonce,
        &client_nonce,
        &local_relay_id,
        &remote_relay_id,
    );
    // Shown while the remote user is still deciding, so both people compare the
    // same number before anybody accepts.
    let _ = events
        .send(RelayLanPairingEvent::VerificationCode {
            code: code.clone(),
            remote_relay_id: remote_relay_id.as_hex(),
        })
        .await;

    match pair_complete(client, protocol, ip, port, proof, request.alias).await {
        Ok(response) if response.is_accepted() => RelayLanPairingOutcome::Paired {
            remote_relay_id: remote_relay_id.as_hex(),
            remote_alias: crate::relay::sanitize_pairing_alias(&response.alias),
            verification_code: code,
        },
        Ok(_) => RelayLanPairingOutcome::Declined,
        Err(outcome) => outcome,
    }
}

async fn pair_challenge(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
    client_nonce: [u8; 32],
) -> Result<[u8; 32], RelayLanPairingOutcome> {
    let response = client
        .post(relay_pair_url(protocol, ip, port, "challenge"))
        .header("Content-Type", "application/json")
        .json(&RelayPairChallengeRequestV1Dto::new(client_nonce))
        .send()
        .await
        .map_err(|err| {
            tracing::warn!("Relay pairing challenge request failed: {err:#}");
            RelayLanPairingOutcome::TransportFailed
        })?;

    if let Some(outcome) = pairing_status(response.status()) {
        return Err(outcome);
    }
    let body = response
        .bytes()
        .await
        .map_err(|_| RelayLanPairingOutcome::TransportFailed)?;
    let dto: RelayPairChallengeResponseV1Dto =
        serde_json::from_slice(&body).map_err(|_| RelayLanPairingOutcome::AuthenticationFailed)?;
    Ok(*dto.server_nonce())
}

async fn pair_complete(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
    proof: crate::crypto::relay_identity_proof::RelayIdentityProofV1,
    alias: &str,
) -> Result<RelayPairCompleteResponseV1Dto, RelayLanPairingOutcome> {
    let response = client
        .post(relay_pair_url(protocol, ip, port, "complete"))
        .header("Content-Type", "application/json")
        .json(&RelayPairCompleteRequestV1Dto::new(
            proof,
            crate::relay::sanitize_pairing_alias(alias),
        ))
        .send()
        .await
        .map_err(|err| {
            tracing::warn!("Relay pairing completion request failed: {err:#}");
            RelayLanPairingOutcome::TransportFailed
        })?;

    if let Some(outcome) = pairing_status(response.status()) {
        return Err(outcome);
    }
    let body = response
        .bytes()
        .await
        .map_err(|_| RelayLanPairingOutcome::TransportFailed)?;
    serde_json::from_slice(&body).map_err(|_| RelayLanPairingOutcome::TransportFailed)
}

fn pairing_status(status: StatusCode) -> Option<RelayLanPairingOutcome> {
    match status {
        StatusCode::OK => None,
        StatusCode::NOT_FOUND
        | StatusCode::METHOD_NOT_ALLOWED
        | StatusCode::SERVICE_UNAVAILABLE => Some(RelayLanPairingOutcome::Unsupported),
        StatusCode::CONFLICT => Some(RelayLanPairingOutcome::Busy),
        StatusCode::FORBIDDEN | StatusCode::BAD_REQUEST => {
            Some(RelayLanPairingOutcome::AuthenticationFailed)
        }
        _ => Some(RelayLanPairingOutcome::TransportFailed),
    }
}

/// SHA-256 of this device's own mTLS client certificate.
///
/// Derived locally from the certificate this client was built with, never from
/// anything a peer sent.
fn client_certificate_fingerprint(certificate_pem: &str) -> Option<[u8; 32]> {
    use rustls::pki_types::pem::PemObject as _;

    rustls::pki_types::CertificateDer::from_pem_slice(certificate_pem.as_bytes())
        .ok()
        .map(|der| fingerprint_digest_from_cert_der(der.as_ref()))
}

fn relay_pair_url(protocol: ProtocolType, ip: &str, port: u16, step: &str) -> String {
    let host = match scoped_host::encode(ip) {
        Some(encoded) => Cow::Owned(encoded),
        None if ip.contains(':') => Cow::Owned(format!("[{ip}]")),
        None => Cow::Borrowed(ip),
    };
    format!(
        "{}://{host}:{port}/api/relay/v1/pair/{step}",
        protocol.as_str()
    )
}

fn relay_proof_url(protocol: ProtocolType, ip: &str, port: u16) -> String {
    let host = match scoped_host::encode(ip) {
        Some(encoded) => Cow::Owned(encoded),
        None if ip.contains(':') => Cow::Owned(format!("[{ip}]")),
        None => Cow::Borrowed(ip),
    };
    format!("{}://{host}:{port}/api/relay/v1/proof", protocol.as_str())
}

#[cfg(test)]
mod tests {
    use std::fmt;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use super::*;
    use crate::crypto::cert::{
        fingerprint_digest_from_cert_der, generate_self_signed, SelfSignedCert,
    };
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::crypto::relay_identity_proof::{create_relay_identity_proof, RelayIdentityProofV1};
    use crate::http::client::LsHttpClientV2;
    use crate::http::server::{
        start_with_port_with_relay_proof_signer, ServerConfigV2, ServerHandle, TlsConfig,
    };
    use crate::http::state::ClientInfo;
    use crate::relay::{RelayProofSigner, RelaySignError, RelayTlsContext};
    use rustls::pki_types::pem::PemObject;
    use rustls::pki_types::CertificateDer;
    use tokio::sync::oneshot;

    enum ProofMode {
        Valid,
        BoundTo([u8; 32]),
        ChangedNonce,
        ClientRole,
        TamperedSignature,
        Fail,
    }

    struct TestSigner {
        identity: RelayIdentity,
        relay_id: String,
        mode: ProofMode,
        calls: AtomicUsize,
    }

    impl TestSigner {
        fn new(mode: ProofMode) -> Self {
            let identity = RelayIdentity::generate();
            let relay_id = identity.relay_id().unwrap();
            Self {
                identity,
                relay_id,
                mode,
                calls: AtomicUsize::new(0),
            }
        }
    }

    impl fmt::Debug for TestSigner {
        fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("TestSigner(..)")
        }
    }

    impl RelayProofSigner for TestSigner {
        fn sign_server_proof(
            &self,
            nonce: &[u8; 32],
            tls: &RelayTlsContext,
        ) -> Result<RelayIdentityProofV1, RelaySignError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if matches!(self.mode, ProofMode::Fail) {
                return Err(RelaySignError::SigningFailed);
            }

            let role = match self.mode {
                ProofMode::ClientRole => RelayProofRole::Client,
                _ => RelayProofRole::Server,
            };
            let mut proof_nonce = *nonce;
            if matches!(self.mode, ProofMode::ChangedNonce) {
                proof_nonce[0] ^= 1;
            }
            let fingerprint = match self.mode {
                ProofMode::BoundTo(fingerprint) => fingerprint,
                _ => tls.own_tls_fingerprint(),
            };
            let mut proof =
                create_relay_identity_proof(&self.identity, role, proof_nonce, fingerprint)
                    .map_err(|_| RelaySignError::SigningFailed)?;
            if matches!(self.mode, ProofMode::TamperedSignature) {
                proof.signature[0] ^= 1;
            }
            Ok(proof)
        }

        fn local_relay_id(&self) -> &str {
            &self.relay_id
        }
    }

    struct TestServer {
        port: u16,
        stop_tx: oneshot::Sender<()>,
        handle: ServerHandle,
    }

    impl TestServer {
        async fn stop(self) {
            let _ = self.stop_tx.send(());
            self.handle.wait_stopped().await;
        }
    }

    fn tls_config(identity: &SelfSignedCert) -> TlsConfig {
        TlsConfig {
            cert: identity.certificate_pem.clone(),
            private_key: identity.private_key_pem.clone(),
        }
    }

    fn certificate_fingerprint(identity: &SelfSignedCert) -> [u8; 32] {
        let certificate =
            CertificateDer::from_pem_slice(identity.certificate_pem.as_bytes()).unwrap();
        fingerprint_digest_from_cert_der(certificate.as_ref())
    }

    async fn start_tls_server(
        identity: &SelfSignedCert,
        signer: Option<Arc<dyn RelayProofSigner>>,
    ) -> TestServer {
        let (stop_tx, stop_rx) = oneshot::channel();
        let handle = start_with_port_with_relay_proof_signer(
            0,
            Some(tls_config(identity)),
            ClientInfo {
                alias: "Relay client test server".to_owned(),
                version: "2.2".to_owned(),
                device_model: None,
                device_type: None,
                token: identity.fingerprint.clone(),
            },
            None,
            None::<ServerConfigV2>,
            None,
            signer,
            stop_rx,
        )
        .await
        .unwrap();
        TestServer {
            port: handle.port(),
            stop_tx,
            handle,
        }
    }

    fn tls_client(
        client_identity: &SelfSignedCert,
        server_identity: &SelfSignedCert,
    ) -> LsHttpClientV2 {
        LsHttpClientV2::try_new(
            &client_identity.private_key_pem,
            &client_identity.certificate_pem,
            Some(server_identity.fingerprint.clone()),
            None,
        )
        .unwrap()
    }

    #[tokio::test]
    async fn authenticates_a_server_proof_against_the_response_certificate() {
        let server_identity = generate_self_signed().unwrap();
        let client_identity = generate_self_signed().unwrap();
        let signer = Arc::new(TestSigner::new(ProofMode::Valid));
        let expected_relay_id = signer.identity.relay_id().unwrap();
        let expected_fingerprint = certificate_fingerprint(&server_identity);
        let server = start_tls_server(&server_identity, Some(signer)).await;

        let auth = tls_client(&client_identity, &server_identity)
            .authenticate_relay_server(ProtocolType::Https, "127.0.0.1", server.port)
            .await;

        assert_eq!(
            auth,
            RelayPeerAuth::Authenticated {
                relay_id: expected_relay_id,
                tls_fingerprint: expected_fingerprint,
            }
        );
        server.stop().await;
    }

    #[tokio::test]
    async fn proof_bound_to_another_certificate_is_crypto_invalid() {
        let server_identity = generate_self_signed().unwrap();
        let client_identity = generate_self_signed().unwrap();
        let other_identity = generate_self_signed().unwrap();
        let signer: Arc<dyn RelayProofSigner> = Arc::new(TestSigner::new(ProofMode::BoundTo(
            certificate_fingerprint(&other_identity),
        )));
        let server = start_tls_server(&server_identity, Some(signer)).await;

        let auth = tls_client(&client_identity, &server_identity)
            .authenticate_relay_server(ProtocolType::Https, "127.0.0.1", server.port)
            .await;

        assert_eq!(auth, RelayPeerAuth::CryptoInvalid);
        server.stop().await;
    }

    #[tokio::test]
    async fn rejects_nonce_role_and_signature_failures_without_collapsing_them() {
        for (mode, expected) in [
            (ProofMode::ChangedNonce, RelayPeerAuth::ChallengeMismatch),
            (ProofMode::ClientRole, RelayPeerAuth::RoleMismatch),
            (ProofMode::TamperedSignature, RelayPeerAuth::CryptoInvalid),
        ] {
            let server_identity = generate_self_signed().unwrap();
            let client_identity = generate_self_signed().unwrap();
            let signer: Arc<dyn RelayProofSigner> = Arc::new(TestSigner::new(mode));
            let server = start_tls_server(&server_identity, Some(signer)).await;

            assert_eq!(
                tls_client(&client_identity, &server_identity)
                    .authenticate_relay_server(ProtocolType::Https, "127.0.0.1", server.port)
                    .await,
                expected
            );
            server.stop().await;
        }
    }

    #[tokio::test]
    async fn signer_unavailable_and_plain_http_are_distinct() {
        let server_identity = generate_self_signed().unwrap();
        let client_identity = generate_self_signed().unwrap();
        let tls_server = start_tls_server(&server_identity, None).await;
        assert_eq!(
            tls_client(&client_identity, &server_identity)
                .authenticate_relay_server(ProtocolType::Https, "127.0.0.1", tls_server.port)
                .await,
            RelayPeerAuth::SignerUnavailable
        );
        tls_server.stop().await;

        let failing_server = start_tls_server(
            &server_identity,
            Some(Arc::new(TestSigner::new(ProofMode::Fail))),
        )
        .await;
        assert_eq!(
            tls_client(&client_identity, &server_identity)
                .authenticate_relay_server(ProtocolType::Https, "127.0.0.1", failing_server.port)
                .await,
            RelayPeerAuth::SignerUnavailable
        );
        failing_server.stop().await;

        let signer = Arc::new(TestSigner::new(ProofMode::Valid));
        let (stop_tx, stop_rx) = oneshot::channel();
        let plain_server = start_with_port_with_relay_proof_signer(
            0,
            None,
            ClientInfo {
                alias: "Plain Relay test server".to_owned(),
                version: "2.2".to_owned(),
                device_model: None,
                device_type: None,
                token: "plain".to_owned(),
            },
            None,
            None::<ServerConfigV2>,
            None,
            Some(signer.clone()),
            stop_rx,
        )
        .await
        .unwrap();
        let plain_client = LsHttpClientV2::try_new_without_cert().unwrap();
        assert_eq!(
            plain_client
                .authenticate_relay_server(ProtocolType::Http, "127.0.0.1", plain_server.port())
                .await,
            RelayPeerAuth::NotAttempted
        );
        assert_eq!(signer.calls.load(Ordering::SeqCst), 0);
        let _ = stop_tx.send(());
        plain_server.wait_stopped().await;
    }

    #[test]
    fn status_tls_and_malformed_proof_mappings_fail_closed() {
        assert_eq!(
            relay_status(StatusCode::NOT_FOUND),
            Some(RelayPeerAuth::Unsupported)
        );
        assert_eq!(
            relay_status(StatusCode::METHOD_NOT_ALLOWED),
            Some(RelayPeerAuth::Unsupported)
        );
        assert_eq!(
            relay_status(StatusCode::SERVICE_UNAVAILABLE),
            Some(RelayPeerAuth::SignerUnavailable)
        );
        assert_eq!(
            relay_status(StatusCode::BAD_REQUEST),
            Some(RelayPeerAuth::Malformed)
        );
        assert_eq!(
            tls_fingerprint_or_transport(Err(anyhow::anyhow!("missing TLS info"))),
            Err(RelayPeerAuth::TransportUnauthenticated)
        );

        let malformed = [
            "{".to_owned(),
            r#"{"proof":"%%%"}"#.to_owned(),
            format!(
                r#"{{"proof":"{}"}}"#,
                crate::util::base64::encode([0_u8; 129])
            ),
            format!(
                r#"{{"proof":"{}"}}"#,
                crate::util::base64::encode([0_u8; 131])
            ),
            {
                let mut encoded = [0_u8; 130];
                encoded[0] = 2;
                format!(r#"{{"proof":"{}"}}"#, crate::util::base64::encode(encoded))
            },
        ];
        for proof in malformed {
            assert_eq!(
                parse_proof_bytes(proof.as_bytes()),
                Err(RelayPeerAuth::Malformed)
            );
        }
    }
}
