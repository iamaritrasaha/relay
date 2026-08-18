//! Relay transport-facing proof abstractions and RA3A production auth boundary.
//!
//! TLS context construction is deliberately deferred until transport code can
//! derive it from the exact rustls configuration in use.

mod coordinator;
#[cfg(feature = "anywhere")]
mod device;
mod id;
mod path;
mod policy;
mod session;
#[cfg(feature = "anywhere")]
mod transport;

pub use coordinator::{RelayAuthCoordinator, RelayAuthError};
#[cfg(feature = "anywhere")]
pub use device::{
    AnywhereTransportCandidate, CandidateFreshness, DeviceCandidateError, LanRouteIdentity,
    LanTransportCandidate, RelayDevice, RelayDeviceDirectory, RelayDeviceMetadata,
    UnresolvedLanCandidate,
};
pub use id::{ClaimedRelayId, RelayId};
pub use path::{ChannelBinding, PathDescriptor};
pub use policy::{
    authorize, authorize_with_memory_directory, AuthorizationAdvisory, AuthorizationDecision,
    DeviceBinding, MemoryTrustDirectory, TransferAuthorization, TransferRequestContext,
    TrustDirectory, TrustRecord,
};
pub use session::{AuthenticatedRelaySession, LegacyLanInboundSession, LocalSendPeer, SessionRole};
#[cfg(feature = "anywhere")]
pub use transport::{
    ConnectionStage, EstablishedTransportSession, IdentityFailure, RelaySecurityRequirement,
    RelaySendError, RelaySendOutcome, RelaySendService, RelaySendTarget, RelayTransferExecutor,
    TransportAttempt, TransportCandidate, TransportKind, TransportOrigin, TransportPolicy,
    TransportResolver, TransportSessionFactory,
};

use std::fmt;

use thiserror::Error;

use crate::crypto::relay_identity::RelayIdentity;
use crate::crypto::relay_identity_proof::create_relay_identity_proof;
use crate::crypto::relay_identity_proof::{RelayIdentityProofV1, RelayProofRole};

/// Opaque TLS context owned by the Relay transport.
///
/// Production construction is intentionally unavailable until the transport
/// can bind this context to the actual TLS configuration.
#[derive(Clone)]
#[allow(dead_code)] // Accessed by production signer implementations in Phase 1B3.
pub struct RelayTlsContext {
    role: RelayProofRole,
    own_tls_fingerprint: [u8; 32],
}

#[allow(dead_code)] // Accessed by production signer implementations in Phase 1B3.
impl RelayTlsContext {
    /// Creates a server context from the exact DER certificate installed into
    /// the rustls server configuration.
    pub(crate) fn from_server_certificate_der(certificate_der: &[u8]) -> Self {
        let own_tls_fingerprint: [u8; 32] = crate::crypto::hash::sha256(certificate_der)
            .try_into()
            .expect("SHA-256 digest has a fixed length");
        Self {
            role: RelayProofRole::Server,
            own_tls_fingerprint,
        }
    }

    pub(crate) fn role(&self) -> RelayProofRole {
        self.role
    }

    pub(crate) fn own_tls_fingerprint(&self) -> [u8; 32] {
        self.own_tls_fingerprint
    }
}

/// Synchronous proof signer supplied to Relay transport code.
pub trait RelayProofSigner: Send + Sync + fmt::Debug {
    fn sign_server_proof(
        &self,
        nonce: &[u8; 32],
        tls: &RelayTlsContext,
    ) -> Result<RelayIdentityProofV1, RelaySignError>;
}

/// Transport-neutral signing failure for later HTTP mapping.
#[derive(Clone, Copy, Debug, Error, Eq, PartialEq)]
pub enum RelaySignError {
    #[error("Relay proof signer is unavailable")]
    SignerUnavailable,
    #[error("Relay TLS context has the wrong proof role")]
    WrongRole,
    #[error("Relay identity is invalid")]
    InvalidIdentity,
    #[error("Relay identity proof signing failed")]
    SigningFailed,
}

/// Failure while installing a Rust-resident Relay server proof signer.
///
/// These errors deliberately carry no private-key material.
#[derive(Clone, Copy, Debug, Error, Eq, PartialEq)]
pub enum RelaySignerInstallError {
    #[error("the Relay server has stopped")]
    ServerStopped,
    #[error("the Relay private key is invalid")]
    InvalidPrivateKey,
    #[error("the Relay private key does not match the expected RelayId")]
    RelayIdMismatch,
}

/// Rust-resident signer for server-side Relay identity proofs.
///
/// This is intentionally crate-private: identity loading and lifecycle are
/// controlled by the running core HTTP server, never by a network request.
pub(crate) struct ProductionRelaySigner {
    identity: RelayIdentity,
    relay_id: String,
}

impl ProductionRelaySigner {
    pub(crate) fn new(identity: RelayIdentity, relay_id: String) -> Self {
        Self { identity, relay_id }
    }
}

impl fmt::Debug for ProductionRelaySigner {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ProductionRelaySigner")
            .field("relay_id", &self.relay_id)
            .finish()
    }
}

