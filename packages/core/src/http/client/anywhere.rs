//! Narrow HTTP/1.1 client for a caller-owned authenticated Anywhere stream.
//!
//! LAN remains on [`reqwest`](super::LsHttpClient). This adapter only accepts
//! an [`AuthenticatedRelaySession`], so HTTP cannot begin before the inner TLS
//! and mutual Relay proof boundary has completed.

use super::{
    classify_prepare_upload_status, classify_upload_status, ClientError, PrepareUploadStatus,
};
use crate::model::transfer::FileContent;
use crate::relay::AuthenticatedRelaySession;
use bytes::Bytes;
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Full, StreamBody};
use hyper::body::{Frame, Incoming};
use hyper::{Method, Request};
use hyper_util::rt::TokioIo;
use serde::de::DeserializeOwned;
use std::convert::Infallible;
use std::io;
use tokio_stream::wrappers::ReceiverStream;
use tokio_stream::StreamExt;
use tokio_util::sync::CancellationToken;

use crate::http::dto_v2::{PrepareUploadRequestDtoV2, PrepareUploadResultV2};

type RequestBody = BoxBody<Bytes, io::Error>;

/// HTTP/1.1 sender over one authenticated Relay Anywhere stream.
pub struct AnywhereHttpClient {
    sender: hyper::client::conn::http1::SendRequest<RequestBody>,
    session: AuthenticatedRelaySession,
}

impl AnywhereHttpClient {
    /// Starts HTTP/1.1 on an already-authenticated stream.
    pub async fn handshake<S>(
        stream: S,
        session: AuthenticatedRelaySession,
    ) -> Result<Self, ClientError>
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        if !session.mutual() {
            return Err(ClientError::Other(anyhow::anyhow!(
                "Anywhere HTTP requires a mutual AuthenticatedRelaySession"
            )));
        }
        let (sender, connection) = hyper::client::conn::http1::handshake(TokioIo::new(stream))
            .await
            .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?;
        tokio::spawn(async move {
            if let Err(error) = connection.await {
                tracing::debug!("Anywhere HTTP connection ended: {error:#}");
            }
        });
        Ok(Self { sender, session })
    }

    pub fn session(&self) -> &AuthenticatedRelaySession {
        &self.session
    }

    /// Shared v2 prepare-upload semantics over the Anywhere stream.
    pub async fn prepare_upload(
        &mut self,
        payload: PrepareUploadRequestDtoV2,
        pin: Option<&str>,
        cancel: CancellationToken,
    ) -> Result<PrepareUploadResultV2, ClientError> {
        let path = v2_path("prepare-upload", pin);
        let body = serde_json::to_vec(&payload)?;
        let request = Request::builder()
            .method(Method::POST)
            .uri(path)
            .header("content-type", "application/json")
            .body(full_body(Bytes::from(body)))
            .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?;
        let response = tokio::select! {
            response = self.sender.send_request(request) => response.map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?,
            _ = cancel.cancelled() => return Err(ClientError::Cancelled),
        };
        let status = response.status();
        if matches!(classify_prepare_upload_status(status.as_u16()), Err(_)) {
            return hyper_into_error(response).await;
        }
        if matches!(
            classify_prepare_upload_status(status.as_u16()),
            Ok(PrepareUploadStatus::NoContent)
        ) {
            return Ok(PrepareUploadResultV2 {
                status_code: status.as_u16(),
                response: None,
            });
        }
        let body = collect_json(response).await?;
        Ok(PrepareUploadResultV2 {
            status_code: status.as_u16(),
            response: Some(body),
        })
    }

    /// Streams one file using the exact v2 upload endpoint and status mapping.
    pub async fn upload(
        &mut self,
        session_id: &str,
        file_id: &str,
        token: &str,
        content: FileContent,
        content_length: u64,
        progress: impl Fn(u64) + Send + Sync + 'static,
        cancel: CancellationToken,
    ) -> Result<(), ClientError> {
        let path = format!(
            "/api/localsend/v2/upload?sessionId={}&fileId={}&token={}",
            encode(session_id),
            encode(file_id),
            encode(token),
        );
        let mut sent = 0_u64;
        let stream = ReceiverStream::new(content.into_receiver()).map(move |chunk| {
            sent = sent.saturating_add(chunk.len() as u64);
            progress(sent.min(content_length));
            Ok::<Frame<Bytes>, Infallible>(Frame::data(chunk))
        });
        let body = StreamBody::new(stream).map_err(io::Error::other).boxed();
        let request = Request::builder()
            .method(Method::POST)
            .uri(path)
            .header("content-length", content_length)
            .body(body)
            .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?;
        let response = tokio::select! {
            response = self.sender.send_request(request) => response.map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?,
            _ = cancel.cancelled() => return Err(ClientError::Cancelled),
        };
        if classify_upload_status(response.status().as_u16()).is_err() {
            return hyper_into_error(response).await;
        }
        Ok(())
    }

    pub async fn cancel(&mut self, session_id: &str) -> Result<(), ClientError> {
        let request = Request::builder()
            .method(Method::POST)
            .uri(format!(
                "/api/localsend/v2/cancel?sessionId={}",
                encode(session_id)
            ))
            .body(empty_body())
            .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?;
        let response = self
            .sender
            .send_request(request)
            .await
            .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?;
        if classify_upload_status(response.status().as_u16()).is_err() {
            return hyper_into_error(response).await;
        }
        Ok(())
    }
}

fn v2_path(endpoint: &str, pin: Option<&str>) -> String {
    match pin {
        Some(pin) => format!("/api/localsend/v2/{endpoint}?pin={}", encode(pin)),
        None => format!("/api/localsend/v2/{endpoint}"),
    }
}

fn encode(value: &str) -> String {
    form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

fn full_body(bytes: Bytes) -> RequestBody {
    Full::new(bytes).map_err(io::Error::other).boxed()
}

fn empty_body() -> RequestBody {
    full_body(Bytes::new())
}

async fn collect_json<T: DeserializeOwned>(
    response: hyper::Response<Incoming>,
) -> Result<T, ClientError> {
    let bytes = response
        .into_body()
        .collect()
        .await
        .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?
        .to_bytes();
    serde_json::from_slice(&bytes).map_err(ClientError::Json)
}

async fn hyper_into_error<T>(response: hyper::Response<Incoming>) -> Result<T, ClientError> {
    let status = response.status().as_u16();
    let body = response
        .into_body()
        .collect()
        .await
        .map_err(|error| ClientError::Other(anyhow::anyhow!(error)))?
        .to_bytes();
    let message = serde_json::from_slice::<serde_json::Value>(&body)
        .ok()
        .and_then(|value| {
            value
                .get("message")
                .and_then(|value| value.as_str())
                .map(str::to_owned)
        })
        .or_else(|| (!body.is_empty()).then(|| String::from_utf8_lossy(&body).into_owned()));
    Err(ClientError::StatusCode(crate::http::StatusCodeError {
        status,
        message,
    }))
}
