//! Production Relay Anywhere API.
//!
//! Flutter never receives private identity keys, inner-TLS keys, or proof
//! bytes. Every call is scoped to one session: there is no process-wide
//! "current session", and answering one inbound request cannot answer another.
//!
//! Iroh starts only when one of the session functions here runs. Importing this
//! module, opening a session, or parsing an address does not touch the network.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use localsend::anywhere::{
    AnywhereBatch, AnywhereDecision, AnywhereError, AnywhereEvent, AnywhereFileSource,
    AnywhereFileSpec, AnywhereIdentity, AnywhereListener, AnywhereListenerConfig,
    AnywhereListenerEvent, AnywhereReceiveRequest, AnywhereRoutingKey, AnywhereRuntime,
    AnywhereSaveTarget, AnywhereSendRequest, AnywhereSessionId, IncomingTransferId, PathPreference,
    RelayAddressV1, authenticate_address, receive, send_batch,
};
use localsend::model::transfer::FileMetadata;

/// Registry of live sessions. A map keyed by session id — never a single-slot
/// lease, so independent transfers coexist.
pub(crate) fn anywhere_runtime() -> &'static Arc<AnywhereRuntime> {
    static RUNTIME: OnceLock<Arc<AnywhereRuntime>> = OnceLock::new();
    RUNTIME.get_or_init(|| Arc::new(AnywhereRuntime::new()))
}

fn anywhere_listener() -> &'static std::sync::Mutex<Option<AnywhereListener>> {
    static LISTENER: OnceLock<std::sync::Mutex<Option<AnywhereListener>>> = OnceLock::new();
    LISTENER.get_or_init(|| std::sync::Mutex::new(None))
}

#[derive(Clone, Copy, Debug)]
pub enum RsRelayPathPreference {
    Auto,
    ForceDirect,
    ForceRelay,
}

impl From<RsRelayPathPreference> for PathPreference {
    fn from(value: RsRelayPathPreference) -> Self {
        match value {
            RsRelayPathPreference::Auto => Self::Auto,
            RsRelayPathPreference::ForceDirect => Self::ForceDirect,
            RsRelayPathPreference::ForceRelay => Self::ForceRelay,
        }
    }
}

/// A parsed Relay address. `claimedRelayId` is a claim to be proven by the
/// session, never evidence of identity or trust.
#[derive(Clone, Debug)]
pub struct RsRelayAddress {
    pub version: u32,
    pub claimed_relay_id: String,
    pub routing_available: bool,
}

/// One outbound file. Android passes a SAF descriptor; desktop passes a path.
#[derive(Clone, Debug)]
pub struct RsRelayAnywhereFile {
    pub path: Option<String>,
    pub file_descriptor: Option<i32>,
    /// Bounded inline text/share content. Picker and folder selections retain
    /// their path or Android SAF descriptor streaming source.
    pub bytes: Option<Vec<u8>>,
    pub name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub preview: Option<String>,
    pub last_modified: Option<String>,
    pub last_accessed: Option<String>,
}

#[derive(serde::Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum RsRelayAnywhereSaveTarget {
    Path { path: String },
    FileDescriptor { file_descriptor: i32 },
}

#[derive(Clone, Debug)]
pub struct RsRelayIncomingFile {
    pub id: String,
    pub name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
}

#[derive(Clone, Debug)]
pub enum RsRelayAnywhereEvent {
    Starting,
    AddressReady {
        address: String,
        local_relay_id: String,
    },
    WaitingForPeer,
    Connecting,
    PeerConnected,
    TlsEstablished,
    PeerAuthenticated {
        remote_relay_id: String,
    },
    IncomingBatch {
        transfer_id: u64,
        files: Vec<RsRelayIncomingFile>,
        remote_relay_id: String,
    },
    Transferring {
        bytes: u64,
        total: u64,
    },
    Completed {
        path: String,
        bytes: u64,
        local_relay_id: String,
        remote_relay_id: String,
        duration_ms: u64,
    },
    /// `stage` names the exact failing operation (bind / connect / accept / …)
    /// so a failure never has to be guessed from the category alone.
    Failed {
        message: String,
        category: String,
        stage: Option<String>,
    },
    Cancelled,
}

