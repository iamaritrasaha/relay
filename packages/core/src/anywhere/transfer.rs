//! Production Anywhere session orchestration.
//!
//! This module only *composes* existing pieces:
//! Iroh endpoint → inner Relay TLS → mutual `RelayIdentityProofV1` →
//! [`AuthenticatedRelaySession`] → authorization → the existing v2 HTTP
//! transfer handlers. There is no Anywhere-specific transfer protocol, DTO,
//! save path, progress model, or integrity check.
//!
//! Iroh is started here and nowhere else: a LAN-only run never reaches this
//! module, so it never binds an endpoint or contacts a relay.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::{mpsc, oneshot};
use tokio_util::sync::CancellationToken;

use super::endpoint::{bind_endpoint, selected_path, AnywhereEndpoint, PathPreference};
use super::error::{AnywhereError, TlsStage, TransportStage};
use super::identity::AnywhereIdentity;
use super::proof::{authenticate_initiator, authenticate_server};
use super::runtime::{AnywhereRuntime, AnywhereSessionId, IncomingTransferId};
use super::stream::{
    client_peer_certificate_fingerprint, server_peer_certificate_fingerprint, IrohBiStream,
};
use super::tls::InnerTlsPeer;
use super::{authorize_unknown_authenticated, empty_trust, RelayAddressV1};
use crate::http::client::AnywhereHttpClient;
use crate::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use crate::http::server::common::save::FileUploadTarget;
use crate::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2, SessionEndReasonV2};
use crate::http::server::{start_v2_stream_only, ConnectionOrigin, ServerConfigV2};
use crate::http::state::ClientInfo;
use crate::model::discovery::ProtocolType;
use crate::model::transfer::{FileContent, FileDto};
use crate::relay::{AuthenticatedRelaySession, PathDescriptor, RelayId, TransferAuthorization};

const SESSION_TIMEOUT: Duration = Duration::from_secs(120);
const ONLINE_TIMEOUT: Duration = Duration::from_secs(20);
const PROTOCOL_VERSION: &str = "2.2";

/// Whether the selected Iroh path is direct or relayed. Status only.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AnywherePathClass {
    Direct,
    Relay,
}

impl AnywherePathClass {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Direct => "direct",
            Self::Relay => "relay",
        }
    }
}

/// Where one outbound file's bytes come from.
#[derive(Debug)]
pub enum AnywhereFileSource {
    Path(PathBuf),
    #[cfg(target_os = "android")]
    FileDescriptor(std::os::fd::RawFd),
}

/// One outbound file. Mirrors the v2 [`FileDto`] that remains authoritative.
#[derive(Debug)]
pub struct AnywhereFileSpec {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub source: AnywhereFileSource,
}

/// One authenticated v2 upload session. Files travel sequentially over the same
/// HTTP/1.1 connection, exactly as v2 session semantics expect.
#[derive(Debug)]
pub struct AnywhereBatch {
    pub files: Vec<AnywhereFileSpec>,
}

/// Metadata for one pending inbound file.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AnywhereIncomingFile {
    pub id: String,
    pub name: String,
    pub size: u64,
}

/// Progress and lifecycle events for one session.
#[derive(Clone, Debug)]
pub enum AnywhereEvent {
    Starting,
    /// The local endpoint is reachable; `address` is the encoded routing bundle.
    EndpointReady {
        address: String,
        local_relay_id: String,
    },
    WaitingForConnection,
    Connecting,
    PeerConnected,
    TlsEstablished,
    /// The remote RelayId is now cryptographically proven.
    PeerAuthenticated {
        remote_relay_id: String,
    },
    /// An inbound batch awaits a decision for `transfer_id`.
    IncomingBatch {
        transfer_id: IncomingTransferId,
        files: Vec<AnywhereIncomingFile>,
        remote_relay_id: String,
    },
    Transferring {
        bytes: u64,
        total: u64,
    },
    Completed {
        outcome: AnywhereOutcome,
    },
    Cancelled,
}

pub type AnywhereEventSink = Arc<dyn Fn(AnywhereEvent) + Send + Sync>;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AnywhereOutcome {
    pub path: AnywherePathClass,
    pub bytes: u64,
    pub local_relay_id: String,
    pub remote_relay_id: String,
    pub duration_ms: u64,
}

