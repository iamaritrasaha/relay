//! Canonical authenticated Relay v2 transfer execution.
//!
//! Transport adapters establish and authenticate a connection.  This module
//! owns everything above that boundary: v2 prepare-upload interpretation,
//! accepted-file selection, streaming order, cancellation, and product
//! transfer events.  It deliberately has no knowledge of Iroh, reqwest,
//! Flutter, or a UI save location.

use std::collections::{HashMap, HashSet};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::http::client::{AnywhereHttpClient, ClientError, LsHttpClient};
use crate::http::dto::{PrepareUploadRequestDto, PrepareUploadResponseDto};
use crate::http::dto_v2::{PrepareUploadRequestDtoV2, PrepareUploadResponseDtoV2, RegisterDtoV2};
use crate::model::discovery::ProtocolType;
use crate::model::transfer::{FileContent, FileDto};

use super::transport::TransferFuture;
use super::{
    EstablishedTransportSession, ProductionLanConnection, RelaySendError, RelayTransferExecutor,
    TransportOrigin,
};

/// One source supplied to the canonical transfer engine.
///
/// [`FileContent`] remains the single bounded streaming source abstraction:
/// paths are read in chunks, Android descriptors are consumed directly, and
/// callers that already own a stream can hand it over without buffering it.
#[derive(Debug)]
pub struct RelayTransferFile {
    pub dto: FileDto,
    pub content: FileContent,
}

/// A complete transport-neutral v2 upload request.
///
/// The DTO metadata is intentionally canonical v2 metadata.  A LAN adapter
/// may translate it for a legacy v3 peer at its I/O boundary, but the state
/// machine never changes with the selected transport.
#[derive(Debug)]
pub struct RelayTransferRequest {
    pub transfer_id: String,
    pub info: RegisterDtoV2,
    pub files: Vec<RelayTransferFile>,
    /// A PIN is presentation input, not transport policy.  If the recipient
    /// requires one, the engine returns a typed failure and the presentation
    /// layer may resubmit this same logical request with a PIN.
    pub pin: Option<String>,
}

impl RelayTransferRequest {
    pub fn total_bytes(&self) -> u64 {
        self.files
            .iter()
            .fold(0_u64, |total, file| total.saturating_add(file.dto.size))
    }

    fn prepare_payload(&self) -> Result<PrepareUploadRequestDtoV2, RelaySendError> {
        if self.files.is_empty() {
            return Err(RelaySendError::TransferFailed {
                detail: "outbound transfer contains no files".to_owned(),
            });
        }
        let mut files = HashMap::with_capacity(self.files.len());
        for file in &self.files {
            if files
                .insert(file.dto.id.clone(), file.dto.clone())
                .is_some()
            {
                return Err(RelaySendError::TransferFailed {
                    detail: "outbound transfer contains duplicate file ids".to_owned(),
                });
            }
        }
        Ok(PrepareUploadRequestDtoV2 {
            info: self.info.clone(),
            files,
        })
    }
}

/// Canonical product lifecycle event.  Every authenticated transport emits
/// this vocabulary; `origin` is status metadata only.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RelayTransferEvent {
    OutgoingStarted {
        transfer_id: String,
        total_bytes: u64,
        origin: TransportOrigin,
    },
    Accepted {
        transfer_id: String,
        session_id: String,
        accepted_files: Vec<String>,
        total_bytes: u64,
        origin: TransportOrigin,
    },
    Declined {
        transfer_id: String,
        file_id: Option<String>,
        origin: TransportOrigin,
    },
    FileStarted {
        transfer_id: String,
        session_id: String,
        file_id: String,
        file_name: String,
        file_index: usize,
        file_count: usize,
        total_bytes: u64,
        origin: TransportOrigin,
    },
    FileProgress {
        transfer_id: String,
        session_id: String,
        file_id: String,
        bytes: u64,
        total_bytes: u64,
        origin: TransportOrigin,
    },
    OverallProgress {
        transfer_id: String,
        session_id: String,
        bytes: u64,
        total_bytes: u64,
        origin: TransportOrigin,
    },
    Completed {
        transfer_id: String,
        session_id: Option<String>,
        bytes: u64,
        origin: TransportOrigin,
    },
    Failed {
        transfer_id: String,
        origin: TransportOrigin,
    },
    Cancelled {
        transfer_id: String,
        origin: TransportOrigin,
    },
}

