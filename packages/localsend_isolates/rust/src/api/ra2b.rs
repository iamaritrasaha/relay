//! Development-only Flutter API for the RA2B dual-app harness.
//!
//! Flutter never receives private identity keys, TLS private keys, or proof
//! signature bytes. The invite string is a test addressing package, not
//! production trust architecture.

use std::sync::Arc;

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use relay_anywhere_ra2b::{
    ActiveSessionGuard, Ra2bPathPreference, Ra2bPeerMaterial, Ra2bPhase, Ra2bRole,
    cancel_active_session, fresh_unrelated_relay_id, parse_invite, process_identity,
    process_relay_id, run_proof, session_is_active,
};

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

/// Starts the in-process RA2B host (responder). Emits invite + progress events.
pub async fn ra2b_start_host(
    path_preference: RsRa2bPathPreference,
    wrong_identity: bool,
    event_sink: StreamSink<RsRa2bEvent>,
) -> anyhow::Result<()> {
    let guard = ActiveSessionGuard::acquire()?;
    let expected = if wrong_identity {
        Some(fresh_unrelated_relay_id()?)
    } else {
        None
    };
    let peer = Ra2bPeerMaterial::from_arc(process_identity(), expected)?;
    run_session(
        Ra2bRole::Responder,
        peer,
        path_preference.into(),
        guard,
        event_sink,
    )
    .await
}

/// Join using a development invite. `wrong_identity` mutates expected host RelayId.
pub async fn ra2b_run_join(
    invite: String,
    path_preference: RsRa2bPathPreference,
    wrong_identity: bool,
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
    run_session(
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

async fn run_session(
    role: Ra2bRole,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    guard: ActiveSessionGuard,
    event_sink: StreamSink<RsRa2bEvent>,
) -> anyhow::Result<()> {
    let result = run_proof(
        role,
        peer,
        path_preference,
        guard.cancellation(),
        Arc::new(move |phase| {
            let _ = event_sink.add(phase.into());
        }),
    )
    .await;
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
