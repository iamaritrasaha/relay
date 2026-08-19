use bytes::Bytes;
use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::{Request, Response, StatusCode};

use crate::crypto::nonce::generate_nonce_32;
use crate::http::dto_relay::{
    RelayChallengeV1Dto, RelayPairChallengeRequestV1Dto, RelayPairChallengeResponseV1Dto,
    RelayPairCompleteRequestV1Dto, RelayPairCompleteResponseV1Dto, RelayProofV1Dto,
};
use crate::http::server::common::response::{self, BoxedBody, JsonResponse};
use crate::http::server::v2::ServerEventV2;
use crate::http::server::{AppState, ConnectionTlsCtx, PendingPairChallenge, RequestClientInfo};
use crate::relay::{
    sanitize_pairing_alias, verification_code, PathDescriptor, RelayAuthCoordinator, RelayId,
    RelayPairingDecision,
};

const MAX_PROOF_REQUEST_BODY_BYTES: usize = 256;
/// Bounds the pairing bodies: a fixed-length proof plus a bounded alias.
const MAX_PAIR_REQUEST_BODY_BYTES: usize = 1024;
/// A challenge is single-use and short-lived, so a captured one is worthless.
const PAIR_CHALLENGE_TTL: std::time::Duration = std::time::Duration::from_secs(60);
/// How long the initiator's request waits for the remote user to answer.
const PAIR_DECISION_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(180);

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

/// Issues a single-use pairing nonce for this exact mTLS connection.
///
/// The nonce is keyed by the verified client certificate, so it can only be
/// spent by the device that presented that certificate — an IP, an alias or a
/// claimed RelayId cannot reach it.
pub(crate) async fn pair_challenge(
    req: Request<Incoming>,
    state: AppState,
) -> Result<Response<BoxedBody>, crate::http::server::common::error::AppError> {
    let Some(peer_cert_fingerprint) = pairing_peer_fingerprint(&req) else {
        return Ok(status_response(StatusCode::NOT_FOUND));
    };
    // Without an installed Relay identity this device has nothing to pair with,
    // and must not pretend otherwise.
    if local_relay_id(&state).is_none() {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    }

    let payload: RelayPairChallengeRequestV1Dto = parse_pair_body(req).await?;
    let server_nonce = generate_nonce_32();
    state.relay_pair.challenges.lock().await.put(
        peer_cert_fingerprint,
        PendingPairChallenge {
            server_nonce,
            client_nonce: *payload.client_nonce(),
            issued_at: std::time::Instant::now(),
        },
    );

    Ok(JsonResponse {
        status: StatusCode::OK,
        body: RelayPairChallengeResponseV1Dto::new(server_nonce),
    }
    .into_response())
}