/// Events from the one persistent Anywhere listener. Every incoming transfer
/// includes its runtime session id so approvals and cancellation stay scoped
/// to that connection.
#[derive(Clone, Debug)]
pub enum RsRelayAnywhereListenerEvent {
    AddressReady {
        address: String,
        local_relay_id: String,
    },
    SessionStarting {
        session_id: u64,
    },
    SessionWaitingForPeer {
        session_id: u64,
    },
    SessionPeerConnected {
        session_id: u64,
    },
    SessionTlsEstablished {
        session_id: u64,
    },
    SessionPeerAuthenticated {
        session_id: u64,
        remote_relay_id: String,
    },
    SessionIncomingBatch {
        session_id: u64,
        transfer_id: u64,
        files: Vec<RsRelayIncomingFile>,
        remote_relay_id: String,
    },
    SessionTransferring {
        session_id: u64,
        bytes: u64,
        total: u64,
    },
    SessionCompleted {
        session_id: u64,
        path: String,
        bytes: u64,
        local_relay_id: String,
        remote_relay_id: String,
        duration_ms: u64,
    },
    SessionCancelled {
        session_id: u64,
    },
    SessionFailed {
        session_id: u64,
        message: String,
        category: String,
        stage: Option<String>,
    },
    Stopped,
}

fn map_event(event: AnywhereEvent) -> RsRelayAnywhereEvent {
    match event {
        AnywhereEvent::Starting => RsRelayAnywhereEvent::Starting,
        AnywhereEvent::EndpointReady {
            address,
            local_relay_id,
        } => RsRelayAnywhereEvent::AddressReady {
            address,
            local_relay_id,
        },
        AnywhereEvent::WaitingForConnection => RsRelayAnywhereEvent::WaitingForPeer,
        AnywhereEvent::Connecting => RsRelayAnywhereEvent::Connecting,
        AnywhereEvent::PeerConnected => RsRelayAnywhereEvent::PeerConnected,
        AnywhereEvent::TlsEstablished => RsRelayAnywhereEvent::TlsEstablished,
        AnywhereEvent::PeerAuthenticated { remote_relay_id } => {
            RsRelayAnywhereEvent::PeerAuthenticated { remote_relay_id }
        }
        AnywhereEvent::IncomingBatch {
            transfer_id,
            files,
            remote_relay_id,
        } => RsRelayAnywhereEvent::IncomingBatch {
            transfer_id: transfer_id.as_u64(),
            files: files
                .into_iter()
                .map(|file| RsRelayIncomingFile {
                    id: file.id,
                    name: file.name,
                    size: file.size,
                    file_type: file.file_type,
                    sha256: file.sha256,
                })
                .collect(),
            remote_relay_id,
        },
        AnywhereEvent::Transferring { bytes, total } => {
            RsRelayAnywhereEvent::Transferring { bytes, total }
        }
        AnywhereEvent::Completed { outcome } => RsRelayAnywhereEvent::Completed {
            path: outcome.path.as_str().to_owned(),
            bytes: outcome.bytes,
            local_relay_id: outcome.local_relay_id,
            remote_relay_id: outcome.remote_relay_id,
            duration_ms: outcome.duration_ms,
        },
        AnywhereEvent::Cancelled => RsRelayAnywhereEvent::Cancelled,
    }
}

pub(crate) fn map_failure(error: &AnywhereError) -> RsRelayAnywhereEvent {
    match error {
        AnywhereError::Cancelled => RsRelayAnywhereEvent::Cancelled,
        other => RsRelayAnywhereEvent::Failed {
            message: other.to_string(),
            category: other.category().to_owned(),
            stage: other.stage().map(str::to_owned),
        },
    }
}

