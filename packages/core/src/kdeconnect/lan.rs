//! LAN discovery and the TCP/TLS link used for pairing.
//!
//! UDP identity broadcasts use port 1716. The TCP listener is bound in
//! 1716..=1764. After a plaintext identity exchange, TLS roles are reversed
//! relative to TCP: the TCP client is the TLS server.

use crate::kdeconnect::identity::{
    certificate_common_name, install_crypto_provider, LocalIdentity,
};
use crate::kdeconnect::packet::{
    is_valid_device_id, NetworkPacket, PairBody, MAX_IDENTITY_PACKET_BYTES, MAX_PACKET_BYTES,
    PROTOCOL_VERSION,
};
use crate::kdeconnect::pairing::{
    now_unix, PairState, PairingEffect, PairingFailReason, PairingSession, PAIRING_TIMEOUT_SECS,
};
use crate::kdeconnect::{DeviceSnapshot, KdeConnectEvent, TrustedDevice};
use anyhow::{Context, Result};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{
    verify_tls12_signature as verify_tls12, verify_tls13_signature as verify_tls13,
};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::{
    ClientConfig, DigitallySignedStruct, DistinguishedName, Error, ServerConfig, SignatureScheme,
};
use socket2::{Domain, Protocol, Socket, Type};
use std::collections::HashMap;
use std::io;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::{mpsc, Mutex};
use tokio_rustls::{TlsAcceptor, TlsConnector, TlsStream};
use tokio_util::sync::CancellationToken;

pub const UDP_PORT: u16 = 1716;
pub const MIN_TCP_PORT: u16 = 1716;
pub const MAX_TCP_PORT: u16 = 1764;
const CONNECT_COOLDOWN: Duration = Duration::from_millis(500);

#[derive(Clone, Copy, Debug)]
pub enum BindMode {
    Any,
    Loopback,
}

#[derive(Clone, Debug)]
pub struct LanConfig {
    pub bind: BindMode,
    pub allow_loopback: bool,
}

impl Default for LanConfig {
    fn default() -> Self {
        Self {
            bind: BindMode::Any,
            allow_loopback: false,
        }
    }
}

#[derive(Clone, Debug)]
pub struct ObservedDevice {
    pub device_id: String,
    pub name: String,
    pub device_type: String,
    pub protocol_version: i64,
    pub ip: IpAddr,
    pub tcp_port: u16,
}

#[derive(Default)]
pub struct DeviceTable {
    by_id: HashMap<String, ObservedDevice>,
}

impl DeviceTable {
    pub fn upsert(&mut self, observed: ObservedDevice) -> &ObservedDevice {
        let id = observed.device_id.clone();
        self.by_id.insert(id.clone(), observed);
        self.by_id.get(&id).expect("just inserted")
    }

    pub fn get(&self, device_id: &str) -> Option<&ObservedDevice> {
        self.by_id.get(device_id)
    }

    pub fn iter(&self) -> impl Iterator<Item = &ObservedDevice> {
        self.by_id.values()
    }
}

#[derive(Default)]
struct TrustStore {
    by_id: HashMap<String, TrustedDevice>,
}

impl TrustStore {
    fn from_list(list: Vec<TrustedDevice>) -> Self {
        Self {
            by_id: list.into_iter().map(|d| (d.device_id.clone(), d)).collect(),
        }
    }

    fn get(&self, device_id: &str) -> Option<&TrustedDevice> {
        self.by_id.get(device_id)
    }

    fn insert(&mut self, device: TrustedDevice) {
        self.by_id.insert(device.device_id.clone(), device);
    }

    fn remove(&mut self, device_id: &str) -> Option<TrustedDevice> {
        self.by_id.remove(device_id)
    }

    fn snapshot(&self) -> Vec<TrustedDevice> {
        self.by_id.values().cloned().collect()
    }

    fn cert_der(&self, device_id: &str) -> Option<Vec<u8>> {
        self.by_id.get(device_id)?.certificate_der().ok()
    }
}

struct Conn {
    packets: mpsc::Sender<Vec<u8>>,
    peer_cert_der: Vec<u8>,
    name: String,
    device_type: String,
    protocol_version: i64,
}

pub(crate) struct LanInner {
    pub identity: LocalIdentity,
    config: LanConfig,
    pub tcp_port: u16,
    devices: Mutex<DeviceTable>,
    trust: Mutex<TrustStore>,
    pairing: Mutex<HashMap<String, PairingSession>>,
    connections: Mutex<HashMap<String, Conn>>,
    last_connect: Mutex<HashMap<String, Instant>>,
    mismatches: Mutex<std::collections::HashSet<String>>,
    incoming: Mutex<std::collections::HashSet<String>>,
    event_tx: mpsc::UnboundedSender<KdeConnectEvent>,
    pub cancel: CancellationToken,
}

impl LanInner {
    pub fn new(
        identity: LocalIdentity,
        trusted: Vec<TrustedDevice>,
        config: LanConfig,
        tcp_port: u16,
        event_tx: mpsc::UnboundedSender<KdeConnectEvent>,
        cancel: CancellationToken,
    ) -> Arc<Self> {
        let pairing = trusted
            .iter()
            .map(|d| (d.device_id.clone(), PairingSession::new(true)))
            .collect();
        Arc::new(Self {
            identity,
            config,
            tcp_port,
            devices: Mutex::new(DeviceTable::default()),
            trust: Mutex::new(TrustStore::from_list(trusted)),
            pairing: Mutex::new(pairing),
            connections: Mutex::new(HashMap::new()),
            last_connect: Mutex::new(HashMap::new()),
            mismatches: Mutex::new(std::collections::HashSet::new()),
            incoming: Mutex::new(std::collections::HashSet::new()),
            event_tx,
            cancel,
        })
    }

