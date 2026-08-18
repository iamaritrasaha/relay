use thiserror::Error;

use crate::relay::{RelayAuthError, RelayId};

/// Production Anywhere failures. Messages contain no private-key or proof bytes.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum AnywhereError {
    #[error("Anywhere transport failed")]
    Transport,
    #[error("Anywhere inner TLS failed")]
    Tls,
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
    #[error("Anywhere session timed out")]
    Timeout,
}

impl AnywhereError {
    pub fn from_auth(error: RelayAuthError) -> Self {
        match error {
            RelayAuthError::ExpectedIdentityMismatch { expected, proven } => {
                Self::ExpectedIdentityMismatch { expected, proven }
            }
            RelayAuthError::CryptoInvalid | RelayAuthError::RoleMismatch => Self::RelayProof,
        }
    }

    pub fn category(&self) -> &'static str {
        match self {
            Self::Transport => "transport",
            Self::Tls => "tls",
            Self::RelayProof => "identity",
            Self::ExpectedIdentityMismatch { .. } => "identity",
            Self::AuthorizationDenied => "authorization",
            Self::ProtocolCompletion => "completion",
            Self::Cancelled => "cancelled",
            Self::Timeout => "timeout",
        }
    }
}
