//! Relay Continuity: one versioned protocol for every device-continuity
//! capability.
//!
//! # Trust boundary
//!
//! Continuity carries clipboard text, message content, notification content and
//! call state. None of it may reach a peer that is merely reachable. The only
//! entry point into a session, [`session::run_session`], takes an
//! [`crate::relay::AuthenticatedRelaySession`] — a type whose sole constructor
//! is the Relay auth coordinator after a verified `RelayIdentityProofV1`. A
//! [`crate::relay::LegacyLanInboundSession`], a [`crate::relay::LocalSendPeer`],
//! a LAN discovery observation, a display name, an IP, an Iroh EndpointId or a
//! stored Relay address cannot be converted into one, so none of them can open
//! continuity.
//!
//! On top of authentication there are two further, separate gates:
//!
//! * the device must be explicitly **trusted** ([`authz::authorize_session`]);
//! * the user must have **enabled that capability** for that device
//!   ([`authz::authorize_capability`]).
//!
//! Pairing satisfies neither.

pub mod authz;
pub mod codec;
pub mod host;
pub mod permission;
pub mod protocol;
pub mod replay;
pub mod session;

#[cfg(test)]
mod tests;

pub use authz::{
    authorize_capability, authorize_session, permissions_for, ContinuityAuthorization,
};
pub use codec::{decode_body, encode_frame, read_envelope, write_envelope, ContinuityCodecError};
pub use host::{ContinuityEvent, ContinuityEventSink, ContinuityHostRequest, ContinuitySessionEnd};
pub use permission::{
    CapabilityGrant, ClipboardMode, ContinuityPermissions, DeviceContinuityPermissions,
};
pub use protocol::*;
pub use replay::{ActionAdmission, ReplayGuard};
pub use session::{
    now_ms, run_session, session_channel, ContinuitySessionConfig, ContinuitySessionHandle,
    SharedPermissions, SharedTrust,
};

/// Lowercase-hex SHA-256 of clipboard text.
///
/// Both ends compute this the same way so loop suppression works without either
/// side having to trust the other's arithmetic.
pub fn clipboard_fingerprint(text: &str) -> String {
    crate::crypto::hash::sha256(text.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// Builds a manifest entry.
pub fn capability_entry(
    capability: ContinuityCapability,
    state: CapabilityState,
) -> CapabilityEntry {
    CapabilityEntry { capability, state }
}
