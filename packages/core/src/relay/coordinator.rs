//! Authentication coordinator: proof sequencing and typed session construction.
//!
//! Does not authorize transfers and does not write trust.

use thiserror::Error;

use crate::crypto::relay_identity_proof::{
    verify_relay_identity_proof, RelayIdentityProofV1, RelayProofRole,
};

use super::id::RelayId;
use super::path::{ChannelBinding, PathDescriptor};
use super::session::{AuthenticatedRelaySession, SessionRole};

/// Narrow coordinator that constructs [`AuthenticatedRelaySession`] only after
/// a successful Relay identity proof.
#[derive(Clone, Debug)]
pub struct RelayAuthCoordinator {
    local_relay_id: RelayId,
}

/// Typed authentication failures. These are not transfer-authorization results.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum RelayAuthError {
    #[error("Relay identity proof is cryptographically invalid")]
    CryptoInvalid,
    #[error("Relay identity proof has the wrong role")]
    RoleMismatch,
    #[error("the proven RelayId does not match the expected identity")]
    ExpectedIdentityMismatch { expected: RelayId, proven: RelayId },
}

impl RelayAuthCoordinator {
    pub fn new(local_relay_id: RelayId) -> Self {
        Self { local_relay_id }
    }

    pub fn local_relay_id(&self) -> &RelayId {
        &self.local_relay_id
    }

    /// LAN initiator: verify a Server-role proof and build an authenticated
    /// session with `mutual = false`.
    ///
    /// There is deliberately no public method that authenticates a LAN
    /// responder's remote client: production does not obtain a Client-role proof.
    pub fn complete_lan_initiator(
        &self,
        proof: &RelayIdentityProofV1,
        observed_tls_fingerprint: [u8; 32],
        expected_remote: Option<&RelayId>,
        path: PathDescriptor,
    ) -> Result<AuthenticatedRelaySession, RelayAuthError> {
        if proof.role != RelayProofRole::Server {
            return Err(RelayAuthError::RoleMismatch);
        }

        let proven_hex =
            verify_relay_identity_proof(proof, RelayProofRole::Server, observed_tls_fingerprint)
                .map_err(|_| RelayAuthError::CryptoInvalid)?;
        let proven =
            RelayId::from_verified_hex(&proven_hex).map_err(|_| RelayAuthError::CryptoInvalid)?;

        if let Some(expected) = expected_remote {
            if !expected.eq_digest(&proven) {
                return Err(RelayAuthError::ExpectedIdentityMismatch {
                    expected: expected.clone(),
                    proven,
                });
            }
        }

        Ok(AuthenticatedRelaySession::from_coordinator(
            proven,
            self.local_relay_id.clone(),
            SessionRole::Initiator,
            false,
            ChannelBinding::tls_cert_sha256(observed_tls_fingerprint),
            path,
        ))
    }
}
