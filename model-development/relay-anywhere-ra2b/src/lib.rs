//! Relay Anywhere RA2B — Android/Linux physical proof library.
//!
//! Development-only. The invite type is a test addressing package, not
//! production trust architecture.

mod endpoint_codec;
mod invite;
mod relay_auth;
mod session;
mod session_guard;

pub use endpoint_codec::{decode_endpoint_addr, encode_endpoint_addr};
pub use invite::{
    parse_invite, validate_relay_id, Ra2bInviteV1, INVITE_PREFIX, INVITE_VERSION, MAX_INVITE_LEN,
};
pub use relay_auth::IDENTITY_REJECTED;
pub use session::{
    error_category, run_proof, Ra2bCancellation, Ra2bPathClass, Ra2bPathPreference,
    send_files_over_authenticated_stream, send_one_file_over_authenticated_stream, Ra4BatchSpec,
    Ra4Decision, Ra4FileSource, Ra4FileSpec, Ra4IncomingFile, Ra2bPeerMaterial, Ra2bPhase,
    Ra2bProofResult, Ra2bRole, run_ra4_batch_sender, run_ra4_receiver, run_ra4_sender,
};
pub use session_guard::{cancel_active_session, session_is_active, ActiveSessionGuard};

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
