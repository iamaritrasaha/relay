use std::{net::Ipv4Addr, time::Duration};

#[cfg(test)]
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, anyhow, bail, ensure};
use iroh::{
    Endpoint, RelayMode,
    endpoint::{Connection, presets},
    tls::CaTlsConfig,
};
use rand::RngCore;
use sha2::{Digest, Sha256};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    task::JoinHandle,
    time::{Instant, sleep, timeout},
};

use crate::{
    inner_tls::{
        InnerTlsPeer, IrohBiStream, authenticate_client, authenticate_server,
        client_peer_certificate_fingerprint, server_peer_certificate_fingerprint,
    },
    rendezvous::TemporaryRendezvous,
};

const ALPN: &[u8] = b"relay-anywhere-ra2a/1";
const ONE_MIB: usize = 1024 * 1024;
const CHUNK_SIZE: usize = 16 * 1024;
const BACKPRESSURE_BYTES: usize = 16 * 1024 * 1024;
const MAX_DECLARED_PAYLOAD: usize = BACKPRESSURE_BYTES;
const SESSION_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PathClass {
    Direct,
    Relay,
}

impl std::fmt::Display for PathClass {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Direct => f.write_str("direct"),
            Self::Relay => f.write_str("relay"),
        }
    }
}

#[derive(Debug)]
pub struct TransferReport {
    pub path: PathClass,
    pub bytes: usize,
    pub hash: [u8; 32],
    pub duration: Duration,
    pub max_application_buffer: usize,
    pub max_write_wait: Duration,
}

#[derive(Debug)]
pub struct ProofReport {
    pub direct: TransferReport,
    pub relay: TransferReport,
    pub cancelled_after: usize,
    pub backpressure: TransferReport,
}

impl ProofReport {
    pub fn print(&self) {
        println!(
            "DIRECT PASS path={} bytes={} hash={}",
            self.direct.path,
            self.direct.bytes,
            hex::encode(self.direct.hash)
        );
        println!(
            "RELAY PASS path={} bytes={} hash={}",
            self.relay.path,
            self.relay.bytes,
            hex::encode(self.relay.hash)
        );
        println!("RENDEZVOUS SUBSTITUTION REJECTED");
        println!("UNEXPECTED CLIENT REJECTED");
        println!("PROOF REPLAY REJECTED (focused test-only coverage)");
        println!("PAYLOAD-BEFORE-AUTH REJECTED (focused test-only coverage)");
        println!("RECONNECT FRESH AUTH PASS");
        println!("CANCELLATION PASS cancelled_after={}", self.cancelled_after);
        println!(
            "BACKPRESSURE PASS bytes={} app_buffer={} max_write_wait_ms={}",
            self.backpressure.bytes,
            self.backpressure.max_application_buffer,
            self.backpressure.max_write_wait.as_millis()
        );
        println!(
            "RELAY TLS CAVEAT: forced-relay validates Relay end-to-end identity/content security over an untrusted relay path; it does not validate deployment-time relay server certificate verification."
        );
    }
}

#[derive(Clone)]
struct World {
    a: InnerTlsPeer,
    b: InnerTlsPeer,
    c: InnerTlsPeer,
}

impl World {
    fn new() -> Result<Self> {
        Ok(Self {
            a: InnerTlsPeer::new("ra2a-a.invalid")?,
            b: InnerTlsPeer::new("ra2a-b.invalid")?,
            c: InnerTlsPeer::new("ra2a-c.invalid")?,
        })
    }
}

#[derive(Clone, Copy)]
enum SessionKind {
    Integrity {
        bytes: usize,
        slow_reader: bool,
    },
    Cancel,
    #[cfg(test)]
    Stall,
}

struct SessionOutcome {
    client: Result<TransferReport>,
    server: Result<usize>,
    claimed_replay_rejected: bool,
    entry_present_before_cleanup: bool,
    cleanup_deleted: bool,
    entries_after_cleanup: usize,
    server_task_joined: bool,
}