    pub async fn snapshot(&self) -> Vec<DeviceSnapshot> {
        let devices = self.devices.lock().await;
        let trust = self.trust.lock().await;
        let connections = self.connections.lock().await;
        let pairing = self.pairing.lock().await;
        let mismatches = self.mismatches.lock().await;
        let incoming = self.incoming.lock().await;
        let mut out = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for observed in devices.iter() {
            seen.insert(observed.device_id.clone());
            let paired = trust.get(&observed.device_id).is_some();
            out.push(DeviceSnapshot {
                device_id: observed.device_id.clone(),
                name: observed.name.clone(),
                device_type: observed.device_type.clone(),
                ip: Some(observed.ip.to_string()),
                port: Some(observed.tcp_port),
                paired,
                connected: connections.contains_key(&observed.device_id),
                incoming_pair: incoming.contains(&observed.device_id),
                identity_mismatch: mismatches.contains(&observed.device_id),
            });
        }
        for trusted in trust.snapshot() {
            if seen.contains(&trusted.device_id) {
                continue;
            }
            out.push(DeviceSnapshot {
                device_id: trusted.device_id.clone(),
                name: trusted.name.clone(),
                device_type: trusted.device_type.clone(),
                ip: None,
                port: None,
                paired: true,
                connected: connections.contains_key(&trusted.device_id),
                incoming_pair: pairing
                    .get(&trusted.device_id)
                    .is_some_and(|s| s.state == PairState::RequestedByPeer),
                identity_mismatch: mismatches.contains(&trusted.device_id),
            });
        }
        out.sort_by(|a, b| {
            a.name
                .to_lowercase()
                .cmp(&b.name.to_lowercase())
                .then(a.device_id.cmp(&b.device_id))
        });
        out
    }

    async fn emit_devices(&self) {
        let devices = self.snapshot().await;
        let _ = self
            .event_tx
            .send(KdeConnectEvent::DevicesChanged { devices });
    }

    async fn emit_trust(&self) {
        let devices = self.trust.lock().await.snapshot();
        let _ = self
            .event_tx
            .send(KdeConnectEvent::TrustChanged { devices });
    }

    pub async fn trusted_devices(&self) -> Vec<TrustedDevice> {
        self.trust.lock().await.snapshot()
    }

    pub async fn request_pair(self: &Arc<Self>, device_id: &str) -> Result<()> {
        tracing::info!("[KDE Connect] [A] request_pair called for device {device_id}");
        self.ensure_connected(device_id).await?;
        let now = now_unix();
        let mut pairing = self.pairing.lock().await;
        let session = pairing
            .entry(device_id.to_string())
            .or_insert_with(|| PairingSession::new(false));
        if session.state == PairState::RequestedByPeer {
            drop(pairing);
            tracing::info!("[KDE Connect] Pairing already requested by peer {device_id}, auto-accepting");
            return self.accept_pair(device_id).await;
        }
        let body = session
            .begin_request(now)
            .map_err(|e| anyhow::anyhow!("{e:?}"))?;
        drop(pairing);
        let req_pkt = PairBody::request(body.timestamp.unwrap_or(now)).serialize();
        tracing::info!(
            "[KDE Connect] [H] Sending pair request to {device_id} with timestamp={:?}",
            body.timestamp
        );
        self.send_packet(device_id, &req_pkt).await?;
        self.spawn_timeout(device_id.to_string());
        self.emit_devices().await;
        Ok(())
    }

    pub async fn accept_pair(self: &Arc<Self>, device_id: &str) -> Result<()> {
        let conn = {
            let connections = self.connections.lock().await;
            connections.get(device_id).map(|c| {
                (
                    c.peer_cert_der.clone(),
                    c.name.clone(),
                    c.device_type.clone(),
                    c.protocol_version,
                )
            })
        };
        let Some((cert_der, name, device_type, protocol_version)) = conn else {
            anyhow::bail!("device is not connected");
        };
        {
            let mut pairing = self.pairing.lock().await;
            let session = pairing
                .entry(device_id.to_string())
                .or_insert_with(|| PairingSession::new(false));
            session.accept();
        }
        self.incoming.lock().await.remove(device_id);
        self.remember_trust(device_id, cert_der, name, device_type, protocol_version)
            .await?;
        self.send_packet(device_id, &PairBody::accept().serialize())
            .await?;
        self.emit_trust().await;
        self.emit_devices().await;
        Ok(())
    }

    pub async fn reject_pair(&self, device_id: &str) -> Result<()> {
        if let Some(session) = self.pairing.lock().await.get_mut(device_id) {
            session.local_cancel();
        }
        self.incoming.lock().await.remove(device_id);
        let _ = self
            .send_packet(device_id, &PairBody::unpair().serialize())
            .await;
        self.emit_devices().await;
        Ok(())
    }

    pub async fn unpair(&self, device_id: &str) -> Result<()> {
        if let Some(session) = self.pairing.lock().await.get_mut(device_id) {
            session.local_cancel();
        }
        self.incoming.lock().await.remove(device_id);
        self.trust.lock().await.remove(device_id);
        let _ = self
            .send_packet(device_id, &PairBody::unpair().serialize())
            .await;
        self.emit_trust().await;
        self.emit_devices().await;
        Ok(())
    }

    async fn remember_trust(
        &self,
        device_id: &str,
        cert_der: Vec<u8>,
        name: String,
        device_type: String,
        protocol_version: i64,
    ) -> Result<()> {
        let pem = pem::encode(&pem::Pem::new("CERTIFICATE", cert_der));
        self.trust.lock().await.insert(TrustedDevice {
            device_id: device_id.to_string(),
            certificate_pem: pem,
            name,
            device_type,
            protocol_version,
            paired_at_unix: now_unix(),
        });
        Ok(())
    }

    async fn send_packet(&self, device_id: &str, bytes: &[u8]) -> Result<()> {
        let connections = self.connections.lock().await;
        let conn = connections.get(device_id).context("no KDE Connect link")?;
        conn.packets
            .send(bytes.to_vec())
            .await
            .context("KDE Connect link closed")?;
        Ok(())
    }