/// Outbound session parameters.
pub struct AnywhereSendRequest {
    pub identity: AnywhereIdentity,
    /// Routing plus the RelayId the sender demands the peer prove.
    pub remote: RelayAddressV1,
    pub preference: PathPreference,
    pub alias: String,
    pub batch: AnywhereBatch,
}

/// Inbound session parameters.
pub struct AnywhereReceiveRequest {
    pub identity: AnywhereIdentity,
    pub preference: PathPreference,
    pub alias: String,
    /// Optional pinned peer identity. `None` accepts any authenticated peer,
    /// still subject to the per-request user decision.
    pub expected_remote_relay_id: Option<String>,
}

/// Runs one outbound Anywhere transfer.
pub async fn send_batch(
    session_id: AnywhereSessionId,
    cancel: CancellationToken,
    request: AnywhereSendRequest,
    events: AnywhereEventSink,
) -> Result<AnywhereOutcome, AnywhereError> {
    let _ = session_id;
    let started = Instant::now();
    let AnywhereSendRequest {
        identity,
        remote,
        preference,
        alias,
        mut batch,
    } = request;
    if batch.files.is_empty() {
        return Err(AnywhereError::transport_reason(
            TransportStage::Stream,
            "outbound batch contains no file",
        ));
    }
    batch
        .files
        .sort_by(|left, right| left.name.cmp(&right.name));
    let mut ids = HashSet::new();
    if !batch.files.iter().all(|file| ids.insert(file.id.as_str())) {
        return Err(AnywhereError::transport_reason(
            TransportStage::Stream,
            "outbound batch contains duplicate file ids",
        ));
    }
    let total = batch.files.iter().map(|file| file.size).sum::<u64>();

    events(AnywhereEvent::Starting);
    let endpoint = bind_endpoint(preference).await?;
    let guard = EndpointGuard::new(endpoint);
    wait_online(guard.endpoint(), preference, &cancel).await?;

    events(AnywhereEvent::Connecting);
    let connection = tokio::select! {
        _ = cancel.cancelled() => return Err(AnywhereError::Cancelled),
        _ = tokio::time::sleep(SESSION_TIMEOUT) => {
            return Err(AnywhereError::Timeout { stage: TransportStage::Connect });
        }
        connection = guard.endpoint().connect(remote.endpoint.clone()) => connection?,
    };
    events(AnywhereEvent::PeerConnected);

    let (send, recv) = connection
        .open_bi()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;
    let path = selected_path(&connection, preference).await?;

    let tls_peer = inner_tls_peer()?;
    let server_name = rustls::pki_types::ServerName::try_from("localhost")
        .map_err(|error| AnywhereError::tls(TlsStage::ClientHandshake, error))?;
    let mut tls = tls_peer
        .connector()
        .connect(server_name, IrohBiStream::new(send, recv))
        .await
        .map_err(|error| AnywhereError::tls(TlsStage::ClientHandshake, error))?;
    events(AnywhereEvent::TlsEstablished);

    let observed_server_cert = client_peer_certificate_fingerprint(&tls)
        .map_err(|error| AnywhereError::tls(TlsStage::PeerCertificate, error))?;
    let expected = RelayId::from_expected_canonical_hex(&remote.claimed_relay_id)
        .map_err(|_| AnywhereError::RelayProof)?;
    let session = authenticate_initiator(
        &mut tls,
        identity.inner(),
        tls_peer.cert_fingerprint,
        &expected,
        observed_server_cert,
        path.clone(),
    )
    .await?;
    approve_authenticated_session(&session)?;
    let remote_relay_id = session.remote_relay_id().as_hex();
    events(AnywhereEvent::PeerAuthenticated {
        remote_relay_id: remote_relay_id.clone(),
    });

    let local_relay_id = identity.relay_id().to_owned();
    let progress_events = events.clone();
    let bytes = send_files_over_authenticated_stream(
        tls,
        session,
        batch,
        alias,
        local_relay_id.clone(),
        cancel.clone(),
        move |bytes| progress_events(AnywhereEvent::Transferring { bytes, total }),
    )
    .await?;

    guard.close().await;
    let outcome = AnywhereOutcome {
        path: path_class(&path),
        bytes,
        local_relay_id,
        remote_relay_id,
        duration_ms: started.elapsed().as_millis() as u64,
    };
    events(AnywhereEvent::Completed {
        outcome: outcome.clone(),
    });
    Ok(outcome)
}

