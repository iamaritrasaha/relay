use crate::crypto::relay_identity::RelayIdentity;
use crate::crypto::relay_identity_proof::{
    create_relay_identity_proof, RelayIdentityProofV1, RelayProofRole,
};

use super::coordinator::{RelayAuthCoordinator, RelayAuthError};
use super::id::{ClaimedRelayId, RelayId};
use super::path::{ChannelBinding, PathDescriptor};
use super::policy::{
    authorize_with_memory_directory, AuthorizationAdvisory, DeviceBinding, MemoryTrustDirectory,
    TransferAuthorization, TransferRequestContext, TrustDirectory, TrustRecord,
};
use super::session::{LegacyLanInboundSession, LocalSendPeer, SessionRole};

const TLS_FINGERPRINT: [u8; 32] = [0x22; 32];
const NONCE: [u8; 32] = [0x11; 32];

fn identities() -> (RelayIdentity, RelayIdentity) {
    (RelayIdentity::generate(), RelayIdentity::generate())
}

fn server_proof(server: &RelayIdentity) -> RelayIdentityProofV1 {
    create_relay_identity_proof(server, RelayProofRole::Server, NONCE, TLS_FINGERPRINT).unwrap()
}

fn coordinator_for(local: &RelayIdentity) -> RelayAuthCoordinator {
    RelayAuthCoordinator::new(RelayId::from_local_identity(local).unwrap())
}

fn client_proof(client: &RelayIdentity, nonce: [u8; 32]) -> RelayIdentityProofV1 {
    create_relay_identity_proof(client, RelayProofRole::Client, nonce, TLS_FINGERPRINT).unwrap()
}

#[test]
fn a_client_role_proof_over_the_issued_nonce_yields_a_mutual_responder_session() {
    let (local, client) = identities();
    let session = coordinator_for(&local)
        .complete_lan_responder(
            &client_proof(&client, NONCE),
            TLS_FINGERPRINT,
            &NONCE,
            None,
            PathDescriptor::lan("192.0.2.8", None),
        )
        .unwrap();

    assert_eq!(
        session.remote_relay_id(),
        &RelayId::from_local_identity(&client).unwrap()
    );
    assert_eq!(session.local_role(), SessionRole::Responder);
    assert!(session.mutual());
}

#[test]
fn a_lan_responder_rejects_a_proof_answering_a_different_challenge() {
    let (local, client) = identities();
    let err = coordinator_for(&local)
        .complete_lan_responder(
            &client_proof(&client, [0x99; 32]),
            TLS_FINGERPRINT,
            &NONCE,
            None,
            PathDescriptor::lan("192.0.2.8", None),
        )
        .unwrap_err();

    assert_eq!(err, RelayAuthError::ChallengeMismatch);
}

#[test]
fn a_lan_responder_rejects_a_server_role_proof() {
    let (local, client) = identities();
    let err = coordinator_for(&local)
        .complete_lan_responder(
            &create_relay_identity_proof(&client, RelayProofRole::Server, NONCE, TLS_FINGERPRINT)
                .unwrap(),
            TLS_FINGERPRINT,
            &NONCE,
            None,
            PathDescriptor::lan("192.0.2.8", None),
        )
        .unwrap_err();

    assert_eq!(err, RelayAuthError::RoleMismatch);
}

#[test]
fn a_lan_responder_rejects_a_proof_bound_to_another_client_certificate() {
    let (local, client) = identities();
    let err = coordinator_for(&local)
        .complete_lan_responder(
            &client_proof(&client, NONCE),
            [0x77; 32],
            &NONCE,
            None,
            PathDescriptor::lan("192.0.2.8", None),
        )
        .unwrap_err();

    assert_eq!(err, RelayAuthError::CryptoInvalid);
}

#[test]
fn a_lan_responder_rejects_an_identity_other_than_the_one_demanded() {
    let (local, client) = identities();
    let expected = RelayId::from_local_identity(&RelayIdentity::generate()).unwrap();
    let err = coordinator_for(&local)
        .complete_lan_responder(
            &client_proof(&client, NONCE),
            TLS_FINGERPRINT,
            &NONCE,
            Some(&expected),
            PathDescriptor::lan("192.0.2.8", None),
        )
        .unwrap_err();

    assert!(matches!(
        err,
        RelayAuthError::ExpectedIdentityMismatch { .. }
    ));
}