    fn spawn_timeout(self: &Arc<Self>, device_id: String) {
        let inner = Arc::clone(self);
        tokio::spawn(async move {
            tokio::select! {
                _ = inner.cancel.cancelled() => {}
                _ = tokio::time::sleep(Duration::from_secs(PAIRING_TIMEOUT_SECS)) => {
                    let mut pairing = inner.pairing.lock().await;
                    if let Some(session) = pairing.get_mut(&device_id) {
                        if session.timeout() != PairingEffect::None {
                            drop(pairing);
                            let _ = inner.send_packet(&device_id, &PairBody::unpair().serialize()).await;
                            inner.incoming.lock().await.remove(&device_id);
                            let _ = inner.event_tx.send(KdeConnectEvent::PairingFailed { device_id: device_id.clone(), reason: "Timed out".into() });
                            inner.emit_devices().await;
                        }
                    }
                }
            }
        });
    }

    async fn ensure_connected(self: &Arc<Self>, device_id: &str) -> Result<()> {
        if self.connections.lock().await.contains_key(device_id) {
            return Ok(());
        }
        let observed = self
            .devices
            .lock()
            .await
            .get(device_id)
            .cloned()
            .context("device is not reachable")?;
        outbound_connect(
            Arc::clone(self),
            observed.ip,
            observed.tcp_port,
            Some(device_id.to_string()),
        )
        .await
    }

    async fn apply_pairing_effect(
        self: &Arc<Self>,
        device_id: &str,
        name: &str,
        cert_der: &[u8],
        device_type: &str,
        protocol_version: i64,
        effect: PairingEffect,
    ) {
        match effect {
            PairingEffect::None => {}
            PairingEffect::IncomingRequest { .. } => {
                self.incoming.lock().await.insert(device_id.to_string());
                self.spawn_timeout(device_id.to_string());
                let _ = self.event_tx.send(KdeConnectEvent::IncomingPair {
                    device_id: device_id.to_string(),
                    name: name.to_string(),
                });
                self.emit_devices().await;
            }
            PairingEffect::Completed => {
                self.incoming.lock().await.remove(device_id);
                let _ = self
                    .remember_trust(
                        device_id,
                        cert_der.to_vec(),
                        name.to_string(),
                        device_type.to_string(),
                        protocol_version,
                    )
                    .await;
                self.emit_trust().await;
                self.emit_devices().await;
            }
            PairingEffect::Failed(reason) => {
                self.incoming.lock().await.remove(device_id);
                let message = match reason {
                    PairingFailReason::CanceledByPeer => "Canceled by other peer",
                    PairingFailReason::TimedOut => "Timed out",
                    PairingFailReason::ClocksOutOfSync => "Device clocks are out of sync",
                    PairingFailReason::MissingTimestamp => "Pairing request was incomplete",
                    PairingFailReason::AlreadyPaired => "Already paired",
                };
                let _ = self.event_tx.send(KdeConnectEvent::PairingFailed {
                    device_id: device_id.to_string(),
                    reason: message.into(),
                });
                self.emit_devices().await;
            }
            PairingEffect::Unpaired => {
                self.incoming.lock().await.remove(device_id);
                self.trust.lock().await.remove(device_id);
                self.emit_trust().await;
                self.emit_devices().await;
            }
        }
    }
}

pub(crate) async fn run(inner: Arc<LanInner>, listener: TcpListener, udp: UdpSocket) {
    let udp = Arc::new(udp);
    broadcast_identity(&inner, &udp).await;
    loop {
        let mut buf = vec![0u8; MAX_IDENTITY_PACKET_BYTES];
        tokio::select! {
            _ = inner.cancel.cancelled() => break,
            accepted = listener.accept() => {
                if let Ok((stream, addr)) = accepted {
                    let inner = Arc::clone(&inner);
                    tokio::spawn(async move {
                        if let Err(err) = inbound_tcp(inner, stream, addr).await {
                            tracing::debug!("KDE Connect inbound handshake failed: {err:#}");
                        }
                    });
                }
            }
            received = udp.recv_from(&mut buf) => {
                if let Ok((n, addr)) = received {
                    let inner = Arc::clone(&inner);
                    let udp = Arc::clone(&udp);
                    let datagram = buf[..n].to_vec();
                    tokio::spawn(async move {
                        if let Err(err) = handle_udp(&inner, &udp, &datagram, addr).await {
                            tracing::debug!("KDE Connect UDP ignored: {err:#}");
                        }
                    });
                }
            }
        }
    }
}

async fn broadcast_identity(inner: &LanInner, shared: &UdpSocket) {
    let payload = inner
        .identity
        .identity_packet(Some(inner.tcp_port))
        .to_packet()
        .serialize();
    let dest = SocketAddr::from((Ipv4Addr::BROADCAST, UDP_PORT));
    let _ = shared.send_to(&payload, dest).await;
    if matches!(inner.config.bind, BindMode::Loopback) || inner.config.allow_loopback {
        let _ = shared
            .send_to(&payload, SocketAddr::from((Ipv4Addr::LOCALHOST, UDP_PORT)))
            .await;
    }
    if let Ok(ifaces) = if_addrs::get_if_addrs() {
        for iface in ifaces {
            let IpAddr::V4(ip) = iface.ip() else { continue };
            if ip.is_loopback() {
                continue;
            }
            if let Ok(socket) = bind_udp_from(ip) {
                let _ = socket.send_to(&payload, dest);
            }
        }
    }
}

fn bind_udp_from(ip: Ipv4Addr) -> io::Result<std::net::UdpSocket> {
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_broadcast(true)?;
    socket.set_reuse_address(true)?;
    socket.bind(&std::net::SocketAddr::from((ip, 0)).into())?;
    Ok(socket.into())
}

pub(crate) fn bind_udp(mode: BindMode) -> Result<UdpSocket> {
    let ip = match mode {
        BindMode::Any => Ipv4Addr::UNSPECIFIED,
        BindMode::Loopback => Ipv4Addr::LOCALHOST,
    };
    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    #[cfg(unix)]
    socket.set_reuse_port(true)?;
    socket.set_broadcast(true)?;
    socket.set_nonblocking(true)?;
    socket.bind(&std::net::SocketAddr::from((ip, UDP_PORT)).into())?;
    Ok(UdpSocket::from_std(socket.into())?)
}

