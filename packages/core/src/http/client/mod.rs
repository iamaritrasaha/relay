mod anywhere;
pub mod relay;
mod scoped_host;
mod server_cert_verifier;
pub(crate) use server_cert_verifier::PinnedServerCertVerifier;
mod url;
pub mod v2;
pub mod v3;

pub use anywhere::AnywhereHttpClient;
pub use v2::LsHttpClientV2;
pub use v3::LsHttpClientV3;

use crate::http::StatusCodeError;
use crate::relay::RelayPeerAuth;
use crate::{crypto, http, model};
use bytes::Bytes;
use futures_util::StreamExt;
use reqwest::Response;
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use thiserror::Error;
use tokio_stream::wrappers::ReceiverStream;

pub enum LsHttpClient {
    V2(LsHttpClientV2),
    V3(LsHttpClientV3),
}

#[derive(Clone, Copy, Debug)]
pub enum LsHttpClientVersion {
    V2,
    V3,
}

#[derive(Debug, Error)]
pub enum ClientError {
    #[error(transparent)]
    StatusCode(StatusCodeError),

    #[error(transparent)]
    Reqwest(#[from] reqwest::Error),

    #[error(transparent)]
    Json(#[from] serde_json::Error),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error(transparent)]
    Other(#[from] anyhow::Error),

    #[error("Upload cancelled")]
    Cancelled,
}

/// Shared v2 semantic result mapping used by both reqwest (LAN) and the
/// caller-owned Hyper (Anywhere) sender.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum PrepareUploadStatus {
    Accepted,
    NoContent,
}

pub(crate) fn classify_prepare_upload_status(
    status: u16,
) -> Result<PrepareUploadStatus, ClientError> {
    match status {
        200..=299 => Ok(if status == 204 {
            PrepareUploadStatus::NoContent
        } else {
            PrepareUploadStatus::Accepted
        }),
        status => Err(ClientError::StatusCode(crate::http::StatusCodeError {
            status,
            message: None,
        })),
    }
}

pub(crate) fn classify_upload_status(status: u16) -> Result<(), ClientError> {
    if status == 200 {
        Ok(())
    } else {
        Err(ClientError::StatusCode(crate::http::StatusCodeError {
            status,
            message: None,
        }))
    }
}

impl LsHttpClient {
    /// Creates a client for the given protocol version.
    ///
    /// `expected_fingerprint` pins the peer to the certificate with that
    /// SHA-256 fingerprint (uppercase hex). It is checked during the TLS
    /// handshake, so a mismatching peer never receives the request. Pass
    /// [`None`] only when the peer is not known yet, i.e. for discovery.
    pub fn new(
        private_key: &str,
        cert: &str,
        version: LsHttpClientVersion,
        expected_fingerprint: Option<String>,
        timeout: Option<std::time::Duration>,
    ) -> Result<LsHttpClient, ClientError> {
        let client = match version {
            LsHttpClientVersion::V2 => LsHttpClient::V2(LsHttpClientV2::try_new(
                private_key,
                cert,
                expected_fingerprint,
                timeout,
            )?),
            LsHttpClientVersion::V3 => LsHttpClient::V3(LsHttpClientV3::try_new(
                private_key,
                cert,
                expected_fingerprint,
                timeout,
            )?),
        };

        Ok(client)
    }

    pub async fn register(
        &self,
        protocol: model::discovery::ProtocolType,
        ip: &str,
        port: u16,
        payload: http::dto::RegisterDto,
    ) -> Result<ResultWithPublicKey<http::dto::RegisterResponseDto>, ClientError> {
        match self {
            LsHttpClient::V2(client) => {
                let result = client.register(protocol, ip, port, payload.into()).await?;
                Ok(ResultWithPublicKey {
                    public_key: result.public_key,
                    cert_fingerprint: result.cert_fingerprint,
                    body: result.body.into(),
                })
            }
            LsHttpClient::V3(client) => client.register(protocol, ip, port, payload).await,
        }
    }

    pub async fn prepare_upload(
        &self,
        protocol: model::discovery::ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        payload: http::dto::PrepareUploadRequestDto,
        pin: Option<&str>,
        cancel: tokio_util::sync::CancellationToken,
    ) -> Result<http::dto::PrepareUploadResult, ClientError> {
        match self {
            LsHttpClient::V2(client) => {
                let result = client
                    .prepare_upload(protocol, ip, port, public_key, payload.into(), pin, cancel)
                    .await?;
                Ok(result.into())
            }
            LsHttpClient::V3(client) => {
                client
                    .prepare_upload(protocol, ip, port, public_key, payload, cancel)
                    .await
            }
        }
    }

    pub async fn upload(
        &self,
        protocol: model::discovery::ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        session_id: &str,
        file_id: &str,
        token: &str,
        content: model::transfer::FileContent,
        progress: impl Fn(u64) + Send + 'static,
        cancel: tokio_util::sync::CancellationToken,
    ) -> Result<(), ClientError> {
        let body = upload_body(content, progress);
        match self {
            LsHttpClient::V2(client) => {
                client
                    .upload(
                        protocol, ip, port, public_key, session_id, file_id, token, body, cancel,
                    )
                    .await
            }
            LsHttpClient::V3(client) => {
                client
                    .upload(
                        protocol, ip, port, public_key, session_id, file_id, token, body, cancel,
                    )
                    .await
            }
        }
    }

    pub async fn cancel(
        &self,
        protocol: model::discovery::ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<(), ClientError> {
        match self {
            LsHttpClient::V2(client) => client.cancel(protocol, ip, port, session_id).await,
            LsHttpClient::V3(client) => client.cancel(protocol, ip, port, session_id).await,
        }
    }

    /// Cryptographically authenticates a Relay server's identity proof over HTTPS.
    pub async fn authenticate_relay_server(
        &self,
        protocol: model::discovery::ProtocolType,
        ip: &str,
        port: u16,
    ) -> RelayPeerAuth {
        match self {
            LsHttpClient::V2(client) => client.authenticate_relay_server(protocol, ip, port).await,
            LsHttpClient::V3(client) => client.authenticate_relay_server(protocol, ip, port).await,
        }
    }

    /// Runs the mutual Relay LAN pairing handshake against another Relay device.
    ///
    /// The client must already be pinned to the peer's certificate, because
    /// both proofs are bound to the certificates of this exact connection.
    pub async fn pair_with_relay_server(
        &self,
        protocol: model::discovery::ProtocolType,
        ip: &str,
        port: u16,
        request: relay::RelayLanPairingRequest<'_>,
        events: &tokio::sync::mpsc::Sender<relay::RelayLanPairingEvent>,
    ) -> crate::relay::RelayLanPairingOutcome {
        match self {
            LsHttpClient::V2(client) => {
                client
                    .pair_with_relay_server(protocol, ip, port, request, events)
                    .await
            }
            LsHttpClient::V3(client) => {
                client
                    .pair_with_relay_server(protocol, ip, port, request, events)
                    .await
            }
        }
    }
}

/// Opens an authenticated local continuity connection to a paired Relay device.
///
/// This is the whole local continuity entry point. It pins a fresh HTTPS client
/// to the certificate discovery observed, upgrades the connection to the Relay
/// continuity protocol, and completes the mutual identity proof over it. The
/// caller receives a stream that `continuity::run_session` can take directly.
///
/// Every connection re-proves the peer. A stored pairing says a relationship
/// exists; it never lets a later connection skip authentication.
#[cfg(feature = "anywhere")]
#[allow(clippy::too_many_arguments)]
pub async fn connect_relay_lan_continuity(
    private_key: &str,
    cert: &str,
    version: LsHttpClientVersion,
    protocol: model::discovery::ProtocolType,
    ip: &str,
    port: u16,
    certificate_fingerprint: &str,
    identity: &crypto::relay_identity::RelayIdentity,
    expected_relay_id: &crate::relay::RelayId,
) -> Result<relay::RelayLanContinuityConnection, relay::RelayLanContinuityError> {
    let client = LsHttpClient::new(
        private_key,
        cert,
        version,
        Some(certificate_fingerprint.to_owned()),
        None,
    )
    .map_err(|err| {
        tracing::debug!("Could not create a pinned Relay continuity client: {err:#}");
        relay::RelayLanContinuityError::TransportFailed
    })?;

    match client {
        LsHttpClient::V2(client) => {
            client
                .connect_lan_continuity(protocol, ip, port, identity, cert, expected_relay_id)
                .await
        }
        LsHttpClient::V3(client) => {
            client
                .connect_lan_continuity(protocol, ip, port, identity, cert, expected_relay_id)
                .await
        }
    }
}

/// Pairs with a Relay device discovered on the LAN.
///
/// This is the whole initiator entry point: it pins a fresh HTTPS client to the
/// certificate fingerprint that discovery observed, then runs the mutual
/// handshake over it. The fingerprint decides *which socket* is talked to; it
/// never decides *who* the peer is — only the two proofs do that, and a peer
/// that swapped identities behind the same certificate still fails
/// `expected_relay_id`.
#[allow(clippy::too_many_arguments)]
pub async fn pair_relay_lan_device(
    private_key: &str,
    cert: &str,
    version: LsHttpClientVersion,
    protocol: model::discovery::ProtocolType,
    ip: &str,
    port: u16,
    certificate_fingerprint: &str,
    identity: &crypto::relay_identity::RelayIdentity,
    alias: &str,
    expected_relay_id: Option<&crate::relay::RelayId>,
    events: &tokio::sync::mpsc::Sender<relay::RelayLanPairingEvent>,
) -> crate::relay::RelayLanPairingOutcome {
    let client = match LsHttpClient::new(
        private_key,
        cert,
        version,
        Some(certificate_fingerprint.to_owned()),
        None,
    ) {
        Ok(client) => client,
        Err(err) => {
            tracing::warn!("Could not create a pinned Relay pairing client: {err:#}");
            let outcome = crate::relay::RelayLanPairingOutcome::TransportFailed;
            let _ = events
                .send(relay::RelayLanPairingEvent::Outcome(outcome.clone()))
                .await;
            return outcome;
        }
    };

    client
        .pair_with_relay_server(
            protocol,
            ip,
            port,
            relay::RelayLanPairingRequest {
                identity,
                client_certificate_pem: cert,
                alias,
                expected_relay_id,
            },
            events,
        )
        .await
}

/// Builds a streaming request body from the file content, invoking `progress`
/// with the cumulative number of bytes read as each chunk is sent.
pub(super) fn upload_body(
    content: model::transfer::FileContent,
    progress: impl Fn(u64) + Send + 'static,
) -> reqwest::Body {
    let mut sent = 0_u64;
    let stream = ReceiverStream::new(content.into_receiver()).map(move |chunk| {
        sent += chunk.len() as u64;
        progress(sent);
        Ok::<Bytes, anyhow::Error>(chunk)
    });
    reqwest::Body::wrap_stream(stream)
}

/// Builds the reqwest client used for all outgoing requests.
///
/// The TLS config is assembled by hand instead of using reqwest's own TLS
/// options, because only a preconfigured [`rustls::ClientConfig`] can carry a
/// custom certificate verifier. reqwest passes such a config straight through,
/// which means the client certificate and ALPN have to be set here as well:
/// `identity()` and the HTTP version preference of the builder no longer apply.
pub(super) fn create_reqwest_client(
    private_key: &str,
    cert: &str,
    expected_fingerprint: Option<String>,
    timeout: Option<std::time::Duration>,
) -> Result<reqwest::Client, ClientError> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    let mut tls_config = {
        let certs =
            vec![CertificateDer::from_pem_slice(cert.as_bytes()).map_err(anyhow::Error::from)?];
        let key =
            PrivateKeyDer::from_pem_slice(private_key.as_bytes()).map_err(anyhow::Error::from)?;

        rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(
                server_cert_verifier::PinnedServerCertVerifier::try_new(
                    cert,
                    expected_fingerprint,
                )?,
            ))
            .with_client_auth_cert(certs, key)
            .map_err(anyhow::Error::from)?
    };

    // Must be set explicitly, see the doc comment above.
    tls_config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];