pub type RelayTransferEventSink = Arc<dyn Fn(RelayTransferEvent) + Send + Sync>;
pub type RelayTransferProgressSink = Arc<dyn Fn(u64) + Send + Sync>;
pub type RelayTransferFuture<'a, T> =
    Pin<Box<dyn Future<Output = Result<T, ClientError>> + Send + 'a>>;

/// Minimal HTTP-like surface supplied by an authenticated transport.
///
/// This is intentionally narrower than either reqwest or Hyper.  The engine
/// owns the v2 protocol interpretation; adapters only execute its requests on
/// an already-authenticated channel.
pub trait AuthenticatedTransferTransport {
    fn prepare_upload<'a>(
        &'a mut self,
        payload: PrepareUploadRequestDtoV2,
        pin: Option<&'a str>,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, CanonicalPrepareUploadResult>;

    fn upload<'a>(
        &'a mut self,
        session_id: &'a str,
        file_id: &'a str,
        token: &'a str,
        content: FileContent,
        content_length: u64,
        progress: RelayTransferProgressSink,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, ()>;

    fn cancel<'a>(&'a mut self, session_id: &'a str) -> RelayTransferFuture<'a, ()>;
}

/// Transport-neutral prepare result.  The normal v2 `204` response is
/// represented without inventing a pseudo session id.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CanonicalPrepareUploadResult {
    NoContent,
    Accepted {
        session_id: String,
        file_tokens: HashMap<String, String>,
    },
}

/// Thin adapter over the already-authenticated HTTP/1.1 stream used by
/// Anywhere.  It has no batch, progress, or decision policy of its own.
pub struct AnywhereTransferTransport<'a> {
    client: &'a mut AnywhereHttpClient,
}

impl<'a> AnywhereTransferTransport<'a> {
    pub fn new(client: &'a mut AnywhereHttpClient) -> Self {
        Self { client }
    }
}

impl AuthenticatedTransferTransport for AnywhereTransferTransport<'_> {
    fn prepare_upload<'a>(
        &'a mut self,
        payload: PrepareUploadRequestDtoV2,
        pin: Option<&'a str>,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, CanonicalPrepareUploadResult> {
        Box::pin(async move {
            let result = self.client.prepare_upload(payload, pin, cancel).await?;
            Ok(canonical_prepare_from_v2(
                result.status_code,
                result.response,
            ))
        })
    }

    fn upload<'a>(
        &'a mut self,
        session_id: &'a str,
        file_id: &'a str,
        token: &'a str,
        content: FileContent,
        content_length: u64,
        progress: RelayTransferProgressSink,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, ()> {
        Box::pin(async move {
            self.client
                .upload(
                    session_id,
                    file_id,
                    token,
                    content,
                    content_length,
                    move |bytes| progress(bytes),
                    cancel,
                )
                .await
        })
    }

    fn cancel<'a>(&'a mut self, session_id: &'a str) -> RelayTransferFuture<'a, ()> {
        Box::pin(async move { self.client.cancel(session_id).await })
    }
}

/// Thin adapter over the certificate-pinned LAN connection returned by
/// [`super::LanRelaySessionFactory`].  It retains that exact client, so the
/// certificate proof and all subsequent metadata/body requests use the same
/// TLS pin.
pub struct LanTransferTransport<'a> {
    connection: &'a ProductionLanConnection,
}

/// Adapter for an application-held LAN client that was already created with
/// the selected peer certificate pin.  This keeps the Rust transfer engine
/// usable at the production bridge without reconstructing an unpinned client.
pub struct PinnedLanTransferTransport<'a> {
    client: &'a LsHttpClient,
    protocol: ProtocolType,
    host: &'a str,
    port: u16,
}

impl<'a> PinnedLanTransferTransport<'a> {
    pub fn new(client: &'a LsHttpClient, protocol: ProtocolType, host: &'a str, port: u16) -> Self {
        Self {
            client,
            protocol,
            host,
            port,
        }
    }
}

