use std::{
    collections::{HashMap, HashSet},
    io::ErrorKind,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use anyhow::{Context as _, Result, bail, ensure};
use iroh::EndpointAddr;
use localsend::anywhere::{
    AnywhereEndpoint, AnywhereError, InnerTlsPeer, PathPreference, authenticate_initiator,
    authenticate_server, authorize_unknown_authenticated, bind_endpoint, empty_trust,
    selected_path, stream::IrohBiStream, stream::client_peer_certificate_fingerprint,
    stream::server_peer_certificate_fingerprint,
};
use localsend::crypto::relay_identity::RelayIdentity;
use localsend::http::client::AnywhereHttpClient;
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2, SessionEndReasonV2};
use localsend::http::server::{ConnectionOrigin, ServerConfigV2, start_v2_stream_only};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::ProtocolType;
use localsend::model::transfer::{FileContent, FileDto};
use localsend::relay::{PathDescriptor, RelayId, TransferAuthorization};
use rand::RngCore;
use sha2::{Digest, Sha256};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    sync::{Notify, mpsc, oneshot},
    time::sleep,
};
use tokio_util::sync::CancellationToken;

#[cfg(test)]
use tokio::time::timeout;

use crate::{invite::Ra2bInviteV1, relay_auth::IDENTITY_REJECTED};

#[allow(dead_code)]
pub const ALPN: &[u8] = localsend::anywhere::ALPN;
pub const ONE_MIB: usize = 1024 * 1024;
const CHUNK_SIZE: usize = 16 * 1024;
const SESSION_TIMEOUT: Duration = Duration::from_secs(120);
const PAYLOAD_MODE: u8 = 1;
const STREAM_FINISH: u8 = 0xac;
const SESSION_RESULT_OK: u8 = 0x5c;

fn diag(message: impl AsRef<str>) {
    let message = message.as_ref();
    tracing::info!(target: "ra2b", "{message}");
    eprintln!("RA2B {message}");
}

fn relay_id_prefix(relay_id: &str) -> &str {
    relay_id.get(..8).unwrap_or(relay_id)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Ra2bPathClass {
    Direct,
    Relay,
}

impl Ra2bPathClass {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Direct => "DIRECT",
            Self::Relay => "RELAY",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Ra2bPathPreference {
    Auto,
    ForceDirect,
    ForceRelay,
}

#[derive(Clone, Debug)]
pub enum Ra2bRole {
    Responder,
    Initiator { remote_endpoint: EndpointAddr },
}

#[derive(Clone)]
pub struct Ra2bPeerMaterial {
    pub identity: Arc<RelayIdentity>,
    pub relay_id: String,
    pub tls: InnerTlsPeer,
    pub expected_remote_relay_id: Option<String>,
}

impl Ra2bPeerMaterial {
    pub fn generate(expected_remote_relay_id: Option<String>) -> Result<Self> {
        Self::from_arc(
            Arc::new(RelayIdentity::generate()),
            expected_remote_relay_id,
        )
    }

    pub fn from_identity(
        identity: RelayIdentity,
        expected_remote_relay_id: Option<String>,
    ) -> Result<Self> {
        Self::from_arc(Arc::new(identity), expected_remote_relay_id)
    }

    pub fn from_arc(
        identity: Arc<RelayIdentity>,
        expected_remote_relay_id: Option<String>,
    ) -> Result<Self> {
        if let Some(expected) = &expected_remote_relay_id {
            crate::invite::validate_relay_id(expected)?;
        }
        let tls = InnerTlsPeer::generate()?;
        let relay_id = identity.relay_id()?;
        Ok(Self {
            identity,
            relay_id,
            tls,
            expected_remote_relay_id,
        })
    }
}

#[derive(Clone, Debug)]
pub enum Ra2bPhase {
    Starting,
    EndpointReady {
        invite: String,
        local_relay_id: String,
    },
    WaitingForConnection,
    Connecting,
    IrohConnected,
    TlsAuthenticated,
    RelayIdentityAuthenticated {
        remote_relay_id: String,
    },
    IncomingFile {
        name: String,
        size: u64,
        remote_relay_id: String,
    },
    IncomingBatch {
        files: Vec<Ra4IncomingFile>,
        remote_relay_id: String,
    },
    Transferring {
        bytes: u64,
        total: u64,
    },
    Complete {
        path: String,
        bytes: u32,
        hash_hex: String,
        local_relay_id: String,
        remote_relay_id: String,
        duration_ms: u64,
    },
    Failed {
        message: String,
        category: String,
    },
    Cancelled,
}

#[derive(Clone, Debug)]
pub struct Ra2bProofResult {
    pub path: Ra2bPathClass,
    pub bytes: usize,
    pub hash_hex: String,
    pub local_relay_id: String,
    pub remote_relay_id: String,
    pub duration_ms: u64,
}

/// One real file for the RA4A HTTP transfer path. The source is consumed as a
/// bounded stream by the existing LocalSend file-content machinery.
#[derive(Debug)]
pub enum Ra4FileSource {
    Path(std::path::PathBuf),
    #[cfg(target_os = "android")]
    FileDescriptor(std::os::fd::RawFd),
}

#[derive(Debug)]
pub struct Ra4FileSpec {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub source: Ra4FileSource,
}

/// Metadata for one pending file in an authenticated RA4B batch.  The file
/// DTO remains the Relay v2 source of truth; this is only the development
/// harness representation needed to pair it with a local source/target.
#[derive(Clone, Debug)]
pub struct Ra4IncomingFile {
    pub id: String,
    pub name: String,
    pub size: u64,
}

/// One authenticated v2 upload session. Files are sent sequentially over the
/// same HTTP/1.1 connection, as Relay's existing v2 session semantics expect.
#[derive(Debug)]
pub struct Ra4BatchSpec {
    pub files: Vec<Ra4FileSpec>,
}

/// Session-scoped receiver decision. The destination is prepared by the
/// existing UI/save-target machinery and is never persisted as trust.
#[derive(Debug)]
pub struct Ra4Decision {
    pub accept: bool,
    pub targets: HashMap<String, PathBuf>,
}

/// Runs the production RA4A sender after Iroh, inner TLS, mutual proof, and
/// authorization have already completed. HTTP semantics are shared with LAN;
/// this function only supplies the caller-owned authenticated stream.
pub async fn send_one_file_over_authenticated_stream<S>(
    stream: S,
    session: localsend::relay::AuthenticatedRelaySession,
    spec: Ra4FileSpec,
    alias: String,
    fingerprint: String,
    cancellation: CancellationToken,
    on_progress: impl Fn(u64) + Send + Sync + 'static,
) -> Result<usize>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    send_files_over_authenticated_stream(
        stream,
        session,
        Ra4BatchSpec { files: vec![spec] },
        alias,
        fingerprint,
        cancellation,
        on_progress,
    )
    .await
}

/// Sends a complete v2 batch over the one authenticated HTTP connection.
/// There is no Anywhere-specific file or folder protocol: the existing v2
/// metadata map, prepare decision, upload endpoints, checksum handling, and
/// cancellation behavior remain authoritative.
pub async fn send_files_over_authenticated_stream<S>(
    stream: S,
    session: localsend::relay::AuthenticatedRelaySession,
    mut batch: Ra4BatchSpec,
    alias: String,
    fingerprint: String,
    cancellation: CancellationToken,
    on_progress: impl Fn(u64) + Send + Sync + 'static,
) -> Result<usize>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    ensure!(
        !batch.files.is_empty(),
        "RA4B batch must contain at least one file"
    );
    batch
        .files
        .sort_by(|left, right| left.name.cmp(&right.name));
    let mut ids = HashSet::new();
    ensure!(
        batch.files.iter().all(|file| ids.insert(file.id.as_str())),
        "RA4B batch contains duplicate file ids"
    );
    let mut client = AnywhereHttpClient::handshake(stream, session)
        .await
        .map_err(|error| anyhow::anyhow!(error))?;
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
            version: "2.2".to_owned(),
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
        .prepare_upload(payload, None, cancellation.clone())
        .await
        .map_err(|error| anyhow::anyhow!(error))?
        .response
        .ok_or_else(|| anyhow::anyhow!("receiver accepted no file"))?;
    ensure!(
        batch
            .files
            .iter()
            .all(|file| prepared.files.contains_key(&file.id)),
        "receiver did not accept the complete requested batch"
    );

    let progress = Arc::new(on_progress);
    let mut completed = 0_u64;
    for spec in batch.files {
        if cancellation.is_cancelled() {
            let _ = client.cancel(&prepared.session_id).await;
            bail!("cancelled");
        }
        let token = prepared.files[&spec.id].clone();
        let size = spec.size;
        let content = match spec.source {
            Ra4FileSource::Path(path) => FileContent::Path(path),
            #[cfg(target_os = "android")]
            Ra4FileSource::FileDescriptor(fd) => FileContent::Fd(fd),
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
                cancellation.clone(),
            )
            .await;
        if matches!(result, Err(localsend::http::client::ClientError::Cancelled)) {
            let _ = client.cancel(&prepared.session_id).await;
            bail!("cancelled");
        }
        result.map_err(|error| anyhow::anyhow!(error))?;
        completed = completed.saturating_add(size);
        progress(completed);
    }
    usize::try_from(completed).context("batch size exceeds usize")
}

