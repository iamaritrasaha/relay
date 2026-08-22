//! Relay WAN wire framing: a length-prefixed reliable QUIC control stream
//! carrying KDE-compatible `NetworkPacket` JSON, plus the WAN hello used to
//! negotiate a session before any KDE packet is exchanged.
//!
//! This is not a parallel protocol for clipboard/notifications/SMS/etc. --
//! the payload of every frame after the hello is exactly the same
//! [`crate::kdeconnect::NetworkPacket`] JSON the LAN transport already uses.
//! Relay WAN only adds framing (LAN uses newline-delimited JSON directly on a
//! TCP+TLS stream; a QUIC stream has no reliable newline boundary guarantee
//! across message sizes, so WAN frames are length-prefixed instead) and a
//! protocol version for the hello handshake itself.

use serde::{Deserialize, Serialize};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::kdeconnect::packet::{is_valid_device_id, NetworkPacket};

/// Relay WAN protocol version. Independent of [`crate::kdeconnect::PROTOCOL_VERSION`]
/// (the KDE Connect protocol version), which is negotiated separately inside
/// [`WanHello::kde_protocol_version`].
pub const WAN_PROTOCOL_VERSION: i64 = 1;

/// Bound on the hello frame -- small, fixed-shape, never attacker-controlled
/// in size the way a packet or payload frame can be.
pub const MAX_HELLO_FRAME_BYTES: usize = 8 * 1024;

/// Bound on a KDE `NetworkPacket` frame carried over WAN. Matches
/// [`crate::kdeconnect::packet::MAX_PACKET_BYTES`] so WAN never accepts a
/// packet the LAN transport would have rejected.
pub const MAX_PACKET_FRAME_BYTES: usize = 4 * 1024 * 1024;

const LEN_PREFIX_BYTES: usize = 4;

#[derive(Debug, Clone, Copy, Eq, PartialEq, thiserror::Error)]
pub enum WanFrameError {
    #[error("Relay WAN frame exceeds the {limit}-byte bound ({len} bytes declared)")]
    TooLarge { len: usize, limit: usize },
    #[error("Relay WAN frame declared zero length")]
    Empty,
    #[error("Relay WAN stream ended before the declared frame length")]
    UnexpectedEof,
    #[error("Relay WAN stream I/O error")]
    Io,
}

impl From<std::io::Error> for WanFrameError {
    fn from(error: std::io::Error) -> Self {
        if error.kind() == std::io::ErrorKind::UnexpectedEof {
            WanFrameError::UnexpectedEof
        } else {
            WanFrameError::Io
        }
    }
}

/// Encodes `payload` as `u32` big-endian length prefix followed by the bytes.
/// Bounded by `max_len` so a caller can never encode a frame its own peer
/// would refuse to parse.
pub fn encode_frame(payload: &[u8], max_len: usize) -> Result<Vec<u8>, WanFrameError> {
    if payload.is_empty() {
        return Err(WanFrameError::Empty);
    }
    if payload.len() > max_len {
        return Err(WanFrameError::TooLarge {
            len: payload.len(),
            limit: max_len,
        });
    }
    let mut framed = Vec::with_capacity(LEN_PREFIX_BYTES + payload.len());
    framed.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    framed.extend_from_slice(payload);
    Ok(framed)
}

/// Reads one length-prefixed frame, rejecting a declared length of zero or
/// above `max_len` before ever allocating or reading the body. This is the
/// bounded-parsing guard against a malicious or corrupt oversized frame.
pub async fn read_frame<R: AsyncRead + Unpin>(
    reader: &mut R,
    max_len: usize,
) -> Result<Vec<u8>, WanFrameError> {
    let mut len_buf = [0_u8; LEN_PREFIX_BYTES];
    reader.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len == 0 {
        return Err(WanFrameError::Empty);
    }
    if len > max_len {
        return Err(WanFrameError::TooLarge { len, limit: max_len });
    }
    let mut body = vec![0_u8; len];
    reader.read_exact(&mut body).await?;
    Ok(body)
}

