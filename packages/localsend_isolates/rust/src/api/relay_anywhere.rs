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
    AnywhereFileSpec, AnywhereIdentity, AnywhereReceiveRequest, AnywhereRuntime,
    AnywhereSendRequest, AnywhereSessionId, IncomingTransferId, PathPreference, RelayAddressV1,
    receive, send_batch,
};

/// Registry of live sessions. A map keyed by session id — never a single-slot
/// lease, so independent transfers coexist.
pub(crate) fn anywhere_runtime() -> &'static Arc<AnywhereRuntime> {
    static RUNTIME: OnceLock<Arc<AnywhereRuntime>> = OnceLock::new();
    RUNTIME.get_or_init(|| Arc::new(AnywhereRuntime::new()))
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
    pub name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
}

#[derive(Clone, Debug)]
pub struct RsRelayIncomingFile {
    pub id: String,
    pub name: String,
    pub size: u64,
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
    let targets: HashMap<String, PathBuf> = match targets_json {
        Some(json) if accept => serde_json::from_str(&json)?,
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
    let identity = AnywhereIdentity::load(&mut private_key_pem, &relay_id)?;
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
    let identity = AnywhereIdentity::load(&mut private_key_pem, &relay_id)?;
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

fn file_spec(file: RsRelayAnywhereFile) -> anyhow::Result<AnywhereFileSpec> {
    let source = match (file.path, file.file_descriptor) {
        (Some(path), _) => AnywhereFileSource::Path(PathBuf::from(path)),
        #[cfg(target_os = "android")]
        (None, Some(fd)) => AnywhereFileSource::FileDescriptor(fd),
        #[cfg(not(target_os = "android"))]
        (None, Some(_)) => anyhow::bail!("file descriptors are only supported on Android"),
        (None, None) => anyhow::bail!("an Anywhere file needs a path or file descriptor"),
    };
    Ok(AnywhereFileSpec {
        id: uuid::Uuid::new_v4().to_string(),
        name: file.name,
        size: file.size,
        file_type: file.file_type,
        sha256: file.sha256,
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