impl AuthenticatedTransferTransport for PinnedLanTransferTransport<'_> {
    fn prepare_upload<'a>(
        &'a mut self,
        payload: PrepareUploadRequestDtoV2,
        pin: Option<&'a str>,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, CanonicalPrepareUploadResult> {
        Box::pin(async move {
            let result = self
                .client
                .prepare_upload(
                    self.protocol,
                    self.host,
                    self.port,
                    None,
                    PrepareUploadRequestDto::from(payload),
                    pin,
                    cancel,
                )
                .await?;
            Ok(canonical_prepare_from_legacy(
                result.status_code,
                result.response,
            ))
        })
    }

    fn upload<'a>(
        &'a mut self,
        session_id: &'a str,
        file_id: &'a str,
        token: &'a str,
        content: FileContent,
        _content_length: u64,
        progress: RelayTransferProgressSink,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, ()> {
        Box::pin(async move {
            self.client
                .upload(
                    self.protocol,
                    self.host,
                    self.port,
                    None,
                    session_id,
                    file_id,
                    token,
                    content,
                    move |bytes| progress(bytes),
                    cancel,
                )
                .await
        })
    }

    fn cancel<'a>(&'a mut self, session_id: &'a str) -> RelayTransferFuture<'a, ()> {
        Box::pin(async move {
            self.client
                .cancel(self.protocol, self.host, self.port, session_id)
                .await
        })
    }
}

impl<'a> LanTransferTransport<'a> {
    pub fn new(connection: &'a ProductionLanConnection) -> Self {
        Self { connection }
    }
}

impl AuthenticatedTransferTransport for LanTransferTransport<'_> {
    fn prepare_upload<'a>(
        &'a mut self,
        payload: PrepareUploadRequestDtoV2,
        pin: Option<&'a str>,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, CanonicalPrepareUploadResult> {
        Box::pin(async move {
            let result = self
                .connection
                .client()
                .prepare_upload(
                    self.connection.protocol(),
                    self.connection.host(),
                    self.connection.port(),
                    None,
                    PrepareUploadRequestDto::from(payload),
                    pin,
                    cancel,
                )
                .await?;
            Ok(canonical_prepare_from_legacy(
                result.status_code,
                result.response,
            ))
        })
    }

    fn upload<'a>(
        &'a mut self,
        session_id: &'a str,
        file_id: &'a str,
        token: &'a str,
        content: FileContent,
        _content_length: u64,
        progress: RelayTransferProgressSink,
        cancel: CancellationToken,
    ) -> RelayTransferFuture<'a, ()> {
        Box::pin(async move {
            self.connection
                .client()
                .upload(
                    self.connection.protocol(),
                    self.connection.host(),
                    self.connection.port(),
                    None,
                    session_id,
                    file_id,
                    token,
                    content,
                    move |bytes| progress(bytes),
                    cancel,
                )
                .await
        })
    }

    fn cancel<'a>(&'a mut self, session_id: &'a str) -> RelayTransferFuture<'a, ()> {
        Box::pin(async move {
            self.connection
                .client()
                .cancel(
                    self.connection.protocol(),
                    self.connection.host(),
                    self.connection.port(),
                    session_id,
                )
                .await
        })
    }
}

fn canonical_prepare_from_v2(
    status_code: u16,
    response: Option<PrepareUploadResponseDtoV2>,
) -> CanonicalPrepareUploadResult {
    match response {
        Some(response) => CanonicalPrepareUploadResult::Accepted {
            session_id: response.session_id,
            file_tokens: response.files,
        },
        None => {
            debug_assert_eq!(status_code, 204);
            CanonicalPrepareUploadResult::NoContent
        }
    }
}

fn canonical_prepare_from_legacy(
    status_code: u16,
    response: Option<PrepareUploadResponseDto>,
) -> CanonicalPrepareUploadResult {
    match response {
        Some(response) => CanonicalPrepareUploadResult::Accepted {
            session_id: response.session_id,
            file_tokens: response.files,
        },
        None => {
            debug_assert_eq!(status_code, 204);
            CanonicalPrepareUploadResult::NoContent
        }
    }
}

/// The sole authenticated outbound v2 lifecycle owner.
#[derive(Clone, Copy, Debug, Default)]
pub struct RelayTransferEngine;