/// Runs one inbound Anywhere transfer.
///
/// The inbound decision is routed through `runtime` against this session's id,
/// so a second concurrent session's approval can never land here.
pub async fn receive(
    runtime: Arc<AnywhereRuntime>,
    session_id: AnywhereSessionId,
    cancel: CancellationToken,
    request: AnywhereReceiveRequest,
    events: AnywhereEventSink,
) -> Result<AnywhereOutcome, AnywhereError> {
    events(AnywhereEvent::Starting);
    let endpoint = bind_endpoint(request.preference).await?;
    let guard = EndpointGuard::new(endpoint);
    wait_online(guard.endpoint(), request.preference, &cancel).await?;

    let address = RelayAddressV1::new(
        request.identity.relay_id().to_owned(),
        guard.endpoint().addr(),
    )
    .and_then(|address| address.encode())
    .map_err(|error| AnywhereError::transport(TransportStage::Bind, error))?;
    events(AnywhereEvent::EndpointReady {
        address,
        local_relay_id: request.identity.relay_id().to_owned(),
    });
    events(AnywhereEvent::WaitingForConnection);

    let incoming = tokio::select! {
        _ = cancel.cancelled() => return Err(AnywhereError::Cancelled),
        _ = tokio::time::sleep(SESSION_TIMEOUT) => {
            return Err(AnywhereError::Timeout { stage: TransportStage::Accept });
        }
        incoming = guard.endpoint().accept() => incoming?,
    };
    let connection = tokio::select! {
        _ = cancel.cancelled() => return Err(AnywhereError::Cancelled),
        _ = tokio::time::sleep(SESSION_TIMEOUT) => {
            return Err(AnywhereError::Timeout { stage: TransportStage::Accept });
        }
        connection = incoming => {
            connection.map_err(|error| AnywhereError::transport(TransportStage::Accept, error))?
        }
    };
    let outcome =
        receive_on_connection(runtime, session_id, cancel, request, connection, events).await?;
    guard.close().await;
    Ok(outcome)
}

/// Receives one authenticated v2 transfer over an already accepted Anywhere
/// connection. A production listener calls this for every accepted connection;
/// the one-shot compatibility entry above merely owns endpoint setup/teardown.
pub(crate) async fn receive_on_connection(
    runtime: Arc<AnywhereRuntime>,
    session_id: AnywhereSessionId,
    cancel: CancellationToken,
    request: AnywhereReceiveRequest,
    connection: iroh::endpoint::Connection,
    events: AnywhereEventSink,
) -> Result<AnywhereOutcome, AnywhereError> {
    let started = Instant::now();
    let AnywhereReceiveRequest {
        identity,
        preference,
        alias,
        expected_remote_relay_id,
    } = request;
    events(AnywhereEvent::PeerConnected);

    let (send, recv) = connection
        .accept_bi()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;
    let path = selected_path(&connection, preference).await?;

    let tls_peer = inner_tls_peer()?;
    let mut tls = tls_peer
        .acceptor()
        .accept(IrohBiStream::new(send, recv))
        .await
        .map_err(|error| AnywhereError::tls(TlsStage::ServerHandshake, error))?;
    events(AnywhereEvent::TlsEstablished);

    let observed_client_cert = server_peer_certificate_fingerprint(&tls)
        .map_err(|error| AnywhereError::tls(TlsStage::PeerCertificate, error))?;
    let expected = expected_remote_relay_id
        .as_deref()
        .map(RelayId::from_expected_canonical_hex)
        .transpose()
        .map_err(|_| AnywhereError::RelayProof)?;
    let session = authenticate_server(
        &mut tls,
        identity.inner(),
        tls_peer.cert_fingerprint,
        expected.as_ref(),
        observed_client_cert,
        path.clone(),
    )
    .await?;
    approve_authenticated_session(&session)?;
    let remote_relay_id = session.remote_relay_id().as_hex();
    events(AnywhereEvent::PeerAuthenticated {
        remote_relay_id: remote_relay_id.clone(),
    });

    let total_bytes = serve_inbound_session(
        &runtime,
        session_id,
        &cancel,
        tls,
        session,
        &path,
        &alias,
        identity.relay_id(),
        &remote_relay_id,
        &events,
    )
    .await?;

    let outcome = AnywhereOutcome {
        path: path_class(&path),
        bytes: total_bytes,
        local_relay_id: identity.relay_id().to_owned(),
        remote_relay_id,
        duration_ms: started.elapsed().as_millis() as u64,
    };
    events(AnywhereEvent::Completed {
        outcome: outcome.clone(),
    });
    Ok(outcome)
}

