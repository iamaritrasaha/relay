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
        self.complete(
            proof,
            RelayProofRole::Server,
            observed_tls_fingerprint,
            expected_remote,
            SessionRole::Initiator,
            false,
            path,
        )
    }

    /// Constructs the LAN initiator session after the production HTTP proof
    /// verifier has already validated a Server-role proof against this exact
    /// TLS certificate. Kept crate-private so callers cannot substitute this
    /// for proof verification.
    pub(crate) fn complete_verified_lan_initiator(
        &self,
        proven_remote: RelayId,
        observed_tls_fingerprint: [u8; 32],
        expected_remote: &RelayId,
        path: PathDescriptor,
    ) -> Result<AuthenticatedRelaySession, RelayAuthError> {
        if !expected_remote.eq_digest(&proven_remote) {
            return Err(RelayAuthError::ExpectedIdentityMismatch {
                expected: expected_remote.clone(),
                proven: proven_remote,
            });
        }
        Ok(AuthenticatedRelaySession::from_coordinator(
            expected_remote.clone(),
            self.local_relay_id.clone(),
            SessionRole::Initiator,
            false,
            ChannelBinding::tls_cert_sha256(observed_tls_fingerprint),
            path,
        ))
    }

    /// Anywhere initiator: Server-role proof of the responder, then a Client-role
    /// proof is sent by the caller. The resulting session is mutual.
    pub fn complete_anywhere_initiator(
        &self,
        proof: &RelayIdentityProofV1,
        observed_tls_fingerprint: [u8; 32],
        expected_remote: &RelayId,
        path: PathDescriptor,
    ) -> Result<AuthenticatedRelaySession, RelayAuthError> {
        self.complete(
            proof,
            RelayProofRole::Server,
            observed_tls_fingerprint,
            Some(expected_remote),
            SessionRole::Initiator,
            true,
            path,
        )
    }

    /// Anywhere responder: Client-role proof of the initiator. Mutual.
    ///
    /// Not used by LAN responders (they still use [`crate::relay::LegacyLanInboundSession`]).
    pub fn complete_anywhere_responder(
        &self,
        proof: &RelayIdentityProofV1,
        observed_tls_fingerprint: [u8; 32],
        expected_remote: Option<&RelayId>,
        path: PathDescriptor,
    ) -> Result<AuthenticatedRelaySession, RelayAuthError> {
        self.complete(
            proof,
            RelayProofRole::Client,
            observed_tls_fingerprint,
            expected_remote,
            SessionRole::Responder,
            true,
            path,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn complete(
        &self,
        proof: &RelayIdentityProofV1,
        expected_role: RelayProofRole,
        observed_tls_fingerprint: [u8; 32],
        expected_remote: Option<&RelayId>,
        local_role: SessionRole,
        mutual: bool,
        path: PathDescriptor,
    ) -> Result<AuthenticatedRelaySession, RelayAuthError> {
        if proof.role != expected_role {
            return Err(RelayAuthError::RoleMismatch);
        }

        let proven_hex =
            verify_relay_identity_proof(proof, expected_role, observed_tls_fingerprint)
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
            local_role,
            mutual,
            ChannelBinding::tls_cert_sha256(observed_tls_fingerprint),
            path,
        ))
    }
}