fn map_listener_event(event: AnywhereListenerEvent) -> RsRelayAnywhereListenerEvent {
    match event {
        AnywhereListenerEvent::AddressReady {
            address,
            local_relay_id,
        } => RsRelayAnywhereListenerEvent::AddressReady {
            address,
            local_relay_id,
        },
        AnywhereListenerEvent::Session { session_id, event } => match event {
            AnywhereEvent::Starting => RsRelayAnywhereListenerEvent::SessionStarting {
                session_id: session_id.as_u64(),
            },
            AnywhereEvent::WaitingForConnection => {
                RsRelayAnywhereListenerEvent::SessionWaitingForPeer {
                    session_id: session_id.as_u64(),
                }
            }
            AnywhereEvent::PeerConnected => RsRelayAnywhereListenerEvent::SessionPeerConnected {
                session_id: session_id.as_u64(),
            },
            AnywhereEvent::TlsEstablished => RsRelayAnywhereListenerEvent::SessionTlsEstablished {
                session_id: session_id.as_u64(),
            },
            AnywhereEvent::PeerAuthenticated { remote_relay_id } => {
                RsRelayAnywhereListenerEvent::SessionPeerAuthenticated {
                    session_id: session_id.as_u64(),
                    remote_relay_id,
                }
            }
            AnywhereEvent::IncomingBatch {
                transfer_id,
                files,
                remote_relay_id,
            } => RsRelayAnywhereListenerEvent::SessionIncomingBatch {
                session_id: session_id.as_u64(),
                transfer_id: transfer_id.as_u64(),
                files: files
                    .into_iter()
                    .map(|file| RsRelayIncomingFile {
                        id: file.id,
                        name: file.name,
                        size: file.size,
                        file_type: file.file_type,
                        sha256: file.sha256,
                    })
                    .collect(),
                remote_relay_id,
            },
            AnywhereEvent::Transferring { bytes, total } => {
                RsRelayAnywhereListenerEvent::SessionTransferring {
                    session_id: session_id.as_u64(),
                    bytes,
                    total,
                }
            }
            AnywhereEvent::Completed { outcome } => {
                RsRelayAnywhereListenerEvent::SessionCompleted {
                    session_id: session_id.as_u64(),
                    path: outcome.path.as_str().to_owned(),
                    bytes: outcome.bytes,
                    local_relay_id: outcome.local_relay_id,
                    remote_relay_id: outcome.remote_relay_id,
                    duration_ms: outcome.duration_ms,
                }
            }
            AnywhereEvent::Cancelled => RsRelayAnywhereListenerEvent::SessionCancelled {
                session_id: session_id.as_u64(),
            },
            // A listener itself publishes the address. A session never owns
            // endpoint setup or a standalone outbound connection state.
            AnywhereEvent::EndpointReady { .. } | AnywhereEvent::Connecting => {
                RsRelayAnywhereListenerEvent::SessionFailed {
                    session_id: session_id.as_u64(),
                    message: "invalid listener session event".to_owned(),
                    category: "protocol".to_owned(),
                    stage: None,
                }
            }
        },
        AnywhereListenerEvent::SessionFailed {
            session_id,
            category,
            stage,
        } => RsRelayAnywhereListenerEvent::SessionFailed {
            session_id: session_id.as_u64(),
            message: "Anywhere listener session failed".to_owned(),
            category,
            stage,
        },
        AnywhereListenerEvent::Stopped => RsRelayAnywhereListenerEvent::Stopped,
    }
}

/// Parses a Relay address bundle. Fail-closed; never panics on bad input.
#[frb(sync)]
pub fn relay_anywhere_parse_address(address: String) -> anyhow::Result<RsRelayAddress> {
    let parsed = RelayAddressV1::decode(&address)?;
    Ok(RsRelayAddress {
        version: parsed.version,
        claimed_relay_id: parsed.claimed_relay_id,
        routing_available: true,
    })
}

/// Creates an opaque private routing key for a persistent Anywhere endpoint.
///
/// The caller must immediately place this material in the platform secret
/// store. It is intentionally unrelated to the Relay identity private key.
#[frb(sync)]
pub fn relay_anywhere_generate_routing_key() -> Vec<u8> {
    AnywhereRoutingKey::generate().secret_bytes().to_vec()
}