/// Sends a complete v2 batch over one already-authenticated stream.
///
/// Exposed so a caller that already owns an authenticated stream (tests, and
/// any future transport) reuses the identical upload semantics.
pub async fn send_files_over_authenticated_stream<S>(
    stream: S,
    session: AuthenticatedRelaySession,
    batch: AnywhereBatch,
    alias: String,
    fingerprint: String,
    cancel: CancellationToken,
    on_progress: impl Fn(u64) + Send + Sync + 'static,
) -> Result<u64, AnywhereError>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let mut client = AnywhereHttpClient::handshake(stream, session)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;
    let files = batch
        .files
        .iter()
        .map(|spec| {
            (
                spec.id.clone(),
                FileDto {
                    id: spec.id.clone(),
                    file_name: spec.name.clone(),
                    size: spec.size,
                    file_type: spec.file_type.clone(),
                    sha256: spec.sha256.clone(),
                    preview: None,
                    metadata: None,
                },
            )
        })
        .collect::<HashMap<_, _>>();
    let payload = PrepareUploadRequestDtoV2 {
        info: RegisterDtoV2 {
            alias,
            version: PROTOCOL_VERSION.to_owned(),
            device_model: None,
            device_type: None,
            fingerprint,
            port: 0,
            protocol: ProtocolType::Https,
            download: false,
        },
        files,
    };
    let prepared = client
        .prepare_upload(payload, None, cancel.clone())
        .await
        .map_err(map_client_error)?
        .response
        .ok_or(AnywhereError::AuthorizationDenied)?;
    if !batch
        .files
        .iter()
        .all(|file| prepared.files.contains_key(&file.id))
    {
        return Err(AnywhereError::ProtocolCompletion);
    }

    let progress = Arc::new(on_progress);
    let mut completed = 0_u64;
    for spec in batch.files {
        if cancel.is_cancelled() {
            let _ = client.cancel(&prepared.session_id).await;
            return Err(AnywhereError::Cancelled);
        }
        let token = prepared.files[&spec.id].clone();
        let size = spec.size;
        let content = match spec.source {
            AnywhereFileSource::Path(path) => FileContent::Path(path),
            #[cfg(target_os = "android")]
            AnywhereFileSource::FileDescriptor(fd) => FileContent::Fd(fd),
        };
        let base = completed;
        let report_progress = progress.clone();
        let result = client
            .upload(
                &prepared.session_id,
                &spec.id,
                &token,
                content,
                size,
                move |bytes| report_progress(base.saturating_add(bytes)),
                cancel.clone(),
            )
            .await;
        if matches!(result, Err(crate::http::client::ClientError::Cancelled)) {
            let _ = client.cancel(&prepared.session_id).await;
            return Err(AnywhereError::Cancelled);
        }
        result.map_err(map_client_error)?;
        completed = completed.saturating_add(size);
        progress(completed);
    }
    Ok(completed)
}