pub async fn write_frame<W: AsyncWrite + Unpin>(
    writer: &mut W,
    payload: &[u8],
    max_len: usize,
) -> Result<(), WanFrameError> {
    let framed = encode_frame(payload, max_len)?;
    writer.write_all(&framed).await?;
    writer.flush().await?;
    Ok(())
}

pub async fn read_packet_frame<R: AsyncRead + Unpin>(
    reader: &mut R,
) -> Result<NetworkPacket, WanFrameError> {
    let bytes = read_frame(reader, MAX_PACKET_FRAME_BYTES).await?;
    NetworkPacket::parse(&bytes).map_err(|_| WanFrameError::Io)
}

pub async fn write_packet_frame<W: AsyncWrite + Unpin>(
    writer: &mut W,
    packet: &NetworkPacket,
) -> Result<(), WanFrameError> {
    let mut bytes = packet.serialize();
    // NetworkPacket::serialize() appends a LAN newline delimiter WAN framing
    // does not need; strip it so the frame carries exactly the JSON body.
    if bytes.last() == Some(&b'\n') {
        bytes.pop();
    }
    write_frame(writer, &bytes, MAX_PACKET_FRAME_BYTES).await
}

/// Relay WAN hello, exchanged by both sides immediately after the Iroh
/// connection is accepted/opened and before any KDE `NetworkPacket` flows.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WanHello {
    pub wan_protocol_version: i64,
    pub kde_device_id: String,
    pub endpoint_id: String,
    pub device_name: String,
    pub device_type: String,
    pub kde_protocol_version: i64,
    pub capability_digest: String,
    pub app_version: String,
}

#[derive(Debug, Clone, Eq, PartialEq, thiserror::Error)]
pub enum WanHelloError {
    #[error("unsupported Relay WAN protocol version {0}")]
    UnsupportedVersion(i64),
    #[error("hello claimed KDE device id does not match the authenticated binding")]
    DeviceIdMismatch,
    #[error("hello claimed EndpointId does not match the authenticated Iroh connection")]
    EndpointIdMismatch,
    #[error("hello KDE device id has an invalid shape")]
    InvalidDeviceId,
    #[error("hello field exceeds its bound")]
    FieldTooLong,
}

const MAX_TEXT_FIELD_LEN: usize = 256;
const MAX_DIGEST_FIELD_LEN: usize = 512;

