use bytes::Bytes;
use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::{Request, Response, StatusCode};

use crate::http::dto_relay::{RelayChallengeV1Dto, RelayProofV1Dto};
use crate::http::server::common::response::{self, BoxedBody, JsonResponse};
use crate::http::server::{AppState, ConnectionTlsCtx};

const MAX_PROOF_REQUEST_BODY_BYTES: usize = 256;

pub(crate) async fn proof(
    req: Request<Incoming>,
    state: AppState,
) -> Result<Response<BoxedBody>, crate::http::server::common::error::AppError> {
    let Some(tls_context) = req.extensions().get::<ConnectionTlsCtx>().cloned() else {
        return Ok(status_response(StatusCode::NOT_FOUND));
    };

    let challenge = parse_challenge(req).await?;

    let permit = match state.relay_proof.semaphore.acquire().await {
        Ok(permit) => permit,
        Err(_) => return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE)),
    };
    let signer = match state.relay_proof.signer.read() {
        Ok(slot) => slot.clone(),
        // A poisoned slot is deliberately indistinguishable from an absent
        // signer to a peer.
        Err(_) => None,
    };
    let Some(signer) = signer else {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    };
    let proof = match signer.sign_server_proof(challenge.nonce(), &tls_context.relay) {
        Ok(proof) => proof,
        Err(err) => {
            tracing::warn!(?err, "Relay proof signing failed");
            return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
        }
    };
    drop(permit);

    Ok(JsonResponse {
        status: StatusCode::OK,
        body: RelayProofV1Dto::new(proof),
    }
    .into_response())
}

async fn parse_challenge(
    req: Request<Incoming>,
) -> Result<RelayChallengeV1Dto, crate::http::server::common::error::AppError> {
    if let Some(content_length) = req.headers().get(hyper::header::CONTENT_LENGTH) {
        let content_length = content_length
            .to_str()
            .ok()
            .and_then(|value| value.parse::<usize>().ok());
        if content_length.is_none_or(|length| length > MAX_PROOF_REQUEST_BODY_BYTES) {
            return Err(bad_request());
        }
    }

    let bytes = collect_bounded(req.into_body()).await?;
    serde_json::from_slice(&bytes).map_err(|_| bad_request())
}

