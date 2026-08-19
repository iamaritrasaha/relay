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

/// The protocol token the local continuity upgrade negotiates. It is distinct
/// from the Anywhere continuity ALPN and from every LocalSend route.
pub const RELAY_CONTINUITY_PROTOCOL: &str = "relay-continuity/1";

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

/// The Relay-only local continuity entry point.
///
/// `POST /api/relay/v1/continuity` upgrades the connection to
/// [`RELAY_CONTINUITY_PROTOCOL`] and then runs the same mutual
/// `RelayIdentityProofV1` exchange the Anywhere transport uses, bound to the
/// certificates of *this* TLS connection. What comes out is an
/// [`crate::relay::AuthenticatedRelaySession`] over a duplex stream — exactly
/// what `continuity::run_session` already takes, so no continuity protocol,
/// authorization layer or session state machine is duplicated here.
///
/// Three things make this structurally unreachable for compatibility traffic:
/// the route lives under `/api/relay/v1`, it requires a client certificate the
/// mTLS handshake verified, and it requires a Relay identity proof afterwards.
/// A LocalSend peer has none of the three, and the v2 routes never reach here.
#[cfg(feature = "anywhere")]
pub(crate) async fn continuity(
    mut req: Request<Incoming>,
    state: AppState,
    client_info: RequestClientInfo,
) -> Result<Response<BoxedBody>, crate::http::server::common::error::AppError> {
    let Some(tls_context) = req.extensions().get::<ConnectionTlsCtx>().cloned() else {
        return Ok(status_response(StatusCode::NOT_FOUND));
    };
    // No verified client certificate means no identity to bind a Client-role
    // proof to, so there is nothing this endpoint could safely do.
    let Some(peer_cert_fingerprint) = tls_context.peer_cert_fingerprint else {
        return Ok(status_response(StatusCode::NOT_FOUND));
    };
    if !requests_continuity_upgrade(&req) {
        return Ok(status_response(StatusCode::BAD_REQUEST));
    }
    // Absent while the user has enabled nothing: this device does not serve
    // continuity at all rather than serving it and then refusing.
    let Some(accept) = state.relay_continuity.config() else {
        return Ok(status_response(StatusCode::SERVICE_UNAVAILABLE));
    };

    let path = PathDescriptor::lan(
        client_info
            .peer_ip()
            .map_or_else(String::new, |ip| ip.to_string()),
        None,
    );
    let on_upgrade = hyper::upgrade::on(&mut req);

    tokio::spawn(async move {
        let upgraded = match on_upgrade.await {
            Ok(upgraded) => upgraded,
            Err(err) => {
                tracing::warn!(?err, "Relay continuity upgrade failed");
                return;
            }
        };
        let mut stream = hyper_util::rt::TokioIo::new(upgraded);

        // No expected remote: the responder learns who called, and the
        // continuity session's own trust and capability gates decide whether
        // that proven identity may do anything.
        match crate::anywhere::authenticate_server(
            &mut stream,
            &accept.identity,
            tls_context.relay.own_tls_fingerprint(),
            None,
            peer_cert_fingerprint,
            path,
        )
        .await
        {
            Ok(session) => {
                let _ = accept
                    .inbound
                    .send(crate::http::server::RelayLanContinuityInbound { session, stream })
                    .await;
            }
            Err(err) => {
                tracing::warn!("Relay continuity proof rejected: {}", err.category());
            }
        }
    });

    let mut response = Response::new(response::empty_body());
    *response.status_mut() = StatusCode::SWITCHING_PROTOCOLS;
    response.headers_mut().insert(
        hyper::header::UPGRADE,
        hyper::header::HeaderValue::from_static(RELAY_CONTINUITY_PROTOCOL),
    );
    response.headers_mut().insert(
        hyper::header::CONNECTION,
        hyper::header::HeaderValue::from_static("upgrade"),
    );
    Ok(response)
}