/// Validates opaque routing-key material before it is used or retained.
/// No endpoint is bound and no routing metadata is exposed by this operation.
#[frb(sync)]
pub fn relay_anywhere_validate_routing_key(mut routing_key: Vec<u8>) -> anyhow::Result<()> {
    let result = AnywhereRoutingKey::from_bytes(&routing_key).map(|_| ());
    routing_key.fill(0);
    result.map_err(anyhow::Error::from)
}

/// Activates the single reusable Anywhere listener. This is the production
/// capability boundary: importing the API or opening an outbound session does
/// not bind Iroh. The caller supplies both unrelated secret materials from the
/// platform stores, and they are wiped after being reconstructed in Rust.
pub async fn relay_anywhere_start_listener(
    mut private_key_pem: Vec<u8>,
    relay_id: String,
    mut routing_key: Vec<u8>,
    alias: String,
    event_sink: StreamSink<RsRelayAnywhereListenerEvent>,
) -> anyhow::Result<()> {
    if anywhere_listener()
        .lock()
        .map_err(|_| anyhow::anyhow!("Anywhere listener state is unavailable"))?
        .is_some()
    {
        anyhow::bail!("Anywhere listener is already running");
    }

    let identity = AnywhereIdentity::load(&mut private_key_pem, &relay_id);
    private_key_pem.fill(0);
    let identity = identity?;
    let routing_key_result = AnywhereRoutingKey::from_bytes(&routing_key);
    routing_key.fill(0);
    let routing_key = routing_key_result?;
    let sink = event_sink.clone();
    let events = Arc::new(move |event| {
        let _ = sink.add(map_listener_event(event));
    });
    let listener = AnywhereListener::start(
        anywhere_runtime().clone(),
        AnywhereListenerConfig {
            identity,
            routing_key,
            preference: PathPreference::Auto,
            alias,
        },
        events,
    )
    .await?;

    // A second caller can pass the initial check while this caller is binding
    // Iroh. Never replace a live listener in that race: doing so would leave
    // the losing listener reachable even though its start call failed.
    let mut pending_listener = Some(listener);
    let already_running = {
        let mut slot = anywhere_listener()
            .lock()
            .map_err(|_| anyhow::anyhow!("Anywhere listener state is unavailable"))?;
        if slot.is_some() {
            true
        } else {
            *slot = pending_listener.take();
            false
        }
    };
    if already_running {
        if let Some(listener) = pending_listener {
            listener.shutdown().await;
        }
        anyhow::bail!("Anywhere listener was started concurrently");
    }
    Ok(())
}

/// Stops remote capability and cleanly closes the persistent endpoint. It is
/// idempotent so normal application shutdown can call it unconditionally.
pub async fn relay_anywhere_stop_listener() {
    let listener = anywhere_listener()
        .lock()
        .ok()
        .and_then(|mut slot| slot.take());
    if let Some(listener) = listener {
        listener.shutdown().await;
    }
}

/// Returns the current public routing address without exposing its private key.
#[frb(sync)]
pub fn relay_anywhere_listener_address() -> Option<String> {
    anywhere_listener()
        .lock()
        .ok()
        .and_then(|slot| slot.as_ref().map(|listener| listener.address().to_owned()))
}

/// Opens a session handle. Any number may be open at once.
#[frb(sync)]
pub fn relay_anywhere_open_session() -> u64 {
    anywhere_runtime().open_session().0.as_u64()
}

/// Cancels exactly one session. Other sessions are unaffected.
#[frb(sync)]
pub fn relay_anywhere_cancel(session_id: u64) -> bool {
    anywhere_runtime().cancel(AnywhereSessionId::from_u64(session_id))
}

/// Drops one session handle after it finished.
#[frb(sync)]
pub fn relay_anywhere_close_session(session_id: u64) -> bool {
    anywhere_runtime().close_session(AnywhereSessionId::from_u64(session_id))
}

#[frb(sync)]
pub fn relay_anywhere_open_session_count() -> u32 {
    anywhere_runtime().open_session_count() as u32
}