impl RelayProofSigner for ProductionRelaySigner {
    fn sign_server_proof(
        &self,
        nonce: &[u8; 32],
        tls: &RelayTlsContext,
    ) -> Result<RelayIdentityProofV1, RelaySignError> {
        if tls.role() != RelayProofRole::Server {
            return Err(RelaySignError::WrongRole);
        }

        create_relay_identity_proof(
            &self.identity,
            tls.role(),
            *nonce,
            tls.own_tls_fingerprint(),
        )
        .map_err(|_| RelaySignError::SigningFailed)
    }
}

/// Result of Relay cryptographic authentication, without trust policy.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RelayPeerAuth {
    NotAttempted,
    Unsupported,
    TransportUnauthenticated,
    SignerUnavailable,
    Malformed,
    RoleMismatch,
    ChallengeMismatch,
    CryptoInvalid,
    Authenticated {
        relay_id: String,
        tls_fingerprint: [u8; 32],
    },
}

#[cfg(test)]
fn test_tls_context(role: RelayProofRole, own_tls_fingerprint: [u8; 32]) -> RelayTlsContext {
    RelayTlsContext {
        role,
        own_tls_fingerprint,
    }
}

#[cfg(test)]
struct TestRelayProofSigner {
    identity: crate::crypto::relay_identity::RelayIdentity,
}

#[cfg(test)]
impl TestRelayProofSigner {
    fn new(identity: crate::crypto::relay_identity::RelayIdentity) -> Self {
        Self { identity }
    }
}

#[cfg(test)]
impl fmt::Debug for TestRelayProofSigner {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("TestRelayProofSigner(..)")
    }
}

#[cfg(test)]
impl RelayProofSigner for TestRelayProofSigner {
    fn sign_server_proof(
        &self,
        nonce: &[u8; 32],
        tls: &RelayTlsContext,
    ) -> Result<RelayIdentityProofV1, RelaySignError> {
        if tls.role() != RelayProofRole::Server {
            return Err(RelaySignError::WrongRole);
        }

        crate::crypto::relay_identity_proof::create_relay_identity_proof(
            &self.identity,
            tls.role(),
            *nonce,
            tls.own_tls_fingerprint(),
        )
        .map_err(|_| RelaySignError::SigningFailed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::crypto::relay_identity_proof::verify_relay_identity_proof;

    const TLS_FINGERPRINT: [u8; 32] = [0x41; 32];

    #[test]
    fn test_signer_produces_server_proofs_bound_to_its_tls_context_and_nonce() {
        let identity = RelayIdentity::generate();
        let expected_relay_id = identity.relay_id().unwrap();
        let signer = TestRelayProofSigner::new(identity);
        let context = test_tls_context(RelayProofRole::Server, TLS_FINGERPRINT);
        let nonce = [0x12; 32];

        let proof = signer.sign_server_proof(&nonce, &context).unwrap();

        assert_eq!(proof.nonce, nonce);
        assert_eq!(
            verify_relay_identity_proof(&proof, RelayProofRole::Server, TLS_FINGERPRINT).unwrap(),
            expected_relay_id
        );
        assert!(verify_relay_identity_proof(&proof, RelayProofRole::Server, [0x42; 32]).is_err());
    }

    #[test]
    fn test_signer_rejects_client_context_and_binds_each_nonce() {
        let signer = TestRelayProofSigner::new(RelayIdentity::generate());
        let server_context = test_tls_context(RelayProofRole::Server, TLS_FINGERPRINT);
        let client_context = test_tls_context(RelayProofRole::Client, TLS_FINGERPRINT);

        assert_eq!(
            signer.sign_server_proof(&[0x01; 32], &client_context),
            Err(RelaySignError::WrongRole)
        );
        let first = signer
            .sign_server_proof(&[0x01; 32], &server_context)
            .unwrap();
        let second = signer
            .sign_server_proof(&[0x02; 32], &server_context)
            .unwrap();
        assert_ne!(first.nonce, second.nonce);
        assert_ne!(first.signature, second.signature);
    }

    #[test]
    fn proof_signer_trait_object_is_send_and_sync() {
        fn assert_send_sync<T: Send + Sync + ?Sized>() {}

        assert_send_sync::<dyn RelayProofSigner>();
    }

    #[test]
    fn production_signer_is_server_only_and_debug_reveals_only_the_relay_id() {
        let identity = RelayIdentity::generate();
        let relay_id = identity.relay_id().unwrap();
        let private_key_pem = identity.private_key_export().unwrap();
        let signer = ProductionRelaySigner::new(identity, relay_id.clone());
        let client_context = test_tls_context(RelayProofRole::Client, TLS_FINGERPRINT);

        assert_eq!(
            signer.sign_server_proof(&[0x01; 32], &client_context),
            Err(RelaySignError::WrongRole)
        );

        let debug = format!("{signer:?}");
        assert!(debug.contains(&relay_id));
        assert!(!debug.contains("PRIVATE KEY"));
        assert!(!debug.contains(private_key_pem.as_str()));
        assert!(!debug.contains(&format!("{:?}", private_key_pem.as_bytes())));
    }

    #[test]
    fn authenticated_peer_auth_keeps_identity_and_tls_binding_together() {
        let auth = RelayPeerAuth::Authenticated {
            relay_id: "A1".to_owned(),
            tls_fingerprint: TLS_FINGERPRINT,
        };

        assert_eq!(
            auth,
            RelayPeerAuth::Authenticated {
                relay_id: "A1".to_owned(),
                tls_fingerprint: TLS_FINGERPRINT,
            }
        );
    }
}

#[cfg(test)]
mod ra3a;