    let mut builder = reqwest::Client::builder()
        .tls_backend_preconfigured(tls_config)
        .tls_info(true)
        // Peers are on the local network: never dial them through a system or
        // environment proxy. Proxied connections also lose the `TlsInfo`
        // response extension that the certificate checks below rely on (#3299).
        .no_proxy()
        // Peers never redirect; following one would talk to a different host
        // than the one whose certificate is being verified.
        .redirect(reqwest::redirect::Policy::none())
        .dns_resolver(Arc::new(ScopedHostResolver));

    if let Some(timeout) = timeout {
        builder = builder.timeout(timeout);
    }

    let client = builder.build()?;

    Ok(client)
}

/// DNS resolver that turns the synthetic host names produced by
/// [`scoped_host::encode`] back into their scoped IPv6 socket address.
/// Every other name is resolved by the system resolver, like by default.
struct ScopedHostResolver;

impl reqwest::dns::Resolve for ScopedHostResolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        Box::pin(async move {
            if let Some(addr) = scoped_host::decode(name.as_str()) {
                return Ok(Box::new(std::iter::once(addr)) as reqwest::dns::Addrs);
            }

            // The port is a placeholder, reqwest replaces it with the URL's.
            let addrs = tokio::net::lookup_host((name.as_str(), 0))
                .await?
                .collect::<Vec<_>>();
            Ok(Box::new(addrs.into_iter()) as reqwest::dns::Addrs)
        })
    }
}