impl SessionOutcome {
    fn assert_cleanup(&self) -> Result<()> {
        ensure!(
            self.claimed_replay_rejected,
            "claimed rendezvous capability was replayable"
        );
        ensure!(
            self.entry_present_before_cleanup,
            "rendezvous entry was not retained for lifecycle cleanup"
        );
        ensure!(
            self.cleanup_deleted,
            "rendezvous entry cleanup did not delete the claimed entry"
        );
        ensure!(
            self.entries_after_cleanup == 0,
            "rendezvous entry survived cleanup"
        );
        ensure!(
            self.server_task_joined,
            "server proof task was not joined deterministically"
        );
        Ok(())
    }
}

pub async fn run_manual_proof() -> Result<ProofReport> {
    let world = World::new()?;
    let direct = run_authenticated_transfer(&world, PathClass::Direct, ONE_MIB, false).await?;
    let relay = run_authenticated_transfer(&world, PathClass::Relay, ONE_MIB, false).await?;
    run_rendezvous_substitution(&world).await?;
    run_unexpected_client(&world).await?;
    run_reconnect(&world).await?;
    let cancelled_after = run_cancellation(&world).await?;
    let backpressure =
        run_authenticated_transfer(&world, PathClass::Direct, BACKPRESSURE_BYTES, true).await?;
    ensure!(
        backpressure.max_write_wait >= Duration::from_millis(1),
        "slow-reader proof did not observe QUIC flow-control pressure"
    );
    Ok(ProofReport {
        direct,
        relay,
        cancelled_after,
        backpressure,
    })
}

async fn run_authenticated_transfer(
    world: &World,
    path: PathClass,
    bytes: usize,
    slow_reader: bool,
) -> Result<TransferReport> {
    let outcome = run_session(
        path,
        world.a.clone(),
        world.b.clone(),
        world.b.relay.relay_id.clone(),
        world.a.relay.relay_id.clone(),
        SessionKind::Integrity { bytes, slow_reader },
        SESSION_TIMEOUT,
    )
    .await?;
    outcome.assert_cleanup()?;
    let received = outcome.server.context("receiver failed")?;
    ensure!(received == bytes, "receiver byte count mismatch");
    outcome.client
}

async fn run_rendezvous_substitution(world: &World) -> Result<()> {
    // A expects B's RelayId, but the one-time rendezvous capability yields real endpoint C.
    let outcome = run_session(
        PathClass::Direct,
        world.a.clone(),
        world.c.clone(),
        world.b.relay.relay_id.clone(),
        world.a.relay.relay_id.clone(),
        SessionKind::Integrity {
            bytes: ONE_MIB,
            slow_reader: false,
        },
        SESSION_TIMEOUT,
    )
    .await?;
    outcome.assert_cleanup()?;
    ensure!(
        outcome.client.is_err(),
        "rendezvous substitution unexpectedly authenticated C as B"
    );
    ensure!(
        outcome.server.is_err(),
        "substituted endpoint accepted application payload"
    );
    Ok(())
}

async fn run_unexpected_client(world: &World) -> Result<()> {
    // C reaches B with valid QUIC, TLS, and a valid C client proof; B expects A.
    let outcome = run_session(
        PathClass::Direct,
        world.c.clone(),
        world.b.clone(),
        world.b.relay.relay_id.clone(),
        world.a.relay.relay_id.clone(),
        SessionKind::Integrity {
            bytes: ONE_MIB,
            slow_reader: false,
        },
        SESSION_TIMEOUT,
    )
    .await?;
    outcome.assert_cleanup()?;
    ensure!(
        outcome.client.is_err(),
        "unexpected client was accepted by responder"
    );
    ensure!(
        outcome.server.is_err(),
        "responder accepted C before client RelayId validation"
    );
    Ok(())
}

async fn run_reconnect(world: &World) -> Result<()> {
    let (client_endpoint, server_endpoint, relay_guard) = make_endpoints(PathClass::Direct).await?;
    authenticate_new_connection(
        &client_endpoint,
        &server_endpoint,
        world.a.clone(),
        world.b.clone(),
    )
    .await?;
    authenticate_new_connection(
        &client_endpoint,
        &server_endpoint,
        world.a.clone(),
        world.b.clone(),
    )
    .await?;
    client_endpoint.close().await;
    server_endpoint.close().await;
    drop(relay_guard);
    Ok(())
}