async fn collect_bounded(
    mut body: Incoming,
) -> Result<Bytes, crate::http::server::common::error::AppError> {
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| bad_request())?;
        if let Some(data) = frame.data_ref() {
            if bytes.len() + data.len() > MAX_PROOF_REQUEST_BODY_BYTES {
                return Err(bad_request());
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(Bytes::from(bytes))
}

fn bad_request() -> crate::http::server::common::error::AppError {
    crate::http::server::common::error::AppError::Status(StatusCode::BAD_REQUEST)
}

fn status_response(status: StatusCode) -> Response<BoxedBody> {
    let mut response = Response::new(response::empty_body());
    *response.status_mut() = status;
    response
}

#[cfg(test)]
mod tests {
    use std::fmt;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use super::*;
    use crate::crypto::cert::generate_self_signed;
    use crate::crypto::hash;
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::crypto::relay_identity_proof::{
        create_relay_identity_proof, verify_relay_identity_proof, RelayIdentityProofV1,
        RelayProofRole,
    };
    use crate::http::server::web::{WebConfig, WebI18n};
    use crate::http::server::{start_with_port_with_relay_proof_signer, ServerConfigV2, TlsConfig};
    use crate::http::state::ClientInfo;
    use crate::relay::{
        RelayProofSigner, RelaySignError, RelaySignerInstallError, RelayTlsContext,
    };
    use rustls::pki_types::pem::PemObject;
    use rustls::pki_types::CertificateDer;
    use tokio::sync::oneshot;

    struct CountingSigner {
        identity: RelayIdentity,
        calls: AtomicUsize,
        fail: bool,
        observed_fingerprint: std::sync::Mutex<Option<[u8; 32]>>,
    }

    impl CountingSigner {
        fn new(fail: bool) -> Self {
            Self {
                identity: RelayIdentity::generate(),
                calls: AtomicUsize::new(0),
                fail,
                observed_fingerprint: std::sync::Mutex::new(None),
            }
        }
    }

    impl fmt::Debug for CountingSigner {
        fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("CountingSigner(..)")
        }
    }

    impl RelayProofSigner for CountingSigner {
        fn sign_server_proof(
            &self,
            nonce: &[u8; 32],
            tls: &RelayTlsContext,
        ) -> Result<RelayIdentityProofV1, RelaySignError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if self.fail {
                return Err(RelaySignError::SigningFailed);
            }
            *self.observed_fingerprint.lock().unwrap() = Some(tls.own_tls_fingerprint());
            create_relay_identity_proof(
                &self.identity,
                tls.role(),
                *nonce,
                tls.own_tls_fingerprint(),
            )
            .map_err(|_| RelaySignError::SigningFailed)
        }
    }

    struct TestServer {
        port: u16,
        stop_tx: oneshot::Sender<()>,
        handle: crate::http::server::ServerHandle,
    }

    impl TestServer {
        async fn stop(self) {
            let _ = self.stop_tx.send(());
            self.handle.wait_stopped().await;
        }
    }

    async fn start_server(
        tls: Option<TlsConfig>,
        signer: Option<Arc<dyn RelayProofSigner>>,
    ) -> TestServer {
        let (stop_tx, stop_rx) = oneshot::channel();
        let handle = start_with_port_with_relay_proof_signer(
            0,
            tls,
            ClientInfo {
                alias: "Relay proof test server".to_owned(),
                version: "2.2".to_owned(),
                device_model: None,
                device_type: None,
                token: "test".to_owned(),
            },
            None,
            None::<ServerConfigV2>,
            Some(WebConfig {
                send: None,
                upload: true,
                i18n: WebI18n::default(),
            }),
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

    fn browser() -> crate::reqwest::Client {
        crate::reqwest::Client::builder()
            .use_rustls_tls()
            .danger_accept_invalid_certs(true)
            .build()
            .unwrap()
    }

    fn tls_config(identity: &crate::crypto::cert::SelfSignedCert) -> TlsConfig {
        TlsConfig {
            cert: identity.certificate_pem.clone(),
            private_key: identity.private_key_pem.clone(),
        }
    }

    fn certificate_fingerprint(identity: &crate::crypto::cert::SelfSignedCert) -> [u8; 32] {
        let certificate =
            CertificateDer::from_pem_slice(identity.certificate_pem.as_bytes()).unwrap();
        hash::sha256(certificate.as_ref()).try_into().unwrap()
    }

    fn challenge_body(nonce: [u8; 32]) -> String {
        serde_json::to_string(&RelayChallengeV1Dto::new(nonce)).unwrap()
    }

    fn private_key_pem_bytes(identity: &RelayIdentity) -> Vec<u8> {
        identity.private_key_export().unwrap().as_bytes().to_vec()
    }

    async fn request_proof(server: &TestServer, nonce: [u8; 32]) -> (StatusCode, String) {
        let response = browser()
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/proof",
                server.port
            ))
            .body(challenge_body(nonce))
            .send()
            .await
            .unwrap();
        let status = response.status();
        (status, response.text().await.unwrap())
    }

    #[tokio::test]
    async fn production_signer_install_wipes_input_and_proves_the_installed_identity() {
        let certificate = generate_self_signed().unwrap();
        let tls_fingerprint = certificate_fingerprint(&certificate);
        let server = start_server(Some(tls_config(&certificate)), None).await;
        let identity = RelayIdentity::generate();
        let expected_relay_id = identity.relay_id().unwrap();
        let mut private_key_pem = private_key_pem_bytes(&identity);

        assert_eq!(
            server
                .handle
                .install_relay_signer(&mut private_key_pem, &expected_relay_id)
                .unwrap(),
            expected_relay_id
        );
        assert!(private_key_pem.is_empty());

        let nonce = [0x41; 32];
        let (status, body) = request_proof(&server, nonce).await;
        assert_eq!(status, StatusCode::OK);
        let dto = serde_json::from_str::<RelayProofV1Dto>(&body).unwrap();
        let proof = dto.proof();
        assert_eq!(proof.nonce, nonce);
        assert_eq!(proof.role, RelayProofRole::Server);
        assert_eq!(
            verify_relay_identity_proof(&proof, RelayProofRole::Server, tls_fingerprint).unwrap(),
            expected_relay_id
        );
        server.stop().await;
    }

    #[tokio::test]
    async fn invalid_and_mismatched_signers_are_wiped_and_do_not_replace_the_current_signer() {
        let certificate = generate_self_signed().unwrap();
        let tls_fingerprint = certificate_fingerprint(&certificate);
        let server = start_server(Some(tls_config(&certificate)), None).await;

        let mut invalid_utf8 = vec![0xff, 0xfe];
        assert_eq!(
            server
                .handle
                .install_relay_signer(&mut invalid_utf8, "relay-id"),
            Err(RelaySignerInstallError::InvalidPrivateKey)
        );
        assert!(invalid_utf8.is_empty());

        let mut invalid_pkcs8 = b"not a PKCS#8 private key".to_vec();
        assert_eq!(
            server
                .handle
                .install_relay_signer(&mut invalid_pkcs8, "relay-id"),
            Err(RelaySignerInstallError::InvalidPrivateKey)
        );
        assert!(invalid_pkcs8.is_empty());

        let identity_a = RelayIdentity::generate();
        let relay_id_a = identity_a.relay_id().unwrap();
        let mut pem_a = private_key_pem_bytes(&identity_a);
        server
            .handle
            .install_relay_signer(&mut pem_a, &relay_id_a)
            .unwrap();
        assert!(pem_a.is_empty());

        let identity_b = RelayIdentity::generate();
        let mut pem_b = private_key_pem_bytes(&identity_b);
        assert_eq!(
            server.handle.install_relay_signer(&mut pem_b, &relay_id_a),
            Err(RelaySignerInstallError::RelayIdMismatch)
        );
        assert!(pem_b.is_empty());

        let (status, body) = request_proof(&server, [0x42; 32]).await;
        assert_eq!(status, StatusCode::OK);
        let dto = serde_json::from_str::<RelayProofV1Dto>(&body).unwrap();
        let proof = dto.proof();
        assert_eq!(
            verify_relay_identity_proof(&proof, RelayProofRole::Server, tls_fingerprint).unwrap(),
            relay_id_a
        );
        server.stop().await;
    }

    #[tokio::test]
    async fn revoke_is_idempotent_and_a_replacement_signer_never_proves_as_the_old_identity() {
        let certificate = generate_self_signed().unwrap();
        let tls_fingerprint = certificate_fingerprint(&certificate);
        let server = start_server(Some(tls_config(&certificate)), None).await;

        let identity_a = RelayIdentity::generate();
        let relay_id_a = identity_a.relay_id().unwrap();
        let mut pem_a = private_key_pem_bytes(&identity_a);
        server
            .handle
            .install_relay_signer(&mut pem_a, &relay_id_a)
            .unwrap();
        let (status_a, body_a) = request_proof(&server, [0x51; 32]).await;
        assert_eq!(status_a, StatusCode::OK);
        let dto_a = serde_json::from_str::<RelayProofV1Dto>(&body_a).unwrap();
        let proof_a = dto_a.proof();
        assert_eq!(
            verify_relay_identity_proof(&proof_a, RelayProofRole::Server, tls_fingerprint).unwrap(),
            relay_id_a
        );

        assert!(server.handle.revoke_relay_signer());
        assert!(!server.handle.revoke_relay_signer());
        let (revoked_status, revoked_body) = request_proof(&server, [0x52; 32]).await;
        assert_eq!(revoked_status, StatusCode::SERVICE_UNAVAILABLE);
        assert!(revoked_body.is_empty());

        let identity_b = RelayIdentity::generate();
        let relay_id_b = identity_b.relay_id().unwrap();
        let mut pem_b = private_key_pem_bytes(&identity_b);
        server
            .handle
            .install_relay_signer(&mut pem_b, &relay_id_b)
            .unwrap();
        let (status_b, body_b) = request_proof(&server, [0x53; 32]).await;
        assert_eq!(status_b, StatusCode::OK);
        let dto_b = serde_json::from_str::<RelayProofV1Dto>(&body_b).unwrap();
        let proof_b = dto_b.proof();
        assert_eq!(
            verify_relay_identity_proof(&proof_b, RelayProofRole::Server, tls_fingerprint).unwrap(),
            relay_id_b
        );
        assert!(
            verify_relay_identity_proof(&proof_b, RelayProofRole::Server, tls_fingerprint)
                .is_ok_and(|relay_id| relay_id != relay_id_a)
        );
        server.stop().await;
    }

    #[tokio::test]
    async fn stop_revokes_the_signer_and_prevents_late_installation() {
        let certificate = generate_self_signed().unwrap();
        let server = start_server(Some(tls_config(&certificate)), None).await;
        let identity = RelayIdentity::generate();
        let relay_id = identity.relay_id().unwrap();
        let mut private_key_pem = private_key_pem_bytes(&identity);
        server
            .handle
            .install_relay_signer(&mut private_key_pem, &relay_id)
            .unwrap();

        let _ = server.stop_tx.send(());
        server.handle.wait_stopped().await;
        assert!(server.handle.relay_proof.signer.read().unwrap().is_none());

        let late_identity = RelayIdentity::generate();
        let late_relay_id = late_identity.relay_id().unwrap();
        let mut late_private_key_pem = private_key_pem_bytes(&late_identity);
        assert_eq!(
            server
                .handle
                .install_relay_signer(&mut late_private_key_pem, &late_relay_id),
            Err(RelaySignerInstallError::ServerStopped)
        );
        assert!(late_private_key_pem.is_empty());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn concurrent_install_and_revoke_do_not_panic_or_deadlock() {
        let certificate = generate_self_signed().unwrap();
        let server = start_server(Some(tls_config(&certificate)), None).await;
        let proof_url = format!("https://127.0.0.1:{}/api/relay/v1/proof", server.port);
        let proof_task = tokio::spawn(async move {
            for nonce in 0..40 {
                let response = browser()
                    .post(&proof_url)
                    .body(challenge_body([nonce; 32]))
                    .send()
                    .await
                    .unwrap();
                assert!(matches!(
                    response.status(),
                    StatusCode::OK | StatusCode::SERVICE_UNAVAILABLE
                ));
            }
        });

        std::thread::scope(|scope| {
            for _ in 0..4 {
                let handle = &server.handle;
                scope.spawn(move || {
                    for _ in 0..40 {
                        let identity = RelayIdentity::generate();
                        let relay_id = identity.relay_id().unwrap();
                        let mut private_key_pem = private_key_pem_bytes(&identity);
                        assert_eq!(
                            handle.install_relay_signer(&mut private_key_pem, &relay_id),
                            Ok(relay_id)
                        );
                        assert!(private_key_pem.is_empty());
                        handle.revoke_relay_signer();
                    }
                });
            }
        });

        proof_task.await.unwrap();
        server.stop().await;
    }

    #[tokio::test]
    async fn https_proof_uses_the_actual_installed_certificate_fingerprint() {
        let certificate = generate_self_signed().unwrap();
        let expected_fingerprint = certificate_fingerprint(&certificate);
        let signer = Arc::new(CountingSigner::new(false));
        let server = start_server(Some(tls_config(&certificate)), Some(signer.clone())).await;
        let nonce = [0x12; 32];

        let response = browser()
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/proof",
                server.port
            ))
            .body(challenge_body(nonce))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let dto: RelayProofV1Dto = serde_json::from_str(&response.text().await.unwrap()).unwrap();
        let proof = dto.proof();
        assert_eq!(proof.role, RelayProofRole::Server);
        assert_eq!(proof.nonce, nonce);
        assert!(
            verify_relay_identity_proof(proof, RelayProofRole::Server, expected_fingerprint)
                .is_ok()
        );
        assert!(verify_relay_identity_proof(proof, RelayProofRole::Server, [0x55; 32]).is_err());
        assert_eq!(
            *signer.observed_fingerprint.lock().unwrap(),
            Some(expected_fingerprint)
        );
        server.stop().await;
    }

    #[tokio::test]
    async fn plain_http_proof_route_is_not_found() {
        let signer = Arc::new(CountingSigner::new(false));
        let server = start_server(None, Some(signer.clone())).await;

        let response = browser()
            .post(format!(
                "http://127.0.0.1:{}/api/relay/v1/proof",
                server.port
            ))
            .body(challenge_body([0x01; 32]))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert_eq!(signer.calls.load(Ordering::SeqCst), 0);
        server.stop().await;
    }

    #[tokio::test]
    async fn https_proof_without_signer_is_unavailable() {
        let certificate = generate_self_signed().unwrap();
        let server = start_server(Some(tls_config(&certificate)), None).await;

        let response = browser()
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/proof",
                server.port
            ))
            .body(challenge_body([0x02; 32]))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        server.stop().await;
    }

    #[tokio::test]
    async fn malformed_and_oversized_requests_do_not_reach_the_signer() {
        let certificate = generate_self_signed().unwrap();
        let signer = Arc::new(CountingSigner::new(false));
        let server = start_server(Some(tls_config(&certificate)), Some(signer.clone())).await;
        let url = format!("https://127.0.0.1:{}/api/relay/v1/proof", server.port);

        for body in [
            "{".to_owned(),
            r#"{"version":2,"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"#.to_owned(),
            r#"{"version":1,"nonce":"%%%"}"#.to_owned(),
            format!(
                r#"{{"version":1,"nonce":"{}"}}"#,
                crate::util::base64::encode([1; 31])
            ),
            format!(
                r#"{{"version":1,"nonce":"{}"}}"#,
                crate::util::base64::encode([1; 33])
            ),
            "x".repeat(MAX_PROOF_REQUEST_BODY_BYTES + 1),
        ] {
            let response = browser().post(&url).body(body).send().await.unwrap();
            assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        }
        assert_eq!(signer.calls.load(Ordering::SeqCst), 0);
        server.stop().await;
    }

    #[tokio::test]
    async fn signer_failure_has_a_generic_unavailable_response() {
        let certificate = generate_self_signed().unwrap();
        let signer = Arc::new(CountingSigner::new(true));
        let server = start_server(Some(tls_config(&certificate)), Some(signer.clone())).await;

        let response = browser()
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/proof",
                server.port
            ))
            .body(challenge_body([0x03; 32]))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(response.text().await.unwrap().is_empty());
        assert_eq!(signer.calls.load(Ordering::SeqCst), 1);
        server.stop().await;
    }
}