/// Whether the request asks for exactly the Relay continuity protocol.
///
/// A request naming any other protocol is refused rather than upgraded, so this
/// endpoint cannot be turned into a generic tunnel.
#[cfg(feature = "anywhere")]
fn requests_continuity_upgrade(req: &Request<Incoming>) -> bool {
    let names_protocol = req
        .headers()
        .get(hyper::header::UPGRADE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.trim().eq_ignore_ascii_case(RELAY_CONTINUITY_PROTOCOL));
    let asks_to_upgrade = req
        .headers()
        .get(hyper::header::CONNECTION)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| {
            value
                .split(',')
                .any(|token| token.trim().eq_ignore_ascii_case("upgrade"))
        });
    names_protocol && asks_to_upgrade
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
pub(crate) mod tests {
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

    pub(crate) struct CountingSigner {
        identity: RelayIdentity,
        relay_id: String,
        calls: AtomicUsize,
        fail: bool,
        observed_fingerprint: std::sync::Mutex<Option<[u8; 32]>>,
    }

    impl CountingSigner {
        pub(crate) fn new(fail: bool) -> Self {
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

/// End-to-end coverage of the Relay-only local continuity transport.
///
/// These run a real TLS server, a real pinned client, a real HTTP upgrade and
/// the real mutual proof, then run the real continuity session loop on both
/// ends. Nothing here is simulated except the two devices being one process.
#[cfg(all(test, feature = "anywhere"))]
mod lan_continuity_tests {
    use std::sync::{Arc, Mutex};

    use tokio::sync::{mpsc, oneshot, RwLock};
    use tokio_util::sync::CancellationToken;

    use crate::continuity::{
        capability_entry, clipboard_fingerprint, run_session, session_channel, BatteryState,
        CapabilityManifest, CapabilityState, ChargingState, ClipboardMode, ClipboardUpdate,
        ContinuityCapability, ContinuityEvent, ContinuityEventSink, ContinuityHostRequest,
        ContinuityPayload, ContinuityPermissions, ContinuitySessionConfig, ContinuitySessionEnd,
        ContinuitySessionHandle, DevicePlatform,
    };
    use crate::crypto::cert::{generate_self_signed, SelfSignedCert};
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::http::client::{connect_relay_lan_continuity, LsHttpClientVersion};
    use crate::http::server::v2::ServerEventV2;
    use crate::http::server::{
        start_with_port_with_relay_proof_signer, RelayContinuityAcceptConfig,
        RelayLanContinuityInbound, ServerConfigV2, ServerHandle, TlsConfig,
    };
    use crate::http::state::ClientInfo;
    use crate::model::discovery::ProtocolType;
    use crate::relay::{
        AuthenticatedRelaySession, DeviceBinding, MemoryTrustDirectory, PathDescriptor, RelayId,
        SessionRole, TrustDirectory,
    };
    use hyper::StatusCode;

    use super::super::relay::tests::CountingSigner;
    use crate::relay::RelayProofSigner;

    // ------------------------------------------------------------ harness

    struct LocalDevice {
        port: u16,
        certificate_fingerprint: String,
        identity: RelayIdentity,
        inbound: mpsc::Receiver<RelayLanContinuityInbound>,
        stop_tx: oneshot::Sender<()>,
        handle: ServerHandle,
    }

    impl LocalDevice {
        fn relay_id(&self) -> RelayId {
            RelayId::from_local_identity(&self.identity).unwrap()
        }

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

    /// Starts a device that serves local continuity, i.e. one whose user has
    /// enabled something. `serving` false models a device with nothing enabled.
    async fn start_device(serving: bool) -> LocalDevice {
        let certificate = generate_self_signed().unwrap();
        let identity = RelayIdentity::generate();
        let signer = Arc::new(CountingSigner::new(false));
        let (event_tx, _event_rx) = mpsc::channel(8);
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
            None,
            Some(signer as Arc<dyn RelayProofSigner>),
            stop_rx,
        )
        .await
        .unwrap();

        let (inbound_tx, inbound) = mpsc::channel(4);
        if serving {
            assert!(
                handle.install_relay_continuity_acceptor(RelayContinuityAcceptConfig {
                    identity: RelayIdentity::from_private_key(
                        identity.private_key_export().unwrap().as_str()
                    )
                    .unwrap(),
                    inbound: inbound_tx,
                })
            );
        }

        LocalDevice {
            port: handle.port(),
            certificate_fingerprint: fingerprint_hex(&certificate),
            identity,
            inbound,
            stop_tx,
            handle,
        }
    }

    /// The initiating device: its own Relay identity plus its own LAN client
    /// certificate, exactly as the app holds them.
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

        fn relay_id(&self) -> RelayId {
            RelayId::from_local_identity(&self.identity).unwrap()
        }

        async fn connect(
            &self,
            device: &LocalDevice,
            expected: &RelayId,
        ) -> Result<
            crate::http::client::relay::RelayLanContinuityConnection,
            crate::http::client::relay::RelayLanContinuityError,
        > {
            connect_relay_lan_continuity(
                &self.certificate.private_key_pem,
                &self.certificate.certificate_pem,
                LsHttpClientVersion::V2,
                ProtocolType::Https,
                "127.0.0.1",
                device.port,
                &device.certificate_fingerprint,
                &self.identity,
                expected,
            )
            .await
        }
    }

    // ------------------------------------------------- continuity plumbing

    struct Peer {
        handle: ContinuitySessionHandle,
        events: Arc<Mutex<Vec<ContinuityEvent>>>,
        task: tokio::task::JoinHandle<ContinuitySessionEnd>,
    }

    fn manifest(label: &str, platform: DevicePlatform) -> CapabilityManifest {
        CapabilityManifest {
            device_label: label.to_owned(),
            platform,
            entries: vec![
                capability_entry(ContinuityCapability::Battery, CapabilityState::Available),
                capability_entry(ContinuityCapability::Clipboard, CapabilityState::Available),
            ],
        }
    }

    fn trusting(remote: &RelayId) -> Arc<dyn TrustDirectory + Send + Sync> {
        let mut directory = MemoryTrustDirectory::new();
        directory.insert(DeviceBinding::new(
            "binding-1",
            remote.clone(),
            "Peer",
            true,
            false,
        ));
        Arc::new(directory)
    }

    fn untrusting() -> Arc<dyn TrustDirectory + Send + Sync> {
        Arc::new(MemoryTrustDirectory::new())
    }

    fn granting(remote_hex: &str) -> ContinuityPermissions {
        let mut permissions = ContinuityPermissions::new();
        for capability in [
            ContinuityCapability::Battery,
            ContinuityCapability::Clipboard,
        ] {
            permissions.set_grant(
                remote_hex,
                capability,
                crate::continuity::CapabilityGrant::Granted,
            );
        }
        permissions.set_clipboard_mode(remote_hex, ClipboardMode::Automatic);
        permissions
    }

    fn spawn_peer<S>(
        stream: S,
        session: AuthenticatedRelaySession,
        label: &str,
        platform: DevicePlatform,
        trust: Arc<dyn TrustDirectory + Send + Sync>,
        permissions: ContinuityPermissions,
        cancel: CancellationToken,
    ) -> Peer
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let events: Arc<Mutex<Vec<ContinuityEvent>>> = Arc::new(Mutex::new(Vec::new()));
        let sink: ContinuityEventSink = {
            let events = events.clone();
            Arc::new(move |event| events.lock().unwrap().push(event))
        };
        let (host_tx, host_rx) = mpsc::channel::<ContinuityHostRequest>(16);
        // Nothing in these tests answers host requests; draining keeps the
        // session from blocking on a full channel.
        tokio::spawn(async move {
            let mut host_rx = host_rx;
            while host_rx.recv().await.is_some() {}
        });
        let (handle, outbound) = session_channel(&session.remote_relay_id().as_hex(), 32);
        let config = ContinuitySessionConfig {
            local_manifest: manifest(label, platform),
            trust,
            permissions: Arc::new(RwLock::new(permissions)),
            events: sink,
            host: host_tx,
        };
        let task = tokio::spawn(run_session(stream, session, config, outbound, cancel));
        Peer {
            handle,
            events,
            task,
        }
    }