async fn run_cancellation(world: &World) -> Result<usize> {
    let outcome = run_session(
        PathClass::Direct,
        world.a.clone(),
        world.b.clone(),
        world.b.relay.relay_id.clone(),
        world.a.relay.relay_id.clone(),
        SessionKind::Cancel,
        SESSION_TIMEOUT,
    )
    .await?;
    outcome.assert_cleanup()?;
    ensure!(outcome.client.is_err(), "cancelled sender returned success");
    ensure!(
        outcome.server.is_err(),
        "cancelled receiver returned success"
    );
    Ok(256 * 1024)
}

async fn run_session(
    path: PathClass,
    client_peer: InnerTlsPeer,
    server_peer: InnerTlsPeer,
    expected_server_relay_id: String,
    expected_client_relay_id: String,
    kind: SessionKind,
    session_timeout: Duration,
) -> Result<SessionOutcome> {
    run_session_inner(
        path,
        client_peer,
        server_peer,
        expected_server_relay_id,
        expected_client_relay_id,
        kind,
        session_timeout,
        #[cfg(test)]
        None,
    )
    .await
}

#[allow(clippy::too_many_arguments)] // The test-only proof behavior is intentionally an explicit extra input.
async fn run_session_inner(
    path: PathClass,
    client_peer: InnerTlsPeer,
    server_peer: InnerTlsPeer,
    expected_server_relay_id: String,
    expected_client_relay_id: String,
    kind: SessionKind,
    session_timeout: Duration,
    #[cfg(test)] test_proof_behavior: Option<crate::inner_tls::TestServerProofBehavior>,
) -> Result<SessionOutcome> {
    let rendezvous = TemporaryRendezvous::default();
    let (client_endpoint, server_endpoint, relay_guard) = make_endpoints(path).await?;
    let capability = rendezvous
        .publish(server_endpoint.addr(), Duration::from_secs(20))
        .await;
    let discovered = rendezvous
        .claim(&capability)
        .await
        .context("temporary rendezvous lookup failed")?;
    let claimed_replay_rejected = rendezvous.claim(&capability).await.is_none();
    let entry_present_before_cleanup = rendezvous.len().await == 1;

    let server_endpoint_task = server_endpoint.clone();
    let server_task: JoinHandle<Result<usize>> = tokio::spawn(async move {
        let incoming = server_endpoint_task
            .accept()
            .await
            .context("accept Iroh connection")?;
        let connection = incoming.await.context("complete Iroh server handshake")?;
        ensure_selected_path(&connection, path).await?;
        let (send, recv) = connection
            .accept_bi()
            .await
            .context("accept Iroh bidirectional stream")?;
        let mut tls = server_peer.accept(IrohBiStream::new(send, recv)).await?;
        let observed_client_cert = server_peer_certificate_fingerprint(&tls)?;
        #[cfg(test)]
        if let Some(behavior) = test_proof_behavior {
            crate::inner_tls::authenticate_server_for_test(
                &mut tls,
                &server_peer.relay,
                &expected_client_relay_id,
                observed_client_cert,
                behavior,
            )
            .await?;
        } else {
            authenticate_server(
                &mut tls,
                &server_peer.relay,
                &expected_client_relay_id,
                observed_client_cert,
            )
            .await?;
        }
        #[cfg(not(test))]
        authenticate_server(
            &mut tls,
            &server_peer.relay,
            &expected_client_relay_id,
            observed_client_cert,
        )
        .await?;
        receive_payload(&mut tls, kind).await
    });

    let client_future = async {
        let connection = client_endpoint
            .connect(discovered, ALPN)
            .await
            .context("connect Iroh endpoint")?;
        let selected = ensure_selected_path(&connection, path).await?;
        let (send, recv) = connection
            .open_bi()
            .await
            .context("open Iroh bidirectional stream")?;
        let result = async {
            let mut tls = client_peer.connect(IrohBiStream::new(send, recv)).await?;
            let observed_server_cert = client_peer_certificate_fingerprint(&tls)?;
            authenticate_client(
                &mut tls,
                &client_peer.relay,
                &expected_server_relay_id,
                observed_server_cert,
            )
            .await?;
            send_payload(&mut tls, kind, selected).await
        }
        .await;
        Ok::<_, anyhow::Error>((result, connection))
    };

    let (client, client_connection_guard, client_timed_out) =
        match timeout(session_timeout, client_future).await {
            Ok(Ok((result, connection))) => (result, Some(connection), false),
            Ok(Err(error)) => (Err(error), None, false),
            Err(_) => (Err(anyhow!("client proof session timed out")), None, true),
        };
    let mut server_task = server_task;
    let server = if client_timed_out {
        server_task.abort();
        match server_task.await {
            Ok(result) => result,
            Err(error) if error.is_cancelled() => {
                Err(anyhow!("server proof task aborted after client timeout"))
            }
            Err(error) => Err(anyhow!("server task join error after timeout: {error}")),
        }
    } else {
        match timeout(session_timeout, &mut server_task).await {
            Ok(Ok(result)) => result,
            Ok(Err(error)) => Err(anyhow!("server task panicked: {error}")),
            Err(_) => {
                server_task.abort();
                let _ = server_task.await;
                Err(anyhow!("server proof session timed out and was aborted"))
            }
        }
    };
    let cleanup_deleted = rendezvous.delete(&capability).await;
    let entries_after_cleanup = rendezvous.len().await;
    client_endpoint.close().await;
    server_endpoint.close().await;
    drop(client_connection_guard);
    drop(relay_guard);

    Ok(SessionOutcome {
        client,
        server,
        claimed_replay_rejected,
        entry_present_before_cleanup,
        cleanup_deleted,
        entries_after_cleanup,
        server_task_joined: true,
    })
}