impl RelayTransferEngine {
    pub async fn send<T>(
        &self,
        transport: &mut T,
        request: RelayTransferRequest,
        origin: TransportOrigin,
        cancel: CancellationToken,
        events: RelayTransferEventSink,
    ) -> Result<u64, RelaySendError>
    where
        T: AuthenticatedTransferTransport,
    {
        let total_bytes = request.total_bytes();
        let transfer_id = request.transfer_id.clone();
        events(RelayTransferEvent::OutgoingStarted {
            transfer_id: transfer_id.clone(),
            total_bytes,
            origin,
        });
        let payload = match request.prepare_payload() {
            Ok(payload) => payload,
            Err(error) => {
                events(RelayTransferEvent::Failed {
                    transfer_id,
                    origin,
                });
                return Err(error);
            }
        };
        if cancel.is_cancelled() {
            events(RelayTransferEvent::Cancelled {
                transfer_id,
                origin,
            });
            return Err(RelaySendError::Cancelled);
        }

        let prepared = match transport
            .prepare_upload(payload, request.pin.as_deref(), cancel.clone())
            .await
        {
            Ok(prepared) => prepared,
            Err(error) => {
                return Err(emit_client_error(
                    &events,
                    &transfer_id,
                    origin,
                    error,
                    false,
                ));
            }
        };

        let CanonicalPrepareUploadResult::Accepted {
            session_id,
            file_tokens,
        } = prepared
        else {
            events(RelayTransferEvent::Completed {
                transfer_id,
                session_id: None,
                bytes: 0,
                origin,
            });
            return Ok(0);
        };

        let accepted_ids = file_tokens.keys().cloned().collect::<HashSet<_>>();
        let accepted_total = request
            .files
            .iter()
            .filter(|file| accepted_ids.contains(&file.dto.id))
            .fold(0_u64, |total, file| total.saturating_add(file.dto.size));
        let accepted_files = request
            .files
            .iter()
            .filter(|file| accepted_ids.contains(&file.dto.id))
            .map(|file| file.dto.id.clone())
            .collect::<Vec<_>>();
        events(RelayTransferEvent::Accepted {
            transfer_id: transfer_id.clone(),
            session_id: session_id.clone(),
            accepted_files,
            total_bytes: accepted_total,
            origin,
        });

        let mut completed = 0_u64;
        let file_count = request.files.len();
        for (file_index, file) in request.files.into_iter().enumerate() {
            let file_id = file.dto.id.clone();
            let Some(token) = file_tokens.get(&file_id) else {
                events(RelayTransferEvent::Declined {
                    transfer_id: transfer_id.clone(),
                    file_id: Some(file_id),
                    origin,
                });
                continue;
            };
            if cancel.is_cancelled() {
                let _ = transport.cancel(&session_id).await;
                events(RelayTransferEvent::Cancelled {
                    transfer_id,
                    origin,
                });
                return Err(RelaySendError::Cancelled);
            }
            events(RelayTransferEvent::FileStarted {
                transfer_id: transfer_id.clone(),
                session_id: session_id.clone(),
                file_id: file_id.clone(),
                file_name: file.dto.file_name.clone(),
                file_index,
                file_count,
                total_bytes: file.dto.size,
                origin,
            });
            let base = completed;
            let file_size = file.dto.size;
            let event_transfer_id = transfer_id.clone();
            let event_session_id = session_id.clone();
            let event_file_id = file_id.clone();
            let events_for_progress = events.clone();
            let progress = Arc::new(move |bytes: u64| {
                let file_bytes = bytes.min(file_size);
                events_for_progress(RelayTransferEvent::FileProgress {
                    transfer_id: event_transfer_id.clone(),
                    session_id: event_session_id.clone(),
                    file_id: event_file_id.clone(),
                    bytes: file_bytes,
                    total_bytes: file_size,
                    origin,
                });
                events_for_progress(RelayTransferEvent::OverallProgress {
                    transfer_id: event_transfer_id.clone(),
                    session_id: event_session_id.clone(),
                    bytes: base.saturating_add(file_bytes),
                    total_bytes: accepted_total,
                    origin,
                });
            });
            let result = transport
                .upload(
                    &session_id,
                    &file_id,
                    token,
                    file.content,
                    file.dto.size,
                    progress,
                    cancel.clone(),
                )
                .await;
            match result {
                Ok(()) => {
                    completed = completed.saturating_add(file.dto.size);
                    events(RelayTransferEvent::OverallProgress {
                        transfer_id: transfer_id.clone(),
                        session_id: session_id.clone(),
                        bytes: completed,
                        total_bytes: accepted_total,
                        origin,
                    });
                }
                Err(ClientError::Cancelled) => {
                    let _ = transport.cancel(&session_id).await;
                    events(RelayTransferEvent::Cancelled {
                        transfer_id,
                        origin,
                    });
                    return Err(RelaySendError::Cancelled);
                }
                Err(error) => {
                    return Err(emit_client_error(
                        &events,
                        &transfer_id,
                        origin,
                        error,
                        true,
                    ));
                }
            }
        }
        events(RelayTransferEvent::Completed {
            transfer_id,
            session_id: Some(session_id),
            bytes: completed,
            origin,
        });
        Ok(completed)
    }
}