/// Answers one specific inbound request.
///
/// Accepting is session-scoped consent for this transfer only; it never becomes
/// persistent trust.
#[frb(sync)]
pub fn relay_anywhere_respond(
    session_id: u64,
    transfer_id: u64,
    accept: bool,
    targets_json: Option<String>,
) -> anyhow::Result<()> {
    let targets: HashMap<String, AnywhereSaveTarget> = match targets_json {
        Some(json) if accept => {
            serde_json::from_str::<HashMap<String, RsRelayAnywhereSaveTarget>>(&json)?
                .into_iter()
                .map(|(file_id, target)| {
                    let target = match target {
                        RsRelayAnywhereSaveTarget::Path { path } => {
                            AnywhereSaveTarget::Path(PathBuf::from(path))
                        }
                        RsRelayAnywhereSaveTarget::FileDescriptor { file_descriptor } => {
                            #[cfg(target_os = "android")]
                            {
                                AnywhereSaveTarget::FileDescriptor(file_descriptor)
                            }
                            #[cfg(not(target_os = "android"))]
                            {
                                let _ = file_descriptor;
                                anyhow::bail!("SAF file descriptors are only available on Android")
                            }
                        }
                    };
                    Ok((file_id, target))
                })
                .collect::<anyhow::Result<_>>()?
        }
        _ => HashMap::new(),
    };
    anywhere_runtime()
        .respond(
            AnywhereSessionId::from_u64(session_id),
            IncomingTransferId::from_u64(transfer_id),
            AnywhereDecision { accept, targets },
        )
        .map_err(anyhow::Error::from)
}

/// Receives one authenticated Anywhere transfer on `session_id`.
///
/// `private_key_pem` is the persisted Relay identity key from the platform
/// secret store. It is zeroed inside Rust before this call returns.
#[allow(clippy::too_many_arguments)]
pub async fn relay_anywhere_receive(
    session_id: u64,
    mut private_key_pem: Vec<u8>,
    relay_id: String,
    alias: String,
    path_preference: RsRelayPathPreference,
    expected_remote_relay_id: Option<String>,
    event_sink: StreamSink<RsRelayAnywhereEvent>,
) -> anyhow::Result<()> {
    let identity_result = AnywhereIdentity::load(&mut private_key_pem, &relay_id);
    private_key_pem.fill(0);
    let identity = identity_result?;
    let session = AnywhereSessionId::from_u64(session_id);
    let runtime = anywhere_runtime().clone();
    let cancel = session_cancellation(&runtime, session)?;
    let sink = event_sink.clone();
    let events = Arc::new(move |event: AnywhereEvent| {
        let _ = sink.add(map_event(event));
    });

    let result = receive(
        runtime.clone(),
        session,
        cancel,
        AnywhereReceiveRequest {
            identity,
            preference: path_preference.into(),
            alias,
            expected_remote_relay_id,
        },
        events,
    )
    .await;
    finish(&runtime, session, &event_sink, result.map(|_| ()))
}

/// Sends one authenticated Anywhere batch on `session_id`.
#[allow(clippy::too_many_arguments)]
pub async fn relay_anywhere_send(
    session_id: u64,
    mut private_key_pem: Vec<u8>,
    relay_id: String,
    address: String,
    alias: String,
    path_preference: RsRelayPathPreference,
    files: Vec<RsRelayAnywhereFile>,
    event_sink: StreamSink<RsRelayAnywhereEvent>,
) -> anyhow::Result<()> {
    let identity_result = AnywhereIdentity::load(&mut private_key_pem, &relay_id);
    private_key_pem.fill(0);
    let identity = identity_result?;
    let remote = RelayAddressV1::decode(&address)?;
    let batch = AnywhereBatch {
        files: files
            .into_iter()
            .map(file_spec)
            .collect::<anyhow::Result<Vec<_>>>()?,
    };
    let session = AnywhereSessionId::from_u64(session_id);
    let runtime = anywhere_runtime().clone();
    let cancel = session_cancellation(&runtime, session)?;
    let sink = event_sink.clone();
    let events = Arc::new(move |event: AnywhereEvent| {
        let _ = sink.add(map_event(event));
    });

    let result = send_batch(
        session,
        cancel,
        AnywhereSendRequest {
            identity,
            remote,
            preference: path_preference.into(),
            alias,
            batch,
        },
        events,
    )
    .await;
    finish(&runtime, session, &event_sink, result.map(|_| ()))
}