/// Runs the RA4A sender after the Iroh, inner-TLS, and mutual Relay proof
/// boundaries. The HTTP body is still the existing v2 upload body.
pub async fn run_ra4_sender(
    remote_endpoint: EndpointAddr,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
    spec: Ra4FileSpec,
) -> Result<Ra2bProofResult> {
    run_ra4_batch_sender(
        remote_endpoint,
        peer,
        path_preference,
        cancellation,
        on_status,
        Ra4BatchSpec { files: vec![spec] },
    )
    .await
}

pub async fn run_ra4_batch_sender(
    remote_endpoint: EndpointAddr,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
    batch: Ra4BatchSpec,
) -> Result<Ra2bProofResult> {
    let started = Instant::now();
    ensure!(
        !batch.files.is_empty(),
        "RA4B batch must contain at least one file"
    );
    let total = batch.files.iter().map(|file| file.size).sum::<u64>();
    let (endpoint, relay_guard) = build_endpoint(path_preference).await?;
    if path_preference != Ra2bPathPreference::ForceDirect {
        tokio::select! {
            _ = cancellation.cancelled() => bail!("cancelled"),
            _ = endpoint.online() => {},
            _ = sleep(Duration::from_secs(20)) => {},
        }
    }
    on_status(Ra2bPhase::Connecting);
    let connection = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out connecting to remote Iroh endpoint"),
        connection = endpoint.connect(remote_endpoint) => connection.map_err(map_anywhere)?,
    };
    on_status(Ra2bPhase::IrohConnected);
    let (send, recv) = connection
        .open_bi()
        .await
        .context("open Iroh bidirectional stream")?;
    let path = selected_path(&connection, to_path_preference(path_preference))
        .await
        .unwrap_or(PathDescriptor::InternetDirect {
            host: String::new(),
            port: None,
        });
    let server_name = rustls::pki_types::ServerName::try_from("localhost")
        .context("parse inner TLS server name")?;
    let mut tls = peer
        .tls
        .connector()
        .connect(server_name, IrohBiStream::new(send, recv))
        .await
        .context("inner TLS client handshake")?;
    on_status(Ra2bPhase::TlsAuthenticated);
    let observed_server_cert = client_peer_certificate_fingerprint(&tls)?;
    let expected = peer
        .expected_remote_relay_id
        .as_deref()
        .map(RelayId::from_expected_canonical_hex)
        .transpose()?;
    let session = authenticate_initiator(
        &mut tls,
        &peer.identity,
        peer.tls.cert_fingerprint,
        expected
            .as_ref()
            .context("join requires expected host RelayId")?,
        observed_server_cert,
        path.clone(),
    )
    .await
    .map_err(map_anywhere)?;
    approve_authenticated_session(&session)?;
    let remote_relay_id = session.remote_relay_id().as_hex();
    on_status(Ra2bPhase::RelayIdentityAuthenticated {
        remote_relay_id: remote_relay_id.clone(),
    });

    let cancel_token = CancellationToken::new();
    let cancel_watch = {
        let cancel_token = cancel_token.clone();
        let cancellation = cancellation.clone();
        tokio::spawn(async move {
            cancellation.cancelled().await;
            cancel_token.cancel();
        })
    };
    let bytes = send_files_over_authenticated_stream(
        tls,
        session,
        batch,
        "Relay Anywhere".to_owned(),
        peer.relay_id.clone(),
        cancel_token,
        {
            let on_status = on_status.clone();
            move |bytes| {
                on_status(Ra2bPhase::Transferring { bytes, total });
            }
        },
    )
    .await?;
    cancel_watch.abort();
    endpoint.close().await;
    drop(relay_guard);
    Ok(Ra2bProofResult {
        path: path_class(&path),
        bytes,
        hash_hex: "per-file SHA-256 verified".to_owned(),
        local_relay_id: peer.relay_id,
        remote_relay_id,
        duration_ms: started.elapsed().as_millis() as u64,
    })
}