pub(crate) async fn bind_tcp(mode: BindMode) -> Result<(TcpListener, u16)> {
    let ip = match mode {
        BindMode::Any => Ipv4Addr::UNSPECIFIED,
        BindMode::Loopback => Ipv4Addr::LOCALHOST,
    };
    for port in MIN_TCP_PORT..=MAX_TCP_PORT {
        if let Ok(listener) = TcpListener::bind((ip, port)).await {
            return Ok((listener, port));
        }
    }
    anyhow::bail!("no KDE Connect TCP port available in {MIN_TCP_PORT}-{MAX_TCP_PORT}");
}

async fn handle_udp(
    inner: &Arc<LanInner>,
    udp: &UdpSocket,
    datagram: &[u8],
    addr: SocketAddr,
) -> Result<()> {
    if datagram.len() > MAX_IDENTITY_PACKET_BYTES {
        anyhow::bail!("udp identity too large");
    }
    if !inner.config.allow_loopback && addr.ip().is_loopback() {
        return Ok(());
    }
    if !is_usable_address(addr.ip(), inner.config.allow_loopback) {
        return Ok(());
    }
    let identity = NetworkPacket::parse(datagram)?.as_identity()?;
    if identity.device_id == inner.identity.device_id {
        return Ok(());
    }
    let tcp_port = identity.tcp_port.context("identity missing tcpPort")?;
    if !(MIN_TCP_PORT..=MAX_TCP_PORT).contains(&tcp_port) {
        anyhow::bail!("tcpPort outside KDE Connect range");
    }
    if !rate_ok(inner, &identity.device_id).await {
        return Ok(());
    }
    inner.devices.lock().await.upsert(ObservedDevice {
        device_id: identity.device_id.clone(),
        name: identity.device_name.clone(),
        device_type: identity.device_type.clone(),
        protocol_version: identity.protocol_version,
        ip: addr.ip(),
        tcp_port,
    });
    inner.emit_devices().await;
    if matches!(inner.config.bind, BindMode::Loopback) {
        return Ok(());
    }
    if inner
        .connections
        .lock()
        .await
        .contains_key(&identity.device_id)
    {
        return Ok(());
    }
    match outbound_connect(
        Arc::clone(inner),
        addr.ip(),
        tcp_port,
        Some(identity.device_id.clone()),
    )
    .await
    {
        Ok(()) => Ok(()),
        Err(err) => {
            tracing::debug!("outbound KDE Connect connect failed, sending reverse udp: {err:#}");
            let payload = inner
                .identity
                .identity_packet(Some(inner.tcp_port))
                .to_packet()
                .serialize();
            let _ = udp
                .send_to(&payload, SocketAddr::new(addr.ip(), UDP_PORT))
                .await;
            Ok(())
        }
    }
}

async fn rate_ok(inner: &LanInner, device_id: &str) -> bool {
    let now = Instant::now();
    let mut last = inner.last_connect.lock().await;
    if let Some(previous) = last.get(device_id) {
        if now.duration_since(*previous) < CONNECT_COOLDOWN {
            return false;
        }
    }
    last.insert(device_id.to_string(), now);
    true
}

fn is_usable_address(ip: IpAddr, allow_loopback: bool) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            v4.is_private()
                || v4.is_link_local()
                || (allow_loopback && v4.is_loopback())
                || is_cgnat(v4)
        }
        IpAddr::V6(v6) => {
            v6.is_unique_local()
                || v6.is_unicast_link_local()
                || (allow_loopback && v6.is_loopback())
        }
    }
}

fn is_cgnat(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    octets[0] == 100 && (octets[1] & 0xc0) == 0x40
}

pub(crate) async fn connect_to(inner: Arc<LanInner>, ip: IpAddr, port: u16) -> Result<()> {
    outbound_connect(inner, ip, port, None).await
}

async fn outbound_connect(
    inner: Arc<LanInner>,
    ip: IpAddr,
    tcp_port: u16,
    expected_id: Option<String>,
) -> Result<()> {
    tracing::info!("[KDE Connect] [B] Opening TCP to {ip}:{tcp_port}");
    let mut stream = match TcpStream::connect(SocketAddr::new(ip, tcp_port)).await {
        Ok(s) => {
            tracing::info!("[KDE Connect] [C] TCP connected to {ip}:{tcp_port}");
            s
        }
        Err(e) => {
            tracing::warn!("[KDE Connect] [C] TCP connect to {ip}:{tcp_port} failed: {e:#}");
            return Err(e.into());
        }
    };
    configure_keepalive(&stream);
    let mut mine = inner.identity.identity_packet(None);
    if let Some(device_id) = &expected_id {
        mine.target_device_id = Some(device_id.clone());
        mine.target_protocol_version = Some(PROTOCOL_VERSION);
    }
    tracing::info!("[KDE Connect] [G] Sending plaintext identity to {ip}:{tcp_port}");
    stream.write_all(&mine.to_packet().serialize()).await?;
    stream.flush().await?;
    let trusted = match &expected_id {
        Some(id) => inner.trust.lock().await.cert_der(id),
        None => None,
    };
    tracing::info!("[KDE Connect] [D] Starting TLS as TLS server with peer {ip}:{tcp_port}");
    let tls = match start_tls_as_server(&inner.identity, stream, trusted.as_deref()).await {
        Ok(t) => {
            tracing::info!("[KDE Connect] [E] TLS handshake as server succeeded with {ip}:{tcp_port}");
            t
        }
        Err(e) => {
            tracing::warn!("[KDE Connect] [E] TLS handshake as server failed with {ip}:{tcp_port}: {e:#}");
            return Err(e);
        }
    };
    let expected_ver = match &expected_id {
        Some(id) => inner.devices.lock().await.get(id).map(|d| d.protocol_version),
        None => None,
    };
    finish_secure_link(inner, tls, ip, expected_id, expected_ver).await
}