impl WanHello {
    /// Validates a *remote* hello against the identity Relay WAN already
    /// authenticated out-of-band (the binding resolved from the Iroh
    /// connection's `remote_id()`). A hello can only narrow what is already
    /// trusted -- it can never itself grant trust.
    pub fn validate(
        &self,
        expected_kde_device_id: &str,
        expected_endpoint_id: &iroh::EndpointId,
    ) -> Result<(), WanHelloError> {
        if self.wan_protocol_version != WAN_PROTOCOL_VERSION {
            return Err(WanHelloError::UnsupportedVersion(self.wan_protocol_version));
        }
        if !is_valid_device_id(&self.kde_device_id) {
            return Err(WanHelloError::InvalidDeviceId);
        }
        if self.kde_device_id != expected_kde_device_id {
            return Err(WanHelloError::DeviceIdMismatch);
        }
        let claimed_endpoint_id: iroh::EndpointId = self
            .endpoint_id
            .parse()
            .map_err(|_| WanHelloError::EndpointIdMismatch)?;
        if &claimed_endpoint_id != expected_endpoint_id {
            return Err(WanHelloError::EndpointIdMismatch);
        }
        if self.device_name.len() > MAX_TEXT_FIELD_LEN
            || self.device_type.len() > MAX_TEXT_FIELD_LEN
            || self.app_version.len() > MAX_TEXT_FIELD_LEN
        {
            return Err(WanHelloError::FieldTooLong);
        }
        if self.capability_digest.len() > MAX_DIGEST_FIELD_LEN {
            return Err(WanHelloError::FieldTooLong);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use iroh::SecretKey;

    #[tokio::test]
    async fn frame_round_trips_through_read_and_write() {
        let mut buf = Vec::new();
        write_frame(&mut buf, b"hello", 1024).await.unwrap();
        let mut cursor = std::io::Cursor::new(buf);
        let read_back = read_frame(&mut cursor, 1024).await.unwrap();
        assert_eq!(read_back, b"hello");
    }

    #[tokio::test]
    async fn oversized_declared_length_is_rejected_before_reading_the_body() {
        // Declares a 10-byte body but never supplies it -- if the reader
        // allocated/blocked on the body this would hang instead of erroring.
        let mut buf = Vec::new();
        buf.extend_from_slice(&10_u32.to_be_bytes());
        let mut cursor = std::io::Cursor::new(buf);
        let error = read_frame(&mut cursor, 4).await.unwrap_err();
        assert_eq!(error, WanFrameError::TooLarge { len: 10, limit: 4 });
    }

    #[tokio::test]
    async fn zero_length_frame_is_rejected() {
        let mut buf = Vec::new();
        buf.extend_from_slice(&0_u32.to_be_bytes());
        let mut cursor = std::io::Cursor::new(buf);
        let error = read_frame(&mut cursor, 1024).await.unwrap_err();
        assert_eq!(error, WanFrameError::Empty);
    }

    #[tokio::test]
    async fn truncated_stream_is_an_unexpected_eof_not_a_hang() {
        let mut buf = Vec::new();
        buf.extend_from_slice(&5_u32.to_be_bytes());
        buf.extend_from_slice(b"ab"); // fewer than the declared 5 bytes
        let mut cursor = std::io::Cursor::new(buf);
        let error = read_frame(&mut cursor, 1024).await.unwrap_err();
        assert_eq!(error, WanFrameError::UnexpectedEof);
    }

    #[test]
    fn encode_frame_refuses_to_build_an_oversized_frame() {
        let payload = vec![0_u8; 10];
        let error = encode_frame(&payload, 4).unwrap_err();
        assert_eq!(error, WanFrameError::TooLarge { len: 10, limit: 4 });
    }

    fn sample_hello(kde_device_id: &str, endpoint_id: &iroh::EndpointId) -> WanHello {
        WanHello {
            wan_protocol_version: WAN_PROTOCOL_VERSION,
            kde_device_id: kde_device_id.to_owned(),
            endpoint_id: endpoint_id.to_string(),
            device_name: "Phone".to_owned(),
            device_type: "phone".to_owned(),
            kde_protocol_version: 8,
            capability_digest: "digest".to_owned(),
            app_version: "0.2.0".to_owned(),
        }
    }

    #[test]
    fn matching_hello_validates() {
        let endpoint_id = SecretKey::generate().public();
        let device_id = "a".repeat(32);
        let hello = sample_hello(&device_id, &endpoint_id);
        assert!(hello.validate(&device_id, &endpoint_id).is_ok());
    }

    #[test]
    fn hello_claiming_a_different_device_id_is_rejected() {
        let endpoint_id = SecretKey::generate().public();
        let device_id = "a".repeat(32);
        let hello = sample_hello(&"b".repeat(32), &endpoint_id);
        assert_eq!(
            hello.validate(&device_id, &endpoint_id).unwrap_err(),
            WanHelloError::DeviceIdMismatch
        );
    }

    #[test]
    fn hello_claiming_a_different_endpoint_id_is_rejected() {
        let endpoint_id = SecretKey::generate().public();
        let other_endpoint_id = SecretKey::generate().public();
        let device_id = "a".repeat(32);
        let hello = sample_hello(&device_id, &other_endpoint_id);
        assert_eq!(
            hello.validate(&device_id, &endpoint_id).unwrap_err(),
            WanHelloError::EndpointIdMismatch
        );
    }

    #[test]
    fn unsupported_protocol_version_is_rejected() {
        let endpoint_id = SecretKey::generate().public();
        let device_id = "a".repeat(32);
        let mut hello = sample_hello(&device_id, &endpoint_id);
        hello.wan_protocol_version = 99;
        assert_eq!(
            hello.validate(&device_id, &endpoint_id).unwrap_err(),
            WanHelloError::UnsupportedVersion(99)
        );
    }
}