/// Runs the RA4A receiver over one authenticated stream and routes the HTTP
/// events through the same v2 prepare/save/session machinery used by LAN.
pub async fn run_ra4_receiver(
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
    decision_rx: &mut mpsc::Receiver<Ra4Decision>,
) -> Result<Ra2bProofResult> {
    let started = Instant::now();
    let (endpoint, relay_guard) = build_endpoint(path_preference).await?;
    if path_preference != Ra2bPathPreference::ForceDirect {
        tokio::select! {
            _ = cancellation.cancelled() => bail!("cancelled"),
            _ = endpoint.online() => {},
            _ = sleep(Duration::from_secs(20)) => {},
        }
    }
    let invite = Ra2bInviteV1::new(peer.relay_id.clone(), endpoint.addr())?.encode()?;
    on_status(Ra2bPhase::EndpointReady {
        invite,
        local_relay_id: peer.relay_id.clone(),
    });
    on_status(Ra2bPhase::WaitingForConnection);
    let incoming = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out waiting for Iroh connection"),
        incoming = endpoint.accept() => incoming.map_err(map_anywhere)?,
    };
    let connection = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out completing Iroh handshake"),
        connection = incoming => connection.context("complete Iroh server handshake")?,
    };
    on_status(Ra2bPhase::IrohConnected);
    let (send, recv) = connection
        .accept_bi()
        .await
        .context("accept Iroh bidirectional stream")?;
    let path = selected_path(&connection, to_path_preference(path_preference))
        .await
        .unwrap_or(PathDescriptor::InternetDirect {
            host: String::new(),
            port: None,
        });
    let mut tls = peer
        .tls
        .acceptor()
        .accept(IrohBiStream::new(send, recv))
        .await
        .context("inner TLS server handshake")?;
    on_status(Ra2bPhase::TlsAuthenticated);
    let observed_client_cert = server_peer_certificate_fingerprint(&tls)?;
    let expected = peer
        .expected_remote_relay_id
        .as_deref()
        .map(RelayId::from_expected_canonical_hex)
        .transpose()?;
    let session = authenticate_server(
        &mut tls,
        &peer.identity,
        peer.tls.cert_fingerprint,
        expected.as_ref(),
        observed_client_cert,
        path.clone(),
    )
    .await
    .map_err(map_anywhere)?;
    approve_authenticated_session(&session)?;
    let remote_relay_id = session.remote_relay_id().as_hex();
    on_status(Ra2bPhase::RelayIdentityAuthenticated {
        remote_relay_id: remote_relay_id.clone(),
    });

    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (stop_tx, stop_rx) = oneshot::channel();
    let server = start_v2_stream_only(
        ClientInfo {
            alias: "Relay Anywhere".to_owned(),
            version: "2.2".to_owned(),
            device_model: None,
            device_type: None,
            token: peer.relay_id.clone(),
        },
        ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx,
        },
        stop_rx,
    )
    .await?;
    let origin = match path {
        PathDescriptor::IrohRelay { .. } | PathDescriptor::Relayed { .. } => {
            ConnectionOrigin::IrohRelay
        }
        _ => ConnectionOrigin::InternetDirect,
    };
    diag("RA4_HTTP_START");
    server
        .serve_authenticated_stream(tls, session, origin)
        .await?;

    let mut accepted_files: HashMap<String, FileDto> = HashMap::new();
    let mut targets: HashMap<String, PathBuf> = HashMap::new();
    let mut started_files: Vec<String> = Vec::new();
    let mut saved_files = HashSet::new();
    let mut total_bytes = 0_u64;
    let (save_tx, mut save_rx) = mpsc::channel::<(String, Result<(), String>)>(32);
    loop {
        tokio::select! {
            _ = cancellation.cancelled() => {
                let _ = stop_tx.send(());
                server.wait_stopped().await;
                bail!("cancelled");
            }
            event = event_rx.recv() => match event {
                Some(ServerEventV2::PrepareUpload { files, decision_tx, authenticated_relay_id, .. }) => {
                    let remote = authenticated_relay_id.unwrap_or_else(|| remote_relay_id.clone());
                    let mut incoming = files
                        .values()
                        .map(|file| Ra4IncomingFile {
                            id: file.id.clone(),
                            name: file.file_name.clone(),
                            size: file.size,
                        })
                        .collect::<Vec<_>>();
                    incoming.sort_by(|left, right| left.name.cmp(&right.name));
                    total_bytes = incoming.iter().map(|file| file.size).sum();
                    on_status(Ra2bPhase::IncomingBatch {
                        files: incoming,
                        remote_relay_id: remote,
                    });
                    let decision = tokio::select! {
                        _ = cancellation.cancelled() => {
                            let _ = stop_tx.send(());
                            server.wait_stopped().await;
                            bail!("cancelled");
                        }
                        decision = decision_rx.recv() => decision.context("receiver decision channel closed")?,
                    };
                    if !decision.accept {
                        let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                        let _ = stop_tx.send(());
                        server.wait_stopped().await;
                        bail!("transfer declined");
                    }
                    if decision.targets.len() != files.len()
                        || !files.keys().all(|file_id| decision.targets.contains_key(file_id))
                    {
                        let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
                        let _ = stop_tx.send(());
                        server.wait_stopped().await;
                        bail!("accepted RA4B batch has an incomplete save-target set");
                    }
                    targets = decision.targets;
                    accepted_files = files;
                    decision_tx.send(PrepareUploadDecisionV2::Accept(accepted_files.keys().cloned().collect()))
                        .map_err(|_| anyhow::anyhow!("sender disconnected during prepare-upload"))?;
                }
                Some(ServerEventV2::FileUpload { file_id, file: _, target_tx, .. }) => {
                    ensure!(accepted_files.contains_key(&file_id), "unexpected RA4B file upload");
                    let path = targets.remove(&file_id).context("accepted transfer has no save target")?;
                    let completed = started_files
                        .iter()
                        .filter_map(|id| accepted_files.get(id))
                        .map(|file| file.size)
                        .sum::<u64>();
                    started_files.push(file_id.clone());
                    let (result_tx, result_rx) = oneshot::channel();
                    let (progress_tx, mut progress_rx) = mpsc::channel(32);
                    let on_status = on_status.clone();
                    tokio::spawn(async move {
                        while let Some(bytes) = progress_rx.recv().await {
                            on_status(Ra2bPhase::Transferring {
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
                    target_tx.send(FileUploadTarget::Path { path, result_tx, progress_tx: Some(progress_tx) })
                        .map_err(|_| anyhow::anyhow!("sender disconnected before file save"))?;
                }
                Some(ServerEventV2::SessionEnd { reason: SessionEndReasonV2::Finished, .. }) => {
                    while saved_files.len() < accepted_files.len() {
                        let (file_id, result) = save_rx.recv().await.context("missing RA4B save result")?;
                        result.map_err(|error| anyhow::anyhow!("failed to save {file_id}: {error}"))?;
                        saved_files.insert(file_id);
                    }
                    ensure!(started_files.len() == accepted_files.len(), "session completed before every accepted file uploaded");
                    ensure!(saved_files.len() == accepted_files.len(), "session completed before every accepted file was saved");
                    break;
                }
                Some(ServerEventV2::SessionEnd { reason: SessionEndReasonV2::Cancelled, .. }) => bail!("cancelled"),
                Some(ServerEventV2::PrepareUploadAborted { .. }) => bail!("prepare-upload aborted"),
                Some(ServerEventV2::CancelReceived { .. }) => bail!("cancelled by sender"),
                Some(ServerEventV2::Register { .. }) => {}
                None => bail!("Anywhere HTTP server stopped before completion"),
            },
            saved = save_rx.recv() => {
                if let Some((file_id, result)) = saved {
                    result.map_err(|error| anyhow::anyhow!("failed to save {file_id}: {error}"))?;
                    saved_files.insert(file_id);
                }
            },
        }
    }
    let _ = stop_tx.send(());
    server.wait_stopped().await;
    endpoint.close().await;
    drop(relay_guard);
    ensure!(
        !accepted_files.is_empty(),
        "RA4B receiver completed without files"
    );
    Ok(Ra2bProofResult {
        path: path_class(&path),
        bytes: usize::try_from(total_bytes).context("batch size exceeds usize")?,
        hash_hex: "per-file SHA-256 verified".to_owned(),
        local_relay_id: peer.relay_id,
        remote_relay_id,
        duration_ms: started.elapsed().as_millis() as u64,
    })
}

#[derive(Clone, Default)]
pub struct Ra2bCancellation {
    cancelled: Arc<AtomicBool>,
    notify: Arc<Notify>,
}

impl Ra2bCancellation {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
        self.notify.notify_waiters();
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    pub async fn cancelled(&self) {
        loop {
            if self.is_cancelled() {
                return;
            }
            self.notify.notified().await;
        }
    }
}

pub type Ra2bStatusCallback = Arc<dyn Fn(Ra2bPhase) + Send + Sync>;

pub fn error_category(error: &anyhow::Error) -> &'static str {
    let text = format!("{error:#}");
    if text.contains(IDENTITY_REJECTED) || text.contains("RelayId mismatch") {
        "identity"
    } else if text.contains("cancelled") {
        "cancelled"
    } else if text.contains("timed out") || text.contains("timeout") {
        "timeout"
    } else if text.contains("did not confirm")
        || text.contains("session result")
        || text.contains("completion frame")
    {
        "completion"
    } else if text.contains("SHA-256") || text.contains("transfer") {
        "payload"
    } else {
        "transport"
    }
}

fn map_anywhere(error: AnywhereError) -> anyhow::Error {
    match error {
        AnywhereError::ExpectedIdentityMismatch { .. } | AnywhereError::RelayProof => {
            anyhow::anyhow!("{IDENTITY_REJECTED}")
        }
        AnywhereError::Cancelled => anyhow::anyhow!("cancelled"),
        AnywhereError::Timeout => anyhow::anyhow!("timed out"),
        AnywhereError::ProtocolCompletion => anyhow::anyhow!("session result / completion frame"),
        AnywhereError::AuthorizationDenied => anyhow::anyhow!("transfer denied"),
        AnywhereError::Tls => anyhow::anyhow!("inner TLS failed"),
        AnywhereError::Transport => anyhow::anyhow!("transport failed"),
    }
}

fn to_path_preference(preference: Ra2bPathPreference) -> PathPreference {
    match preference {
        Ra2bPathPreference::Auto => PathPreference::Auto,
        Ra2bPathPreference::ForceDirect => PathPreference::ForceDirect,
        Ra2bPathPreference::ForceRelay => PathPreference::ForceRelay,
    }
}

fn path_class(path: &PathDescriptor) -> Ra2bPathClass {
    match path {
        PathDescriptor::IrohRelay { .. } | PathDescriptor::Relayed { .. } => Ra2bPathClass::Relay,
        _ => Ra2bPathClass::Direct,
    }
}

fn approve_authenticated_session(
    session: &localsend::relay::AuthenticatedRelaySession,
) -> Result<()> {
    let decision = authorize_unknown_authenticated(session, &empty_trust());
    match decision.outcome {
        TransferAuthorization::Denied => bail!("transfer denied"),
        TransferAuthorization::PromptRequired | TransferAuthorization::AutoAccept => Ok(()),
    }
}

pub async fn run_proof(
    role: Ra2bRole,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: Ra2bStatusCallback,
) -> Result<Ra2bProofResult> {
    let started = Instant::now();
    let role_label = match &role {
        Ra2bRole::Responder => "host",
        Ra2bRole::Initiator { .. } => "join",
    };
    diag(format!(
        "SESSION_START role={role_label} local={}",
        relay_id_prefix(&peer.relay_id)
    ));
    on_status(Ra2bPhase::Starting);
    if cancellation.is_cancelled() {
        diag("SESSION_CANCELLED");
        on_status(Ra2bPhase::Cancelled);
        bail!("cancelled before start");
    }

    let (endpoint, relay_guard) = build_endpoint(path_preference).await?;
    if path_preference != Ra2bPathPreference::ForceDirect {
        tokio::select! {
            _ = cancellation.cancelled() => {
                endpoint.close().await;
                diag("SESSION_CANCELLED");
                on_status(Ra2bPhase::Cancelled);
                bail!("cancelled");
            }
            _ = endpoint.online() => {}
            _ = sleep(Duration::from_secs(20)) => {}
        }
    }
    if cancellation.is_cancelled() {
        endpoint.close().await;
        diag("SESSION_CANCELLED");
        on_status(Ra2bPhase::Cancelled);
        bail!("cancelled");
    }
    let invite = Ra2bInviteV1::new(peer.relay_id.clone(), endpoint.addr())?.encode()?;
    on_status(Ra2bPhase::EndpointReady {
        invite,
        local_relay_id: peer.relay_id.clone(),
    });

    let result = match role {
        Ra2bRole::Responder => {
            on_status(Ra2bPhase::WaitingForConnection);
            run_responder(
                endpoint.clone(),
                peer,
                path_preference,
                cancellation,
                &on_status,
            )
            .await
        }
        Ra2bRole::Initiator { remote_endpoint } => {
            on_status(Ra2bPhase::Connecting);
            run_initiator(
                endpoint.clone(),
                peer,
                remote_endpoint,
                path_preference,
                cancellation,
                &on_status,
            )
            .await
        }
    };

    endpoint.close().await;
    drop(relay_guard);
    match result {
        Ok(mut done) => {
            done.duration_ms = started.elapsed().as_millis() as u64;
            diag(format!(
                "SESSION_COMPLETE local={} remote={} path={} bytes={}",
                relay_id_prefix(&done.local_relay_id),
                relay_id_prefix(&done.remote_relay_id),
                done.path.as_str(),
                done.bytes
            ));
            on_status(Ra2bPhase::Complete {
                path: done.path.as_str().to_owned(),
                bytes: done.bytes as u32,
                hash_hex: done.hash_hex.clone(),
                local_relay_id: done.local_relay_id.clone(),
                remote_relay_id: done.remote_relay_id.clone(),
                duration_ms: done.duration_ms,
            });
            Ok(done)
        }
        Err(error) => {
            if cancellation.is_cancelled() {
                diag("SESSION_CANCELLED");
                on_status(Ra2bPhase::Cancelled);
            } else {
                let category = error_category(&error).to_owned();
                diag(format!("SESSION_ERROR={category} {error:#}"));
                let message = if category == "identity" {
                    "IDENTITY REJECTED".to_owned()
                } else {
                    error.to_string()
                };
                on_status(Ra2bPhase::Failed { message, category });
            }
            Err(error)
        }
    }
}

async fn run_responder(
    endpoint: AnywhereEndpoint,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
) -> Result<Ra2bProofResult> {
    let incoming = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out waiting for Iroh connection"),
        incoming = endpoint.accept() => incoming.map_err(map_anywhere)?,
    };
    let connection = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out completing Iroh handshake"),
        connection = incoming => connection.context("complete Iroh server handshake")?,
    };
    diag(format!(
        "IROH_ACCEPT local={}",
        relay_id_prefix(&peer.relay_id)
    ));
    on_status(Ra2bPhase::IrohConnected);

    let (send, recv) = connection
        .accept_bi()
        .await
        .context("accept Iroh bidirectional stream")?;
    let path = selected_path(&connection, to_path_preference(path_preference))
        .await
        .unwrap_or(PathDescriptor::InternetDirect {
            host: String::new(),
            port: None,
        });
    diag(format!(
        "PATH={}",
        path_class(&path).as_str().to_ascii_lowercase()
    ));
    diag("INNER_TLS_START");
    let mut tls = peer
        .tls
        .acceptor()
        .accept(IrohBiStream::new(send, recv))
        .await
        .context("inner TLS server handshake")?;
    diag("INNER_TLS_OK");
    on_status(Ra2bPhase::TlsAuthenticated);

    let observed_client_cert = server_peer_certificate_fingerprint(&tls)?;
    let expected = peer
        .expected_remote_relay_id
        .as_deref()
        .map(RelayId::from_expected_canonical_hex)
        .transpose()?;
    let session = authenticate_server(
        &mut tls,
        &peer.identity,
        peer.tls.cert_fingerprint,
        expected.as_ref(),
        observed_client_cert,
        path.clone(),
    )
    .await
    .map_err(map_anywhere)?;
    approve_authenticated_session(&session)?;
    let remote_relay_id = session.remote_relay_id().as_hex();
    diag(format!(
        "AUTH_OK local={} remote={}",
        relay_id_prefix(&peer.relay_id),
        relay_id_prefix(&remote_relay_id)
    ));
    on_status(Ra2bPhase::RelayIdentityAuthenticated {
        remote_relay_id: remote_relay_id.clone(),
    });

    let (bytes, hash) = receive_payload(&mut tls, cancellation, on_status).await?;
    Ok(Ra2bProofResult {
        path: path_class(&path),
        bytes,
        hash_hex: hex::encode(hash),
        local_relay_id: peer.relay_id,
        remote_relay_id,
        duration_ms: 0,
    })
}

async fn run_initiator(
    endpoint: AnywhereEndpoint,
    peer: Ra2bPeerMaterial,
    remote_endpoint: EndpointAddr,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
) -> Result<Ra2bProofResult> {
    let expected = peer
        .expected_remote_relay_id
        .clone()
        .context("join requires expected host RelayId")?;
    let expected = RelayId::from_expected_canonical_hex(&expected)?;
    let connection = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out connecting to remote Iroh endpoint"),
        connection = endpoint.connect(remote_endpoint) => connection.map_err(map_anywhere)?,
    };
    diag(format!(
        "IROH_CONNECT local={}",
        relay_id_prefix(&peer.relay_id)
    ));
    on_status(Ra2bPhase::IrohConnected);

    let (send, recv) = connection
        .open_bi()
        .await
        .context("open Iroh bidirectional stream")?;
    let path = selected_path(&connection, to_path_preference(path_preference))
        .await
        .unwrap_or(PathDescriptor::InternetDirect {
            host: String::new(),
            port: None,
        });
    let server_name = rustls::pki_types::ServerName::try_from("localhost")
        .context("parse inner TLS server name")?;
    diag(format!(
        "PATH={}",
        path_class(&path).as_str().to_ascii_lowercase()
    ));
    diag("INNER_TLS_START");
    let mut tls = peer
        .tls
        .connector()
        .connect(server_name, IrohBiStream::new(send, recv))
        .await
        .context("inner TLS client handshake")?;
    diag("INNER_TLS_OK");
    on_status(Ra2bPhase::TlsAuthenticated);

    let observed_server_cert = client_peer_certificate_fingerprint(&tls)?;
    let session = authenticate_initiator(
        &mut tls,
        &peer.identity,
        peer.tls.cert_fingerprint,
        &expected,
        observed_server_cert,
        path.clone(),
    )
    .await
    .map_err(map_anywhere)?;
    approve_authenticated_session(&session)?;
    let remote_relay_id = session.remote_relay_id().as_hex();
    diag(format!(
        "AUTH_OK local={} remote={}",
        relay_id_prefix(&peer.relay_id),
        relay_id_prefix(&remote_relay_id)
    ));
    on_status(Ra2bPhase::RelayIdentityAuthenticated {
        remote_relay_id: remote_relay_id.clone(),
    });

    let (bytes, hash) = send_payload(&mut tls, cancellation, on_status).await?;
    Ok(Ra2bProofResult {
        path: path_class(&path),
        bytes,
        hash_hex: hex::encode(hash),
        local_relay_id: peer.relay_id,
        remote_relay_id,
        duration_ms: 0,
    })
}