#[allow(clippy::too_many_arguments)]
async fn serve_inbound_session<S>(
    runtime: &Arc<AnywhereRuntime>,
    session_id: AnywhereSessionId,
    cancel: &CancellationToken,
    stream: S,
    session: AuthenticatedRelaySession,
    path: &PathDescriptor,
    alias: &str,
    local_relay_id: &str,
    remote_relay_id: &str,
    events: &AnywhereEventSink,
) -> Result<u64, AnywhereError>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (stop_tx, stop_rx) = oneshot::channel();
    let server = start_v2_stream_only(
        ClientInfo {
            alias: alias.to_owned(),
            version: PROTOCOL_VERSION.to_owned(),
            device_model: None,
            device_type: None,
            token: local_relay_id.to_owned(),
        },
        ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
        },
        stop_rx,
    )
    .await
    .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;
    let origin = match path {
        PathDescriptor::IrohRelay { .. } | PathDescriptor::Relayed { .. } => {
            ConnectionOrigin::IrohRelay
        }
        _ => ConnectionOrigin::InternetDirect,
    };
    server
        .serve_authenticated_stream(stream, session, origin)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;

    let mut accepted_files: HashMap<String, FileDto> = HashMap::new();
    let mut targets: HashMap<String, PathBuf> = HashMap::new();
    let mut started_files: Vec<String> = Vec::new();
    let mut saved_files: HashSet<String> = HashSet::new();
    let mut total_bytes = 0_u64;
    let (save_tx, mut save_rx) = mpsc::channel::<(String, Result<(), String>)>(32);

    macro_rules! stop_with {
        ($error:expr) => {{
            let _ = stop_tx.send(());
            server.wait_stopped().await;
            return Err($error);
        }};
    }

    loop {
        tokio::select! {
            _ = cancel.cancelled() => stop_with!(AnywhereError::Cancelled),
            event = event_rx.recv() => match event {
                Some(ServerEventV2::PrepareUpload { files, decision_tx, authenticated_relay_id, .. }) => {
                    let remote = authenticated_relay_id
                        .unwrap_or_else(|| remote_relay_id.to_owned());
                    let mut incoming = files
                        .values()
                        .map(|file| AnywhereIncomingFile {
                            id: file.id.clone(),
                            name: file.file_name.clone(),
                            size: file.size,
                        })
                        .collect::<Vec<_>>();
                    incoming.sort_by(|left, right| left.name.cmp(&right.name));
                    total_bytes = incoming.iter().map(|file| file.size).sum();

                    let Some((transfer_id, decision_rx)) = runtime.register_incoming(session_id)
                    else {
                        let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                        stop_with!(AnywhereError::Cancelled);
                    };
                    events(AnywhereEvent::IncomingBatch {
                        transfer_id,
                        files: incoming,
                        remote_relay_id: remote,
                    });
                    let decision = tokio::select! {
                        _ = cancel.cancelled() => {
                            let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                            stop_with!(AnywhereError::Cancelled);
                        }
                        decision = decision_rx => match decision {
                            Ok(decision) => decision,
                            Err(_) => {
                                let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                                stop_with!(AnywhereError::Cancelled);
                            }
                        },
                    };
                    if !decision.accept {
                        let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                        stop_with!(AnywhereError::AuthorizationDenied);
                    }
                    if decision.targets.len() != files.len()
                        || !files.keys().all(|file_id| decision.targets.contains_key(file_id))
                    {
                        let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                        stop_with!(AnywhereError::ProtocolCompletion);
                    }
                    targets = decision.targets;
                    accepted_files = files;
                    if decision_tx
                        .send(PrepareUploadDecisionV2::Accept(
                            accepted_files.keys().cloned().collect(),
                        ))
                        .is_err()
                    {
                        stop_with!(AnywhereError::transport_reason(
                            TransportStage::Stream,
                            "sender disconnected during prepare-upload",
                        ));
                    }
                }
                Some(ServerEventV2::FileUpload { file_id, file: _, target_tx, .. }) => {
                    if !accepted_files.contains_key(&file_id) {
                        stop_with!(AnywhereError::ProtocolCompletion);
                    }
                    let Some(path) = targets.remove(&file_id) else {
                        stop_with!(AnywhereError::ProtocolCompletion);
                    };
                    let completed = started_files
                        .iter()
                        .filter_map(|id| accepted_files.get(id))
                        .map(|file| file.size)
                        .sum::<u64>();
                    started_files.push(file_id.clone());
                    let (result_tx, result_rx) = oneshot::channel();
                    let (progress_tx, mut progress_rx) = mpsc::channel(32);
                    let events = events.clone();
                    tokio::spawn(async move {
                        while let Some(bytes) = progress_rx.recv().await {
                            events(AnywhereEvent::Transferring {
                                bytes: completed.saturating_add(bytes),
                                total: total_bytes,
                            });
                        }
                    });
                    let save_tx = save_tx.clone();
                    tokio::spawn(async move {
                        let result = result_rx
                            .await
                            .unwrap_or_else(|_| Err("upload save result dropped".to_owned()));
                        let _ = save_tx.send((file_id.clone(), result)).await;
                    });
                    if target_tx
                        .send(FileUploadTarget::Path {
                            path,
                            result_tx,
                            progress_tx: Some(progress_tx),
                        })
                        .is_err()
                    {
                        stop_with!(AnywhereError::transport_reason(
                            TransportStage::Stream,
                            "sender disconnected before file save",
                        ));
                    }
                }
                Some(ServerEventV2::SessionEnd { reason: SessionEndReasonV2::Finished, .. }) => {
                    while saved_files.len() < accepted_files.len() {
                        let Some((file_id, result)) = save_rx.recv().await else {
                            stop_with!(AnywhereError::ProtocolCompletion);
                        };
                        if result.is_err() {
                            stop_with!(AnywhereError::ProtocolCompletion);
                        }
                        saved_files.insert(file_id);
                    }
                    if started_files.len() != accepted_files.len()
                        || saved_files.len() != accepted_files.len()
                    {
                        stop_with!(AnywhereError::ProtocolCompletion);
                    }
                    break;
                }
                Some(ServerEventV2::SessionEnd { reason: SessionEndReasonV2::Cancelled, .. })
                | Some(ServerEventV2::CancelReceived { .. }) => {
                    stop_with!(AnywhereError::Cancelled);
                }
                Some(ServerEventV2::PrepareUploadAborted { .. }) => {
                    stop_with!(AnywhereError::ProtocolCompletion);
                }
                Some(ServerEventV2::Register { .. }) => {}
                None => stop_with!(AnywhereError::transport_reason(
                    TransportStage::Stream,
                    "Anywhere HTTP server stopped before completion",
                )),
            },
            saved = save_rx.recv() => {
                if let Some((file_id, result)) = saved {
                    if result.is_err() {
                        stop_with!(AnywhereError::ProtocolCompletion);
                    }
                    saved_files.insert(file_id);
                }
            },
        }
    }

    let _ = stop_tx.send(());
    server.wait_stopped().await;
    if accepted_files.is_empty() {
        return Err(AnywhereError::ProtocolCompletion);
    }
    Ok(total_bytes)
}