    async fn wait_for<T>(
        events: &Arc<Mutex<Vec<ContinuityEvent>>>,
        mut predicate: impl FnMut(&ContinuityEvent) -> Option<T>,
    ) -> T {
        for _ in 0..400 {
            if let Some(found) = events.lock().unwrap().iter().find_map(&mut predicate) {
                return found;
            }
            tokio::time::sleep(std::time::Duration::from_millis(5)).await;
        }
        panic!("expected continuity event never arrived");
    }

    // ------------------------------------------------------ entry gating

    #[tokio::test]
    async fn a_peer_without_a_certificate_cannot_reach_the_continuity_entry() {
        let device = start_device(true).await;
        // A LocalSend-compatible peer, a browser, anything that is not running
        // Relay's client: no client certificate, so the mTLS handshake itself
        // ends the attempt.
        let anonymous = crate::reqwest::Client::builder()
            .use_rustls_tls()
            .danger_accept_invalid_certs(true)
            .build()
            .unwrap();

        let result = anonymous
            .post(format!(
                "https://127.0.0.1:{}/api/relay/v1/continuity",
                device.port
            ))
            .header("Connection", "upgrade")
            .header("Upgrade", super::RELAY_CONTINUITY_PROTOCOL)
            .send()
            .await;

        assert!(result.is_err());
        device.stop().await;
    }