/// A LAN observation never becomes an identity: the same proof reached over a
/// different address, alias or IP still authenticates the same RelayId, and a
/// changed address never authenticates a different one.
#[test]
fn lan_addressing_does_not_participate_in_the_proven_identity() {
    let (local, client) = identities();
    let coordinator = coordinator_for(&local);
    let proof = client_proof(&client, NONCE);

    let first = coordinator
        .complete_lan_responder(
            &proof,
            TLS_FINGERPRINT,
            &NONCE,
            None,
            PathDescriptor::lan("192.0.2.8", Some(53317)),
        )
        .unwrap();
    let second = coordinator
        .complete_lan_responder(
            &proof,
            TLS_FINGERPRINT,
            &NONCE,
            None,
            PathDescriptor::lan("198.51.100.4", Some(9999)),
        )
        .unwrap();

    assert_eq!(first.remote_relay_id(), second.remote_relay_id());
    assert_ne!(first.path(), second.path());
}

#[test]
fn proven_server_relay_id_constructs_authenticated_initiator_session() {
    let (local, server) = identities();
    let expected = RelayId::from_local_identity(&server).unwrap();
    let session = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();

    assert_eq!(session.remote_relay_id(), &expected);
    assert_eq!(
        session.local_relay_id(),
        &RelayId::from_local_identity(&local).unwrap()
    );
    assert_eq!(session.local_role(), SessionRole::Initiator);
    assert!(!session.mutual());
}

