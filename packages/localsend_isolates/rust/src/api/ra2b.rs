//! Development-only Flutter API for the RA2B dual-app harness.
//!
//! Flutter never receives private identity keys, TLS private keys, or proof
//! signature bytes. The invite string is a test addressing package, not
//! production trust architecture.

use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use crate::frb_generated::StreamSink;
use anyhow::Context as _;
use flutter_rust_bridge::frb;
use localsend::anywhere::{
    AnywhereBatch, AnywhereError, AnywhereEvent, AnywhereFileSource, AnywhereFileSpec,
    AnywhereIdentity, AnywhereReceiveRequest, AnywhereSendRequest, AnywhereSessionId,
    PathPreference, RelayAddressV1, receive as anywhere_receive, send_batch as anywhere_send,
};
use relay_anywhere_ra2b::{
    ActiveSessionGuard, Ra2bPathPreference, Ra2bPeerMaterial, Ra2bPhase, Ra2bRole,
    cancel_active_session, fresh_unrelated_relay_id, parse_invite, process_identity,
    process_relay_id, run_proof, session_is_active,
};

use super::relay_anywhere::anywhere_runtime;

/// The harness UI drives one session at a time; the production runtime does
/// not. This slot only remembers which production session this UI started so
/// its single Cancel button can target it.
fn harness_session() -> &'static Mutex<Option<u64>> {
    static SESSION: OnceLock<Mutex<Option<u64>>> = OnceLock::new();
    SESSION.get_or_init(|| Mutex::new(None))
}

fn set_harness_session(session: Option<u64>) {
    *harness_session()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = session;
}

fn map_anywhere_event(event: AnywhereEvent) -> Option<RsRa2bEvent> {
    Some(match event {
        AnywhereEvent::Starting => RsRa2bEvent::Starting,
        AnywhereEvent::EndpointReady {
            address,
            local_relay_id,
        } => RsRa2bEvent::InviteReady {
            invite: address,
            local_relay_id,
            auto_relay_available: true,
        },
        AnywhereEvent::WaitingForConnection => RsRa2bEvent::WaitingForPeer,
        AnywhereEvent::Connecting => RsRa2bEvent::Connecting,
        AnywhereEvent::PeerConnected => RsRa2bEvent::IrohConnected,
        AnywhereEvent::TlsEstablished => RsRa2bEvent::TlsAuthenticated,
        AnywhereEvent::PeerAuthenticated { remote_relay_id } => {
            RsRa2bEvent::RelayIdentityVerified { remote_relay_id }
        }
        AnywhereEvent::IncomingBatch {
            transfer_id,
            files,
            remote_relay_id,
        } => RsRa2bEvent::Failed {
            message: serde_json::json!({
                "transferId": transfer_id.as_u64().to_string(),
                "files": files
                    .into_iter()
                    .map(|file| serde_json::json!({
                        "id": file.id,
                        "name": file.name,
                        "size": file.size,
                    }))
                    .collect::<Vec<_>>(),
                "remoteRelayId": remote_relay_id,
            })
            .to_string(),
            category: "prompt".to_owned(),
        },
        AnywhereEvent::Transferring { bytes, total } => RsRa2bEvent::Transferring { bytes, total },
        AnywhereEvent::Completed { outcome } => RsRa2bEvent::Complete {
            path: outcome.path.as_str().to_uppercase(),
            bytes: u32::try_from(outcome.bytes).unwrap_or(u32::MAX),
            hash_hex: "per-file SHA-256 verified".to_owned(),
            local_relay_id: outcome.local_relay_id,
            remote_relay_id: outcome.remote_relay_id,
            duration_ms: outcome.duration_ms,
        },
        AnywhereEvent::Cancelled => RsRa2bEvent::Cancelled,
    })
}

fn map_anywhere_failure(error: &AnywhereError) -> RsRa2bEvent {
    match error {
        AnywhereError::Cancelled => RsRa2bEvent::Cancelled,
        AnywhereError::ExpectedIdentityMismatch { .. } | AnywhereError::RelayProof => {
            RsRa2bEvent::Rejected {
                message: error.to_string(),
                category: error.category().to_owned(),
            }
        }
        other => RsRa2bEvent::Failed {
            message: match other.stage() {
                Some(stage) => format!("{other} [stage={stage}]"),
                None => other.to_string(),
            },
            category: other.category().to_owned(),
        },
    }
}

enum Ra4RuntimeConfig {
    Sender { files: Vec<Ra4RuntimeFile> },
}


struct Ra4RuntimeFile {
    path: Option<String>,
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    file_descriptor: Option<i32>,
    name: String,
    size: u64,
    file_type: String,
    sha256: Option<String>,
}