async fn inbound_tcp(inner: Arc<LanInner>, mut stream: TcpStream, addr: SocketAddr) -> Result<()> {
    if !is_usable_address(addr.ip(), inner.config.allow_loopback) {
        anyhow::bail!("non-local tcp peer");
    }
    tracing::info!("[KDE Connect] [C] Inbound TCP connection accepted from {addr}");
    configure_keepalive(&stream);
    let line = match tokio::time::timeout(
        Duration::from_secs(5),
        read_line_bounded(&mut stream, MAX_IDENTITY_PACKET_BYTES),
    )
    .await {
        Ok(Ok(l)) => l,
        Ok(Err(e)) => {
            tracing::warn!("[KDE Connect] [G] Failed to read plaintext identity from {addr}: {e:#}");
            return Err(e.into());
        }
        Err(_) => {
            tracing::warn!("[KDE Connect] [G] Timed out waiting for plaintext identity from {addr}");
            anyhow::bail!("timed out waiting for plaintext identity");
        }
    };
    let identity = NetworkPacket::parse(&line)?.as_identity()?;
    tracing::info!(
        "[KDE Connect] [G] Inbound identity received from {addr}: device_id={}, device_name={}",
        identity.device_id,
        identity.device_name
    );
    if let Some(target) = &identity.target_device_id {
        if target != &inner.identity.device_id {
            anyhow::bail!("connection targeted a different device");
        }
    }
    if let Some(version) = identity.target_protocol_version {
        if version != PROTOCOL_VERSION {
            anyhow::bail!("connection targeted a different protocol version");
        }
    }
    if identity.device_id == inner.identity.device_id {
        return Ok(());
    }
    inner.devices.lock().await.upsert(ObservedDevice {
        device_id: identity.device_id.clone(),
        name: identity.device_name.clone(),
        device_type: identity.device_type.clone(),
        protocol_version: identity.protocol_version,
        ip: addr.ip(),
        tcp_port: identity.tcp_port.unwrap_or(MIN_TCP_PORT),
    });
    let trusted = inner.trust.lock().await.cert_der(&identity.device_id);
    if let Some(last) = inner.trust.lock().await.get(&identity.device_id) {
        if last.protocol_version > identity.protocol_version {
            anyhow::bail!("protocol downgrade");
        }
    }
    tracing::info!("[KDE Connect] [D] Starting TLS as TLS client with peer {addr}");
    let tls = match start_tls_as_client(
        &inner.identity,
        stream,
        &identity.device_id,
        trusted.as_deref(),
    )
    .await
    {
        Ok(tls) => {
            tracing::info!("[KDE Connect] [E] TLS handshake as client succeeded with {addr}");
            tls
        }
        Err(err) => {
            tracing::warn!("[KDE Connect] [E] TLS handshake as client failed with {addr}: {err:#}");
            if trusted.is_some() {
                inner
                    .mismatches
                    .lock()
                    .await
                    .insert(identity.device_id.clone());
                inner.emit_devices().await;
            }
            return Err(err);
        }
    };
    finish_secure_link(inner, tls, addr.ip(), Some(identity.device_id), Some(identity.protocol_version)).await
}

async fn finish_secure_link(
    inner: Arc<LanInner>,
    mut tls: TlsStream<TcpStream>,
    ip: IpAddr,
    expected_id: Option<String>,
    expected_protocol_version: Option<i64>,
) -> Result<()> {
    let peer_cert = peer_certificate(&tls).context("peer presented no certificate")?;
    let cert_cn = certificate_common_name(&peer_cert)?;
    tracing::info!(
        "[KDE Connect] [F] Peer certificate presented with CN={cert_cn}, cert_len={}",
        peer_cert.len()
    );
    if !is_valid_device_id(&cert_cn) {
        anyhow::bail!("peer certificate CN is not a deviceId: {cert_cn}");
    }
    // G1: Write local secure identity without transient routing fields
    let my_identity = inner.identity.identity_packet(None).to_packet().serialize();
    tls.write_all(&my_identity).await?;
    tracing::info!("[KDE Connect] [G1] secure local identity written");

    // G2: Flush local secure identity
    tls.flush().await?;
    tracing::info!("[KDE Connect] [G2] secure local identity flushed");

    // G3: Read remote secure identity
    let line = tokio::time::timeout(
        Duration::from_secs(10),
        read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
    )
    .await
    .context("timed out waiting for secure remote identity")??;

    let secure = NetworkPacket::parse(&line)?.as_identity()?;
    tracing::info!(
        "[KDE Connect] [G3] secure remote identity received: device_id={}, protocol_version={}",
        secure.device_id,
        secure.protocol_version
    );

    // G4: Validate deviceId
    if secure.device_id != cert_cn {
        anyhow::bail!("deviceId does not match certificate CN");
    }
    if let Some(expected) = &expected_id {
        if expected != &secure.device_id {
            anyhow::bail!("deviceId changed during handshake");
        }
    }
    tracing::info!("[KDE Connect] [G4] secure identity deviceId matched");

    // G5: Validate protocolVersion
    if let Some(expected_ver) = expected_protocol_version {
        if secure.protocol_version != expected_ver {
            anyhow::bail!(
                "protocolVersion changed during handshake: expected {expected_ver}, got {}",
                secure.protocol_version
            );
        }
    }
    tracing::info!("[KDE Connect] [G5] secure identity protocolVersion matched");

    if let Some(stored) = inner.trust.lock().await.cert_der(&secure.device_id) {
        if stored != peer_cert {
            inner
                .mismatches
                .lock()
                .await
                .insert(secure.device_id.clone());
            inner.emit_devices().await;
            anyhow::bail!("paired certificate does not match");
        }
        inner.mismatches.lock().await.remove(&secure.device_id);
    }
    let tcp_port = {
        let devices = inner.devices.lock().await;
        devices
            .get(&secure.device_id)
            .map(|d| d.tcp_port)
            .or(secure.tcp_port)
            .unwrap_or(MIN_TCP_PORT)
    };
    inner.devices.lock().await.upsert(ObservedDevice {
        device_id: secure.device_id.clone(),
        name: secure.device_name.clone(),
        device_type: secure.device_type.clone(),
        protocol_version: secure.protocol_version,
        ip,
        tcp_port,
    });
    let (mut reader, mut writer) = tokio::io::split(tls);
    let (tx, mut rx) = mpsc::channel::<Vec<u8>>(16);
    {
        let mut connections = inner.connections.lock().await;
        connections.insert(
            secure.device_id.clone(),
            Conn {
                packets: tx,
                peer_cert_der: peer_cert.clone(),
                name: secure.device_name.clone(),
                device_type: secure.device_type.clone(),
                protocol_version: secure.protocol_version,
            },
        );
    }
    tracing::info!("[KDE Connect] [G6] secure link established with {}", secure.device_id);
    inner.emit_devices().await;
    let device_id = secure.device_id.clone();
    let writer_cancel = inner.cancel.clone();
    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = writer_cancel.cancelled() => break,
                packet = rx.recv() => {
                    let Some(packet) = packet else { break };
                    if writer.write_all(&packet).await.is_err() {
                        break;
                    }
                    let _ = writer.flush().await;
                }
            }
        }
    });
    let read_inner = Arc::clone(&inner);
    let read_id = device_id.clone();
    let name = secure.device_name.clone();
    let device_type = secure.device_type.clone();
    let protocol_version = secure.protocol_version;
    tokio::spawn(async move {
        loop {
            match read_line_bounded(&mut reader, MAX_PACKET_BYTES).await {
                Ok(line) => {
                    if let Ok(packet) = NetworkPacket::parse(&line) {
                        if let Ok(pair) = packet.as_pair() {
                            tracing::info!(
                                "[KDE Connect] [I] Received pair packet from {read_id}: pair={}, timestamp={:?}",
                                pair.pair,
                                pair.timestamp
                            );
                            let mut pairing = read_inner.pairing.lock().await;
                            let paired = read_inner.trust.lock().await.get(&read_id).is_some();
                            let session = pairing
                                .entry(read_id.clone())
                                .or_insert_with(|| PairingSession::new(paired));
                            let effect = session.on_packet(&pair, now_unix(), protocol_version);
                            drop(pairing);
                            read_inner
                                .apply_pairing_effect(
                                    &read_id,
                                    &name,
                                    &peer_cert,
                                    &device_type,
                                    protocol_version,
                                    effect,
                                )
                                .await;
                        }
                    }
                }
                Err(e) => {
                    tracing::info!("[KDE Connect] [J] Connection to {read_id} closed: {e:#}");
                    break;
                }
            }
        }
        read_inner.connections.lock().await.remove(&read_id);
        read_inner.emit_devices().await;
    });
    Ok(())
}

