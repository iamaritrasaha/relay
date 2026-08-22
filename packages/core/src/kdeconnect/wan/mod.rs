//! Relay WAN: an Iroh-based additional transport for the KDE Connect
//! compatibility protocol, alongside (never instead of) the existing KDE LAN
//! implementation in [`super::lan`].
//!
//! Iroh is the WAN connectivity layer only -- KDE Connect packet/plugin
//! semantics are unchanged and unaware of which transport carried them. LAN
//! is always preferred; see [`transport::TransportKind::priority`].
//!
//! This module never starts Iroh on its own: constructing a [`WanRuntime`]
//! (via [`WanRuntime::start`]) is the only thing that binds a Relay WAN
//! endpoint. KDE LAN startup never calls into this module.

pub mod binding;
pub mod endpoint;
pub mod identity;
pub mod payload;
pub mod protocol;
pub mod runtime;
pub mod transport;

pub use binding::{WanBinding, WanBindingRegistry};
pub use endpoint::{bind_wan_endpoint, wan_iroh_endpoint_bind_count, WanEndpoint, WAN_ALPN};
pub use identity::{WanIdentity, WanIdentityError};
pub use payload::{
    generate_relay_payload_id, validate_payload_size, WanPayloadError, WanPayloadTransferInfo,
    MAX_WAN_PAYLOAD_BYTES,
};
pub use protocol::{WanFrameError, WanHello, WanHelloError, WAN_PROTOCOL_VERSION};
pub use runtime::{WanAcceptError, WanIncomingEvent, WanLink, WanRuntime, WanRuntimeConfig};
pub use transport::{
    DeviceTransportSnapshot, PayloadOutcome, PayloadRequest, TransportKind, TransportLink,
    TransportMetadata, TransportRouter, TransportState,
};
