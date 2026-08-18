use std::borrow::Cow;

use reqwest::StatusCode;

use crate::crypto::nonce::generate_nonce_32;
use crate::crypto::relay_identity_proof::{verify_relay_identity_proof, RelayProofRole};
use crate::http::client::{cert_fingerprint_digest_from_res, scoped_host};
use crate::http::dto_relay::{RelayChallengeV1Dto, RelayProofV1Dto};
use crate::model::discovery::ProtocolType;
use crate::relay::RelayPeerAuth;

pub(super) async fn authenticate_relay_server(
    client: &reqwest::Client,
    protocol: ProtocolType,
    ip: &str,
    port: u16,
) -> RelayPeerAuth {
    if protocol != ProtocolType::Https {
        return RelayPeerAuth::NotAttempted;
    }

    let nonce = generate_nonce_32();
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
        mode: ProofMode,
        calls: AtomicUsize,
    }

    impl TestSigner {
        fn new(mode: ProofMode) -> Self {
            Self {
                identity: RelayIdentity::generate(),
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