/// Verifies the initiator's Client-role proof and asks this device's user.
///
/// Everything before the prompt is cryptography; everything after it is the
/// user's decision. Neither substitutes for the other: a valid proof with a
/// declined prompt creates no relationship, and there is no path to the prompt
/// without a valid proof.
pub(crate) async fn pair_complete(
    req: Request<Incoming>,
    state: AppState,
    client_info: RequestClientInfo,
) -> Result<Response<BoxedBody>, crate::http::server::common::error::AppError> {
    let Some(peer_cert_fingerprint) = pairing_peer_fingerprint(&req) else {
        return Ok(status_response(StatusCode::NOT_FOUND));
    };
    let Some(local_relay_id) = local_relay_id(&state) else {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    };
    let Some(v2) = state.v2.clone() else {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    };

    let payload: RelayPairCompleteRequestV1Dto = parse_pair_body(req).await?;

    // Single use: the challenge is removed whether or not the proof verifies,
    // so a failed attempt cannot be retried against the same nonce.
    let challenge = state
        .relay_pair
        .challenges
        .lock()
        .await
        .pop(&peer_cert_fingerprint);
    let Some(challenge) = challenge.filter(|entry| entry.issued_at.elapsed() <= PAIR_CHALLENGE_TTL)
    else {
        return Ok(status_response(StatusCode::BAD_REQUEST));
    };

    let Ok(local_relay_id) = RelayId::from_expected_canonical_hex(&local_relay_id) else {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    };
    let coordinator = RelayAuthCoordinator::new(local_relay_id.clone());
    let session = match coordinator.complete_lan_responder(
        payload.proof(),
        peer_cert_fingerprint,
        &challenge.server_nonce,
        None,
        PathDescriptor::lan(
            client_info
                .peer_ip()
                .map_or_else(String::new, |ip| ip.to_string()),
            None,
        ),
    ) {
        Ok(session) => session,
        Err(err) => {
            tracing::warn!(?err, "Relay LAN pairing proof rejected");
            return Ok(status_response(StatusCode::FORBIDDEN));
        }
    };

    // One prompt at a time. A second device asking while the user is deciding
    // is told to try again rather than silently queued behind the first.
    let Ok(_prompt) = state.relay_pair.prompt.try_lock() else {
        return Ok(status_response(StatusCode::CONFLICT));
    };

    let code = verification_code(
        &challenge.server_nonce,
        &challenge.client_nonce,
        &local_relay_id,
        session.remote_relay_id(),
    );
    let (decision_tx, decision_rx) = tokio::sync::oneshot::channel();
    if v2
        .event_tx
        .send(ServerEventV2::RelayPairRequest {
            relay_id: session.remote_relay_id().as_hex(),
            alias: sanitize_pairing_alias(payload.alias()),
            ip: client_info.peer_ip(),
            verification_code: code,
            decision_tx,
        })
        .await
        .is_err()
    {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    }

    // A dropped responder, a closed application, or a user who never answers
    // all resolve to "declined": pairing is never completed by inaction.
    let decision = match tokio::time::timeout(PAIR_DECISION_TIMEOUT, decision_rx).await {
        Ok(Ok(decision)) => decision,
        Ok(Err(_)) | Err(_) => RelayPairingDecision::Declined,
    };

    let body = if decision.is_accepted() {
        RelayPairCompleteResponseV1Dto::accepted(state.info.lock().await.alias.clone())
    } else {
        RelayPairCompleteResponseV1Dto::declined()
    };
    Ok(JsonResponse {
        status: StatusCode::OK,
        body,
    }
    .into_response())
}

/// The verified client-certificate fingerprint, or `None` when the connection
/// cannot carry a Relay pairing at all (plain HTTP, or a browser that presented
/// no client certificate).
fn pairing_peer_fingerprint(req: &Request<Incoming>) -> Option<[u8; 32]> {
    req.extensions()
        .get::<ConnectionTlsCtx>()
        .and_then(|context| context.peer_cert_fingerprint)
}

fn local_relay_id(state: &AppState) -> Option<String> {
    let signer = state.relay_proof.signer.read().ok()?.clone()?;
    Some(signer.local_relay_id().to_owned())
}

async fn parse_pair_body<T: serde::de::DeserializeOwned>(
    req: Request<Incoming>,
) -> Result<T, crate::http::server::common::error::AppError> {
    if let Some(content_length) = req.headers().get(hyper::header::CONTENT_LENGTH) {
        let content_length = content_length
            .to_str()
            .ok()
            .and_then(|value| value.parse::<usize>().ok());
        if content_length.is_none_or(|length| length > MAX_PAIR_REQUEST_BODY_BYTES) {
            return Err(bad_request());
        }
    }

    let bytes = collect_bounded_to(req.into_body(), MAX_PAIR_REQUEST_BODY_BYTES).await?;
    serde_json::from_slice(&bytes).map_err(|_| bad_request())
}

