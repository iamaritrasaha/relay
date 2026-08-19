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
    #[error("the Relay identity proof answers a different challenge")]
    ChallengeMismatch,
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
    /// This is the one-directional LAN result: the transfer client learns who
    /// the server is, and the server learns nothing about the client. The
    /// mutual LAN result lives in [`Self::complete_lan_responder`], which is
    /// reached only through the Relay pairing endpoints — never through the
    /// LocalSend-compatible v2 routes.
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

    /// LAN responder: a Client-role proof of the initiator, bound to the client
    /// certificate this connection actually presented and to the nonce this
    /// device issued.
    ///
    /// `observed_client_tls_fingerprint` must come from the rustls peer
    /// certificate of the live connection, never from the request payload, and
    /// `issued_nonce` must be a single-use challenge this device generated. The
    /// resulting session is the LAN counterpart of
    /// [`Self::complete_anywhere_responder`]: the initiator can only obtain
    /// `issued_nonce` after it has fetched this device's Server-role proof, so
    /// both directions are authenticated by the time this succeeds.
    pub fn complete_lan_responder(
        &self,
        proof: &RelayIdentityProofV1,
        observed_client_tls_fingerprint: [u8; 32],
        issued_nonce: &[u8; 32],
        expected_remote: Option<&RelayId>,
        path: PathDescriptor,
    ) -> Result<AuthenticatedRelaySession, RelayAuthError> {
        if &proof.nonce != issued_nonce {
            return Err(RelayAuthError::ChallengeMismatch);
        }
        self.complete(
            proof,
            RelayProofRole::Client,
            observed_client_tls_fingerprint,
            expected_remote,
            SessionRole::Responder,
            true,
            path,
        )
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