    #[tokio::test]
    async fn a_device_with_nothing_enabled_does_not_serve_local_continuity() {
        let device = start_device(false).await;
        let initiator = Initiator::new();

        let error = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap_err();

        assert_eq!(
            error,
            crate::http::client::relay::RelayLanContinuityError::Unsupported
        );
        device.stop().await;
    }

    #[tokio::test]
    async fn a_request_that_does_not_ask_for_the_relay_protocol_is_refused() {
        let device = start_device(true).await;
        let initiator = Initiator::new();
        let client = crate::http::client::create_reqwest_client(
            &initiator.certificate.private_key_pem,
            &initiator.certificate.certificate_pem,
            Some(device.certificate_fingerprint.clone()),
            None,
        )
        .unwrap();

        // A plain POST, and an upgrade naming somebody else's protocol.
        for headers in [
            vec![],
            vec![("Connection", "upgrade"), ("Upgrade", "websocket")],
        ] {
            let mut request = client.post(format!(
                "https://127.0.0.1:{}/api/relay/v1/continuity",
                device.port
            ));
            for (name, value) in headers {
                request = request.header(name, value);
            }
            let response = request.send().await.unwrap();
            assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        }

        device.stop().await;
    }

    // -------------------------------------------------------- identity

    #[tokio::test]
    async fn a_mutual_proof_yields_an_authenticated_session_on_both_ends() {
        let device = start_device(true).await;
        let initiator = Initiator::new();

        let connection = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap();
        let inbound = {
            let mut device = device;
            let inbound = device.inbound.recv().await.expect("an inbound session");
            // The responder proved the caller and learned its real identity.
            assert_eq!(inbound.session.remote_relay_id(), &initiator.relay_id());
            assert_eq!(inbound.session.local_relay_id(), &device.relay_id());
            assert_eq!(inbound.session.local_role(), SessionRole::Responder);
            assert!(inbound.session.mutual());
            device.stop().await;
            inbound
        };

        // And the initiator proved the responder is the identity it demanded.
        assert_eq!(
            connection.session.remote_relay_id(),
            inbound.session.local_relay_id()
        );
        assert_eq!(connection.session.local_role(), SessionRole::Initiator);
        assert!(matches!(
            connection.session.path(),
            PathDescriptor::Lan { .. }
        ));
    }

    #[tokio::test]
    async fn a_device_proving_another_identity_is_rejected() {
        let device = start_device(true).await;
        let initiator = Initiator::new();
        let someone_else = RelayId::from_local_identity(&RelayIdentity::generate()).unwrap();

        let error = initiator.connect(&device, &someone_else).await.unwrap_err();

        assert_eq!(
            error,
            crate::http::client::relay::RelayLanContinuityError::AuthenticationFailed
        );
        device.stop().await;
    }