async fn collect_bounded_to(
    mut body: Incoming,
    limit: usize,
) -> Result<Bytes, crate::http::server::common::error::AppError> {
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| bad_request())?;
        if let Some(data) = frame.data_ref() {
            if bytes.len() + data.len() > limit {
                return Err(bad_request());
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(Bytes::from(bytes))
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

    pub(super) struct CountingSigner {
        identity: RelayIdentity,
        relay_id: String,
        calls: AtomicUsize,
        fail: bool,
        observed_fingerprint: std::sync::Mutex<Option<[u8; 32]>>,
    }

    impl CountingSigner {
        pub(super) fn new(fail: bool) -> Self {
            let identity = RelayIdentity::generate();
            let relay_id = identity.relay_id().unwrap();
            Self {
                identity,
                relay_id,
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

        fn local_relay_id(&self) -> &str {
            &self.relay_id
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

/// End-to-end coverage of the mutual LAN pairing handshake.
///
/// These run a real TLS server and a real pinned client, so every assertion is
/// about what actually crosses the socket rather than about an in-process
/// shortcut.
#[cfg(test)]
mod pairing_tests {
    use std::sync::Arc;

    use tokio::sync::{mpsc, oneshot};

    use crate::crypto::cert::{generate_self_signed, SelfSignedCert};
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::http::client::{pair_relay_lan_device, LsHttpClientVersion};
    use crate::http::dto_relay::{
        RelayPairChallengeRequestV1Dto, RelayPairChallengeResponseV1Dto,
        RelayPairCompleteRequestV1Dto,
    };
    use crate::http::server::v2::ServerEventV2;
    use crate::http::server::{
        start_with_port_with_relay_proof_signer, ServerConfigV2, ServerHandle, TlsConfig,
    };
    use crate::http::state::ClientInfo;
    use crate::model::discovery::ProtocolType;
    use crate::relay::{RelayLanPairingOutcome, RelayPairingDecision, RelayProofSigner};
    use hyper::StatusCode;

    use super::tests::CountingSigner;

    struct PairingServer {
        port: u16,
        certificate_fingerprint: String,
        relay_id: String,
        stop_tx: oneshot::Sender<()>,
        handle: ServerHandle,
    }

    impl PairingServer {
        async fn stop(self) {
            let _ = self.stop_tx.send(());
            self.handle.wait_stopped().await;
        }
    }

    fn tls_config(certificate: &SelfSignedCert) -> TlsConfig {
        TlsConfig {
            cert: certificate.certificate_pem.clone(),
            private_key: certificate.private_key_pem.clone(),
        }
    }

    fn fingerprint_hex(certificate: &SelfSignedCert) -> String {
        use rustls::pki_types::pem::PemObject as _;

        let der = rustls::pki_types::CertificateDer::from_pem_slice(
            certificate.certificate_pem.as_bytes(),
        )
        .unwrap();
        crate::crypto::cert::fingerprint_from_cert_der(der.as_ref())
    }

    async fn start_pairing_server() -> (PairingServer, mpsc::Receiver<ServerEventV2>) {
        start_pairing_server_with_web(false).await
    }

    /// `serve_web` mirrors production: serving the browser pages downgrades
    /// client certificates to optional, which is exactly the configuration in
    /// which a certificate-less peer can reach the router at all.
    async fn start_pairing_server_with_web(
        serve_web: bool,
    ) -> (PairingServer, mpsc::Receiver<ServerEventV2>) {
        let certificate = generate_self_signed().unwrap();
        let signer = Arc::new(CountingSigner::new(false));
        let relay_id = signer.local_relay_id().to_owned();
        let (event_tx, event_rx) = mpsc::channel(8);
        let (stop_tx, stop_rx) = oneshot::channel();
        let handle = start_with_port_with_relay_proof_signer(
            0,
            Some(tls_config(&certificate)),
            ClientInfo {
                alias: "Workstation".to_owned(),
                version: "2.2".to_owned(),
                device_model: None,
                device_type: None,
                token: "test".to_owned(),
            },
            None,
            Some(ServerConfigV2 {
                pin: None,
                verify_checksums: false,
                event_tx,
            }),
            serve_web.then(|| crate::http::server::web::WebConfig {
                send: None,
                upload: true,
                i18n: crate::http::server::web::WebI18n::default(),
            }),
            Some(signer as Arc<dyn RelayProofSigner>),
            stop_rx,
        )
        .await
        .unwrap();

        (
            PairingServer {
                port: handle.port(),
                certificate_fingerprint: fingerprint_hex(&certificate),
                relay_id,
                stop_tx,
                handle,
            },
            event_rx,
        )
    }

    /// Answers the next pairing prompt the way a user would, and reports what
    /// the prompt actually said.
    fn answer_next_prompt(
        mut events: mpsc::Receiver<ServerEventV2>,
        decision: RelayPairingDecision,
    ) -> tokio::task::JoinHandle<Option<(String, String, String)>> {
        tokio::spawn(async move {
            while let Some(event) = events.recv().await {
                if let ServerEventV2::RelayPairRequest {
                    relay_id,
                    alias,
                    verification_code,
                    decision_tx,
                    ..
                } = event
                {
                    let _ = decision_tx.send(decision);
                    return Some((relay_id, alias, verification_code));
                }
            }
            None
        })
    }

    struct Initiator {
        certificate: SelfSignedCert,
        identity: RelayIdentity,
    }

    impl Initiator {
        fn new() -> Self {
            Self {
                certificate: generate_self_signed().unwrap(),
                identity: RelayIdentity::generate(),
            }
        }

        fn relay_id(&self) -> String {
            self.identity.relay_id().unwrap()
        }

        async fn pair(
            &self,
            server: &PairingServer,
            alias: &str,
            expected: Option<&crate::relay::RelayId>,
        ) -> (
            RelayLanPairingOutcome,
            Vec<crate::http::client::relay::RelayLanPairingEvent>,
        ) {
            let (tx, mut rx) = mpsc::channel(8);
            let outcome = pair_relay_lan_device(
                &self.certificate.private_key_pem,
                &self.certificate.certificate_pem,
                LsHttpClientVersion::V2,
                ProtocolType::Https,
                "127.0.0.1",
                server.port,
                &server.certificate_fingerprint,
                &self.identity,
                alias,
                expected,
                &tx,
            )
            .await;
            drop(tx);

            let mut events = Vec::new();
            while let Some(event) = rx.recv().await {
                events.push(event);
            }
            (outcome, events)
        }
    }

    #[tokio::test]
    async fn mutual_proof_pairs_both_devices_on_the_same_proven_identities_and_code() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);
        let initiator = Initiator::new();

        let (outcome, stream) = initiator.pair(&server, "Redmi", None).await;

        let (prompted_relay_id, prompted_alias, prompted_code) =
            prompt.await.unwrap().expect("a pairing prompt");
        // The responder was told who the initiator is by the proof, not by the
        // payload: the alias travels separately and does not key anything.
        assert_eq!(prompted_relay_id, initiator.relay_id());
        assert_eq!(prompted_alias, "Redmi");

        match outcome {
            RelayLanPairingOutcome::Paired {
                remote_relay_id,
                remote_alias,
                verification_code,
            } => {
                assert_eq!(remote_relay_id, server.relay_id);
                assert_eq!(remote_alias, "Workstation");
                // Both users are shown the same number, derived independently.
                assert_eq!(verification_code, prompted_code);
                assert_eq!(verification_code.len(), 6);
            }
            other => panic!("expected a completed pairing, got {other:?}"),
        }

        // The code is published before the remote user is asked, so the two
        // people can actually compare it.
        assert!(matches!(
            stream.first(),
            Some(crate::http::client::relay::RelayLanPairingEvent::VerificationCode { .. })
        ));
        server.stop().await;
    }

    #[tokio::test]
    async fn a_rejected_pairing_leaves_no_relationship() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Declined);
        let initiator = Initiator::new();

        let (outcome, _) = initiator.pair(&server, "Redmi", None).await;

        assert!(prompt.await.unwrap().is_some());
        // Declined is its own outcome: there is no partial pairing the caller
        // could mistake for success.
        assert_eq!(outcome, RelayLanPairingOutcome::Declined);
        server.stop().await;
    }

    #[tokio::test]
    async fn pairing_without_any_remote_answer_never_completes() {
        let (server, mut events) = start_pairing_server().await;
        // Drop the responder without answering: the user walked away.
        let dropped = tokio::spawn(async move {
            let event = events.recv().await;
            drop(event);
            drop(events);
        });
        let initiator = Initiator::new();

        let (outcome, _) = initiator.pair(&server, "Redmi", None).await;

        dropped.await.unwrap();
        assert_eq!(outcome, RelayLanPairingOutcome::Declined);
        server.stop().await;
    }

    #[tokio::test]
    async fn a_different_expected_relay_id_fails_before_anybody_is_prompted() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);
        let initiator = Initiator::new();
        let someone_else =
            crate::relay::RelayId::from_local_identity(&RelayIdentity::generate()).unwrap();

        let (outcome, stream) = initiator.pair(&server, "Redmi", Some(&someone_else)).await;

        assert_eq!(outcome, RelayLanPairingOutcome::AuthenticationFailed);
        // Nothing was displayed and nobody was asked: the identity check is
        // ahead of the human step, not behind it.
        assert!(stream.iter().all(|event| matches!(
            event,
            crate::http::client::relay::RelayLanPairingEvent::Outcome(_)
        )));
        server.stop().await;
        assert!(prompt.await.unwrap().is_none());
    }

    fn anonymous_client() -> crate::reqwest::Client {
        crate::reqwest::Client::builder()
            .use_rustls_tls()
            .danger_accept_invalid_certs(true)
            .build()
            .unwrap()
    }

    #[tokio::test]
    async fn a_client_without_a_certificate_never_completes_the_transport() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);

        // With client certificates mandatory, a peer that has none — a browser,
        // a LocalSend-compatible client, anything not running Relay's pairing
        // client — is stopped by the TLS handshake itself.
        let result = anonymous_client()
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/pair/challenge",
                server.port
            ))
            .header("Content-Type", "application/json")
            .body("{}")
            .send()
            .await;

        assert!(result.is_err());
        server.stop().await;
        assert!(prompt.await.unwrap().is_none());
    }

    #[tokio::test]
    async fn a_certificate_less_peer_is_refused_even_when_the_web_pages_are_served() {
        // Serving the browser pages makes client certificates optional, so this
        // is the one configuration where a certificate-less request reaches the
        // router. It still has no way into the Relay pairing path.
        let (server, events) = start_pairing_server_with_web(true).await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);
        let anonymous = anonymous_client();

        for step in ["challenge", "complete"] {
            let response = anonymous
                .post(format!(
                    "https://127.0.0.1:{}/api/relay/v1/pair/{step}",
                    server.port
                ))
                .header("Content-Type", "application/json")
                .body("{}")
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "step {step}");
        }

        server.stop().await;
        assert!(prompt.await.unwrap().is_none());
    }

    /// Raw HTTP access with a real client certificate, for the cases the
    /// well-behaved client never produces.
    fn raw_client(initiator: &Initiator, server: &PairingServer) -> crate::reqwest::Client {
        crate::http::client::create_reqwest_client(
            &initiator.certificate.private_key_pem,
            &initiator.certificate.certificate_pem,
            Some(server.certificate_fingerprint.clone()),
            None,
        )
        .unwrap()
    }

    async fn post_pair(
        client: &crate::reqwest::Client,
        server: &PairingServer,
        step: &str,
        body: String,
    ) -> crate::reqwest::Response {
        client
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/pair/{step}",
                server.port
            ))
            .header("Content-Type", "application/json")
            .body(body)
            .send()
            .await
            .unwrap()
    }

    fn client_proof(
        initiator: &Initiator,
        role: crate::crypto::relay_identity_proof::RelayProofRole,
        nonce: [u8; 32],
    ) -> String {
        use rustls::pki_types::pem::PemObject as _;

        let der = rustls::pki_types::CertificateDer::from_pem_slice(
            initiator.certificate.certificate_pem.as_bytes(),
        )
        .unwrap();
        let fingerprint = crate::crypto::cert::fingerprint_digest_from_cert_der(der.as_ref());
        let proof = crate::crypto::relay_identity_proof::create_relay_identity_proof(
            &initiator.identity,
            role,
            nonce,
            fingerprint,
        )
        .unwrap();
        serde_json::to_string(&RelayPairCompleteRequestV1Dto::new(proof, "Redmi")).unwrap()
    }

    async fn request_challenge(
        client: &crate::reqwest::Client,
        server: &PairingServer,
        client_nonce: [u8; 32],
    ) -> [u8; 32] {
        let body =
            serde_json::to_string(&RelayPairChallengeRequestV1Dto::new(client_nonce)).unwrap();
        let response = post_pair(client, server, "challenge", body).await;
        assert_eq!(response.status(), StatusCode::OK);
        let dto: RelayPairChallengeResponseV1Dto =
            serde_json::from_slice(&response.bytes().await.unwrap()).unwrap();
        *dto.server_nonce()
    }

    #[tokio::test]
    async fn a_proof_over_a_nonce_this_device_never_issued_is_refused() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);
        let initiator = Initiator::new();
        let client = raw_client(&initiator, &server);

        let response = post_pair(
            &client,
            &server,
            "complete",
            client_proof(
                &initiator,
                crate::crypto::relay_identity_proof::RelayProofRole::Client,
                [0x5A; 32],
            ),
        )
        .await;

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        server.stop().await;
        assert!(prompt.await.unwrap().is_none());
    }

    #[tokio::test]
    async fn a_challenge_is_single_use() {
        let (server, mut events) = start_pairing_server().await;
        let accepted = tokio::spawn(async move {
            let mut prompts = 0_usize;
            while let Some(event) = events.recv().await {
                if let ServerEventV2::RelayPairRequest { decision_tx, .. } = event {
                    prompts += 1;
                    let _ = decision_tx.send(RelayPairingDecision::Accepted);
                }
            }
            prompts
        });
        let initiator = Initiator::new();
        let client = raw_client(&initiator, &server);

        let server_nonce = request_challenge(&client, &server, [0x01; 32]).await;
        let body = client_proof(
            &initiator,
            crate::crypto::relay_identity_proof::RelayProofRole::Client,
            server_nonce,
        );

        let first = post_pair(&client, &server, "complete", body.clone()).await;
        assert_eq!(first.status(), StatusCode::OK);
        let replayed = post_pair(&client, &server, "complete", body).await;
        assert_eq!(replayed.status(), StatusCode::BAD_REQUEST);

        server.stop().await;
        assert_eq!(accepted.await.unwrap(), 1);
    }

    #[tokio::test]
    async fn a_server_role_proof_cannot_stand_in_for_the_client_role_proof() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);
        let initiator = Initiator::new();
        let client = raw_client(&initiator, &server);

        let server_nonce = request_challenge(&client, &server, [0x01; 32]).await;
        let response = post_pair(
            &client,
            &server,
            "complete",
            client_proof(
                &initiator,
                crate::crypto::relay_identity_proof::RelayProofRole::Server,
                server_nonce,
            ),
        )
        .await;

        assert_eq!(response.status(), StatusCode::FORBIDDEN);
        server.stop().await;
        assert!(prompt.await.unwrap().is_none());
    }

    #[tokio::test]
    async fn a_challenge_belongs_to_the_certificate_it_was_issued_to() {
        let (server, events) = start_pairing_server().await;
        let prompt = answer_next_prompt(events, RelayPairingDecision::Accepted);
        let holder = Initiator::new();
        let impostor = Initiator::new();

        let server_nonce =
            request_challenge(&raw_client(&holder, &server), &server, [0x01; 32]).await;
        // A second device that observed the nonce still cannot spend it: the
        // challenge is filed under the client certificate, and this one is
        // presenting a different certificate.
        let response = post_pair(
            &raw_client(&impostor, &server),
            &server,
            "complete",
            client_proof(
                &impostor,
                crate::crypto::relay_identity_proof::RelayProofRole::Client,
                server_nonce,
            ),
        )
        .await;

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        server.stop().await;
        assert!(prompt.await.unwrap().is_none());
    }
}