fn configure_keepalive(stream: &TcpStream) {
    let _ = stream.set_nodelay(true);
}

fn peer_certificate(tls: &TlsStream<TcpStream>) -> Option<Vec<u8>> {
    tls.get_ref()
        .1
        .peer_certificates()?
        .first()
        .map(|c| c.as_ref().to_vec())
}

async fn start_tls_as_server(
    identity: &LocalIdentity,
    stream: TcpStream,
    pin: Option<&[u8]>,
) -> Result<TlsStream<TcpStream>> {
    install_crypto_provider();
    let acceptor = TlsAcceptor::from(Arc::new(server_config(identity, pin)?));
    Ok(TlsStream::Server(
        tokio::time::timeout(Duration::from_secs(10), acceptor.accept(stream)).await??,
    ))
}

async fn start_tls_as_client(
    identity: &LocalIdentity,
    stream: TcpStream,
    device_id: &str,
    pin: Option<&[u8]>,
) -> Result<TlsStream<TcpStream>> {
    install_crypto_provider();
    let connector = TlsConnector::from(Arc::new(client_config(identity, pin)?));
    let name = ServerName::try_from(device_id.to_string()).unwrap_or_else(|_| {
        ServerName::try_from("localhost").expect("localhost is a valid server name")
    });
    Ok(TlsStream::Client(
        tokio::time::timeout(Duration::from_secs(10), connector.connect(name, stream)).await??,
    ))
}

fn server_config(identity: &LocalIdentity, pin: Option<&[u8]>) -> Result<ServerConfig> {
    let verifier = Arc::new(PeerCertVerifier::new(identity, pin.map(|p| p.to_vec()))?);
    let mut config = ServerConfig::builder()
        .with_client_cert_verifier(verifier)
        .with_single_cert(
            vec![identity.certificate_der()?],
            identity.private_key_der()?,
        )?;
    config.alpn_protocols = Vec::new();
    Ok(config)
}

fn client_config(identity: &LocalIdentity, pin: Option<&[u8]>) -> Result<ClientConfig> {
    let verifier = Arc::new(PeerCertVerifier::new(identity, pin.map(|p| p.to_vec()))?);
    let config = ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_client_auth_cert(
            vec![identity.certificate_der()?],
            identity.private_key_der()?,
        )?;
    Ok(config)
}

struct PeerCertVerifier {
    pin: Option<Vec<u8>>,
}

impl PeerCertVerifier {
    fn new(_identity: &LocalIdentity, pin: Option<Vec<u8>>) -> Result<Self> {
        Ok(Self { pin })
    }

    fn check(&self, cert: &CertificateDer<'_>) -> Result<(), Error> {
        if let Some(expected) = &self.pin {
            if cert.as_ref() != expected.as_slice() {
                return Err(Error::InvalidCertificate(
                    rustls::CertificateError::ApplicationVerificationFailure,
                ));
            }
        }
        Ok(())
    }
}

impl std::fmt::Debug for PeerCertVerifier {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("PeerCertVerifier")
    }
}