fn ra4_config() -> &'static Mutex<Option<Ra4RuntimeConfig>> {
    static CONFIG: OnceLock<Mutex<Option<Ra4RuntimeConfig>>> = OnceLock::new();
    CONFIG.get_or_init(|| Mutex::new(None))
}

#[derive(Clone, Debug)]
pub enum RsRa2bPathPreference {
    Auto,
    ForceRelay,
}

impl From<RsRa2bPathPreference> for PathPreference {
    fn from(value: RsRa2bPathPreference) -> Self {
        match value {
            RsRa2bPathPreference::Auto => Self::Auto,
            RsRa2bPathPreference::ForceRelay => Self::ForceRelay,
        }
    }
}

impl From<RsRa2bPathPreference> for Ra2bPathPreference {
    fn from(value: RsRa2bPathPreference) -> Self {
        match value {
            RsRa2bPathPreference::Auto => Self::Auto,
            RsRa2bPathPreference::ForceRelay => Self::ForceRelay,
        }
    }
}

#[derive(Clone, Debug)]
pub struct RsRa2bLocalIdentity {
    pub relay_id: String,
}

#[derive(Clone, Debug)]
pub struct RsRa2bParsedInvite {
    pub version: u32,
    pub host_relay_id: String,
    pub routing_available: bool,
    /// Short session capability label (development only).
    pub capability: Option<String>,
}