/// Concrete production executor for the verified LAN session factory.
///
/// The resolver has already checked the authenticated-session requirement
/// before this executor runs.  The adapter is constructed from the exact
/// [`ProductionLanConnection`] whose TLS pin was used for proof, so the engine
/// cannot accidentally swap to an unrestricted HTTP client for file bytes.
#[derive(Clone)]
pub struct CanonicalLanTransferExecutor {
    cancel: CancellationToken,
    events: RelayTransferEventSink,
}

impl CanonicalLanTransferExecutor {
    pub fn new(cancel: CancellationToken, events: RelayTransferEventSink) -> Self {
        Self { cancel, events }
    }
}

impl RelayTransferExecutor<ProductionLanConnection, RelayTransferRequest>
    for CanonicalLanTransferExecutor
{
    fn send<'a>(
        &'a self,
        session: &'a mut EstablishedTransportSession<ProductionLanConnection>,
        request: RelayTransferRequest,
    ) -> TransferFuture<'a> {
        let origin = session.origin();
        let connection = match session {
            EstablishedTransportSession::AuthenticatedRelay { connection, .. }
            | EstablishedTransportSession::LegacyLan { connection, .. } => connection,
        };
        let cancel = self.cancel.clone();
        let events = self.events.clone();
        Box::pin(async move {
            RelayTransferEngine
                .send(
                    &mut LanTransferTransport::new(connection),
                    request,
                    origin,
                    cancel,
                    events,
                )
                .await
                .map(|_| ())
        })
    }
}