impl ServerCertVerifier for PeerCertVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        self.check(end_entity)?;
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        let provider = rustls::crypto::ring::default_provider();
        verify_tls12(
            message,
            cert,
            dss,
            &provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        let provider = rustls::crypto::ring::default_provider();
        verify_tls13(
            message,
            cert,
            dss,
            &provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

impl ClientCertVerifier for PeerCertVerifier {
    fn offer_client_auth(&self) -> bool {
        true
    }

    fn client_auth_mandatory(&self) -> bool {
        true
    }

    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }

    fn verify_client_cert(
        &self,
        cert: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: UnixTime,
    ) -> Result<ClientCertVerified, Error> {
        self.check(cert)?;
        Ok(ClientCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        let provider = rustls::crypto::ring::default_provider();
        verify_tls12(
            message,
            cert,
            dss,
            &provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        let provider = rustls::crypto::ring::default_provider();
        verify_tls13(
            message,
            cert,
            dss,
            &provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

async fn read_line_bounded<R: AsyncReadExt + Unpin>(
    reader: &mut R,
    max: usize,
) -> io::Result<Vec<u8>> {
    let mut out = Vec::new();
    loop {
        if out.len() >= max {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "line exceeds bound",
            ));
        }
        let mut byte = [0u8; 1];
        let n = reader.read(&mut byte).await?;
        if n == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "eof before newline",
            ));
        }
        if byte[0] == b'\n' {
            return Ok(out);
        }
        if byte[0] != b'\r' {
            out.push(byte[0]);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[test]
    fn table_dedupes_device_id_and_updates_ip() {
        let mut table = DeviceTable::default();
        table.upsert(ObservedDevice {
            device_id: "a".repeat(32),
            name: "Phone".into(),
            device_type: "phone".into(),
            protocol_version: 8,
            ip: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 8)),
            tcp_port: 1716,
        });
        table.upsert(ObservedDevice {
            device_id: "a".repeat(32),
            name: "Phone".into(),
            device_type: "phone".into(),
            protocol_version: 8,
            ip: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 9)),
            tcp_port: 1717,
        });
        assert_eq!(table.by_id.len(), 1);
        let stored = table.get(&"a".repeat(32)).unwrap();
        assert_eq!(stored.ip, IpAddr::V4(Ipv4Addr::new(192, 168, 1, 9)));
        assert_eq!(stored.tcp_port, 1717);
    }

    #[test]
    fn unrelated_devices_stay_isolated() {
        let mut table = DeviceTable::default();
        table.upsert(ObservedDevice {
            device_id: "a".repeat(32),
            name: "A".into(),
            device_type: "phone".into(),
            protocol_version: 8,
            ip: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 8)),
            tcp_port: 1716,
        });
        table.upsert(ObservedDevice {
            device_id: "b".repeat(32),
            name: "B".into(),
            device_type: "phone".into(),
            protocol_version: 8,
            ip: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 8)),
            tcp_port: 1716,
        });
        assert_eq!(table.by_id.len(), 2);
        assert_ne!(
            table.get(&"a".repeat(32)).unwrap().name,
            table.get(&"b".repeat(32)).unwrap().name
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn reversed_tls_roles_complete() {
        let alice = crate::kdeconnect::LocalIdentity::generate("Alice").unwrap();
        let bob = crate::kdeconnect::LocalIdentity::generate("Bob").unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let alice_for_inbound = alice.clone();
        let bob_id = bob.device_id.clone();
        let inbound = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            start_tls_as_client(&alice_for_inbound, stream, &bob_id, None).await
        });
        let stream = TcpStream::connect(addr).await.unwrap();
        let outbound = start_tls_as_server(&bob, stream, None).await;
        let inbound = inbound.await.unwrap();
        assert!(outbound.is_ok(), "{outbound:?}");
        assert!(inbound.is_ok(), "{inbound:?}");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn identity_then_reversed_tls_completes() {
        let alice = crate::kdeconnect::LocalIdentity::generate("Alice").unwrap();
        let bob = crate::kdeconnect::LocalIdentity::generate("Bob").unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let alice_for_inbound = alice.clone();
        let bob_id = bob.device_id.clone();
        let inbound = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let line = read_line_bounded(&mut stream, MAX_IDENTITY_PACKET_BYTES)
                .await
                .unwrap();
            let identity = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();
            assert_eq!(identity.device_id, bob_id);
            start_tls_as_client(&alice_for_inbound, stream, &bob_id, None).await
        });
        let mut stream = TcpStream::connect(addr).await.unwrap();
        stream
            .write_all(&bob.identity_packet(None).to_packet().serialize())
            .await
            .unwrap();
        stream.flush().await.unwrap();
        let outbound = start_tls_as_server(&bob, stream, None).await;
        let inbound = inbound.await.unwrap();
        assert!(outbound.is_ok(), "{outbound:?}");
        assert!(inbound.is_ok(), "{inbound:?}");
    }

    #[test]
    fn unpaired_certificate_is_accepted_but_not_trusted() {
        let alice = crate::kdeconnect::LocalIdentity::generate("Alice").unwrap();
        let bob = crate::kdeconnect::LocalIdentity::generate("Bob").unwrap();
        let verifier = PeerCertVerifier::new(&alice, None).unwrap();
        assert!(verifier.check(&bob.certificate_der().unwrap()).is_ok());
    }

    #[test]
    fn pinned_certificate_rejects_identity_mismatch() {
        let alice = crate::kdeconnect::LocalIdentity::generate("Alice").unwrap();
        let bob = crate::kdeconnect::LocalIdentity::generate("Bob").unwrap();
        let impostor = crate::kdeconnect::LocalIdentity::generate("Impostor").unwrap();
        let pin = bob.certificate_der().unwrap();
        let verifier = PeerCertVerifier::new(&alice, Some(pin.as_ref().to_vec())).unwrap();
        assert!(verifier.check(&pin).is_ok());
        assert!(verifier
            .check(&impostor.certificate_der().unwrap())
            .is_err());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn v8_secure_identity_exchange_inbound() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let phone_id = phone_identity.device_id.clone();
        let relay_id = relay_identity.device_id.clone();

        let relay_inner = LanInner::new(
            relay_identity.clone(),
            Vec::new(),
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            tokio::sync::mpsc::unbounded_channel().0,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_inner_clone = Arc::clone(&relay_inner);
        let relay_task = tokio::spawn(async move {
            let (stream, peer_addr) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
                .await
                .expect("R0: accept timeout")
                .unwrap();
            tokio::time::timeout(Duration::from_secs(2), inbound_tcp(relay_inner_clone, stream, peer_addr))
                .await
                .expect("Relay inbound_tcp timeout")
        });

        let phone_identity_clone = phone_identity.clone();
        let phone_task = tokio::spawn(async move {
            let mut stream = tokio::time::timeout(Duration::from_secs(2), TcpStream::connect(addr))
                .await
                .expect("K0: connect timeout")
                .unwrap();
            // Pre-TLS identity
            let pre_tls = phone_identity_clone.identity_packet(Some(1716)).to_packet().serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();
            // TLS server
            eprintln!("[TEST] K1 TLS start as server");
            let mut tls = tokio::time::timeout(Duration::from_secs(2), start_tls_as_server(&phone_identity_clone, stream, None))
                .await
                .expect("K1: TLS handshake timeout")
                .unwrap();
            eprintln!("[TEST] K1 TLS complete");

            eprintln!("[TEST] K2 secure identity serialize");
            let secure_id = phone_identity_clone.identity_packet(None).to_packet().serialize();

            eprintln!("[TEST] K3 secure identity write start");
            tls.write_all(&secure_id).await.unwrap();
            eprintln!("[TEST] K4 secure identity write complete");

            tls.flush().await.unwrap();
            eprintln!("[TEST] K5 flush complete");

            eprintln!("[TEST] K6 read Relay secure identity start");
            let line = tokio::time::timeout(Duration::from_secs(2), read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES))
                .await
                .expect("K6: read Relay secure identity timeout")
                .unwrap();
            eprintln!("[TEST] K7 read Relay secure identity complete");

            let remote_id = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();
            assert_eq!(remote_id.device_id, relay_id);
            assert_eq!(remote_id.protocol_version, PROTOCOL_VERSION);
            Ok::<(), anyhow::Error>(())
        });

        let (relay_res, phone_res) = tokio::join!(relay_task, phone_task);
        assert!(relay_res.unwrap().is_ok());
        assert!(phone_res.unwrap().is_ok());

        assert!(relay_inner.connections.lock().await.contains_key(&phone_id));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn v8_secure_identity_exchange_outbound() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let phone_id = phone_identity.device_id.clone();
        let relay_id = relay_identity.device_id.clone();

        let phone_identity_clone = phone_identity.clone();
        let phone_id_clone = phone_id.clone();
        let phone_task = tokio::spawn(async move {
            let (mut stream, _) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
                .await
                .expect("K0: accept timeout")
                .unwrap();
            // Read pre-TLS identity from Relay
            let line = tokio::time::timeout(Duration::from_secs(2), read_line_bounded(&mut stream, MAX_IDENTITY_PACKET_BYTES))
                .await
                .expect("K0: read pre-TLS line timeout")
                .unwrap();
            let _relay_pre = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // Phone is TCP server -> acts as TLS client
            eprintln!("[TEST] K1 TLS start as client");
            let mut tls = tokio::time::timeout(Duration::from_secs(2), start_tls_as_client(&phone_identity_clone, stream, &relay_id, None))
                .await
                .expect("K1: TLS client handshake timeout")
                .unwrap();
            eprintln!("[TEST] K1 TLS complete");

            eprintln!("[TEST] K2 secure identity serialize");
            let secure_id = phone_identity_clone.identity_packet(None).to_packet().serialize();

            eprintln!("[TEST] K3 secure identity write start");
            tls.write_all(&secure_id).await.unwrap();
            eprintln!("[TEST] K4 secure identity write complete");

            tls.flush().await.unwrap();
            eprintln!("[TEST] K5 flush complete");

            eprintln!("[TEST] K6 read Relay secure identity start");
            let line = tokio::time::timeout(Duration::from_secs(2), read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES))
                .await
                .expect("K6: read Relay secure identity timeout")
                .unwrap();
            eprintln!("[TEST] K7 read Relay secure identity complete");

            let remote_id = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();
            assert_eq!(remote_id.device_id, relay_id);
            assert_eq!(remote_id.protocol_version, PROTOCOL_VERSION);
            Ok::<(), anyhow::Error>(())
        });

        let relay_inner = LanInner::new(
            relay_identity.clone(),
            Vec::new(),
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            tokio::sync::mpsc::unbounded_channel().0,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_task = tokio::spawn(async move {
            tokio::time::timeout(
                Duration::from_secs(2),
                outbound_connect(relay_inner, addr.ip(), addr.port(), Some(phone_id_clone)),
            )
            .await
            .expect("Relay outbound_connect timeout")
        });

        let (phone_res, relay_res) = tokio::join!(phone_task, relay_task);
        assert!(phone_res.unwrap().is_ok());
        assert!(relay_res.unwrap().is_ok());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn v8_secure_identity_mismatch_rejected() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();

        let relay_inner = LanInner::new(
            relay_identity.clone(),
            Vec::new(),
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            tokio::sync::mpsc::unbounded_channel().0,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_task = tokio::spawn(async move {
            let (stream, peer_addr) = listener.accept().await.unwrap();
            inbound_tcp(relay_inner, stream, peer_addr).await
        });

        let phone_task = tokio::spawn(async move {
            let mut stream = TcpStream::connect(addr).await.unwrap();
            let pre_tls = phone_identity.identity_packet(Some(1716)).to_packet().serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();
            let mut tls = start_tls_as_server(&phone_identity, stream, None).await.unwrap();
            // Send mismatching protocol version post-TLS
            let mut bad_body = phone_identity.identity_packet(None);
            bad_body.protocol_version = 7; // Downgrade
            tls.write_all(&bad_body.to_packet().serialize()).await.unwrap();
            tls.flush().await.unwrap();
        });

        let (relay_res, _) = tokio::join!(relay_task, phone_task);
        assert!(relay_res.unwrap().is_err());
    }
}