#[derive(Clone, Debug)]
pub enum RsRa2bEvent {
    Starting,
    InviteReady {
        invite: String,
        local_relay_id: String,
        auto_relay_available: bool,
    },
    WaitingForPeer,
    Connecting,
    IrohConnected,
    TlsAuthenticated,
    RelayIdentityVerified {
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
    Rejected {
        message: String,
        category: String,
    },
    Failed {
        message: String,
        category: String,
    },
    Cancelled,
}

impl From<Ra2bPhase> for RsRa2bEvent {
    fn from(value: Ra2bPhase) -> Self {
        match value {
            Ra2bPhase::Starting => Self::Starting,
            Ra2bPhase::EndpointReady {
                invite,
                local_relay_id,
            } => Self::InviteReady {
                invite,
                local_relay_id,
                auto_relay_available: true,
            },
            Ra2bPhase::WaitingForConnection => Self::WaitingForPeer,
            Ra2bPhase::Connecting => Self::Connecting,
            Ra2bPhase::IrohConnected => Self::IrohConnected,
            Ra2bPhase::TlsAuthenticated => Self::TlsAuthenticated,
            Ra2bPhase::RelayIdentityAuthenticated { remote_relay_id } => {
                Self::RelayIdentityVerified { remote_relay_id }
            }
            Ra2bPhase::IncomingFile {
                name,
                size,
                remote_relay_id,
            } => Self::Failed {
                message: serde_json::json!({
                    "name": name,
                    "size": size,
                    "remoteRelayId": remote_relay_id,
                })
                .to_string(),
                category: "prompt".to_owned(),
            },
            Ra2bPhase::IncomingBatch {
                files,
                remote_relay_id,
            } => Self::Failed {
                message: serde_json::json!({
                    "files": files
                        .into_iter()
                        .map(|file| serde_json::json!({
                            "id": file.id,
                            "name": file.name,
                            "size": file.size,
                        }))
                        .collect::<Vec<_>>(),
                    "remoteRelayId": remote_relay_id,
                })
                .to_string(),
                category: "prompt".to_owned(),
            },
            Ra2bPhase::Transferring { bytes, total } => Self::Transferring { bytes, total },
            Ra2bPhase::Complete {
                path,
                bytes,
                hash_hex,
                local_relay_id,
                remote_relay_id,
                duration_ms,
            } => Self::Complete {
                path,
                bytes,
                hash_hex,
                local_relay_id,
                remote_relay_id,
                duration_ms,
            },
            Ra2bPhase::Failed { message, category } => {
                if category == "identity" {
                    Self::Rejected { message, category }
                } else {
                    Self::Failed { message, category }
                }
            }
            Ra2bPhase::Cancelled => Self::Cancelled,
        }
    }
}

/// Returns this process's in-memory development RelayId. Not a stored favorite.
#[frb(sync)]
pub fn ra2b_local_identity() -> anyhow::Result<RsRa2bLocalIdentity> {
    Ok(RsRa2bLocalIdentity {
        relay_id: process_relay_id()?,
    })
}

/// Parses a development invite. Fail-closed; never panics on bad input.
#[frb(sync)]
pub fn ra2b_parse_invite(invite: String) -> anyhow::Result<RsRa2bParsedInvite> {
    if let Ok(address) = RelayAddressV1::decode(&invite) {
        return Ok(RsRa2bParsedInvite {
            version: address.version,
            host_relay_id: address.claimed_relay_id,
            routing_available: true,
            capability: None,
        });
    }
    let parsed = parse_invite(&invite)?;
    Ok(RsRa2bParsedInvite {
        version: parsed.version,
        host_relay_id: parsed.host_relay_id,
        routing_available: true,
        capability: parsed.capability,
    })
}

#[frb(sync)]
pub fn ra2b_session_is_active() -> bool {
    session_is_active()
        || harness_session()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_some()
}

/// Cancels the single active host or join session, if any.
#[frb(sync)]
pub fn ra2b_cancel_session() {
    cancel_active_session();
    let session = harness_session()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take();
    if let Some(session) = session {
        anywhere_runtime().cancel(AnywhereSessionId::from_u64(session));
    }
}

/// Adds one real file to the RA4B sender batch without copying it into Dart.
/// Android passes a SAF descriptor; desktop passes a regular path. Call
/// [ra4_clear] before beginning a new batch.
#[frb(sync)]
pub fn ra4_set_sender(
    path: Option<String>,
    file_descriptor: Option<i32>,
    name: String,
    size: u64,
    file_type: String,
    sha256: Option<String>,
) -> anyhow::Result<()> {
    if path.is_none() && file_descriptor.is_none() {
        anyhow::bail!("RA4A sender needs a path or file descriptor");
    }
    #[cfg(not(target_os = "android"))]
    if file_descriptor.is_some() {
        anyhow::bail!("file descriptors are only supported on Android");
    }
    let file = Ra4RuntimeFile {
        path,
        file_descriptor,
        name,
        size,
        file_type,
        sha256,
    };
    let mut config = ra4_config()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    match config.as_mut() {
        Some(Ra4RuntimeConfig::Sender { files }) => files.push(file),
        None => *config = Some(Ra4RuntimeConfig::Sender { files: vec![file] }),
    }
    Ok(())
}

#[frb(sync)]
pub fn ra4_clear() {
    *ra4_config()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
}

/// Answers one specific pending inbound batch.
///
/// The decision is routed to `(session, transfer_id)` in the production
/// runtime, so it can never answer a different request.
#[frb(sync)]
pub fn ra4_respond(
    transfer_id: String,
    accept: bool,
    targets_json: Option<String>,
) -> anyhow::Result<()> {
    let session = harness_session()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .ok_or_else(|| anyhow::anyhow!("no Anywhere session is running"))?;
    let transfer_id: u64 = transfer_id
        .parse()
        .context("parse pending transfer identifier")?;
    super::relay_anywhere::relay_anywhere_respond(session, transfer_id, accept, targets_json)
}

/// Starts the harness host. RA4 file transfer runs on the production
/// orchestration; only the legacy proof mode still uses the harness session.
pub async fn ra2b_start_host(
    path_preference: RsRa2bPathPreference,
    wrong_identity: bool,
    ra4_file_transfer: bool,
    event_sink: StreamSink<RsRa2bEvent>,
) -> anyhow::Result<()> {
    let guard = ActiveSessionGuard::acquire()?;
    let expected = if wrong_identity {
        Some(fresh_unrelated_relay_id()?)
    } else {
        None
    };
    if ra4_file_transfer {
        let runtime = anywhere_runtime().clone();
        let (session, cancel) = runtime.open_session();
        set_harness_session(Some(session.as_u64()));
        let sink = production_sink(event_sink.clone());
        let result = anywhere_receive(
            runtime.clone(),
            session,
            cancel,
            AnywhereReceiveRequest {
                identity: AnywhereIdentity::from_shared(process_identity())?,
                preference: path_preference.into(),
                alias: "Relay Anywhere".to_owned(),
                expected_remote_relay_id: expected,
            },
            sink,
        )
        .await;
        return finish_production(&runtime, session, guard, &event_sink, result.map(|_| ()));
    }
    let peer = Ra2bPeerMaterial::from_arc(process_identity(), expected)?;
    run_legacy_proof(
        Ra2bRole::Responder,
        peer,
        path_preference.into(),
        guard,
        event_sink,
    )
    .await
}

/// Joins a host. RA4 file transfer sends through the production orchestration.
pub async fn ra2b_run_join(
    invite: String,
    path_preference: RsRa2bPathPreference,
    wrong_identity: bool,
    ra4_file_transfer: bool,
    event_sink: StreamSink<RsRa2bEvent>,
) -> anyhow::Result<()> {
    let guard = ActiveSessionGuard::acquire()?;
    let config = ra4_config()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take();
    if ra4_file_transfer {
        let Some(Ra4RuntimeConfig::Sender { files }) = config else {
            anyhow::bail!("RA4 file-transfer mode requires a configured sender batch");
        };
        let mut remote = production_address(&invite)?;
        if wrong_identity {
            remote.claimed_relay_id = fresh_unrelated_relay_id()?;
        }
        let batch = AnywhereBatch {
            files: files
                .into_iter()
                .map(production_file)
                .collect::<anyhow::Result<Vec<_>>>()?,
        };
        let runtime = anywhere_runtime().clone();
        let (session, cancel) = runtime.open_session();
        set_harness_session(Some(session.as_u64()));
        let sink = production_sink(event_sink.clone());
        let result = anywhere_send(
            session,
            cancel,
            AnywhereSendRequest {
                identity: AnywhereIdentity::from_shared(process_identity())?,
                remote,
                preference: path_preference.into(),
                alias: "Relay Anywhere".to_owned(),
                batch,
            },
            sink,
        )
        .await;
        return finish_production(&runtime, session, guard, &event_sink, result.map(|_| ()));
    }
    anyhow::ensure!(
        config.is_none(),
        "RA4 sender configuration requires file-transfer mode"
    );
    let parsed = parse_invite(&invite)?;
    let expected = if wrong_identity {
        fresh_unrelated_relay_id()?
    } else {
        parsed.host_relay_id.clone()
    };
    let peer = Ra2bPeerMaterial::from_arc(process_identity(), Some(expected))?;
    run_legacy_proof(
        Ra2bRole::Initiator {
            remote_endpoint: parsed.endpoint,
        },
        peer,
        path_preference.into(),
        guard,
        event_sink,
    )
    .await
}

/// Accepts a production Relay address, or an older RA2B invite, as routing.
fn production_address(raw: &str) -> anyhow::Result<RelayAddressV1> {
    if let Ok(address) = RelayAddressV1::decode(raw) {
        return Ok(address);
    }
    let legacy = parse_invite(raw)?;
    RelayAddressV1::new(legacy.host_relay_id, legacy.endpoint)
}

fn production_file(file: Ra4RuntimeFile) -> anyhow::Result<AnywhereFileSpec> {
    let source = if let Some(path) = file.path {
        AnywhereFileSource::Path(PathBuf::from(path))
    } else {
        #[cfg(target_os = "android")]
        {
            AnywhereFileSource::FileDescriptor(
                file.file_descriptor
                    .ok_or_else(|| anyhow::anyhow!("Anywhere file needs a path or descriptor"))?,
            )
        }
        #[cfg(not(target_os = "android"))]
        {
            anyhow::bail!("file descriptors are only supported on Android")
        }
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

fn production_sink(event_sink: StreamSink<RsRa2bEvent>) -> localsend::anywhere::AnywhereEventSink {
    Arc::new(move |event: AnywhereEvent| {
        if let Some(mapped) = map_anywhere_event(event) {
            let _ = event_sink.add(mapped);
        }
    })
}

fn finish_production(
    runtime: &Arc<localsend::anywhere::AnywhereRuntime>,
    session: AnywhereSessionId,
    guard: ActiveSessionGuard,
    event_sink: &StreamSink<RsRa2bEvent>,
    result: Result<(), AnywhereError>,
) -> anyhow::Result<()> {
    runtime.close_session(session);
    set_harness_session(None);
    drop(guard);
    if let Err(error) = result {
        let _ = event_sink.add(map_anywhere_failure(&error));
    }
    Ok(())
}

async fn run_legacy_proof(
    role: Ra2bRole,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    guard: ActiveSessionGuard,
    event_sink: StreamSink<RsRa2bEvent>,
) -> anyhow::Result<()> {
    let callback: Arc<dyn Fn(Ra2bPhase) + Send + Sync> = Arc::new(move |phase: Ra2bPhase| {
        let _ = event_sink.add(phase.into());
    });
    let result = run_proof(role, peer, path_preference, guard.cancellation(), callback).await;
    drop(guard);
    match result {
        Ok(_) => Ok(()),
        Err(error) => {
            if format!("{error:#}").contains("cancelled") {
                Ok(())
            } else {
                Err(error)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_identity_is_valid_relay_id() {
        let identity = ra2b_local_identity().unwrap();
        assert_eq!(identity.relay_id.len(), 64);
        relay_anywhere_ra2b::validate_relay_id(&identity.relay_id).unwrap();
    }
}