    #[tokio::test]
    async fn every_connection_re_proves_the_peer() {
        let device = start_device(true).await;
        let initiator = Initiator::new();

        // Two separate connections, each with its own nonces and its own proof:
        // being connected once never lets the next connection skip the check.
        let first = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap();
        let second = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap();

        let mut device = device;
        let a = device.inbound.recv().await.unwrap();
        let b = device.inbound.recv().await.unwrap();
        assert_eq!(a.session.remote_relay_id(), &initiator.relay_id());
        assert_eq!(b.session.remote_relay_id(), &initiator.relay_id());
        assert_eq!(
            first.session.remote_relay_id(),
            second.session.remote_relay_id()
        );
        device.stop().await;
    }

    // ------------------------------------------------- capabilities over LAN

    /// Connects two real devices and runs the real session loop on both ends of
    /// the authenticated LAN stream.
    async fn connected_over_lan(
        cancel: &CancellationToken,
        responder_permissions: Option<ContinuityPermissions>,
        initiator_trusts: bool,
    ) -> (Peer, Peer, LocalDevice) {
        let mut device = start_device(true).await;
        let initiator = Initiator::new();
        let connection = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap();
        let inbound = device.inbound.recv().await.expect("an inbound session");

        let responder_remote = inbound.session.remote_relay_id().clone();
        let responder = spawn_peer(
            inbound.stream,
            inbound.session,
            "Workstation",
            DevicePlatform::Linux,
            trusting(&responder_remote),
            responder_permissions.unwrap_or_else(|| granting(&responder_remote.as_hex())),
            cancel.clone(),
        );

        let initiator_remote = connection.session.remote_relay_id().clone();
        let dialer = spawn_peer(
            connection.stream,
            connection.session,
            "Pixel",
            DevicePlatform::Android,
            if initiator_trusts {
                trusting(&initiator_remote)
            } else {
                untrusting()
            },
            granting(&initiator_remote.as_hex()),
            cancel.clone(),
        );

        (dialer, responder, device)
    }

    #[tokio::test]
    async fn battery_state_crosses_the_authenticated_lan_session() {
        let cancel = CancellationToken::new();
        let (phone, computer, device) = connected_over_lan(&cancel, None, true).await;
        // Until the computer has subscribed a push is correctly dropped, so the
        // test waits for the negotiation the session performs on connect.
        wait_for(&phone.events, |event| {
            matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
        })
        .await;

        // The phone publishes what the platform reported; the computer receives
        // it attributed to the proven RelayId, not to an address.
        assert!(
            phone
                .handle
                .publish(ContinuityPayload::Battery(BatteryState {
                    percentage: Some(64),
                    charging: ChargingState::Charging,
                }))
                .await
        );

        let (remote, state) = wait_for(&computer.events, |event| match event {
            ContinuityEvent::BatteryChanged {
                remote_relay_id,
                state,
            } => Some((remote_relay_id.clone(), state.clone())),
            _ => None,
        })
        .await;

        // The computer attributes the reading to the phone's proven RelayId.
        assert_eq!(remote, computer.handle.remote_relay_id().to_owned());
        assert_eq!(state.percentage, Some(64));
        assert_eq!(state.charging, ChargingState::Charging);

        cancel.cancel();
        device.stop().await;
    }

    #[tokio::test]
    async fn clipboard_content_crosses_the_authenticated_lan_session() {
        let cancel = CancellationToken::new();
        let (phone, computer, device) = connected_over_lan(&cancel, None, true).await;
        wait_for(&phone.events, |event| {
            matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
        })
        .await;

        let text = "one time code 482731";
        assert!(
            phone
                .handle
                .publish(ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
                    text: text.to_owned(),
                    content_fingerprint: clipboard_fingerprint(text),
                    origin_relay_id: computer.handle.remote_relay_id().to_owned(),
                    explicit: true,
                }))
                .await
        );

        let update = wait_for(&computer.events, |event| match event {
            ContinuityEvent::ClipboardOffered { update, .. } => Some(update.clone()),
            _ => None,
        })
        .await;