async fn make_endpoints(
    path: PathClass,
) -> Result<(Endpoint, Endpoint, Option<iroh_relay::server::Server>)> {
    match path {
        PathClass::Direct => {
            let server = Endpoint::builder(presets::Minimal)
                .relay_mode(RelayMode::Disabled)
                .alpns(vec![ALPN.to_vec()])
                .bind_addr((Ipv4Addr::LOCALHOST, 0))?
                .bind()
                .await?;
            let client = Endpoint::builder(presets::Minimal)
                .relay_mode(RelayMode::Disabled)
                .alpns(vec![ALPN.to_vec()])
                .bind_addr((Ipv4Addr::LOCALHOST, 0))?
                .bind()
                .await?;
            Ok((client, server, None))
        }
        PathClass::Relay => {
            let (relay_map, _relay_url, relay_guard) =
                iroh::test_utils::run_relay_server()
                    .await
                    .context("start stock self-hosted iroh-relay")?;
            let server = Endpoint::builder(presets::Minimal)
                .relay_mode(RelayMode::Custom(relay_map.clone()))
                .ca_tls_config(CaTlsConfig::insecure_skip_verify())
                .clear_ip_transports()
                .alpns(vec![ALPN.to_vec()])
                .bind()
                .await?;
            let client = Endpoint::builder(presets::Minimal)
                .relay_mode(RelayMode::Custom(relay_map))
                .ca_tls_config(CaTlsConfig::insecure_skip_verify())
                .clear_ip_transports()
                .alpns(vec![ALPN.to_vec()])
                .bind()
                .await?;
            server.online().await;
            client.online().await;
            Ok((client, server, Some(relay_guard)))
        }
    }
}

