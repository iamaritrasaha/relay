use std::fmt;

use thiserror::Error;

use crate::relay::{RelayAuthError, RelayId};

/// Maximum length of a retained library cause string.
const MAX_CAUSE_LEN: usize = 200;

/// The exact transport operation that failed.
///
/// Categories stay stable for UI; the stage exists so a failure can be located
/// without re-running an investigation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransportStage {
    /// Binding the local Iroh endpoint.
    Bind,
    /// Dialing the remote endpoint.
    Connect,
    /// Accepting an inbound Iroh connection.
    Accept,
    /// Opening or accepting the bidirectional stream.
    Stream,
    /// Reading or writing Relay proof frames on an established stream.
    ProofIo,
}

impl TransportStage {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bind => "bind",
            Self::Connect => "connect",
            Self::Accept => "accept",
            Self::Stream => "stream",
            Self::ProofIo => "proof-io",
        }
    }
}

impl fmt::Display for TransportStage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// Which side of the inner TLS handshake failed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TlsStage {
    /// Inner TLS client handshake (initiator).
    ClientHandshake,
    /// Inner TLS server handshake (responder).
    ServerHandshake,
    /// Reading the peer certificate off a completed handshake.
    PeerCertificate,
}

impl TlsStage {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ClientHandshake => "client-handshake",
            Self::ServerHandshake => "server-handshake",
            Self::PeerCertificate => "peer-certificate",
        }
    }
}

impl fmt::Display for TlsStage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// Production Anywhere failures.
///
/// Messages carry a sanitized library cause only. No private key, proof frame,
/// certificate body, or address token is ever placed in an error.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum AnywhereError {
    #[error("Anywhere transport failed at {stage}: {cause}")]
    Transport {
        stage: TransportStage,
        cause: String,
    },
    #[error("Anywhere inner TLS failed at {stage}: {cause}")]
    Tls { stage: TlsStage, cause: String },
    #[error("Anywhere Relay proof failed")]
    RelayProof,
    #[error("the proven RelayId does not match the expected identity")]
    ExpectedIdentityMismatch { expected: RelayId, proven: RelayId },
    #[error("Anywhere transfer was denied")]
    AuthorizationDenied,
    #[error("Anywhere completion protocol failed")]
    ProtocolCompletion,
    #[error("Anywhere session cancelled")]
    Cancelled,
    #[error("Anywhere session timed out at {stage}")]
    Timeout { stage: TransportStage },
}

impl AnywhereError {
    /// Builds a transport failure with a sanitized cause from any library error.
    pub fn transport<E: fmt::Display>(stage: TransportStage, cause: E) -> Self {
        Self::Transport {
            stage,
            cause: sanitize_cause(cause),
        }
    }

    /// Builds a transport failure with a fixed, already-safe cause label.
    pub fn transport_reason(stage: TransportStage, cause: &str) -> Self {
        Self::Transport {
            stage,
            cause: sanitize_cause(cause),
        }
    }

    pub fn tls<E: fmt::Display>(stage: TlsStage, cause: E) -> Self {
        Self::Tls {
            stage,
            cause: sanitize_cause(cause),
        }
    }

    pub fn from_auth(error: RelayAuthError) -> Self {
        match error {
            RelayAuthError::ExpectedIdentityMismatch { expected, proven } => {
                Self::ExpectedIdentityMismatch { expected, proven }
            }
            RelayAuthError::CryptoInvalid
            | RelayAuthError::RoleMismatch
            | RelayAuthError::ChallengeMismatch => Self::RelayProof,
        }
    }

    /// Stable high-level category. Unchanged by the stage detail.
    pub fn category(&self) -> &'static str {
        match self {
            Self::Transport { .. } => "transport",
            Self::Tls { .. } => "tls",
            Self::RelayProof => "identity",
            Self::ExpectedIdentityMismatch { .. } => "identity",
            Self::AuthorizationDenied => "authorization",
            Self::ProtocolCompletion => "completion",
            Self::Cancelled => "cancelled",
            Self::Timeout { .. } => "timeout",
        }
    }

    /// Machine-readable failing operation, for logs and bug reports.
    pub fn stage(&self) -> Option<&'static str> {
        match self {
            Self::Transport { stage, .. } | Self::Timeout { stage } => Some(stage.as_str()),
            Self::Tls { stage, .. } => Some(stage.as_str()),
            _ => None,
        }
    }
}

/// Reduces a library error to a short, single-line, printable cause.
///
/// Truncation plus control-character stripping keeps an unexpected payload from
/// reaching a log or a UI verbatim.
fn sanitize_cause<E: fmt::Display>(cause: E) -> String {
    let raw = cause.to_string();
    let mut cleaned = String::with_capacity(raw.len().min(MAX_CAUSE_LEN));
    let mut last_was_space = false;
    for character in raw.chars() {
        let character = if character.is_control() || character == '\n' {
            ' '
        } else {
            character
        };
        if character == ' ' {
            if last_was_space || cleaned.is_empty() {
                continue;
            }
            last_was_space = true;
        } else {
            last_was_space = false;
        }
        if cleaned.chars().count() >= MAX_CAUSE_LEN {
            cleaned.push('…');
            break;
        }
        cleaned.push(character);
    }
    let cleaned = cleaned.trim_end().to_owned();
    if cleaned.is_empty() {
        "unspecified".to_owned()
    } else {
        cleaned
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stage_is_reported_without_changing_category() {
        let error = AnywhereError::transport(TransportStage::Connect, "no route to host");
        assert_eq!(error.category(), "transport");
        assert_eq!(error.stage(), Some("connect"));
        assert!(error.to_string().contains("connect"));
        assert!(error.to_string().contains("no route to host"));
    }

    #[test]
    fn bind_connect_accept_are_distinguishable() {
        let bind = AnywhereError::transport(TransportStage::Bind, "address in use");
        let connect = AnywhereError::transport(TransportStage::Connect, "address in use");
        let accept = AnywhereError::transport(TransportStage::Accept, "address in use");
        assert_ne!(bind, connect);
        assert_ne!(connect, accept);
        assert_eq!(bind.category(), accept.category());
    }

    #[test]
    fn cause_is_truncated_and_single_line() {
        let error = AnywhereError::transport(TransportStage::Stream, "a\nb\r\tc");
        let AnywhereError::Transport { cause, .. } = &error else {
            panic!("expected transport error");
        };
        assert_eq!(cause, "a b c");

        let long = "x".repeat(1000);
        let error = AnywhereError::transport(TransportStage::Stream, long);
        let AnywhereError::Transport { cause, .. } = &error else {
            panic!("expected transport error");
        };
        assert!(cause.chars().count() <= MAX_CAUSE_LEN + 1);
    }

    #[test]
    fn tls_stage_distinguishes_client_and_server() {
        let client = AnywhereError::tls(TlsStage::ClientHandshake, "bad certificate");
        let server = AnywhereError::tls(TlsStage::ServerHandshake, "bad certificate");
        assert_ne!(client, server);
        assert_eq!(client.category(), "tls");
        assert_eq!(server.stage(), Some("server-handshake"));
    }
}
