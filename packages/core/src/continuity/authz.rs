//! The continuity authorization boundary.
//!
//! Every continuity payload must pass through [`authorize_capability`]. The
//! function's signature is the enforcement: it takes an
//! [`AuthenticatedRelaySession`], which is only constructible by
//! [`crate::relay::RelayAuthCoordinator`] after a verified
//! `RelayIdentityProofV1`. There is deliberately no overload accepting a
//! [`crate::relay::LegacyLanInboundSession`], a [`crate::relay::LocalSendPeer`],
//! a display name, an IP, an EndpointId, or a stored Relay address, so no
//! caller can substitute a routing fact for a trust fact.

use super::permission::{ContinuityPermissions, DeviceContinuityPermissions};
use super::protocol::ContinuityCapability;
use crate::relay::{AuthenticatedRelaySession, TrustDirectory, TrustRecord};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ContinuityAuthorization {
    Allowed,
    /// The peer is proven but the user has not marked the device trusted.
    /// Pairing a route is not trust.
    DeniedNotTrusted,
    /// The device is explicitly blocked.
    DeniedBlocked,
    /// The device is trusted but the user has not enabled this capability.
    DeniedNotEnabled { capability: ContinuityCapability },
    /// The peer named a capability this build does not implement.
    DeniedUnknownCapability,
}

impl ContinuityAuthorization {
    pub fn is_allowed(&self) -> bool {
        matches!(self, Self::Allowed)
    }
}

/// Whether an authenticated session may run continuity at all.
///
/// This is the coarse gate: only an explicitly trusted device gets a continuity
/// session. An unknown-but-authenticated peer can still receive files (that path
/// prompts the user per transfer) but never reaches a capability dispatcher.
pub fn authorize_session(
    session: &AuthenticatedRelaySession,
    trust: &impl TrustDirectory,
) -> ContinuityAuthorization {
    match trust.lookup(session.remote_relay_id()) {
        TrustRecord::Blocked => ContinuityAuthorization::DeniedBlocked,
        TrustRecord::Unknown => ContinuityAuthorization::DeniedNotTrusted,
        TrustRecord::Trusted => ContinuityAuthorization::Allowed,
    }
}

/// Whether one capability may be exercised over an authenticated session.
///
/// `Session` control traffic is allowed on any session that already passed
/// [`authorize_session`]; it carries no user data. Every other capability
/// additionally requires an explicit local grant for this exact RelayId.
pub fn authorize_capability(
    session: &AuthenticatedRelaySession,
    trust: &impl TrustDirectory,
    permissions: &ContinuityPermissions,
    capability: ContinuityCapability,
) -> ContinuityAuthorization {
    let gate = authorize_session(session, trust);
    if !gate.is_allowed() {
        return gate;
    }
    match capability {
        ContinuityCapability::Unknown => ContinuityAuthorization::DeniedUnknownCapability,
        ContinuityCapability::Session => ContinuityAuthorization::Allowed,
        capability => {
            let device = permissions.for_device(&session.remote_relay_id().as_hex());
            if device.is_enabled(capability) {
                ContinuityAuthorization::Allowed
            } else {
                ContinuityAuthorization::DeniedNotEnabled { capability }
            }
        }
    }
}

/// The permissions in force for the proven peer of a session.
pub fn permissions_for(
    session: &AuthenticatedRelaySession,
    permissions: &ContinuityPermissions,
) -> DeviceContinuityPermissions {
    permissions.for_device(&session.remote_relay_id().as_hex())
}
