//! Relay Anywhere RA2B — Android/Linux physical proof library.
//!
//! Development-only. The invite type is a test addressing package, not
//! production trust architecture.

mod endpoint_codec;
mod invite;
mod iroh_stream;
mod relay_auth;
mod session;
mod session_guard;

pub use endpoint_codec::{decode_endpoint_addr, encode_endpoint_addr};
pub use invite::{
    INVITE_PREFIX, INVITE_VERSION, MAX_INVITE_LEN, Ra2bInviteV1, parse_invite, validate_relay_id,
};
pub use relay_auth::IDENTITY_REJECTED;
pub use session::{
    Ra2bCancellation, Ra2bPathClass, Ra2bPathPreference, Ra2bPeerMaterial, Ra2bPhase,
    Ra2bProofResult, Ra2bRole, error_category, run_proof,
};
pub use session_guard::{ActiveSessionGuard, cancel_active_session, session_is_active};

use std::sync::{Arc, OnceLock};

use localsend::crypto::relay_identity::RelayIdentity;

/// In-memory development identity for this process. Not persisted as a favorite.
pub fn process_identity() -> Arc<RelayIdentity> {
    static IDENTITY: OnceLock<Arc<RelayIdentity>> = OnceLock::new();
    IDENTITY
        .get_or_init(|| Arc::new(RelayIdentity::generate()))
        .clone()
}

pub fn process_relay_id() -> anyhow::Result<String> {
    process_identity().relay_id()
}

pub fn fresh_unrelated_relay_id() -> anyhow::Result<String> {
    RelayIdentity::generate().relay_id()
}