/// Verifies the certificate from the response.
/// Returns the public key extracted from the certificate.
pub(super) fn verify_cert_from_res(
    response: &Response,
    public_key: Option<String>,
) -> anyhow::Result<String> {
    let tls_info_ext = response
        .extensions()
        .get::<reqwest::tls::TlsInfo>()
        .ok_or_else(|| anyhow::anyhow!("TLS info not found"))?;
    let cert = tls_info_ext
        .peer_certificate()
        .ok_or_else(|| anyhow::anyhow!("Certificate not found"))?;
    crypto::cert::verify_cert_from_der(cert, public_key.as_deref())?;
    let public_key = match public_key {
        Some(public_key) => public_key,
        None => crypto::cert::public_key_from_cert_der(cert)?,
    };
    Ok(public_key)
}

/// The SHA-256 fingerprint (uppercase hex) of the peer certificate the
/// response was received over. This — not any fingerprint claimed in the
/// body — is the peer's identity in HTTPS mode.
pub(super) fn cert_fingerprint_from_res(response: &Response) -> anyhow::Result<String> {
    Ok(crypto::cert::fingerprint_from_cert_der(
        peer_certificate_from_res(response)?,
    ))
}

/// The raw SHA-256 fingerprint of the certificate on this exact response's
/// TLS connection.
pub(super) fn cert_fingerprint_digest_from_res(response: &Response) -> anyhow::Result<[u8; 32]> {
    Ok(crypto::cert::fingerprint_digest_from_cert_der(
        peer_certificate_from_res(response)?,
    ))
}

