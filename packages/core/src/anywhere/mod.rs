//! Production Relay Anywhere path: Iroh transport + inner TLS + RA3A auth.
//!
//! Iroh is started only through this module's explicit APIs. LAN HTTP/multicast
//! startup never calls into this module.

pub mod endpoint;
pub mod error;
pub mod proof;
pub mod stream;
pub mod tls;

pub use endpoint::{
    bind_endpoint, iroh_endpoint_bind_count, selected_path, wrap_endpoint, AnywhereEndpoint,
    PathPreference, ALPN,
};
pub use error::AnywhereError;
pub use iroh::EndpointAddr;
pub use proof::{authenticate_initiator, authenticate_server};
pub use tls::InnerTlsPeer;

use crate::relay::{
    authorize, AuthenticatedRelaySession, AuthorizationDecision, MemoryTrustDirectory,
    TransferRequestContext, TrustDirectory,
};

/// RA3B harness: unknown authenticated peers require an explicit session-scoped
/// accept. This does not write [`crate::relay::DeviceBinding`].
pub fn authorize_unknown_authenticated(
    session: &AuthenticatedRelaySession,
    trust: &impl TrustDirectory,
) -> AuthorizationDecision {
    authorize(
        session,
        trust,
        &TransferRequestContext {
            claimed_display_name: None,
            auto_accept_trusted: false,
        },
    )
}

pub fn empty_trust() -> MemoryTrustDirectory {
    MemoryTrustDirectory::new()
}

#[cfg(test)]
mod e2e;
#[cfg(test)]
mod proof_tests;
#[cfg(test)]
mod ra3b;