async fn build_endpoint(
    path_preference: Ra2bPathPreference,
) -> Result<(AnywhereEndpoint, Option<Box<dyn std::any::Any + Send>>)> {
    match path_preference {
        Ra2bPathPreference::ForceRelay => {
            #[cfg(feature = "linux-harness")]
            {
                let (relay_map, _relay_url, relay_guard) = iroh::test_utils::run_relay_server()
                    .await
                    .context("start stock self-hosted iroh-relay for forced relay proof")?;
                let endpoint = iroh::endpoint::Endpoint::builder(iroh::endpoint::presets::N0)
                    .relay_mode(iroh::RelayMode::Custom(relay_map))
                    .ca_tls_config(iroh::tls::CaTlsConfig::insecure_skip_verify())
                    .clear_ip_transports()
                    .alpns(vec![ALPN.to_vec()])
                    .bind()
                    .await?;
                Ok((
                    localsend::anywhere::wrap_endpoint(endpoint),
                    Some(Box::new(relay_guard)),
                ))
            }
            #[cfg(not(feature = "linux-harness"))]
            {
                Ok((
                    bind_endpoint(PathPreference::ForceRelay)
                        .await
                        .map_err(map_anywhere)?,
                    None,
                ))
            }
        }
        other => Ok((
            bind_endpoint(to_path_preference(other))
                .await
                .map_err(map_anywhere)?,
            None,
        )),
    }
}

