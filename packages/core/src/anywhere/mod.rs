//! Production Relay Anywhere path: Iroh transport + inner TLS + RA3A auth.
//!
//! Iroh is started only through this module's explicit APIs. LAN HTTP/multicast
//! startup never calls into this module.

pub mod address;
pub mod endpoint;
pub mod error;
pub mod identity;
pub mod listener;
pub mod proof;
pub mod routing_key;
pub mod runtime;
pub mod stream;
pub mod tls;
pub mod transfer;

pub use address::{
    parse_relay_address, validate_relay_id, RelayAddressV1, MAX_RELAY_ADDRESS_LEN,
    RELAY_ADDRESS_PREFIX, RELAY_ADDRESS_VERSION,
};
pub use endpoint::{
    bind_endpoint, bind_endpoint_with_key, iroh_endpoint_bind_count, selected_path, wrap_endpoint,
    AnywhereEndpoint, PathPreference, ALPN,
};
pub use error::{AnywhereError, TlsStage, TransportStage};
pub use identity::AnywhereIdentity;
pub use iroh::EndpointAddr;
pub use listener::{
    AnywhereListener, AnywhereListenerConfig, AnywhereListenerEvent, AnywhereListenerEventSink,
};
pub use proof::{authenticate_initiator, authenticate_server};
pub use routing_key::{AnywhereRoutingKey, RoutingKeyError};
pub use runtime::{
    AnywhereDecision, AnywhereRespondError, AnywhereRuntime, AnywhereSessionId, IncomingTransferId,
};
pub use tls::InnerTlsPeer;
pub use transfer::{
    receive, send_batch, send_files_over_authenticated_stream, AnywhereBatch, AnywhereEvent,
    AnywhereEventSink, AnywhereFileSource, AnywhereFileSpec, AnywhereIncomingFile, AnywhereOutcome,
    AnywherePathClass, AnywhereReceiveRequest, AnywhereSendRequest,
};

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