fn peer_certificate_from_res(response: &Response) -> anyhow::Result<&[u8]> {
    let tls_info_ext = response
        .extensions()
        .get::<reqwest::tls::TlsInfo>()
        .ok_or_else(|| anyhow::anyhow!("TLS info not found"))?;
    let cert = tls_info_ext
        .peer_certificate()
        .ok_or_else(|| anyhow::anyhow!("Certificate not found"))?;
    Ok(cert)
}

#[derive(Serialize, Deserialize)]
struct ErrorResponse {
    message: String,
}

pub struct ResultWithPublicKey<T> {
    /// The public key extracted from the certificate.
    /// Encoded in PEM format.
    /// Only available in HTTPS mode.
    pub public_key: Option<String>,

    /// The SHA-256 fingerprint (uppercase hex) of the peer certificate.
    /// Only available in HTTPS mode, where it is the peer's identity and
    /// overrules any fingerprint claimed in the body.
    pub cert_fingerprint: Option<String>,

    /// The response body.
    pub body: T,
}

pub(super) trait ResponseExt {
    async fn into_error<T>(self) -> Result<T, ClientError>;
}

impl ResponseExt for Response {
    async fn into_error<T>(self) -> Result<T, ClientError> {
        let status = self.status().as_u16();
        let body = self.text().await.unwrap_or_default();
        let message = match serde_json::from_str::<ErrorResponse>(&body) {
            Ok(error) => error.message,
            Err(_) => body,
        };
        Err(ClientError::StatusCode(StatusCodeError {
            status,
            message: if message.is_empty() {
                None
            } else {
                Some(message)
            },
        }))
    }
}

#[cfg(test)]
mod transfer_semantics_tests {
    use super::*;

    #[test]
    fn lan_and_anywhere_share_prepare_status_mapping() {
        assert_eq!(
            classify_prepare_upload_status(200).unwrap(),
            PrepareUploadStatus::Accepted
        );
        assert_eq!(
            classify_prepare_upload_status(204).unwrap(),
            PrepareUploadStatus::NoContent
        );
        assert_eq!(
            classify_prepare_upload_status(403).unwrap_err().to_string(),
            "403;None"
        );
    }

    #[test]
    fn lan_and_anywhere_share_upload_status_mapping() {
        assert!(classify_upload_status(200).is_ok());
        assert_eq!(
            classify_upload_status(422).unwrap_err().to_string(),
            "422;None"
        );
    }
}