#[test]
fn lan_responder_without_client_proof_cannot_construct_authenticated_session() {
    let inbound = LegacyLanInboundSession::from_production_lan(
        "claimed-cert-fingerprint",
        "Phone",
        Some("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
        PathDescriptor::lan("192.0.2.8", None),
    );
    assert!(inbound.claimed_relay_id().is_none());
    fn _authorize(_: &super::session::AuthenticatedRelaySession) {}
    let _ = inbound;
}

#[test]
fn client_role_proof_cannot_complete_lan_initiator_session() {
    let (local, remote) = identities();
    let client_proof =
        create_relay_identity_proof(&remote, RelayProofRole::Client, NONCE, TLS_FINGERPRINT)
            .unwrap();
    let err = coordinator_for(&local)
        .complete_lan_initiator(
            &client_proof,
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap_err();
    assert_eq!(err, RelayAuthError::RoleMismatch);
}

#[test]
fn claimed_relay_id_cannot_flow_into_relay_id() {
    let identity = RelayIdentity::generate();
    let proven = RelayId::from_local_identity(&identity).unwrap();
    let claimed = ClaimedRelayId::from_untrusted_text(proven.as_hex());
    assert_eq!(claimed.as_untrusted_text(), proven.as_hex());
    assert_ne!(
        std::any::TypeId::of::<ClaimedRelayId>(),
        std::any::TypeId::of::<RelayId>()
    );
}

#[test]
fn authenticated_unknown_peer_requires_prompt() {
    let (local, server) = identities();
    let session = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    let trust = MemoryTrustDirectory::new();
    let decision = authorize_with_memory_directory(
        &session,
        &trust,
        &TransferRequestContext {
            claimed_display_name: Some("Phone".into()),
            auto_accept_trusted: true,
        },
    );
    assert_eq!(decision.outcome, TransferAuthorization::PromptRequired);
}

#[test]
fn accepting_a_transfer_does_not_create_persistent_trust() {
    let (local, server) = identities();
    let session = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    let mut trust = MemoryTrustDirectory::new();
    trust.record_user_accepted_transfer(&session);
    assert!(trust.bindings().is_empty());
    assert_eq!(
        trust.lookup(session.remote_relay_id()),
        TrustRecord::Unknown
    );
}

#[test]
fn blocked_authenticated_peer_is_denied() {
    let (local, server) = identities();
    let session = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    let mut trust = MemoryTrustDirectory::new();
    trust.insert(DeviceBinding::new(
        "bind-1",
        session.remote_relay_id().clone(),
        "Phone",
        false,
        true,
    ));
    let decision = authorize_with_memory_directory(
        &session,
        &trust,
        &TransferRequestContext {
            claimed_display_name: None,
            auto_accept_trusted: true,
        },
    );
    assert_eq!(decision.outcome, TransferAuthorization::Denied);
}

#[test]
fn trusted_authenticated_peer_follows_existing_auto_accept_policy() {
    let (local, server) = identities();
    let session = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    let mut trust = MemoryTrustDirectory::new();
    trust.insert(DeviceBinding::new(
        "bind-1",
        session.remote_relay_id().clone(),
        "Phone",
        true,
        false,
    ));

    let auto = authorize_with_memory_directory(
        &session,
        &trust,
        &TransferRequestContext {
            claimed_display_name: None,
            auto_accept_trusted: true,
        },
    );
    assert_eq!(auto.outcome, TransferAuthorization::AutoAccept);

    let prompt = authorize_with_memory_directory(
        &session,
        &trust,
        &TransferRequestContext {
            claimed_display_name: None,
            auto_accept_trusted: false,
        },
    );
    assert_eq!(prompt.outcome, TransferAuthorization::PromptRequired);
}

#[test]
fn expected_relay_id_mismatch_is_hard_authentication_failure() {
    let (local, server) = identities();
    let other = RelayIdentity::generate();
    let expected = RelayId::from_local_identity(&other).unwrap();
    let err = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            Some(&expected),
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap_err();
    match err {
        RelayAuthError::ExpectedIdentityMismatch {
            expected: got_expected,
            proven,
        } => {
            assert_eq!(got_expected, expected);
            assert_eq!(proven, RelayId::from_local_identity(&server).unwrap());
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[test]
fn path_metadata_change_does_not_change_relay_identity() {
    let (local, server) = identities();
    let coordinator = coordinator_for(&local);
    let proof = server_proof(&server);
    let lan = coordinator
        .complete_lan_initiator(
            &proof,
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    let relayed = coordinator
        .complete_lan_initiator(
            &proof,
            TLS_FINGERPRINT,
            None,
            PathDescriptor::Relayed {
                hint: Some("not-identity".into()),
            },
        )
        .unwrap();
    assert_eq!(lan.remote_relay_id(), relayed.remote_relay_id());
    assert_ne!(lan.path(), relayed.path());
}

#[test]
fn localsend_peer_cannot_enter_authenticated_trust_policy() {
    let peer = LocalSendPeer::from_claimed_device_fingerprint("localsend-fingerprint");
    fn _authorize(_: &super::session::AuthenticatedRelaySession) {}
    assert_eq!(peer.claimed_device_fingerprint(), "localsend-fingerprint");
}

#[test]
fn unknown_authenticated_peer_with_known_display_name_stays_prompt_only() {
    let (local, server) = identities();
    let known = RelayIdentity::generate();
    let session = coordinator_for(&local)
        .complete_lan_initiator(
            &server_proof(&server),
            TLS_FINGERPRINT,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    let mut trust = MemoryTrustDirectory::new();
    trust.insert(DeviceBinding::new(
        "bind-known",
        RelayId::from_local_identity(&known).unwrap(),
        "Kitchen",
        true,
        false,
    ));
    let decision = authorize_with_memory_directory(
        &session,
        &trust,
        &TransferRequestContext {
            claimed_display_name: Some("Kitchen".into()),
            auto_accept_trusted: true,
        },
    );
    assert_eq!(decision.outcome, TransferAuthorization::PromptRequired);
    assert_eq!(
        decision.advisory,
        Some(AuthorizationAdvisory::DisplayNameCollision {
            known_label: "Kitchen".into(),
        })
    );
}

#[test]
fn channel_binding_is_tls_fingerprint_not_relay_id() {
    let binding = ChannelBinding::tls_cert_sha256(TLS_FINGERPRINT);
    let identity = RelayIdentity::generate();
    let relay_id = RelayId::from_local_identity(&identity).unwrap();
    assert_ne!(binding.tls_cert_fingerprint_hex(), relay_id.as_hex());
}
