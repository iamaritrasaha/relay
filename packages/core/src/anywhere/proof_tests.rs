use super::*;
use crate::crypto::relay_identity::RelayIdentity;
use crate::relay::{PathDescriptor, RelayId, SessionRole, TransferAuthorization, TrustRecord};

async fn mutual_over_duplex() -> (
    crate::relay::AuthenticatedRelaySession,
    crate::relay::AuthenticatedRelaySession,
) {
    let initiator_id = RelayIdentity::generate();
    let responder_id = RelayIdentity::generate();
    let initiator_hex = initiator_id.relay_id().unwrap();
    let responder_hex = responder_id.relay_id().unwrap();
    let initiator_tls = InnerTlsPeer::generate().unwrap();
    let responder_tls = InnerTlsPeer::generate().unwrap();
    let expected = RelayId::from_local_identity(&responder_id).unwrap();
    let path = PathDescriptor::InternetDirect {
        host: String::new(),
        port: None,
    };

    let (mut a, mut b) = tokio::io::duplex(16 * 1024);
    let init_fp = initiator_tls.cert_fingerprint;
    let resp_fp = responder_tls.cert_fingerprint;
    let path_i = path.clone();
    let path_r = path;

    let responder = tokio::spawn(async move {
        authenticate_server(&mut b, &responder_id, resp_fp, None, init_fp, path_r).await
    });
    let initiator_session =
        authenticate_initiator(&mut a, &initiator_id, init_fp, &expected, resp_fp, path_i)
            .await
            .unwrap();
    let responder_session = responder.await.unwrap().unwrap();
    assert_eq!(initiator_session.remote_relay_id().as_hex(), responder_hex);
    assert_eq!(responder_session.remote_relay_id().as_hex(), initiator_hex);
    (initiator_session, responder_session)
}

#[tokio::test]
async fn duplex_mutual_auth_produces_sessions_before_any_payload() {
    let (initiator_session, responder_session) = mutual_over_duplex().await;
    assert!(initiator_session.mutual());
    assert!(responder_session.mutual());
    assert_eq!(initiator_session.local_role(), SessionRole::Initiator);
    assert_eq!(responder_session.local_role(), SessionRole::Responder);

    let decision = authorize_unknown_authenticated(&responder_session, &empty_trust());
    assert_eq!(decision.outcome, TransferAuthorization::PromptRequired);
    let mut trust = empty_trust();
    trust.record_user_accepted_transfer(&responder_session);
    assert!(matches!(
        trust.lookup(responder_session.remote_relay_id()),
        TrustRecord::Unknown
    ));
}

#[tokio::test]
async fn wrong_expected_relay_id_fails_without_auth_ok() {
    let initiator_id = RelayIdentity::generate();
    let responder_id = RelayIdentity::generate();
    let wrong = RelayId::from_local_identity(&RelayIdentity::generate()).unwrap();
    let initiator_tls = InnerTlsPeer::generate().unwrap();
    let responder_tls = InnerTlsPeer::generate().unwrap();
    let path = PathDescriptor::InternetDirect {
        host: String::new(),
        port: None,
    };
    let (mut a, mut b) = tokio::io::duplex(16 * 1024);
    let init_fp = initiator_tls.cert_fingerprint;
    let resp_fp = responder_tls.cert_fingerprint;
    let path_r = path.clone();

    let responder = tokio::spawn(async move {
        authenticate_server(&mut b, &responder_id, resp_fp, None, init_fp, path_r).await
    });
    let err = authenticate_initiator(&mut a, &initiator_id, init_fp, &wrong, resp_fp, path)
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        AnywhereError::ExpectedIdentityMismatch { .. }
    ));
    drop(a);
    let _ = tokio::time::timeout(std::time::Duration::from_secs(2), responder).await;
}

#[tokio::test]
async fn fresh_auth_on_new_connection_succeeds_twice() {
    let first = mutual_over_duplex().await;
    let second = mutual_over_duplex().await;
    assert_ne!(
        first.0.local_relay_id().as_hex(),
        second.0.local_relay_id().as_hex()
    );
}
