use crate::crypto::relay_identity::RelayIdentity;
use crate::crypto::relay_identity_proof::{create_relay_identity_proof, RelayProofRole};
use crate::relay::{
    authorize, DeviceBinding, MemoryTrustDirectory, PathDescriptor, RelayAuthCoordinator, RelayId,
    SessionRole, TransferAuthorization, TransferRequestContext,
};

const TLS: [u8; 32] = [0x44; 32];
const NONCE: [u8; 32] = [0x55; 32];

fn coordinator(identity: &RelayIdentity) -> RelayAuthCoordinator {
    RelayAuthCoordinator::new(RelayId::from_local_identity(identity).unwrap())
}

#[test]
fn anywhere_initiator_session_is_mutual() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Server, NONCE, TLS).unwrap();
    let expected = RelayId::from_local_identity(&remote).unwrap();
    let session = coordinator(&local)
        .complete_anywhere_initiator(
            &proof,
            TLS,
            &expected,
            PathDescriptor::InternetDirect {
                host: String::new(),
                port: None,
            },
        )
        .unwrap();
    assert!(session.mutual());
    assert_eq!(session.local_role(), SessionRole::Initiator);
    assert_eq!(session.remote_relay_id(), &expected);
}

#[test]
fn anywhere_responder_session_is_mutual() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Client, NONCE, TLS).unwrap();
    let session = coordinator(&local)
        .complete_anywhere_responder(
            &proof,
            TLS,
            None,
            PathDescriptor::IrohRelay {
                hint: Some("iroh-relay".into()),
            },
        )
        .unwrap();
    assert!(session.mutual());
    assert_eq!(session.local_role(), SessionRole::Responder);
    assert_eq!(
        session.remote_relay_id(),
        &RelayId::from_local_identity(&remote).unwrap()
    );
}

#[test]
fn anywhere_expected_identity_mismatch_hard_fails() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let other = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Server, NONCE, TLS).unwrap();
    let err = coordinator(&local)
        .complete_anywhere_initiator(
            &proof,
            TLS,
            &RelayId::from_local_identity(&other).unwrap(),
            PathDescriptor::InternetDirect {
                host: String::new(),
                port: None,
            },
        )
        .unwrap_err();
    assert!(matches!(
        err,
        crate::relay::RelayAuthError::ExpectedIdentityMismatch { .. }
    ));
}

#[test]
fn iroh_endpoint_id_is_not_relay_id() {
    let relay_id = RelayId::from_local_identity(&RelayIdentity::generate()).unwrap();
    let endpoint_hex = "B".repeat(64);
    assert_ne!(relay_id.as_hex(), endpoint_hex);
    assert!(RelayId::from_expected_canonical_hex(&endpoint_hex).is_ok());
}

#[test]
fn direct_and_relay_paths_have_identical_auth_semantics() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Server, NONCE, TLS).unwrap();
    let expected = RelayId::from_local_identity(&remote).unwrap();
    let coordinator = coordinator(&local);
    let direct = coordinator
        .complete_anywhere_initiator(
            &proof,
            TLS,
            &expected,
            PathDescriptor::InternetDirect {
                host: "203.0.113.1".into(),
                port: Some(443),
            },
        )
        .unwrap();
    let relayed = coordinator
        .complete_anywhere_initiator(
            &proof,
            TLS,
            &expected,
            PathDescriptor::IrohRelay {
                hint: Some("n0".into()),
            },
        )
        .unwrap();
    assert_eq!(direct.remote_relay_id(), relayed.remote_relay_id());
    assert_eq!(direct.mutual(), relayed.mutual());
}

#[test]
fn path_descriptor_does_not_alter_authorization() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Client, NONCE, TLS).unwrap();
    let session = coordinator(&local)
        .complete_anywhere_responder(&proof, TLS, None, PathDescriptor::IrohRelay { hint: None })
        .unwrap();
    let trust = MemoryTrustDirectory::new();
    let ctx = TransferRequestContext {
        claimed_display_name: None,
        auto_accept_trusted: true,
    };
    assert_eq!(
        authorize(&session, &trust, &ctx).outcome,
        TransferAuthorization::PromptRequired
    );
}

#[test]
fn unknown_authenticated_anywhere_peer_requires_prompt() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Client, NONCE, TLS).unwrap();
    let session = coordinator(&local)
        .complete_anywhere_responder(
            &proof,
            TLS,
            None,
            PathDescriptor::InternetDirect {
                host: String::new(),
                port: None,
            },
        )
        .unwrap();
    assert_eq!(
        crate::anywhere::authorize_unknown_authenticated(&session, &MemoryTrustDirectory::new())
            .outcome,
        TransferAuthorization::PromptRequired
    );
}

#[test]
fn blocked_authenticated_anywhere_peer_is_denied() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Client, NONCE, TLS).unwrap();
    let session = coordinator(&local)
        .complete_anywhere_responder(
            &proof,
            TLS,
            None,
            PathDescriptor::InternetDirect {
                host: String::new(),
                port: None,
            },
        )
        .unwrap();
    let mut trust = MemoryTrustDirectory::new();
    trust.insert(DeviceBinding::new(
        "b1",
        session.remote_relay_id().clone(),
        "x",
        false,
        true,
    ));
    assert_eq!(
        crate::anywhere::authorize_unknown_authenticated(&session, &trust).outcome,
        TransferAuthorization::Denied
    );
}

#[test]
fn lan_initiator_session_is_still_not_mutual() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof = create_relay_identity_proof(&remote, RelayProofRole::Server, NONCE, TLS).unwrap();
    let session = coordinator(&local)
        .complete_lan_initiator(
            &proof,
            TLS,
            None,
            PathDescriptor::lan("192.0.2.1", Some(53317)),
        )
        .unwrap();
    assert!(!session.mutual());
    assert_eq!(session.local_role(), SessionRole::Initiator);
}