async fn send_payload<S>(
    tls: &mut S,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
) -> Result<(usize, [u8; 32])>
where
    S: AsyncReadExt + AsyncWriteExt + Unpin,
{
    diag("PAYLOAD_START");
    tls.write_u8(PAYLOAD_MODE).await?;
    tls.write_u64(ONE_MIB as u64).await?;
    let mut hasher = Sha256::new();
    let mut sent = 0usize;
    let mut chunk = vec![0_u8; CHUNK_SIZE];
    while sent < ONE_MIB {
        if cancellation.is_cancelled() {
            bail!("cancelled during transfer");
        }
        let size = CHUNK_SIZE.min(ONE_MIB - sent);
        rand::rng().fill_bytes(&mut chunk[..size]);
        hasher.update(&chunk[..size]);
        tls.write_all(&chunk[..size]).await?;
        sent += size;
        on_status(Ra2bPhase::Transferring {
            bytes: sent as u64,
            total: ONE_MIB as u64,
        });
    }
    tls.flush().await?;
    diag(format!("PAYLOAD_BYTES={sent}"));
    let sender_hash: [u8; 32] = hasher.finalize().into();
    let mut receiver_hash = [0_u8; 32];
    tls.read_exact(&mut receiver_hash)
        .await
        .context("read receiver SHA-256")?;
    ensure!(
        sender_hash == receiver_hash,
        "sender and receiver SHA-256 differ"
    );
    diag("PAYLOAD_HASH_OK");
    tls.write_u8(STREAM_FINISH).await?;
    tls.flush().await?;
    diag("STREAM_FINISH_SENT");
    let result = tls
        .read_u8()
        .await
        .context("host did not confirm session result")?;
    ensure!(
        result == SESSION_RESULT_OK,
        "host session result was not PASS"
    );
    diag("SESSION_RESULT_RECEIVED");
    cleanup_after_success(tls).await;
    Ok((sent, sender_hash))
}