        assert_eq!(update.text, text);
        assert_eq!(update.content_fingerprint, clipboard_fingerprint(text));

        cancel.cancel();
        device.stop().await;
    }

    #[tokio::test]
    async fn clipboard_loop_suppression_survives_the_lan_transport() {
        let cancel = CancellationToken::new();
        let (phone, computer, device) = connected_over_lan(&cancel, None, true).await;
        for events in [&phone.events, &computer.events] {
            wait_for(events, |event| {
                matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
            })
            .await;
        }

        let text = "shared once";
        let fingerprint = clipboard_fingerprint(text);
        phone
            .handle
            .publish(ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
                text: text.to_owned(),
                content_fingerprint: fingerprint.clone(),
                origin_relay_id: computer.handle.remote_relay_id().to_owned(),
                explicit: true,
            }))
            .await;

        wait_for(&computer.events, |event| match event {
            ContinuityEvent::ClipboardOffered { update, .. } if update.text == text => Some(()),
            _ => None,
        })
        .await;

        // The computer echoes the content it just received. The session drops
        // it rather than sending it back, so the two devices cannot ping-pong.
        computer
            .handle
            .publish(ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
                text: text.to_owned(),
                content_fingerprint: fingerprint,
                origin_relay_id: phone.handle.remote_relay_id().to_owned(),
                explicit: false,
            }))
            .await;
        tokio::time::sleep(std::time::Duration::from_millis(120)).await;

        let echoes = phone
            .events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| matches!(event, ContinuityEvent::ClipboardOffered { .. }))
            .count();
        assert_eq!(echoes, 0);

        cancel.cancel();
        device.stop().await;
    }

    // --------------------------------------------------------- gating

    #[tokio::test]
    async fn an_authenticated_but_untrusted_peer_exchanges_nothing() {
        let cancel = CancellationToken::new();
        let mut device = start_device(true).await;
        let initiator = Initiator::new();
        let connection = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap();
        let inbound = device.inbound.recv().await.expect("an inbound session");
        let remote = inbound.session.remote_relay_id().clone();

        // Proven, paired, reachable — and still not trusted. The session ends
        // instead of carrying anything.
        let responder = spawn_peer(
            inbound.stream,
            inbound.session,
            "Workstation",
            DevicePlatform::Linux,
            untrusting(),
            granting(&remote.as_hex()),
            cancel.clone(),
        );

        let end = responder.task.await.unwrap();
        assert_eq!(end, ContinuitySessionEnd::NotTrusted);

        drop(connection);
        cancel.cancel();
        device.stop().await;
    }

    #[tokio::test]
    async fn a_trusted_peer_with_no_capability_granted_shares_nothing() {
        let cancel = CancellationToken::new();
        let mut device = start_device(true).await;
        let initiator = Initiator::new();
        let connection = initiator
            .connect(&device, &device.relay_id())
            .await
            .unwrap();
        let inbound = device.inbound.recv().await.expect("an inbound session");
        let remote = inbound.session.remote_relay_id().clone();

        // Pairing and trust exist; the user enabled nothing.
        let responder = spawn_peer(
            inbound.stream,
            inbound.session,
            "Workstation",
            DevicePlatform::Linux,
            trusting(&remote),
            ContinuityPermissions::new(),
            cancel.clone(),
        );
        let phone_remote = connection.session.remote_relay_id().clone();
        let phone = spawn_peer(
            connection.stream,
            connection.session,
            "Pixel",
            DevicePlatform::Android,
            trusting(&phone_remote),
            ContinuityPermissions::new(),
            cancel.clone(),
        );

        phone
            .handle
            .publish(ContinuityPayload::Battery(BatteryState {
                percentage: Some(64),
                charging: ChargingState::Charging,
            }))
            .await;
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;

        let battery_events = responder
            .events
            .lock()
            .unwrap()
            .iter()
            .filter(|event| matches!(event, ContinuityEvent::BatteryChanged { .. }))
            .count();
        assert_eq!(battery_events, 0);

        cancel.cancel();
        device.stop().await;
    }
}
