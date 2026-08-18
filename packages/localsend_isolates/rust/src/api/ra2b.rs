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
use relay_anywhere_ra2b::{
    ActiveSessionGuard, Ra2bPathPreference, Ra2bPeerMaterial, Ra2bPhase, Ra2bRole, Ra4BatchSpec,
    Ra4Decision, Ra4FileSource, Ra4FileSpec, cancel_active_session, fresh_unrelated_relay_id,
    parse_invite, process_identity, process_relay_id, run_proof, run_ra4_batch_sender,
    run_ra4_receiver, session_is_active,
};

enum Ra4RuntimeConfig {
    Sender { files: Vec<Ra4RuntimeFile> },
}

/// Chooses the post-authentication application protocol before either side
/// reads from the authenticated stream. RA4 uses ordinary HTTP/1.1; the
/// legacy proof framing is retained only when explicitly requested.
enum Ra2bApplicationMode {
    LegacyProof,
    Ra4HttpReceiver,
    Ra4HttpSender,
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

fn ra4_decision_sender() -> &'static Mutex<Option<tokio::sync::mpsc::Sender<Ra4Decision>>> {
    static SENDER: OnceLock<Mutex<Option<tokio::sync::mpsc::Sender<Ra4Decision>>>> =
        OnceLock::new();
    SENDER.get_or_init(|| Mutex::new(None))
}

#[derive(Clone, Debug)]
pub enum RsRa2bPathPreference {
    Auto,
    ForceRelay,
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
}

/// Cancels the single active host or join session, if any.
#[frb(sync)]
pub fn ra2b_cancel_session() {
    cancel_active_session();
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
    *ra4_decision_sender()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
}

/// Answers the session-scoped incoming batch prompt.
#[frb(sync)]
pub fn ra4_respond(accept: bool, targets_json: Option<String>) -> anyhow::Result<()> {
    let sender = ra4_decision_sender()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
        .ok_or_else(|| anyhow::anyhow!("no RA4B transfer is awaiting approval"))?;
    let targets = match targets_json {
        Some(json) if accept => serde_json::from_str(&json).context("parse RA4B save targets")?,
        _ => Default::default(),
    };
    sender
        .try_send(Ra4Decision { accept, targets })
        .map_err(|_| anyhow::anyhow!("RA4B approval prompt is no longer active"))
}

/// Starts the in-process RA2B host (responder). Emits invite + progress events.
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
    let peer = Ra2bPeerMaterial::from_arc(process_identity(), expected)?;
    let application_mode = if ra4_file_transfer {
        Ra2bApplicationMode::Ra4HttpReceiver
    } else {
        Ra2bApplicationMode::LegacyProof
    };
    let decision_rx = if ra4_file_transfer {
        let (sender, receiver) = tokio::sync::mpsc::channel(1);
        *ra4_decision_sender()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(sender);
        Some(receiver)
    } else {
        None
    };
    run_session(
        Ra2bRole::Responder,
        peer,
        path_preference.into(),
        guard,
        event_sink,
        application_mode,
        None,
        decision_rx,
    )
    .await
}

/// Join using a development invite. `wrong_identity` mutates expected host RelayId.
pub async fn ra2b_run_join(
    invite: String,
    path_preference: RsRa2bPathPreference,
    wrong_identity: bool,
    ra4_file_transfer: bool,
    event_sink: StreamSink<RsRa2bEvent>,
) -> anyhow::Result<()> {
    let guard = ActiveSessionGuard::acquire()?;
    let parsed = parse_invite(&invite)?;
    let expected = if wrong_identity {
        fresh_unrelated_relay_id()?
    } else {
        parsed.host_relay_id.clone()
    };
    let peer = Ra2bPeerMaterial::from_arc(process_identity(), Some(expected))?;
    let config = ra4_config()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .take();
    let application_mode = if ra4_file_transfer {
        anyhow::ensure!(
            matches!(&config, Some(Ra4RuntimeConfig::Sender { .. })),
            "RA4 file-transfer mode requires a configured sender batch"
        );
        Ra2bApplicationMode::Ra4HttpSender
    } else {
        anyhow::ensure!(
            config.is_none(),
            "RA4 sender configuration requires file-transfer mode"
        );
        Ra2bApplicationMode::LegacyProof
    };
    run_session(
        Ra2bRole::Initiator {
            remote_endpoint: parsed.endpoint,
        },
        peer,
        path_preference.into(),
        guard,
        event_sink,
        application_mode,
        config,
        None,
    )
    .await
}

async fn run_session(
    role: Ra2bRole,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    guard: ActiveSessionGuard,
    event_sink: StreamSink<RsRa2bEvent>,
    application_mode: Ra2bApplicationMode,
    config: Option<Ra4RuntimeConfig>,
    mut decision_rx: Option<tokio::sync::mpsc::Receiver<Ra4Decision>>,
) -> anyhow::Result<()> {
    let callback: Arc<dyn Fn(Ra2bPhase) + Send + Sync> = Arc::new(move |phase: Ra2bPhase| {
        let _ = event_sink.add(phase.into());
    });
    let result = match (application_mode, config, role) {
        (
            Ra2bApplicationMode::Ra4HttpSender,
            Some(Ra4RuntimeConfig::Sender { files }),
            Ra2bRole::Initiator { remote_endpoint },
        ) => {
            let specs = files
                .into_iter()
                .map(|file| {
                    let source = if let Some(path) = file.path {
                        Ra4FileSource::Path(PathBuf::from(path))
                    } else {
                        #[cfg(target_os = "android")]
                        {
                            Ra4FileSource::FileDescriptor(
                                file.file_descriptor.expect("validated descriptor"),
                            )
                        }
                        #[cfg(not(target_os = "android"))]
                        {
                            unreachable!("non-Android descriptor rejected above")
                        }
                    };
                    Ra4FileSpec {
                        id: uuid::Uuid::new_v4().to_string(),
                        name: file.name,
                        size: file.size,
                        file_type: file.file_type,
                        sha256: file.sha256,
                        source,
                    }
                })
                .collect();
            run_ra4_batch_sender(
                remote_endpoint,
                peer,
                path_preference,
                guard.cancellation(),
                &callback,
                Ra4BatchSpec { files: specs },
            )
            .await
        }
        (Ra2bApplicationMode::Ra4HttpReceiver, None, Ra2bRole::Responder) => {
            let mut decision_rx = decision_rx
                .take()
                .ok_or_else(|| anyhow::anyhow!("RA4A receiver approval channel is unavailable"))?;
            run_ra4_receiver(
                peer,
                path_preference,
                guard.cancellation(),
                &callback,
                &mut decision_rx,
            )
            .await
        }
        (Ra2bApplicationMode::LegacyProof, None, role) => {
            run_proof(role, peer, path_preference, guard.cancellation(), callback).await
        }
        _ => anyhow::bail!("RA2B application mode/configuration role mismatch"),
    };
    *ra4_decision_sender()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
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