async fn ensure_selected_path(connection: &Connection, expected: PathClass) -> Result<PathClass> {
    timeout(Duration::from_secs(10), async {
        loop {
            if let Some(path) = connection
                .paths()
                .iter()
                .find(|candidate| candidate.is_selected())
            {
                let actual = if path.is_relay() {
                    PathClass::Relay
                } else if path.is_ip() {
                    PathClass::Direct
                } else {
                    bail!("selected Iroh path was neither IP nor relay");
                };
                ensure!(
                    actual == expected,
                    "selected {actual} path, expected {expected}"
                );
                return Ok(actual);
            }
            sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .context("Iroh did not report a selected path")?
}

async fn send_payload(
    tls: &mut tokio_rustls::client::TlsStream<IrohBiStream>,
    kind: SessionKind,
    path: PathClass,
) -> Result<TransferReport> {
    let started = Instant::now();
    match kind {
        SessionKind::Integrity { bytes, .. } => {
            ensure!(
                bytes <= MAX_DECLARED_PAYLOAD,
                "proof payload exceeds conservative declared maximum"
            );
            tls.write_u8(1).await?;
            tls.write_u64(bytes as u64).await?;
            let mut hasher = Sha256::new();
            let mut sent = 0;
            let mut max_write_wait = Duration::ZERO;
            let mut chunk = vec![0_u8; CHUNK_SIZE];
            while sent < bytes {
                let size = CHUNK_SIZE.min(bytes - sent);
                rand::rng().fill_bytes(&mut chunk[..size]);
                hasher.update(&chunk[..size]);
                let before = Instant::now();
                tls.write_all(&chunk[..size]).await?;
                tls.flush().await?;
                max_write_wait = max_write_wait.max(before.elapsed());
                sent += size;
            }
            let sender_hash: [u8; 32] = hasher.finalize().into();
            let mut receiver_hash = [0_u8; 32];
            tls.read_exact(&mut receiver_hash)
                .await
                .context("read receiver SHA-256")?;
            ensure!(
                sender_hash == receiver_hash,
                "sender and receiver SHA-256 differ"
            );
            tls.write_u8(0xac).await?;
            tls.flush().await?;
            Ok(TransferReport {
                path,
                bytes: sent,
                hash: sender_hash,
                duration: started.elapsed(),
                max_application_buffer: chunk.len(),
                max_write_wait,
            })
        }
        SessionKind::Cancel => {
            tls.write_u8(2).await?;
            tls.write_u64((8 * 1024 * 1024) as u64).await?;
            let chunk = vec![0x6d; CHUNK_SIZE];
            for _ in 0..(256 * 1024 / CHUNK_SIZE) {
                tls.write_all(&chunk).await?;
            }
            tls.flush().await?;
            tls.get_mut().0.reset_send()?;
            bail!("sender cancelled after 262144 bytes")
        }
        #[cfg(test)]
        SessionKind::Stall => {
            tls.write_u8(3).await?;
            tls.flush().await?;
            let _ = tls.read_u8().await?;
            bail!("unexpected stalled proof response")
        }
    }
}

async fn receive_payload(
    tls: &mut tokio_rustls::server::TlsStream<IrohBiStream>,
    kind: SessionKind,
) -> Result<usize> {
    #[cfg(test)]
    if matches!(kind, SessionKind::Stall) {
        sleep(Duration::from_secs(5)).await;
        bail!("intentional proof stall")
    }
    let mode = tls
        .read_u8()
        .await
        .context("read transfer mode after authentication")?;
    let declared = tls
        .read_u64()
        .await
        .context("read bounded transfer length")? as usize;
    ensure!(
        declared <= MAX_DECLARED_PAYLOAD,
        "peer declared proof payload over conservative maximum"
    );
    let mut received = 0;
    let mut hasher = Sha256::new();
    let mut chunk = vec![0_u8; CHUNK_SIZE];
    while received < declared {
        let size = CHUNK_SIZE.min(declared - received);
        tls.read_exact(&mut chunk[..size])
            .await
            .context("read bounded proof payload")?;
        hasher.update(&chunk[..size]);
        received += size;
        if matches!(
            kind,
            SessionKind::Integrity {
                slow_reader: true,
                ..
            }
        ) {
            sleep(Duration::from_millis(2)).await;
        }
    }
    ensure!(
        mode == 1,
        "cancelled stream was incorrectly treated as complete"
    );
    let hash: [u8; 32] = hasher.finalize().into();
    tls.write_all(&hash).await?;
    tls.flush().await?;
    ensure!(
        tls.read_u8().await? == 0xac,
        "sender did not acknowledge receiver hash"
    );
    Ok(received)
}

async fn authenticate_new_connection(
    client_endpoint: &Endpoint,
    server_endpoint: &Endpoint,
    client_peer: InnerTlsPeer,
    server_peer: InnerTlsPeer,
) -> Result<()> {
    let server_endpoint_task = server_endpoint.clone();
    let expected_client = client_peer.relay.relay_id.clone();
    let server_peer_task = server_peer.clone();
    let server_task = tokio::spawn(async move {
        let incoming = server_endpoint_task
            .accept()
            .await
            .context("accept reconnect Iroh connection")?;
        let connection = incoming
            .await
            .context("complete reconnect Iroh handshake")?;
        let (send, recv) = connection
            .accept_bi()
            .await
            .context("accept reconnect stream")?;
        let mut tls = server_peer_task
            .accept(IrohBiStream::new(send, recv))
            .await?;
        let observed_client_cert = server_peer_certificate_fingerprint(&tls)?;
        authenticate_server(
            &mut tls,
            &server_peer_task.relay,
            &expected_client,
            observed_client_cert,
        )
        .await?;
        ensure!(
            tls.read_u8().await? == 0xad,
            "reconnect client did not acknowledge authentication"
        );
        Ok(())
    });
    let connection = client_endpoint
        .connect(server_endpoint.addr(), ALPN)
        .await?;
    let (send, recv) = connection.open_bi().await?;
    let mut tls = client_peer.connect(IrohBiStream::new(send, recv)).await?;
    let observed_server_cert = client_peer_certificate_fingerprint(&tls)?;
    authenticate_client(
        &mut tls,
        &client_peer.relay,
        &server_peer.relay.relay_id,
        observed_server_cert,
    )
    .await?;
    tls.write_u8(0xad).await?;
    tls.flush().await?;
    timeout(SESSION_TIMEOUT, server_task)
        .await
        .context("reconnect server task timed out")?
        .context("reconnect server task panicked")??;
    drop(connection);
    Ok(())
}

#[cfg(test)]
async fn raw_payload_before_auth_is_rejected(world: &World) -> Result<()> {
    let rendezvous = TemporaryRendezvous::default();
    let (client_endpoint, server_endpoint, relay_guard) = make_endpoints(PathClass::Direct).await?;
    let capability = rendezvous
        .publish(server_endpoint.addr(), Duration::from_secs(20))
        .await;
    let discovered = rendezvous
        .claim(&capability)
        .await
        .context("claim pre-auth rendezvous capability")?;
    assert!(rendezvous.claim(&capability).await.is_none());

    let server_peer = world.b.clone();
    let server_endpoint_task = server_endpoint.clone();
    let server_task = tokio::spawn(async move {
        let incoming = server_endpoint_task
            .accept()
            .await
            .context("accept raw pre-auth Iroh connection")?;
        let connection = incoming.await?;
        let (send, recv) = connection.accept_bi().await?;
        // This is deliberately not a TLS handshake. The TLS layer must reject it before any
        // Relay proof or receive_payload/application code runs.
        server_peer.accept(IrohBiStream::new(send, recv)).await
    });

    let connection = client_endpoint.connect(discovered, ALPN).await?;
    let (mut send, _recv) = connection.open_bi().await?;
    send.write_all(b"application bytes before Relay authentication")
        .await?;
    send.flush().await?;
    let server_result = timeout(SESSION_TIMEOUT, server_task)
        .await
        .context("pre-auth server task timed out")?
        .context("pre-auth server task panicked")?;
    assert!(
        server_result.is_err(),
        "raw pre-auth bytes unexpectedly completed inner TLS"
    );

    assert!(rendezvous.delete(&capability).await);
    assert!(rendezvous.is_empty().await);
    client_endpoint.close().await;
    server_endpoint.close().await;
    drop(connection);
    drop(relay_guard);
    Ok(())
}

#[cfg(test)]
async fn authenticate_new_connection_on_existing_endpoints(
    client_endpoint: &Endpoint,
    server_endpoint: &Endpoint,
    client_peer: InnerTlsPeer,
    server_peer: InnerTlsPeer,
    capture: Arc<Mutex<Option<[u8; crate::inner_tls::RELAY_PROOF_BYTES]>>>,
) -> Result<()> {
    let server_endpoint_task = server_endpoint.clone();
    let expected_client = client_peer.relay.relay_id.clone();
    let server_peer_task = server_peer.clone();
    let server_task = tokio::spawn(async move {
        let incoming = server_endpoint_task
            .accept()
            .await
            .context("accept reconnect Iroh connection")?;
        let connection = incoming
            .await
            .context("complete reconnect Iroh handshake")?;
        let (send, recv) = connection
            .accept_bi()
            .await
            .context("accept reconnect stream")?;
        let mut tls = server_peer_task
            .accept(IrohBiStream::new(send, recv))
            .await?;
        let observed_client_cert = server_peer_certificate_fingerprint(&tls)?;
        crate::inner_tls::authenticate_server_for_test(
            &mut tls,
            &server_peer_task.relay,
            &expected_client,
            observed_client_cert,
            crate::inner_tls::TestServerProofBehavior::Capture(capture),
        )
        .await?;
        ensure!(
            tls.read_u8().await? == 0xad,
            "reconnect client did not acknowledge authentication"
        );
        Ok(())
    });

    let connection = client_endpoint
        .connect(server_endpoint.addr(), ALPN)
        .await?;
    let (send, recv) = connection.open_bi().await?;
    let mut tls = client_peer.connect(IrohBiStream::new(send, recv)).await?;
    let observed_server_cert = client_peer_certificate_fingerprint(&tls)?;
    authenticate_client(
        &mut tls,
        &client_peer.relay,
        &server_peer.relay.relay_id,
        observed_server_cert,
    )
    .await?;
    tls.write_u8(0xad).await?;
    tls.flush().await?;
    timeout(SESSION_TIMEOUT, server_task)
        .await
        .context("reconnect server task timed out")?
        .context("reconnect server task panicked")??;
    drop(connection);
    Ok(())
}

#[cfg(test)]
mod tests {
    use relay_core::crypto::relay_identity_proof::RelayIdentityProofV1;

    use super::*;
    use crate::inner_tls::TestServerProofBehavior;

    #[tokio::test]
    async fn direct_path_inner_auth_and_one_mib_integrity() {
        let report =
            run_authenticated_transfer(&World::new().unwrap(), PathClass::Direct, ONE_MIB, false)
                .await
                .unwrap();
        assert_eq!(report.path, PathClass::Direct);
        assert_eq!(report.bytes, ONE_MIB);
    }

    #[tokio::test]
    async fn forced_stock_relay_inner_auth_and_one_mib_integrity() {
        let report =
            run_authenticated_transfer(&World::new().unwrap(), PathClass::Relay, ONE_MIB, false)
                .await
                .unwrap();
        assert_eq!(report.path, PathClass::Relay);
        assert_eq!(report.bytes, ONE_MIB);
    }

    #[tokio::test]
    async fn real_rendezvous_substitution_reaches_c_then_rejects_its_valid_relay_identity() {
        run_rendezvous_substitution(&World::new().unwrap())
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn responder_rejects_valid_unexpected_client_c_before_payload() {
        run_unexpected_client(&World::new().unwrap()).await.unwrap();
    }

    #[tokio::test]
    async fn wrong_expected_relay_id_is_rejected_without_unverified_fallback() {
        let world = World::new().unwrap();
        let outcome = run_session(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.c.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Integrity {
                bytes: ONE_MIB,
                slow_reader: false,
            },
            SESSION_TIMEOUT,
        )
        .await
        .unwrap();
        outcome.assert_cleanup().unwrap();
        assert!(outcome.client.is_err());
        assert!(outcome.server.is_err());
    }

    #[tokio::test]
    async fn corrupted_proof_is_test_only_and_rejected_without_payload() {
        let world = World::new().unwrap();
        let outcome = run_session_inner(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.b.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Integrity {
                bytes: ONE_MIB,
                slow_reader: false,
            },
            SESSION_TIMEOUT,
            Some(TestServerProofBehavior::CorruptSignature),
        )
        .await
        .unwrap();
        outcome.assert_cleanup().unwrap();
        assert!(outcome.client.is_err());
        assert!(outcome.server.is_err());
    }

    #[tokio::test]
    async fn wrong_certificate_proof_binding_is_rejected() {
        let world = World::new().unwrap();
        let outcome = run_session_inner(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.b.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Integrity {
                bytes: ONE_MIB,
                slow_reader: false,
            },
            SESSION_TIMEOUT,
            Some(TestServerProofBehavior::WrongCertificateBinding),
        )
        .await
        .unwrap();
        outcome.assert_cleanup().unwrap();
        assert!(outcome.client.is_err());
        assert!(outcome.server.is_err());
    }

    #[tokio::test]
    async fn captured_server_proof_replayed_on_new_connection_is_rejected() {
        let world = World::new().unwrap();
        let capture = Arc::new(Mutex::new(None));
        let first = run_session_inner(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.b.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Integrity {
                bytes: ONE_MIB,
                slow_reader: false,
            },
            SESSION_TIMEOUT,
            Some(TestServerProofBehavior::Capture(capture.clone())),
        )
        .await
        .unwrap();
        first.assert_cleanup().unwrap();
        assert!(first.client.is_ok() && first.server.is_ok());
        let captured = capture
            .lock()
            .unwrap()
            .expect("captured first server proof");
        let second = run_session_inner(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.b.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Integrity {
                bytes: ONE_MIB,
                slow_reader: false,
            },
            SESSION_TIMEOUT,
            Some(TestServerProofBehavior::Replay(captured)),
        )
        .await
        .unwrap();
        second.assert_cleanup().unwrap();
        assert!(second.client.is_err());
        assert!(second.server.is_err());
    }

    #[tokio::test]
    async fn reconnect_uses_fresh_relay_proofs_and_authentication() {
        let world = World::new().unwrap();
        let (client_endpoint, server_endpoint, relay_guard) =
            make_endpoints(PathClass::Direct).await.unwrap();
        let client_endpoint_id = client_endpoint.id();
        let server_endpoint_id = server_endpoint.id();
        let first_capture: Arc<Mutex<Option<[u8; crate::inner_tls::RELAY_PROOF_BYTES]>>> =
            Arc::new(Mutex::new(None));
        let second_capture: Arc<Mutex<Option<[u8; crate::inner_tls::RELAY_PROOF_BYTES]>>> =
            Arc::new(Mutex::new(None));
        for capture in [&first_capture, &second_capture] {
            authenticate_new_connection_on_existing_endpoints(
                &client_endpoint,
                &server_endpoint,
                world.a.clone(),
                world.b.clone(),
                capture.clone(),
            )
            .await
            .unwrap();
        }
        let first =
            RelayIdentityProofV1::decode(&first_capture.lock().unwrap().expect("first proof"))
                .unwrap();
        let second =
            RelayIdentityProofV1::decode(&second_capture.lock().unwrap().expect("second proof"))
                .unwrap();
        assert_ne!(first.nonce, second.nonce);
        assert_eq!(client_endpoint.id(), client_endpoint_id);
        assert_eq!(server_endpoint.id(), server_endpoint_id);
        client_endpoint.close().await;
        server_endpoint.close().await;
        drop(relay_guard);
    }

    #[tokio::test]
    async fn cancellation_cleans_claimed_rendezvous_and_joins_server() {
        assert_eq!(
            run_cancellation(&World::new().unwrap()).await.unwrap(),
            256 * 1024
        );
    }

    #[tokio::test]
    async fn slow_receiver_uses_bounded_chunks_and_observes_backpressure() {
        let report = run_authenticated_transfer(
            &World::new().unwrap(),
            PathClass::Direct,
            BACKPRESSURE_BYTES,
            true,
        )
        .await
        .unwrap();
        assert_eq!(report.max_application_buffer, CHUNK_SIZE);
        assert!(report.max_write_wait >= Duration::from_millis(1));
    }

    #[tokio::test]
    async fn timeout_aborts_server_task_and_cleans_claimed_rendezvous() {
        let world = World::new().unwrap();
        let outcome = run_session(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.b.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Stall,
            Duration::from_secs(2),
        )
        .await
        .unwrap();
        outcome.assert_cleanup().unwrap();
        assert!(outcome.client.is_err());
        assert!(outcome.server.is_err());
    }

    #[tokio::test]
    async fn application_bytes_before_relay_auth_are_never_accepted() {
        raw_payload_before_auth_is_rejected(&World::new().unwrap())
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn declared_payload_over_proof_limit_is_rejected() {
        let world = World::new().unwrap();
        let outcome = run_session(
            PathClass::Direct,
            world.a.clone(),
            world.b.clone(),
            world.b.relay.relay_id.clone(),
            world.a.relay.relay_id.clone(),
            SessionKind::Integrity {
                bytes: MAX_DECLARED_PAYLOAD + 1,
                slow_reader: false,
            },
            SESSION_TIMEOUT,
        )
        .await
        .unwrap();
        outcome.assert_cleanup().unwrap();
        assert!(outcome.client.is_err());
        assert!(outcome.server.is_err());
    }
}
