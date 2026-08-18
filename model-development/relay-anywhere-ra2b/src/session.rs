use std::{
    io::ErrorKind,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use anyhow::{Context as _, Result, bail, ensure};
use iroh::{
    EndpointAddr, RelayMode,
    endpoint::{Connection, Endpoint, presets},
};
use localsend::{anywhere_dev::inner_tls::InnerTlsPeer, crypto::relay_identity::RelayIdentity};
use rand::RngCore;
use sha2::{Digest, Sha256};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    sync::Notify,
    time::{sleep, timeout},
};

use crate::{
    invite::Ra2bInviteV1,
    iroh_stream::{
        IrohBiStream, client_peer_certificate_fingerprint, server_peer_certificate_fingerprint,
    },
    relay_auth::{IDENTITY_REJECTED, RelayAuthPeer, authenticate_client, authenticate_server},
};

pub const ALPN: &[u8] = b"relay-anywhere-ra2b/1";
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
    pub relay_id: String,
    pub tls: InnerTlsPeer,
    pub auth: RelayAuthPeer,
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
        let auth = RelayAuthPeer::from_arc(identity, tls.cert_fingerprint)?;
        Ok(Self {
            relay_id: auth.relay_id.clone(),
            tls,
            auth,
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
    endpoint: Endpoint,
    peer: Ra2bPeerMaterial,
    path_preference: Ra2bPathPreference,
    cancellation: &Ra2bCancellation,
    on_status: &Ra2bStatusCallback,
) -> Result<Ra2bProofResult> {
    let incoming = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out waiting for Iroh connection"),
        incoming = endpoint.accept() => incoming.context("accept Iroh connection")?,
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

    let path = selected_path(&connection, path_preference).await?;
    diag(format!("PATH={}", path.as_str().to_ascii_lowercase()));
    let (send, recv) = connection
        .accept_bi()
        .await
        .context("accept Iroh bidirectional stream")?;
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
    let remote_relay_id = authenticate_server(
        &mut tls,
        &peer.auth,
        peer.expected_remote_relay_id.as_deref(),
        observed_client_cert,
    )
    .await
    .context("mutual Relay authentication on responder")?;
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
        path,
        bytes,
        hash_hex: hex::encode(hash),
        local_relay_id: peer.relay_id,
        remote_relay_id,
        duration_ms: 0,
    })
}

async fn run_initiator(
    endpoint: Endpoint,
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
    let connection = tokio::select! {
        _ = cancellation.cancelled() => bail!("cancelled"),
        _ = sleep(SESSION_TIMEOUT) => bail!("timed out connecting to remote Iroh endpoint"),
        connection = endpoint.connect(remote_endpoint, ALPN) => {
            connection.context("connect Iroh endpoint")?
        }
    };
    diag(format!(
        "IROH_CONNECT local={}",
        relay_id_prefix(&peer.relay_id)
    ));
    on_status(Ra2bPhase::IrohConnected);

    let path = selected_path(&connection, path_preference).await?;
    diag(format!("PATH={}", path.as_str().to_ascii_lowercase()));
    let (send, recv) = connection
        .open_bi()
        .await
        .context("open Iroh bidirectional stream")?;
    let server_name = rustls::pki_types::ServerName::try_from("localhost")
        .context("parse inner TLS server name")?;
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
    let remote_relay_id =
        authenticate_client(&mut tls, &peer.auth, &expected, observed_server_cert)
            .await
            .context("mutual Relay authentication on initiator")?;
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
        path,
        bytes,
        hash_hex: hex::encode(hash),
        local_relay_id: peer.relay_id,
        remote_relay_id,
        duration_ms: 0,
    })
}

async fn build_endpoint(
    path_preference: Ra2bPathPreference,
) -> Result<(Endpoint, Option<Box<dyn std::any::Any + Send>>)> {
    match path_preference {
        Ra2bPathPreference::Auto => {
            let endpoint = Endpoint::builder(presets::N0)
                .relay_mode(RelayMode::Default)
                .alpns(vec![ALPN.to_vec()])
                .bind()
                .await?;
            Ok((endpoint, None))
        }
        Ra2bPathPreference::ForceRelay => {
            #[cfg(feature = "linux-harness")]
            {
                let (relay_map, _relay_url, relay_guard) = iroh::test_utils::run_relay_server()
                    .await
                    .context("start stock self-hosted iroh-relay for forced relay proof")?;
                let endpoint = Endpoint::builder(presets::N0)
                    .relay_mode(RelayMode::Custom(relay_map))
                    .ca_tls_config(iroh::tls::CaTlsConfig::insecure_skip_verify())
                    .clear_ip_transports()
                    .alpns(vec![ALPN.to_vec()])
                    .bind()
                    .await?;
                Ok((endpoint, Some(Box::new(relay_guard))))
            }
            #[cfg(not(feature = "linux-harness"))]
            {
                let endpoint = Endpoint::builder(presets::N0)
                    .relay_mode(RelayMode::Default)
                    .clear_ip_transports()
                    .alpns(vec![ALPN.to_vec()])
                    .bind()
                    .await?;
                Ok((endpoint, None))
            }
        }
        Ra2bPathPreference::ForceDirect => {
            let endpoint = Endpoint::builder(presets::Minimal)
                .relay_mode(RelayMode::Disabled)
                .alpns(vec![ALPN.to_vec()])
                .bind()
                .await?;
            Ok((endpoint, None))
        }
    }
}

async fn selected_path(
    connection: &Connection,
    preference: Ra2bPathPreference,
) -> Result<Ra2bPathClass> {
    let expected = match preference {
        Ra2bPathPreference::ForceDirect => Ra2bPathClass::Direct,
        Ra2bPathPreference::ForceRelay => Ra2bPathClass::Relay,
        Ra2bPathPreference::Auto => {
            return timeout(Duration::from_secs(30), async {
                loop {
                    if let Some(path) = connection
                        .paths()
                        .iter()
                        .find(|candidate| candidate.is_selected())
                    {
                        return Ok(if path.is_relay() {
                            Ra2bPathClass::Relay
                        } else if path.is_ip() {
                            Ra2bPathClass::Direct
                        } else {
                            bail!("selected Iroh path was neither IP nor relay");
                        });
                    }
                    sleep(Duration::from_millis(25)).await;
                }
            })
            .await
            .context("Iroh did not report a selected path")?;
        }
    };

    timeout(Duration::from_secs(30), async {
        loop {
            if let Some(path) = connection
                .paths()
                .iter()
                .find(|candidate| candidate.is_selected())
            {
                let actual = if path.is_relay() {
                    Ra2bPathClass::Relay
                } else if path.is_ip() {
                    Ra2bPathClass::Direct
                } else {
                    bail!("selected Iroh path was neither IP nor relay");
                };
                ensure!(
                    actual == expected,
                    "selected {} path, expected {}",
                    actual.as_str(),
                    expected.as_str()
                );
                return Ok(actual);
            }
            sleep(Duration::from_millis(25)).await;
        }
    })
    .await
    .context("Iroh did not report the expected selected path")?
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
}