fn emit_client_error(
    events: &RelayTransferEventSink,
    transfer_id: &str,
    origin: TransportOrigin,
    error: ClientError,
    _after_prepare: bool,
) -> RelaySendError {
    let result = match error {
        ClientError::Cancelled => {
            events(RelayTransferEvent::Cancelled {
                transfer_id: transfer_id.to_owned(),
                origin,
            });
            return RelaySendError::Cancelled;
        }
        ClientError::StatusCode(status) if status.status == 403 => {
            RelaySendError::AuthorizationDenied
        }
        ClientError::StatusCode(status) if status.status == 401 => RelaySendError::TransferFailed {
            detail: "recipient requires a PIN".to_owned(),
        },
        other => RelaySendError::TransferFailed {
            detail: other.to_string(),
        },
    };
    events(RelayTransferEvent::Failed {
        transfer_id: transfer_id.to_owned(),
        origin,
    });
    result
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;
    use crate::model::discovery::ProtocolType;

    struct MockTransport {
        prepare: Option<Result<CanonicalPrepareUploadResult, ClientError>>,
        uploads: Mutex<Vec<String>>,
        cancelled: Mutex<Vec<String>>,
    }

    impl AuthenticatedTransferTransport for MockTransport {
        fn prepare_upload<'a>(
            &'a mut self,
            _payload: PrepareUploadRequestDtoV2,
            _pin: Option<&'a str>,
            _cancel: CancellationToken,
        ) -> RelayTransferFuture<'a, CanonicalPrepareUploadResult> {
            Box::pin(async move { self.prepare.take().expect("one prepare") })
        }

        fn upload<'a>(
            &'a mut self,
            _session_id: &'a str,
            file_id: &'a str,
            _token: &'a str,
            _content: FileContent,
            content_length: u64,
            progress: RelayTransferProgressSink,
            _cancel: CancellationToken,
        ) -> RelayTransferFuture<'a, ()> {
            let file_id = file_id.to_owned();
            Box::pin(async move {
                progress(content_length);
                self.uploads.lock().unwrap().push(file_id);
                Ok(())
            })
        }

        fn cancel<'a>(&'a mut self, session_id: &'a str) -> RelayTransferFuture<'a, ()> {
            let session_id = session_id.to_owned();
            Box::pin(async move {
                self.cancelled.lock().unwrap().push(session_id);
                Ok(())
            })
        }
    }

    fn request() -> RelayTransferRequest {
        RelayTransferRequest {
            transfer_id: "transfer".to_owned(),
            info: RegisterDtoV2 {
                alias: "Relay".to_owned(),
                version: "2.2".to_owned(),
                device_model: None,
                device_type: None,
                fingerprint: "fingerprint".to_owned(),
                port: 0,
                protocol: ProtocolType::Https,
                download: false,
            },
            files: vec![
                RelayTransferFile {
                    dto: FileDto {
                        id: "one".to_owned(),
                        file_name: "one.txt".to_owned(),
                        size: 3,
                        file_type: "text".to_owned(),
                        sha256: None,
                        preview: None,
                        metadata: None,
                    },
                    content: FileContent::Path("/tmp/one".into()),
                },
                RelayTransferFile {
                    dto: FileDto {
                        id: "two".to_owned(),
                        file_name: "two.txt".to_owned(),
                        size: 5,
                        file_type: "text".to_owned(),
                        sha256: None,
                        preview: None,
                        metadata: None,
                    },
                    content: FileContent::Path("/tmp/two".into()),
                },
            ],
            pin: None,
        }
    }

    #[tokio::test]
    async fn engine_owns_partial_acceptance_and_progress_for_every_transport() {
        let mut transport = MockTransport {
            prepare: Some(Ok(CanonicalPrepareUploadResult::Accepted {
                session_id: "remote".to_owned(),
                file_tokens: HashMap::from([("two".to_owned(), "token".to_owned())]),
            })),
            uploads: Mutex::new(Vec::new()),
            cancelled: Mutex::new(Vec::new()),
        };
        let received = Arc::new(Mutex::new(Vec::new()));
        let events = {
            let received = received.clone();
            Arc::new(move |event| received.lock().unwrap().push(event)) as RelayTransferEventSink
        };

        let bytes = RelayTransferEngine
            .send(
                &mut transport,
                request(),
                TransportOrigin::InternetDirect,
                CancellationToken::new(),
                events,
            )
            .await
            .unwrap();

        assert_eq!(bytes, 5);
        assert_eq!(*transport.uploads.lock().unwrap(), vec!["two"]);
        assert!(received.lock().unwrap().iter().any(|event| {
            matches!(
                event,
                RelayTransferEvent::Declined {
                    file_id: Some(file_id),
                    ..
                } if file_id == "one"
            )
        }));
        assert!(
            received
                .lock()
                .unwrap()
                .iter()
                .any(|event| { matches!(event, RelayTransferEvent::Completed { bytes: 5, .. }) })
        );
    }

    #[tokio::test]
    async fn cancellation_before_upload_is_terminal_and_not_a_fallback_signal() {
        let mut transport = MockTransport {
            prepare: Some(Ok(CanonicalPrepareUploadResult::Accepted {
                session_id: "remote".to_owned(),
                file_tokens: HashMap::from([("one".to_owned(), "token".to_owned())]),
            })),
            uploads: Mutex::new(Vec::new()),
            cancelled: Mutex::new(Vec::new()),
        };
        let cancel = CancellationToken::new();
        cancel.cancel();
        let error = RelayTransferEngine
            .send(
                &mut transport,
                request(),
                TransportOrigin::Local,
                cancel,
                Arc::new(|_| {}),
            )
            .await
            .unwrap_err();
        assert_eq!(error, RelaySendError::Cancelled);
        assert!(transport.uploads.lock().unwrap().is_empty());
    }
}
