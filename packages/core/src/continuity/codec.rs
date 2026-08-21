//! Length-prefixed framing for [`ContinuityEnvelopeV1`].
//!
//! Wire frame: a 4-byte big-endian length followed by that many bytes of JSON.
//! The length is checked against [`MAX_ENVELOPE_BYTES`] *before* any buffer is
//! allocated, so a hostile peer cannot make this side reserve memory it names.
//! Decoding never panics: malformed JSON, truncated frames and oversized frames
//! are all ordinary errors.

use thiserror::Error;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use super::protocol::{ContinuityEnvelopeV1, ContinuityProtocolError, MAX_ENVELOPE_BYTES};

pub const LENGTH_PREFIX_BYTES: usize = 4;

#[derive(Debug, Error)]
pub enum ContinuityCodecError {
    #[error("continuity frame of {size} bytes exceeds the {MAX_ENVELOPE_BYTES} byte limit")]
    FrameTooLarge { size: usize },
    #[error("continuity frame was empty")]
    EmptyFrame,
    #[error("continuity frame was not valid JSON")]
    Malformed,
    #[error(transparent)]
    Protocol(#[from] ContinuityProtocolError),
    #[error("continuity stream closed")]
    Closed,
    #[error("continuity stream I/O failed: {0}")]
    Io(#[from] std::io::Error),
}

impl ContinuityCodecError {
    /// Whether the peer merely sent something this build cannot use, as opposed
    /// to the transport failing. Recoverable errors are answered with an error
    /// envelope and the session continues.
    pub fn is_recoverable(&self) -> bool {
        matches!(
            self,
            Self::FrameTooLarge { .. } | Self::EmptyFrame | Self::Malformed | Self::Protocol(_)
        )
    }
}

/// Serialises and validates one envelope into a complete frame.
///
/// Validation runs on the way out too: a local bug must not put a frame on the
/// wire that the peer is obliged to reject.
pub fn encode_frame(envelope: &ContinuityEnvelopeV1) -> Result<Vec<u8>, ContinuityCodecError> {
    envelope.validate()?;
    let body = serde_json::to_vec(envelope).map_err(|_| ContinuityCodecError::Malformed)?;
    if body.len() > MAX_ENVELOPE_BYTES {
        return Err(ContinuityCodecError::FrameTooLarge { size: body.len() });
    }
    let mut frame = Vec::with_capacity(LENGTH_PREFIX_BYTES + body.len());
    frame.extend_from_slice(&(body.len() as u32).to_be_bytes());
    frame.extend_from_slice(&body);
    Ok(frame)
}

/// Decodes one already-read frame body.
pub fn decode_body(body: &[u8]) -> Result<ContinuityEnvelopeV1, ContinuityCodecError> {
    if body.is_empty() {
        return Err(ContinuityCodecError::EmptyFrame);
    }
    let envelope: ContinuityEnvelopeV1 =
        serde_json::from_slice(body).map_err(|_| ContinuityCodecError::Malformed)?;
    envelope.validate()?;
    Ok(envelope)
}

pub async fn write_envelope<W>(
    writer: &mut W,
    envelope: &ContinuityEnvelopeV1,
) -> Result<(), ContinuityCodecError>
where
    W: AsyncWrite + Unpin,
{
    let frame = encode_frame(envelope)?;
    writer.write_all(&frame).await?;
    writer.flush().await?;
    Ok(())
}

/// Reads exactly one frame.
///
/// An oversized length prefix is reported without reading the body, which also
/// ends the session: the stream position can no longer be trusted.
pub async fn read_envelope<R>(reader: &mut R) -> Result<ContinuityEnvelopeV1, ContinuityCodecError>
where
    R: AsyncRead + Unpin,
{
    let mut length_bytes = [0_u8; LENGTH_PREFIX_BYTES];
    match reader.read_exact(&mut length_bytes).await {
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::UnexpectedEof => {
            return Err(ContinuityCodecError::Closed)
        }
        Err(error) => return Err(error.into()),
    }
    let size = u32::from_be_bytes(length_bytes) as usize;
    if size == 0 {
        return Err(ContinuityCodecError::EmptyFrame);
    }
    if size > MAX_ENVELOPE_BYTES {
        return Err(ContinuityCodecError::FrameTooLarge { size });
    }
    let mut body = vec![0_u8; size];
    reader.read_exact(&mut body).await?;
    decode_body(&body)
}
