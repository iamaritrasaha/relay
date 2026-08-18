use thiserror::Error;

pub mod client;
pub mod dto;
pub mod dto_relay;
pub mod dto_v2;
#[cfg(any(feature = "anywhere", feature = "anywhere-dev"))]
pub(crate) mod inner_tls;
pub mod server;
pub mod state;

#[derive(Debug, Error)]
#[error("{status};{message:?}")]
pub struct StatusCodeError {
    pub status: u16,
    pub message: Option<String>,
}