/// Authenticates an address claim before pairing it. This sends no payload and
/// never persists routing metadata itself; Dart only records the route after a
/// successful proof of the claimed RelayId.
pub async fn relay_anywhere_authenticate_address(
    session_id: u64,
    mut private_key_pem: Vec<u8>,
    relay_id: String,
    address: String,
    path_preference: RsRelayPathPreference,
    event_sink: StreamSink<RsRelayAnywhereEvent>,
) -> anyhow::Result<()> {
    let identity_result = AnywhereIdentity::load(&mut private_key_pem, &relay_id);
    private_key_pem.fill(0);
    let identity = identity_result?;
    let remote = RelayAddressV1::decode(&address)?;
    let session = AnywhereSessionId::from_u64(session_id);
    let runtime = anywhere_runtime().clone();
    let cancel = session_cancellation(&runtime, session)?;
    let sink = event_sink.clone();
    let events = Arc::new(move |event: AnywhereEvent| {
        let _ = sink.add(map_event(event));
    });

    let result = authenticate_address(
        session,
        cancel,
        AnywhereSendRequest {
            identity,
            remote,
            preference: path_preference.into(),
            alias: String::new(),
            batch: AnywhereBatch { files: Vec::new() },
        },
        events,
    )
    .await;
    finish(&runtime, session, &event_sink, result.map(|_| ()))
}

fn file_spec(file: RsRelayAnywhereFile) -> anyhow::Result<AnywhereFileSpec> {
    let source = match (file.path, file.file_descriptor, file.bytes) {
        (Some(_), Some(_), _) | (Some(_), _, Some(_)) | (_, Some(_), Some(_)) => {
            anyhow::bail!("a Relay file source must have exactly one source")
        }
        (Some(path), None, None) => AnywhereFileSource::Path(PathBuf::from(path)),
        #[cfg(target_os = "android")]
        (None, Some(fd), None) => AnywhereFileSource::FileDescriptor(fd),
        #[cfg(not(target_os = "android"))]
        (None, Some(_), None) => anyhow::bail!("file descriptors are only supported on Android"),
        (None, None, Some(bytes)) => {
            const MAX_INLINE_SOURCE_BYTES: usize = 1024 * 1024;
            if bytes.len() > MAX_INLINE_SOURCE_BYTES {
                anyhow::bail!("an inline Relay source exceeds 1 MiB")
            }
            AnywhereFileSource::Bytes(bytes)
        }
        (None, None, None) => anyhow::bail!(
            "an Anywhere file needs a path, file descriptor, or bounded inline source"
        ),
    };
    Ok(AnywhereFileSpec {
        id: uuid::Uuid::new_v4().to_string(),
        name: file.name,
        size: file.size,
        file_type: file.file_type,
        sha256: file.sha256,
        preview: file.preview,
        metadata: match (file.last_modified, file.last_accessed) {
            (None, None) => None,
            (modified, accessed) => Some(FileMetadata { modified, accessed }),
        },
        source,
    })
}

/// Looks up the session's own cancellation token. A session must be opened
/// before it can run, so its lifetime is always caller-controlled.
fn session_cancellation(
    runtime: &Arc<AnywhereRuntime>,
    session: AnywhereSessionId,
) -> anyhow::Result<tokio_util::sync::CancellationToken> {
    anyhow::ensure!(
        runtime.is_open(session),
        "Anywhere session {} is not open",
        session.as_u64()
    );
    Ok(runtime.cancellation(session).expect("session is open"))
}

fn finish(
    runtime: &Arc<AnywhereRuntime>,
    session: AnywhereSessionId,
    sink: &StreamSink<RsRelayAnywhereEvent>,
    result: Result<(), AnywhereError>,
) -> anyhow::Result<()> {
    // Completion removes only this session's handle.
    runtime.close_session(session);
    match result {
        Ok(()) => Ok(()),
        Err(error) => {
            let _ = sink.add(map_failure(&error));
            Ok(())
        }
    }
}
