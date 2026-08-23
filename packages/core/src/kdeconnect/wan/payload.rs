//! Relay WAN payload transport policy.
//!
//! KDE packet payload metadata (`payloadTransferInfo`) is link-specific. On
//! LAN, KDE Connect opens a second TCP+TLS listener; Relay WAN never opens a
//! TCP listening port at all -- each binary payload gets its own Iroh/QUIC
//! stream, correlated by a random `relayPayloadId` the control-stream packet
//! carries in its `payloadTransferInfo` body alongside the existing
//! `payloadSize` field.
//!
//! V1 enforces a strict size ceiling: payloads above [`MAX_WAN_PAYLOAD_BYTES`]
//! are refused outright, before any bytes move, with a structured error the
//! caller can turn into "use a local connection instead". Silent truncation
//! or starting a transfer and cancelling partway through are both explicitly
//! disallowed by design here.

use uuid::Uuid;

pub use crate::kdeconnect::files::MAX_WAN_PAYLOAD_BYTES;

#[derive(Debug, Clone, Copy, Eq, PartialEq, thiserror::Error)]
pub enum WanPayloadError {
    /// The payload is larger than Relay WAN V1 will ever carry. The caller
    /// must surface this as "requires a local connection", not fall back to
    /// a partial or truncated transfer.
    #[error("WanPayloadTooLarge: {size} bytes exceeds the {limit}-byte Relay WAN limit; RequiresLocalConnection")]
    TooLarge { size: u64, limit: u64 },
}

pub fn validate_payload_size(size: u64) -> Result<(), WanPayloadError> {
    if size > MAX_WAN_PAYLOAD_BYTES {
        Err(WanPayloadError::TooLarge {
            size,
            limit: MAX_WAN_PAYLOAD_BYTES,
        })
    } else {
        Ok(())
    }
}

pub fn generate_relay_payload_id() -> String {
    Uuid::new_v4().simple().to_string()
}

/// The WAN-specific half of `payloadTransferInfo`: a random correlation id for
/// the dedicated payload stream, plus the already-existing `payloadSize`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WanPayloadTransferInfo {
    pub relay_payload_id: String,
    pub payload_size: u64,
}

impl WanPayloadTransferInfo {
    /// Builds transfer info for a new outgoing payload, rejecting it up front
    /// if it is over [`MAX_WAN_PAYLOAD_BYTES`] -- no stream is opened and no
    /// bytes are sent for a payload this returns `Err` for.
    pub fn new(payload_size: u64) -> Result<Self, WanPayloadError> {
        validate_payload_size(payload_size)?;
        Ok(Self {
            relay_payload_id: generate_relay_payload_id(),
            payload_size,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exactly_at_the_limit_is_accepted() {
        assert!(validate_payload_size(MAX_WAN_PAYLOAD_BYTES).is_ok());
    }

    #[test]
    fn one_byte_over_the_limit_is_refused() {
        let error = validate_payload_size(MAX_WAN_PAYLOAD_BYTES + 1).unwrap_err();
        assert_eq!(
            error,
            WanPayloadError::TooLarge {
                size: MAX_WAN_PAYLOAD_BYTES + 1,
                limit: MAX_WAN_PAYLOAD_BYTES,
            }
        );
    }

    #[test]
    fn one_byte_under_the_limit_is_accepted() {
        assert!(validate_payload_size(MAX_WAN_PAYLOAD_BYTES - 1).is_ok());
    }

    #[test]
    fn oversized_payload_never_receives_transfer_info() {
        assert!(WanPayloadTransferInfo::new(MAX_WAN_PAYLOAD_BYTES + 1).is_err());
    }

    #[test]
    fn each_payload_gets_a_distinct_relay_payload_id() {
        let a = WanPayloadTransferInfo::new(1024).unwrap();
        let b = WanPayloadTransferInfo::new(1024).unwrap();
        assert_ne!(a.relay_payload_id, b.relay_payload_id);
    }
}