async fn receive_payload<S>(
    tls: &mut S,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
) -> Result<(usize, [u8; 32])>
where
    S: AsyncReadExt + AsyncWriteExt + Unpin,
{
    diag("PAYLOAD_START");
    let mode = tls.read_u8().await.context("read transfer mode")?;
    ensure!(mode == PAYLOAD_MODE, "unexpected transfer mode {mode}");
    let declared = tls.read_u64().await.context("read transfer length")? as usize;
    ensure!(declared == ONE_MIB, "unexpected transfer length {declared}");
    let mut received = 0usize;
    let mut hasher = Sha256::new();
    let mut chunk = vec![0_u8; CHUNK_SIZE];
    while received < declared {
        if cancellation.is_cancelled() {
            bail!("cancelled during transfer");
        }
        let size = CHUNK_SIZE.min(declared - received);
        tls.read_exact(&mut chunk[..size])
            .await
            .context("read payload chunk")?;
        hasher.update(&chunk[..size]);
        received += size;
        on_status(Ra2bPhase::Transferring {
            bytes: received as u64,
            total: declared as u64,
        });
    }
    diag(format!("PAYLOAD_BYTES={received}"));
    let hash: [u8; 32] = hasher.finalize().into();
    tls.write_all(&hash).await?;
    tls.flush().await?;
    diag("PAYLOAD_HASH_OK");
    let finish = tls
        .read_u8()
        .await
        .context("stream closed before completion frame")?;
    ensure!(finish == STREAM_FINISH, "sender did not confirm completion");
    diag("STREAM_FINISH_RECEIVED");
    tls.write_u8(SESSION_RESULT_OK).await?;
    tls.flush().await?;
    diag("SESSION_RESULT_SENT");
    cleanup_after_success(tls).await;
    Ok((received, hash))
}

/// TLS close_notify / QUIC FIN after 0x5C. Close here is cleanup, not proof authority.
async fn cleanup_after_success<S>(tls: &mut S)
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    match tls.shutdown().await {
        Ok(()) => diag("CLEANUP write_shutdown"),
        Err(error) => diag(format!("CLEANUP write_shutdown ignored: {error}")),
    }
    match wait_peer_write_closed(tls).await {
        Ok(()) => diag("CLEANUP peer_write_closed"),
        Err(error) => diag(format!("CLEANUP peer_close ignored: {error}")),
    }
}