/// Closes the endpoint even when a session fails early.
struct EndpointGuard {
    endpoint: Option<AnywhereEndpoint>,
}

impl EndpointGuard {
    fn new(endpoint: AnywhereEndpoint) -> Self {
        Self {
            endpoint: Some(endpoint),
        }
    }

    fn endpoint(&self) -> &AnywhereEndpoint {
        self.endpoint.as_ref().expect("endpoint is live")
    }

    async fn close(mut self) {
        if let Some(endpoint) = self.endpoint.take() {
            endpoint.close().await;
        }
    }
}

pub(crate) async fn wait_online(
    endpoint: &AnywhereEndpoint,
    preference: PathPreference,
    cancel: &CancellationToken,
) -> Result<(), AnywhereError> {
    if preference == PathPreference::ForceDirect {
        return Ok(());
    }
    tokio::select! {
        _ = cancel.cancelled() => Err(AnywhereError::Cancelled),
        _ = endpoint.online() => Ok(()),
        _ = tokio::time::sleep(ONLINE_TIMEOUT) => Ok(()),
    }
}

fn inner_tls_peer() -> Result<InnerTlsPeer, AnywhereError> {
    InnerTlsPeer::generate().map_err(|error| AnywhereError::tls(TlsStage::ClientHandshake, error))
}

fn path_class(path: &PathDescriptor) -> AnywherePathClass {
    match path {
        PathDescriptor::IrohRelay { .. } | PathDescriptor::Relayed { .. } => {
            AnywherePathClass::Relay
        }
        _ => AnywherePathClass::Direct,
    }
}

fn map_client_error(error: crate::http::client::ClientError) -> AnywhereError {
    match error {
        crate::http::client::ClientError::Cancelled => AnywhereError::Cancelled,
        other => AnywhereError::transport(TransportStage::Stream, other),
    }
}

/// Session-scoped authorization. An accepted transfer never writes a
/// [`crate::relay::DeviceBinding`].
fn approve_authenticated_session(session: &AuthenticatedRelaySession) -> Result<(), AnywhereError> {
    let decision = authorize_unknown_authenticated(session, &empty_trust());
    match decision.outcome {
        TransferAuthorization::Denied => Err(AnywhereError::AuthorizationDenied),
        TransferAuthorization::PromptRequired | TransferAuthorization::AutoAccept => Ok(()),
    }
}