async fn wait_peer_write_closed<S>(tls: &mut S) -> Result<()>
where
    S: AsyncRead + Unpin,
{
    let mut buf = [0_u8; 8];
    match tls.read(&mut buf).await {
        Ok(0) => Ok(()),
        Ok(_) => bail!("unexpected bytes after session result"),
        Err(error)
            if matches!(
                error.kind(),
                ErrorKind::UnexpectedEof
                    | ErrorKind::ConnectionReset
                    | ErrorKind::ConnectionAborted
                    | ErrorKind::BrokenPipe
            ) =>
        {
            Ok(())
        }
        Err(error) => Err(error.into()),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::*;

    #[tokio::test]
    async fn cancel_before_start_is_clean() {
        let peer = Ra2bPeerMaterial::generate(None).unwrap();
        let cancellation = Ra2bCancellation::new();
        cancellation.cancel();
        let err = run_proof(
            Ra2bRole::Responder,
            peer,
            Ra2bPathPreference::ForceDirect,
            &cancellation,
            Arc::new(|_| {}),
        )
        .await
        .unwrap_err();
        assert!(err.to_string().contains("cancelled"));
    }

    #[tokio::test]
    async fn cancel_aborts_host_wait() {
        let peer = Ra2bPeerMaterial::generate(None).unwrap();
        let cancellation = Ra2bCancellation::new();
        let cancel = cancellation.clone();
        let task = tokio::spawn(async move {
            run_proof(
                Ra2bRole::Responder,
                peer,
                Ra2bPathPreference::ForceDirect,
                &cancellation,
                Arc::new(|_| {}),
            )
            .await
        });
        sleep(Duration::from_millis(200)).await;
        cancel.cancel();
        let err = timeout(Duration::from_secs(8), task)
            .await
            .expect("cancel should not wait for session timeout")
            .expect("task join")
            .unwrap_err();
        assert!(err.to_string().contains("cancelled"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn wrong_identity_rejects_without_payload() {
        let host = Ra2bPeerMaterial::generate(None).unwrap();
        let host_id = host.relay_id.clone();
        let host_phases = Arc::new(Mutex::new(Vec::new()));
        let join_phases = Arc::new(Mutex::new(Vec::new()));
        let host_seen = host_phases.clone();
        let join_seen = join_phases.clone();

        let host_cancel = Ra2bCancellation::new();
        let host_task = {
            let host_cancel = host_cancel.clone();
            tokio::spawn(async move {
                run_proof(
                    Ra2bRole::Responder,
                    host,
                    Ra2bPathPreference::ForceDirect,
                    &host_cancel,
                    Arc::new(move |phase| host_seen.lock().unwrap().push(phase)),
                )
                .await
            })
        };

        let invite = loop {
            sleep(Duration::from_millis(50)).await;
            let snapshot = host_phases.lock().unwrap().clone();
            if let Some(Ra2bPhase::EndpointReady { invite, .. }) = snapshot
                .into_iter()
                .rev()
                .find(|p| matches!(p, Ra2bPhase::EndpointReady { .. }))
            {
                break invite;
            }
            assert!(
                !host_task.is_finished(),
                "host exited before publishing invite"
            );
        };
        let parsed = crate::parse_invite(&invite).unwrap();
        assert_eq!(parsed.host_relay_id, host_id);

        let wrong = RelayIdentity::generate().relay_id().unwrap();
        assert_ne!(wrong, host_id);
        let join = Ra2bPeerMaterial::generate(Some(wrong)).unwrap();
        let join_err = run_proof(
            Ra2bRole::Initiator {
                remote_endpoint: parsed.endpoint,
            },
            join,
            Ra2bPathPreference::ForceDirect,
            &Ra2bCancellation::new(),
            Arc::new(move |phase| join_seen.lock().unwrap().push(phase)),
        )
        .await
        .unwrap_err();
        assert!(
            format!("{join_err:#}").contains(IDENTITY_REJECTED),
            "join error: {join_err:#}"
        );
        let join_snapshot = join_phases.lock().unwrap().clone();
        assert!(
            !join_snapshot
                .iter()
                .any(|phase| matches!(phase, Ra2bPhase::Transferring { .. })),
            "payload must not start before identity verification"
        );
        assert!(
            !join_snapshot
                .iter()
                .any(|phase| matches!(phase, Ra2bPhase::RelayIdentityAuthenticated { .. }))
        );

        host_cancel.cancel();
        let _ = timeout(Duration::from_secs(8), host_task).await;
    }

    #[tokio::test]
    async fn payload_roundtrip_waits_for_host_session_result() {
        let (join, host) = tokio::io::duplex(64 * 1024);
        let join_cancel = Ra2bCancellation::new();
        let host_cancel = Ra2bCancellation::new();
        let noop: Ra2bStatusCallback = Arc::new(|_| {});
        let host_cb = noop.clone();
        let join_cb = noop;
        let host_task = tokio::spawn(async move {
            let mut host = host;
            receive_payload(&mut host, &host_cancel, &host_cb).await
        });
        let mut join = join;
        let (sent, sender_hash) = send_payload(&mut join, &join_cancel, &join_cb)
            .await
            .expect("join payload");
        let (received, receiver_hash) = host_task.await.expect("host join").expect("host payload");
        assert_eq!(sent, ONE_MIB);
        assert_eq!(received, ONE_MIB);
        assert_eq!(sender_hash, receiver_hash);
    }

    #[tokio::test]
    async fn close_after_ack_keeps_both_complete() {
        let (join, host) = tokio::io::duplex(64 * 1024);
        let join_cancel = Ra2bCancellation::new();
        let host_cancel = Ra2bCancellation::new();
        let noop: Ra2bStatusCallback = Arc::new(|_| {});
        let host_cb = noop.clone();
        let join_cb = noop;
        let host_task = tokio::spawn(async move {
            let mut host = host;
            receive_payload(&mut host, &host_cancel, &host_cb).await
        });
        let mut join = join;
        send_payload(&mut join, &join_cancel, &join_cb)
            .await
            .expect("join complete after 0x5C");
        drop(join);
        let (received, _) = timeout(Duration::from_secs(15), host_task)
            .await
            .expect("host should not hang on EOF")
            .expect("host join")
            .expect("host complete after 0x5C despite peer close");
        assert_eq!(received, ONE_MIB);
    }

    #[tokio::test]
    async fn host_fails_if_closed_before_ac() {
        let (mut join, host) = tokio::io::duplex(64 * 1024);
        let host_cancel = Ra2bCancellation::new();
        let host_cb: Ra2bStatusCallback = Arc::new(|_| {});
        let host_task = tokio::spawn(async move {
            let mut host = host;
            receive_payload(&mut host, &host_cancel, &host_cb).await
        });
        join.write_u8(PAYLOAD_MODE).await.unwrap();
        join.write_u64(ONE_MIB as u64).await.unwrap();
        let mut chunk = vec![0_u8; CHUNK_SIZE];
        let mut sent = 0usize;
        while sent < ONE_MIB {
            let size = CHUNK_SIZE.min(ONE_MIB - sent);
            rand::rng().fill_bytes(&mut chunk[..size]);
            join.write_all(&chunk[..size]).await.unwrap();
            sent += size;
        }
        join.flush().await.unwrap();
        let mut hash = [0_u8; 32];
        join.read_exact(&mut hash).await.unwrap();
        drop(join);
        let err = host_task
            .await
            .expect("host join")
            .expect_err("host must fail");
        let text = format!("{err:#}");
        assert!(
            text.contains("completion frame") || text.contains("sender did not confirm"),
            "host error: {text}"
        );
        assert_eq!(error_category(&err), "completion");
    }

    #[tokio::test]
    async fn join_fails_if_closed_before_5c() {
        let (join, mut host) = tokio::io::duplex(64 * 1024);
        let join_cancel = Ra2bCancellation::new();
        let join_cb: Ra2bStatusCallback = Arc::new(|_| {});
        let join_task = tokio::spawn(async move {
            let mut join = join;
            send_payload(&mut join, &join_cancel, &join_cb).await
        });
        let mode = host.read_u8().await.unwrap();
        assert_eq!(mode, PAYLOAD_MODE);
        let declared = host.read_u64().await.unwrap() as usize;
        assert_eq!(declared, ONE_MIB);
        let mut buf = vec![0_u8; declared];
        host.read_exact(&mut buf).await.unwrap();
        let hash: [u8; 32] = Sha256::digest(&buf).into();
        host.write_all(&hash).await.unwrap();
        host.flush().await.unwrap();
        let finish = host.read_u8().await.unwrap();
        assert_eq!(finish, STREAM_FINISH);
        drop(host);
        let err = join_task
            .await
            .expect("join join")
            .expect_err("join must fail");
        let text = format!("{err:#}");
        assert!(
            text.contains("did not confirm") || text.contains("session result"),
            "join error: {text}"
        );
        assert_eq!(error_category(&err), "completion");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn ra4_http_roundtrip_uses_existing_server_save_path() {
        let host = Ra2bPeerMaterial::generate(None).unwrap();
        let host_id = host.relay_id.clone();
        let sender = Ra2bPeerMaterial::generate(Some(host_id.clone())).unwrap();
        let host_phases = Arc::new(Mutex::new(Vec::new()));
        let sender_phases = Arc::new(Mutex::new(Vec::new()));
        let host_seen = host_phases.clone();
        let sender_seen = sender_phases.clone();
        let host_cancel = Ra2bCancellation::new();
        let (decision_tx, mut decision_rx) = mpsc::channel(1);
        let suffix = format!(
            "{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let source = std::env::temp_dir().join(format!("relay-ra4a-src-{suffix}"));
        let destination = std::env::temp_dir().join(format!("relay-ra4a-dst-{suffix}"));
        let bytes = b"RA4A streamed body over authenticated HTTP".to_vec();
        std::fs::write(&source, &bytes).unwrap();
        let expected_hash = hex::encode(sha2::Sha256::digest(&bytes));

        let host_callback: Ra2bStatusCallback =
            Arc::new(move |phase| host_seen.lock().unwrap().push(phase));
        let host_task = tokio::spawn(async move {
            run_ra4_receiver(
                host,
                Ra2bPathPreference::ForceDirect,
                &host_cancel,
                &host_callback,
                &mut decision_rx,
            )
            .await
        });
        let invite = loop {
            sleep(Duration::from_millis(20)).await;
            let snapshot = host_phases.lock().unwrap().clone();
            if let Some(Ra2bPhase::EndpointReady { invite, .. }) = snapshot
                .into_iter()
                .find(|phase| matches!(phase, Ra2bPhase::EndpointReady { .. }))
            {
                break invite;
            }
            assert!(
                !host_task.is_finished(),
                "RA4A host stopped before publishing invite"
            );
        };
        let parsed = crate::parse_invite(&invite).unwrap();
        let sender_bytes = bytes.clone();
        let sender_source = source.clone();
        let sender_hash = expected_hash.clone();
        let sender_callback: Ra2bStatusCallback =
            Arc::new(move |phase| sender_seen.lock().unwrap().push(phase));
        let sender_task = tokio::spawn(async move {
            run_ra4_sender(
                parsed.endpoint,
                sender,
                Ra2bPathPreference::ForceDirect,
                &Ra2bCancellation::new(),
                &sender_callback,
                Ra4FileSpec {
                    id: "ra4a-file".to_owned(),
                    name: "ra4a.txt".to_owned(),
                    size: sender_bytes.len() as u64,
                    file_type: "text/plain".to_owned(),
                    sha256: Some(sender_hash),
                    source: Ra4FileSource::Path(sender_source),
                },
            )
            .await
        });

        loop {
            sleep(Duration::from_millis(20)).await;
            let snapshot = host_phases.lock().unwrap().clone();
            if let Some(Ra2bPhase::IncomingBatch { .. }) = snapshot
                .into_iter()
                .find(|phase| matches!(phase, Ra2bPhase::IncomingBatch { .. }))
            {
                decision_tx
                    .send(Ra4Decision {
                        accept: true,
                        targets: HashMap::from([("ra4a-file".to_owned(), destination.clone())]),
                    })
                    .await
                    .unwrap();
                break;
            }
            assert!(
                !sender_task.is_finished(),
                "sender stopped before prepare-upload prompt"
            );
        }

        let sender_result = timeout(Duration::from_secs(20), sender_task)
            .await
            .expect("sender timeout")
            .expect("sender join")
            .expect("sender transfer");
        let host_result = timeout(Duration::from_secs(20), host_task)
            .await
            .expect("host timeout")
            .expect("host join")
            .expect("host transfer");
        assert_eq!(sender_result.bytes, bytes.len());
        assert_eq!(host_result.bytes, bytes.len());
        assert_eq!(std::fs::read(&destination).unwrap(), bytes);
        assert_eq!(sender_result.hash_hex, "per-file SHA-256 verified");
        let _ = std::fs::remove_file(source);
        let _ = std::fs::remove_file(destination);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn ra4b_batch_preserves_relative_paths_and_per_file_integrity() {
        let host = Ra2bPeerMaterial::generate(None).unwrap();
        let host_id = host.relay_id.clone();
        let sender = Ra2bPeerMaterial::generate(Some(host_id)).unwrap();
        let host_phases = Arc::new(Mutex::new(Vec::new()));
        let sender_phases = Arc::new(Mutex::new(Vec::new()));
        let host_seen = host_phases.clone();
        let sender_seen = sender_phases.clone();
        let host_cancel = Ra2bCancellation::new();
        let (decision_tx, mut decision_rx) = mpsc::channel(1);
        let suffix = format!(
            "{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let source_root = std::env::temp_dir().join(format!("relay-ra4b-src-{suffix}"));
        let destination_root = std::env::temp_dir().join(format!("relay-ra4b-dst-{suffix}"));
        std::fs::create_dir_all(&source_root).unwrap();
        std::fs::create_dir_all(destination_root.join("photos")).unwrap();
        let first = vec![0x41; 96 * 1024];
        // Cross the suspected 128 KiB plateau by a large margin over the
        // complete Iroh -> TLS -> Hyper -> v2 save path.
        let second = vec![0x42; 16 * 1024 * 1024];
        let first_expected = first.clone();
        let second_expected = second.clone();
        let first_len = first.len();
        let second_len = second.len();
        let first_source = source_root.join("first.txt");
        let second_source = source_root.join("second.txt");
        std::fs::write(&first_source, &first).unwrap();
        std::fs::write(&second_source, &second).unwrap();

        let host_callback: Ra2bStatusCallback =
            Arc::new(move |phase| host_seen.lock().unwrap().push(phase));
        let host_task = tokio::spawn(async move {
            run_ra4_receiver(
                host,
                Ra2bPathPreference::ForceDirect,
                &host_cancel,
                &host_callback,
                &mut decision_rx,
            )
            .await
        });
        let invite = loop {
            sleep(Duration::from_millis(20)).await;
            let phases = host_phases.lock().unwrap().clone();
            if let Some(Ra2bPhase::EndpointReady { invite, .. }) = phases
                .into_iter()
                .find(|phase| matches!(phase, Ra2bPhase::EndpointReady { .. }))
            {
                break invite;
            }
            assert!(
                !host_task.is_finished(),
                "RA4B host stopped before publishing invite"
            );
        };
        let endpoint = crate::parse_invite(&invite).unwrap().endpoint;
        let sender_callback: Ra2bStatusCallback =
            Arc::new(move |phase| sender_seen.lock().unwrap().push(phase));
        let sender_task = tokio::spawn(async move {
            run_ra4_batch_sender(
                endpoint,
                sender,
                Ra2bPathPreference::ForceDirect,
                &Ra2bCancellation::new(),
                &sender_callback,
                Ra4BatchSpec {
                    files: vec![
                        Ra4FileSpec {
                            id: "first".to_owned(),
                            name: "photos/first.txt".to_owned(),
                            size: first.len() as u64,
                            file_type: "text/plain".to_owned(),
                            sha256: Some(hex::encode(Sha256::digest(&first))),
                            source: Ra4FileSource::Path(first_source),
                        },
                        Ra4FileSpec {
                            id: "second".to_owned(),
                            name: "photos/second.txt".to_owned(),
                            size: second.len() as u64,
                            file_type: "text/plain".to_owned(),
                            sha256: Some(hex::encode(Sha256::digest(&second))),
                            source: Ra4FileSource::Path(second_source),
                        },
                    ],
                },
            )
            .await
        });

        loop {
            sleep(Duration::from_millis(20)).await;
            let phases = host_phases.lock().unwrap().clone();
            if let Some(Ra2bPhase::IncomingBatch { files, .. }) = phases
                .into_iter()
                .find(|phase| matches!(phase, Ra2bPhase::IncomingBatch { .. }))
            {
                assert_eq!(files.len(), 2);
                assert!(files.iter().any(|file| file.name == "photos/first.txt"));
                assert!(files.iter().any(|file| file.name == "photos/second.txt"));
                decision_tx
                    .send(Ra4Decision {
                        accept: true,
                        targets: HashMap::from([
                            (
                                "first".to_owned(),
                                destination_root.join("photos/first.txt"),
                            ),
                            (
                                "second".to_owned(),
                                destination_root.join("photos/second.txt"),
                            ),
                        ]),
                    })
                    .await
                    .unwrap();
                break;
            }
            assert!(
                !sender_task.is_finished(),
                "sender stopped before RA4B batch prompt"
            );
        }

        let sender_result = timeout(Duration::from_secs(20), sender_task)
            .await
            .expect("sender timeout")
            .expect("sender join")
            .expect("sender transfer");
        let host_result = timeout(Duration::from_secs(20), host_task)
            .await
            .expect("host timeout")
            .expect("host join")
            .expect("host transfer");
        assert_eq!(sender_result.bytes, first_len + second_len);
        assert_eq!(host_result.bytes, first_len + second_len);
        assert_eq!(
            std::fs::read(destination_root.join("photos/first.txt")).unwrap(),
            first_expected
        );
        assert_eq!(
            std::fs::read(destination_root.join("photos/second.txt")).unwrap(),
            second_expected
        );
        assert!(sender_phases
            .lock()
            .unwrap()
            .iter()
            .any(|phase| matches!(phase, Ra2bPhase::Transferring { total, .. } if *total == (first_len + second_len) as u64)));
        let _ = std::fs::remove_dir_all(source_root);
        let _ = std::fs::remove_dir_all(destination_root);
    }
}
