//! LAN discovery and the TCP/TLS link used for pairing.
//!
//! UDP identity broadcasts use port 1716. The TCP listener is bound in
//! 1716..=1764. After a plaintext identity exchange, TLS roles are reversed
//! relative to TCP: the TCP client is the TLS server.

use crate::kdeconnect::identity::{
    certificate_common_name, install_crypto_provider, LocalIdentity,
};
use crate::kdeconnect::packet::{
    is_valid_device_id, ClipboardBody, ConnectivityReportBody, FindMyPhoneBody, NetworkPacket,
    NotificationBody, PairBody, PingBody, RelayDeviceStateBody, RelayHeartbeatBody, SmsMessage,
    SmsRequestConversationBody, SmsRequestConversationsBody, MAX_IDENTITY_PACKET_BYTES,
    MAX_PACKET_BYTES, PROTOCOL_VERSION,
};
use crate::kdeconnect::pairing::{
    now_unix, PairState, PairingEffect, PairingFailReason, PairingSession, PAIRING_TIMEOUT_SECS,
};
use crate::kdeconnect::{
    DeviceSnapshot, KdeConnectEvent, KdeNotification, KdeSmsConversation, TrustedDevice,
};
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
use std::sync::atomic::{AtomicU64, Ordering};
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

/// A file announced by a control packet, waiting for its payload stream.
///
/// Held only between the announcement and the stream arriving; a stream that
/// never comes simply leaves an entry that is replaced or dropped, and no file
/// is ever created for it.
#[derive(Clone, Debug)]
pub(crate) struct PendingFile {
    pub device_id: String,
    pub transfer_id: String,
    pub filename: String,
    pub size: u64,
}

/// Maps a peer's advertised KDE packet types onto Relay's feature set.
///
/// A feature is present when the peer can take part in it at all -- either by
/// accepting Relay's requests or by sending Relay the data. Which direction
/// matters differs per feature, so each is stated explicitly rather than
/// guessed from one list.
fn relay_features_from_capabilities(
    incoming: &[String],
    outgoing: &[String],
) -> std::collections::BTreeSet<crate::kdeconnect::fabric::RelayFeature> {
    use crate::kdeconnect::fabric::RelayFeature;
    let accepts = |packet: &str| incoming.iter().any(|value| value == packet);
    let sends = |packet: &str| outgoing.iter().any(|value| value == packet);

    let mut features = std::collections::BTreeSet::new();
    if sends(crate::kdeconnect::PACKET_TYPE_NOTIFICATION) {
        features.insert(RelayFeature::Notifications);
    }
    if accepts(crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS) {
        features.insert(RelayFeature::Messages);
    }
    if accepts(crate::kdeconnect::PACKET_TYPE_MPRIS_REQUEST) || sends(crate::kdeconnect::PACKET_TYPE_MPRIS) {
        features.insert(RelayFeature::Media);
    }
    if sends(crate::kdeconnect::PACKET_TYPE_RUNCOMMAND_REQUEST) {
        features.insert(RelayFeature::Commands);
    }
    if sends(crate::kdeconnect::PACKET_TYPE_MOUSEPAD_REQUEST) {
        features.insert(RelayFeature::RemoteInput);
    }
    if accepts(crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT)
        || sends(crate::kdeconnect::PACKET_TYPE_CLIPBOARD)
    {
        features.insert(RelayFeature::Clipboard);
    }
    if accepts(crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST)
        || sends(crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST)
    {
        features.insert(RelayFeature::Files);
    }
    if sends(crate::kdeconnect::PACKET_TYPE_BATTERY) {
        features.insert(RelayFeature::Battery);
    }
    if accepts(crate::kdeconnect::PACKET_TYPE_PING) {
        features.insert(RelayFeature::Ping);
    }
    features
}

/// Where a reply produced while handling an inbound packet is sent: always the
/// transport the packet itself arrived on. Answering a `kdeconnect.relay.ping`
/// over a *different* route than it came in on would make one route's liveness
/// look like the other's.
#[derive(Clone)]
pub(crate) enum PacketReplyRoute {
    /// The LAN writer channel belonging to the connection that delivered the packet.
    Lan(mpsc::Sender<Vec<u8>>),
    /// Any registered non-LAN link, addressed through the transport trait
    /// rather than a concrete type. Relay WAN is the only implementation in
    /// production; keeping this abstract is also what lets a test drive a real
    /// WAN-priority route without an Iroh connection.
    #[cfg(feature = "kdeconnect-wan")]
    Wan(Arc<dyn crate::kdeconnect::wan::TransportLink>),
}

impl PacketReplyRoute {
    /// Human-readable name of the transport that delivered the request, for
    /// logs. This is the evidence that a feature is genuinely running over the
    /// route it appears to -- a surviving stale LAN link would show up here.
    pub(crate) fn label(&self) -> &'static str {
        match self {
            PacketReplyRoute::Lan(_) => "KdeLan",
            #[cfg(feature = "kdeconnect-wan")]
            PacketReplyRoute::Wan(_) => "RelayWan",
        }
    }

    async fn send(&self, packet: &NetworkPacket) {
        match self {
            PacketReplyRoute::Lan(tx) => {
                let _ = tx.send(packet.serialize()).await;
            }
            #[cfg(feature = "kdeconnect-wan")]
            PacketReplyRoute::Wan(link) => {
                let _ = link.send_packet(packet).await;
            }
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

    fn remove(&mut self, device_id: &str) {
        self.by_id.remove(device_id);
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

    fn set_wan_endpoint_id(&mut self, device_id: &str, endpoint_id: String) -> bool {
        let Some(device) = self.by_id.get_mut(device_id) else {
            return false;
        };
        if device.wan_endpoint_id.as_deref() == Some(endpoint_id.as_str()) {
            return false;
        }
        device.wan_endpoint_id = Some(endpoint_id);
        true
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BatteryState {
    pub current_charge: i32,
    pub is_charging: bool,
    pub threshold_event: Option<i32>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ConnectivityState {
    pub report: ConnectivityReportBody,
    pub stale: bool,
}

struct Conn {
    packets: mpsc::Sender<Vec<u8>>,
    peer_cert_der: Vec<u8>,
    name: String,
    device_type: String,
    protocol_version: i64,
    /// Distinguishes this `Conn` from any other ever installed for the same
    /// device_id, so a closing reader task can only evict the entry it
    /// itself installed rather than a newer connection that has since
    /// replaced it (see the reader-task cleanup in `finish_secure_link`).
    epoch: u64,
}

/// Relay-native heartbeat state, tracked per device regardless of which
/// transport (LAN or WAN) carried the most recent `kdeconnect.relay.ping` /
/// `kdeconnect.relay.pong`. A device whose pings go unanswered past
/// [`HEARTBEAT_TIMEOUT`] is treated as no longer live on that transport --
/// this is what lets a stale connection self-correct without waiting for a
/// TCP/TLS-level error.
#[derive(Clone, Copy, Debug, Default)]
struct HeartbeatState {
    last_rtt_ms: Option<i64>,
    last_seen_unix: Option<i64>,
}

/// How long a route may go unheard before it is dropped when it is the device's
/// *only* route.
///
/// Deliberately generous: dropping the sole route takes the device Offline, and
/// a brief stall on an otherwise healthy link should not do that.
#[cfg(feature = "kdeconnect-wan")]
const HEARTBEAT_TIMEOUT_SECS: i64 = 60;

/// How long a route may go unheard before it is dropped when the device has
/// *another* route available.
///
/// Much shorter than [`HEARTBEAT_TIMEOUT_SECS`], because the consequence is
/// different in kind: failing over LAN -> Relay WAN keeps the device connected
/// and reverses itself the moment LAN answers again (LAN outranks WAN at
/// priority 20 vs 15). Waiting the full sole-route budget here is what made a
/// Local -> Remote handoff look stalled after Wi-Fi disappeared, since a TCP
/// socket whose network is gone stays writable and produces no error to react
/// to.
///
/// Sized above the heartbeat probe interval so a single missed probe cannot
/// trigger a failover.
#[cfg(feature = "kdeconnect-wan")]
const FAILOVER_TIMEOUT_SECS: i64 = 12;

/// How often stale routes are re-examined. Cheap -- an in-memory scan over
/// trusted devices, no I/O -- so it runs far more often than the heartbeat
/// probe. Previously this ran every 15s, which added itself to whichever
/// timeout applied.
#[cfg(feature = "kdeconnect-wan")]
const ROUTE_SWEEP_INTERVAL: Duration = Duration::from_secs(3);

/// How often a live route is probed with a relay ping.
#[cfg(feature = "kdeconnect-wan")]
const HEARTBEAT_PROBE_INTERVAL: Duration = Duration::from_secs(15);

// The handoff budgets only behave as intended in a particular order, and each
// is easy to retune in isolation. Checked at compile time so a change that
// breaks the relationship fails the build rather than quietly reintroducing
// route flapping or a stalled Local -> Remote transition.
#[cfg(feature = "kdeconnect-wan")]
const _: () = {
    // Failing over must be cheaper than declaring the device Offline.
    assert!(FAILOVER_TIMEOUT_SECS < HEARTBEAT_TIMEOUT_SECS);
    // The sweep has to run several times inside the failover budget, or the
    // sweep interval becomes the real (and much coarser) transition latency.
    assert!(ROUTE_SWEEP_INTERVAL.as_secs() * 2 < FAILOVER_TIMEOUT_SECS as u64);
};

fn now_unix_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

/// A `TransportLink` over the existing LAN per-connection writer channel, so
/// KDE LAN participates in the same [`crate::kdeconnect::wan::TransportRouter`]
/// that Relay WAN links register with -- registering `RelayWan` for a device
/// that already has `KdeLan` here never creates a second logical device (see
/// `TransportRouter::register`). Payload sends are intentionally not routed
/// through this link: LAN payload transfer has its own existing path.
#[cfg(feature = "kdeconnect-wan")]
struct LanTransportLink {
    device_id: String,
    packets: mpsc::Sender<Vec<u8>>,
    /// Our own identity, used as the TLS server certificate on payload
    /// connections.
    identity: Arc<LocalIdentity>,
    /// The paired device's certificate. Payload connections are pinned to it, so
    /// a local process that merely guesses the port cannot complete the
    /// handshake.
    peer_cert: Vec<u8>,
}

#[cfg(feature = "kdeconnect-wan")]
impl crate::kdeconnect::wan::TransportLink for LanTransportLink {
    fn device_id(&self) -> &str {
        &self.device_id
    }

    fn kind(&self) -> crate::kdeconnect::wan::TransportKind {
        crate::kdeconnect::wan::TransportKind::KdeLan
    }

    fn state(&self) -> crate::kdeconnect::wan::TransportState {
        crate::kdeconnect::wan::TransportState::Local
    }

    fn metadata(&self) -> crate::kdeconnect::wan::TransportMetadata {
        crate::kdeconnect::wan::TransportMetadata {
            kind: self.kind(),
            state: self.state(),
            last_seen_unix: None,
            last_transition_reason: None,
        }
    }

    fn send_packet<'a>(
        &'a self,
        packet: &'a NetworkPacket,
    ) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<()>> {
        Box::pin(async move {
            self.packets
                .send(packet.serialize())
                .await
                .map_err(|_| anyhow::anyhow!("LAN writer channel for {} closed", self.device_id))
        })
    }

    /// Sends a payload using KDE Connect's LAN mechanism.
    ///
    /// The listener is bound and its port returned to the caller *before* this
    /// runs -- the port has to be inside the control packet, which must reach
    /// the peer before it can dial back. So this half only accepts the dial-back,
    /// completes the TLS handshake as the server, and streams.
    ///
    /// There is no Relay size ceiling here: the 20 MiB limit is a Relay WAN
    /// policy, and LAN carries files of any size exactly as KDE Connect does.
    fn send_payload<'a>(
        &'a self,
        request: crate::kdeconnect::wan::PayloadRequest<'a>,
    ) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<crate::kdeconnect::wan::PayloadOutcome>>
    {
        Box::pin(async move {
            let listener = request
                .lan_listener
                .context("LAN payload send requires a bound listener")?;
            let stream = listener.accept().await?;
            // The sender is the TLS *server* on a payload connection, which is
            // the reverse of the TCP direction.
            let mut tls =
                start_tls_as_server(&self.identity, stream, Some(&self.peer_cert)).await?;
            let on_progress = request.on_progress;
            crate::kdeconnect::files::lan_payload::stream_payload(
                request.source,
                &mut tls,
                request.payload_size,
                on_progress,
            )
            .await?;
            tokio::io::AsyncWriteExt::shutdown(&mut tls).await.ok();
            Ok(crate::kdeconnect::wan::PayloadOutcome::Sent)
        })
    }

    fn disconnect(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, ()> {
        // Lifecycle is owned by the LAN connection itself (see
        // `finish_secure_link`'s reader/writer tasks); the router never tears
        // down a LAN link directly.
        Box::pin(async move {})
    }

    fn health(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, bool> {
        Box::pin(async move { !self.packets.is_closed() })
    }
}

pub(crate) struct LanInner {
    pub identity: LocalIdentity,
    config: LanConfig,
    pub tcp_port: u16,
    devices: Mutex<DeviceTable>,
    trust: Mutex<TrustStore>,
    pairing: Mutex<HashMap<String, PairingSession>>,
    connections: Mutex<HashMap<String, Conn>>,
    battery: Mutex<HashMap<String, BatteryState>>,
    connectivity: Mutex<HashMap<String, ConnectivityState>>,
    clipboard: Mutex<HashMap<String, i64>>,
    notifications: Mutex<HashMap<String, Vec<KdeNotification>>>,
    sms: Mutex<HashMap<String, HashMap<i64, HashMap<i64, SmsMessage>>>>,
    peer_capabilities: Mutex<HashMap<String, (Vec<String>, Vec<String>)>>,
    last_connect: Mutex<HashMap<String, Instant>>,
    mismatches: Mutex<std::collections::HashSet<String>>,
    incoming: Mutex<std::collections::HashSet<String>>,
    event_tx: mpsc::UnboundedSender<KdeConnectEvent>,
    pub cancel: CancellationToken,
    conn_epoch: AtomicU64,
    /// Desktop-configured RunCommand allow-list. Owned here (not per device)
    /// because the commands belong to this machine; which device asked is
    /// carried in the request, not in the storage key.
    pub(crate) commands: Arc<crate::kdeconnect::commands::RunCommandRegistry>,
    command_runner: Mutex<Arc<dyn crate::kdeconnect::commands::CommandRunner>>,
    /// MPRIS players on this machine, once media support has been enabled.
    /// `None` when there is no session bus (headless, or a non-Linux build), in
    /// which case media requests are answered with an empty player list rather
    /// than being ignored.
    media: Mutex<Option<Arc<dyn crate::kdeconnect::media::MediaPlayerHost>>>,
    /// Remote-input backend, present only once the desktop user has authorised
    /// an input session. `None` means every input packet is refused.
    input: Mutex<Option<Arc<dyn crate::kdeconnect::input::RemoteInputBackend>>>,
    /// Desktop-side switch. Separate from the backend so a user can turn the
    /// feature off without tearing down an authorised session, and so being
    /// paired never implies permission to move the cursor.
    input_enabled: std::sync::atomic::AtomicBool,
    /// Loop suppression shared by both clipboard directions. One guard, not one
    /// per transport or per device: an echo must be caught wherever it returns
    /// from.
    clipboard_guard: Mutex<crate::kdeconnect::clipboard::ClipboardGuard>,
    /// User-facing clipboard sync switch. Being paired is never sufficient.
    clipboard_enabled: std::sync::atomic::AtomicBool,
    /// Every transfer, keyed by (device, transfer id). Never by filename or
    /// route, so two devices sending the same name stay independent.
    transfers: Mutex<crate::kdeconnect::files::TransferRegistry>,
    /// Announced files awaiting their payload stream, by `relayPayloadId`. An
    /// arriving stream whose id is not here has no announcement behind it and is
    /// dropped without a byte being written.
    pending_payloads: Mutex<HashMap<String, PendingFile>>,
    /// Where received files are written.
    download_dir: Mutex<Option<std::path::PathBuf>>,
    /// One input queue per logical device, so a burst from one phone cannot
    /// delay another's clicks.
    input_queues: Mutex<HashMap<String, Arc<crate::kdeconnect::input::InputQueue>>>,
    heartbeat: Mutex<HashMap<String, HeartbeatState>>,
    /// Last packet observed on each concrete route. This must remain
    /// transport-specific: WAN traffic is proof that the device is alive, but
    /// it must never keep a dead LAN socket classified as Local.
    #[cfg(feature = "kdeconnect-wan")]
    route_last_seen: Mutex<HashMap<(String, crate::kdeconnect::wan::TransportKind), i64>>,
    /// Devices with a live Relay WAN link. Kept separate from `connections`
    /// (which owns the LAN writer-channel lifecycle) rather than inserting a
    /// synthetic `Conn` -- `connected` below is `connections.contains_key(..)
    /// || wan_active.contains(..)`, so it stays live-derived either way.
    #[cfg(feature = "kdeconnect-wan")]
    wan_active: Mutex<std::collections::HashSet<String>>,
    /// Generation of the currently registered WAN receive task per logical
    /// device. A superseded task must not unregister its replacement when its
    /// old Iroh stream finally closes.
    #[cfg(feature = "kdeconnect-wan")]
    wan_epoch: Mutex<HashMap<String, u64>>,
    #[cfg(feature = "kdeconnect-wan")]
    pub(crate) router: crate::kdeconnect::wan::TransportRouter,
    #[cfg(feature = "kdeconnect-wan")]
    pub(crate) wan_bindings: Arc<crate::kdeconnect::wan::WanBindingRegistry>,
    #[cfg(feature = "kdeconnect-wan")]
    wan_runtime: Mutex<Option<Arc<crate::kdeconnect::wan::WanRuntime>>>,
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
        #[cfg(feature = "kdeconnect-wan")]
        let initial_wan_bindings = trusted
            .iter()
            .filter_map(|device| {
                let endpoint_id = device.wan_endpoint_id.as_deref()?.parse().ok()?;
                Some(crate::kdeconnect::wan::WanBinding {
                    kde_device_id: device.device_id.clone(),
                    endpoint_id,
                    display_name: device.name.clone(),
                    device_type: device.device_type.clone(),
                    capabilities: Vec::new(),
                    binding_version: 1,
                    updated_at_unix: device.paired_at_unix,
                    last_wan_connected_at_unix: None,
                    last_transport: None,
                })
            })
            .collect();
        let pairing = trusted
            .iter()
            .map(|d| (d.device_id.clone(), PairingSession::new(true)))
            .collect();
        Arc::new(Self {
            commands: Arc::new(crate::kdeconnect::commands::RunCommandRegistry::default()),
            command_runner: Mutex::new(Arc::new(crate::kdeconnect::commands::ShellCommandRunner)),
            media: Mutex::new(None),
            input: Mutex::new(None),
            input_enabled: std::sync::atomic::AtomicBool::new(false),
            clipboard_guard: Mutex::new(crate::kdeconnect::clipboard::ClipboardGuard::new()),
            clipboard_enabled: std::sync::atomic::AtomicBool::new(true),
            transfers: Mutex::new(crate::kdeconnect::files::TransferRegistry::new()),
            pending_payloads: Mutex::new(HashMap::new()),
            download_dir: Mutex::new(None),
            input_queues: Mutex::new(HashMap::new()),
            identity,
            config,
            tcp_port,
            devices: Mutex::new(DeviceTable::default()),
            trust: Mutex::new(TrustStore::from_list(trusted)),
            pairing: Mutex::new(pairing),
            connections: Mutex::new(HashMap::new()),
            battery: Mutex::new(HashMap::new()),
            connectivity: Mutex::new(HashMap::new()),
            clipboard: Mutex::new(HashMap::new()),
            notifications: Mutex::new(HashMap::new()),
            sms: Mutex::new(HashMap::new()),
            peer_capabilities: Mutex::new(HashMap::new()),
            last_connect: Mutex::new(HashMap::new()),
            mismatches: Mutex::new(std::collections::HashSet::new()),
            incoming: Mutex::new(std::collections::HashSet::new()),
            event_tx,
            cancel,
            conn_epoch: AtomicU64::new(0),
            heartbeat: Mutex::new(HashMap::new()),
            #[cfg(feature = "kdeconnect-wan")]
            route_last_seen: Mutex::new(HashMap::new()),
            #[cfg(feature = "kdeconnect-wan")]
            wan_active: Mutex::new(std::collections::HashSet::new()),
            #[cfg(feature = "kdeconnect-wan")]
            wan_epoch: Mutex::new(HashMap::new()),
            #[cfg(feature = "kdeconnect-wan")]
            router: crate::kdeconnect::wan::TransportRouter::new(),
            #[cfg(feature = "kdeconnect-wan")]
            wan_bindings: Arc::new(crate::kdeconnect::wan::WanBindingRegistry::new(initial_wan_bindings)),
            #[cfg(feature = "kdeconnect-wan")]
            wan_runtime: Mutex::new(None),
        })
    }

    pub async fn snapshot(&self) -> Vec<DeviceSnapshot> {
        let devices = self.devices.lock().await;
        let trust = self.trust.lock().await;
        let connections = self.connections.lock().await;
        let pairing = self.pairing.lock().await;
        let mismatches = self.mismatches.lock().await;
        let incoming = self.incoming.lock().await;
        let battery_map = self.battery.lock().await;
        let connectivity_map = self.connectivity.lock().await;
        let caps_map = self.peer_capabilities.lock().await;
        let heartbeat_map = self.heartbeat.lock().await;
        #[cfg(feature = "kdeconnect-wan")]
        let wan_active = self.wan_active.lock().await;
        let mut out = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for observed in devices.iter() {
            seen.insert(observed.device_id.clone());
            let paired = trust.get(&observed.device_id).is_some();
            let b = battery_map.get(&observed.device_id);
            let connectivity = connectivity_map.get(&observed.device_id);
            let selected = connectivity
                .and_then(|state| state.report.selected_signal().map(|(_, signal)| signal));
            let (inc, out_caps) = caps_map
                .get(&observed.device_id)
                .cloned()
                .unwrap_or_default();
            let hb = heartbeat_map.get(&observed.device_id).copied().unwrap_or_default();
            #[cfg(feature = "kdeconnect-wan")]
            let connected = connections.contains_key(&observed.device_id)
                || wan_active.contains(&observed.device_id);
            #[cfg(not(feature = "kdeconnect-wan"))]
            let connected = connections.contains_key(&observed.device_id);
            out.push(DeviceSnapshot {
                device_id: observed.device_id.clone(),
                name: observed.name.clone(),
                device_type: observed.device_type.clone(),
                ip: Some(observed.ip.to_string()),
                port: Some(observed.tcp_port),
                paired,
                connected,
                incoming_pair: incoming.contains(&observed.device_id),
                identity_mismatch: mismatches.contains(&observed.device_id),
                battery_percentage: b.map(|s| s.current_charge),
                battery_is_charging: b.map(|s| s.is_charging),
                network_type: selected.map(|signal| signal.network_type.clone()),
                signal_level: selected.map(|signal| signal.signal_strength as i32),
                connectivity_stale: connectivity.is_some_and(|state| state.stale),
                incoming_capabilities: inc,
                outgoing_capabilities: out_caps,
                #[cfg(feature = "kdeconnect-wan")]
                transport_kind: self.router.active_transport(&observed.device_id),
                #[cfg(feature = "kdeconnect-wan")]
                transport_state: self.router.snapshot(&observed.device_id).state,
                last_rtt_ms: hb.last_rtt_ms,
                last_seen_unix: hb.last_seen_unix,
            });
        }
        for trusted in trust.snapshot() {
            if seen.contains(&trusted.device_id) {
                continue;
            }
            let b = battery_map.get(&trusted.device_id);
            let connectivity = connectivity_map.get(&trusted.device_id);
            let selected = connectivity
                .and_then(|state| state.report.selected_signal().map(|(_, signal)| signal));
            let (inc, out_caps) = caps_map
                .get(&trusted.device_id)
                .cloned()
                .unwrap_or_default();
            let hb = heartbeat_map.get(&trusted.device_id).copied().unwrap_or_default();
            #[cfg(feature = "kdeconnect-wan")]
            let connected = connections.contains_key(&trusted.device_id)
                || wan_active.contains(&trusted.device_id);
            #[cfg(not(feature = "kdeconnect-wan"))]
            let connected = connections.contains_key(&trusted.device_id);
            out.push(DeviceSnapshot {
                device_id: trusted.device_id.clone(),
                name: trusted.name.clone(),
                device_type: trusted.device_type.clone(),
                ip: None,
                port: None,
                paired: true,
                connected,
                incoming_pair: pairing
                    .get(&trusted.device_id)
                    .is_some_and(|s| s.state == PairState::RequestedByPeer),
                identity_mismatch: mismatches.contains(&trusted.device_id),
                battery_percentage: b.map(|s| s.current_charge),
                battery_is_charging: b.map(|s| s.is_charging),
                network_type: selected.map(|signal| signal.network_type.clone()),
                signal_level: selected.map(|signal| signal.signal_strength as i32),
                connectivity_stale: connectivity.is_some_and(|state| state.stale),
                incoming_capabilities: inc,
                outgoing_capabilities: out_caps,
                #[cfg(feature = "kdeconnect-wan")]
                transport_kind: self.router.active_transport(&trusted.device_id),
                #[cfg(feature = "kdeconnect-wan")]
                transport_state: self.router.snapshot(&trusted.device_id).state,
                last_rtt_ms: hb.last_rtt_ms,
                last_seen_unix: hb.last_seen_unix,
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

    /// The one place device state reaches the product.
    ///
    /// Both the legacy snapshot and the Device Fabric are computed here from the
    /// same observation, so the two can never describe different moments, and
    /// one event still covers one change.
    async fn emit_devices(&self) {
        let devices = self.snapshot().await;
        let fabric = self.device_fabric().await;
        let _ = self
            .event_tx
            .send(KdeConnectEvent::DevicesChanged { devices, fabric });
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

    async fn record_heartbeat_seen(&self, device_id: &str) {
        let mut map = self.heartbeat.lock().await;
        map.entry(device_id.to_owned()).or_default().last_seen_unix = Some(now_unix());
    }

    async fn record_heartbeat_rtt(&self, device_id: &str, sent_at: i64) {
        let now_ms = now_unix_millis();
        let mut map = self.heartbeat.lock().await;
        let state = map.entry(device_id.to_owned()).or_default();
        state.last_seen_unix = Some(now_unix());
        // `sent_at` is this device's own clock; RTT is only meaningful when it
        // is not ahead of local time (best-effort, matching how `record_heartbeat_seen`
        // already tolerates clock skew by never trusting the peer's clock alone).
        if now_ms >= sent_at {
            state.last_rtt_ms = Some(now_ms - sent_at);
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn record_route_seen(
        &self,
        device_id: &str,
        kind: crate::kdeconnect::wan::TransportKind,
    ) {
        self.route_last_seen
            .lock()
            .await
            .insert((device_id.to_owned(), kind), now_unix());
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn local_wan_identity_packet(&self) -> Option<NetworkPacket> {
        let runtime = self.wan_runtime.lock().await.clone()?;
        Some(crate::kdeconnect::packet::RelayWanIdentityBody::new(
            runtime.endpoint_id().to_string(),
            self.identity.device_id.clone(),
        ))
    }

    fn local_device_state_packet(&self) -> NetworkPacket {
        crate::kdeconnect::packet::RelayDeviceStateBody::new(
            crate::kdeconnect::packet::RelayDeviceStateBody {
                protocol_version: Some(1),
                device_name: Some(self.identity.device_name.clone()),
                device_class: Some("desktop".to_owned()),
                os: Some(std::env::consts::OS.to_owned()),
                relay_version: Some(env!("CARGO_PKG_VERSION").to_owned()),
                capabilities: crate::kdeconnect::canonical_incoming_capabilities(),
                timestamp: Some(now_unix_millis()),
                ..Default::default()
            },
        )
    }


    /// Installs the MPRIS host. Idempotent; replacing it swaps the source of
    /// player state without disturbing any link.
    pub(crate) async fn set_media_host(
        self: &Arc<Self>,
        host: Arc<dyn crate::kdeconnect::media::MediaPlayerHost>,
    ) {
        *self.media.lock().await = Some(host.clone());
        self.spawn_media_change_pusher(host).await;
    }

    /// Pushes fresh player state to every paired, connected device whenever the
    /// desktop's players change.
    ///
    /// Without this the phone only ever sees state it explicitly asked for, so
    /// its now-playing view goes stale the moment a track changes on the
    /// desktop. Sends go through the `TransportRouter`, which picks LAN or Relay
    /// WAN per device on its own -- this code never learns which was used, and a
    /// Remote device is updated exactly like a Local one.
    #[cfg(feature = "kdeconnect-wan")]
    async fn spawn_media_change_pusher(
        self: &Arc<Self>,
        host: Arc<dyn crate::kdeconnect::media::MediaPlayerHost>,
    ) {
        let Some(mut changes) = host.subscribe().await else {
            return;
        };
        let inner = Arc::clone(self);
        tokio::spawn(async move {
            let mut last: Vec<crate::kdeconnect::media::PlayerSnapshot> = Vec::new();
            loop {
                tokio::select! {
                    _ = inner.cancel.cancelled() => break,
                    tick = changes.recv() => {
                        if tick.is_none() {
                            break;
                        }
                    }
                }
                // Coalesce the burst a single track change produces (Metadata,
                // PlaybackStatus and Position all fire within milliseconds).
                tokio::time::sleep(Duration::from_millis(150)).await;
                while changes.try_recv().is_ok() {}

                let players = host.players().await;
                let targets = inner.connected_paired_devices().await;
                if targets.is_empty() {
                    last = players;
                    continue;
                }

                let names: Vec<String> = players.iter().map(|p| p.name.clone()).collect();
                let last_names: Vec<String> = last.iter().map(|p| p.name.clone()).collect();
                if names != last_names {
                    let list = crate::kdeconnect::packet::MprisBody::player_list(&names);
                    for device_id in &targets {
                        let _ = inner.router.send_packet(device_id, &list).await;
                    }
                }
                for player in &players {
                    // Only actual changes go out; players are otherwise silent.
                    if last.iter().any(|previous| previous == player) {
                        continue;
                    }
                    let packet = player.to_body().to_packet();
                    for device_id in &targets {
                        let _ = inner.router.send_packet(device_id, &packet).await;
                    }
                }
                last = players;
            }
        });
    }

    #[cfg(not(feature = "kdeconnect-wan"))]
    async fn spawn_media_change_pusher(
        self: &Arc<Self>,
        _host: Arc<dyn crate::kdeconnect::media::MediaPlayerHost>,
    ) {
    }

    /// Paired devices with at least one live route, in a stable order.
    #[cfg(feature = "kdeconnect-wan")]
    async fn connected_paired_devices(&self) -> Vec<String> {
        let trusted: Vec<String> = self
            .trust
            .lock()
            .await
            .snapshot()
            .into_iter()
            .map(|device| device.device_id)
            .collect();
        let mut connected: Vec<String> = trusted
            .into_iter()
            .filter(|device_id| self.router.active_transport(device_id).is_some())
            .collect();
        connected.sort();
        connected
    }

    /// Swaps the process launcher. Tests use this to assert *what would have
    /// run* without running anything.
    #[cfg(test)]
    pub(crate) async fn set_command_runner(
        &self,
        runner: Arc<dyn crate::kdeconnect::commands::CommandRunner>,
    ) {
        *self.command_runner.lock().await = runner;
    }

    /// Replaces the RunCommand allow-list, as the desktop settings UI does.
    ///
    /// The new list is pushed to every connected paired device straight away.
    /// A phone only asks for the list when its plugin starts, so without this
    /// push it keeps showing whatever was configured at connect time -- a
    /// command added while the phone is already connected would stay invisible
    /// until it reconnected. The push goes through the `TransportRouter`, so a
    /// Local device gets it over LAN and a Remote one over Relay WAN, with no
    /// transport-specific code here.
    #[cfg(feature = "kdeconnect-wan")]
    pub(crate) fn set_run_commands(
        self: &Arc<Self>,
        entries: Vec<crate::kdeconnect::commands::RunCommandEntry>,
    ) {
        self.commands.replace(entries);
        let inner = Arc::clone(self);
        tokio::spawn(async move {
            let packet = crate::kdeconnect::packet::RunCommandListBody::to_packet(
                &inner.commands.advertised(),
            );
            for device_id in inner.connected_paired_devices().await {
                tracing::info!("[Relay RunCommand] device={device_id} pushing updated commandList");
                let _ = inner.router.send_packet(&device_id, &packet).await;
            }
        });
    }

    #[cfg(not(feature = "kdeconnect-wan"))]
    pub(crate) fn set_run_commands(
        self: &Arc<Self>,
        entries: Vec<crate::kdeconnect::commands::RunCommandEntry>,
    ) {
        self.commands.replace(entries);
    }

    /// The Device Fabric: one record per trusted logical device, plus the local
    /// feature policy that was in force when it was read.
    ///
    /// Assembled from live state each time rather than cached, so it cannot
    /// disagree with the routes, trust store and capability sets it summarises.
    /// A device that is reachable over both LAN and WAN appears exactly once,
    /// with both routes recorded against it.
    ///
    /// The policy travels with the records because availability is a function of
    /// both: reading them separately could produce an answer that neither state
    /// ever actually justified.
    pub(crate) async fn device_fabric(&self) -> crate::kdeconnect::fabric::RelayFabricSnapshot {
        use crate::kdeconnect::fabric::{
            LocalFeaturePolicy, RelayDeviceClass, RelayDeviceRecord, RelayFabricSnapshot,
        };

        let trusted = self.trust.lock().await.snapshot();
        let battery = self.battery.lock().await.clone();
        let capabilities = self.peer_capabilities.lock().await.clone();
        #[cfg(not(feature = "kdeconnect-wan"))]
        let heartbeat = self.heartbeat.lock().await.clone();
        #[cfg(feature = "kdeconnect-wan")]
        let route_last_seen = self.route_last_seen.lock().await.clone();
        let connections = self.connections.lock().await;

        let mut records = Vec::with_capacity(trusted.len());
        for device in trusted {
            let id = device.device_id.clone();
            let mut record = RelayDeviceRecord::remembered(
                id.clone(),
                device.name.clone(),
                RelayDeviceClass::from_peer_string(&device.device_type),
            );
            record.platform = Some(device.device_type.clone());
            record.relay_version = Some(device.protocol_version.to_string());

            // Route availability is runtime truth, read from the router rather
            // than from anything persisted.
            #[cfg(feature = "kdeconnect-wan")]
            {
                use crate::kdeconnect::wan::TransportKind;
                let transports = self.router.available_transports(&id);
                record.routes.lan_available =
                    transports.contains(&TransportKind::KdeLan) && connections.contains_key(&id);
                record.routes.wan_available = transports.contains(&TransportKind::RelayWan);
                record.routes.wan_bound = device.wan_endpoint_id.is_some();
                record.routes.wan_relayed = self.router.snapshot(&id).state
                    == crate::kdeconnect::wan::TransportState::RemoteRelay;
                record.routes.lan_last_seen = route_last_seen
                    .get(&(id.clone(), TransportKind::KdeLan))
                    .copied();
                record.routes.wan_last_seen = route_last_seen
                    .get(&(id.clone(), TransportKind::RelayWan))
                    .copied();
            }
            #[cfg(not(feature = "kdeconnect-wan"))]
            {
                // Without the WAN feature there is exactly one route, and the
                // live LAN session is the only evidence of it.
                record.routes.lan_available = connections.contains_key(&id);
                record.routes.lan_last_seen =
                    heartbeat.get(&id).and_then(|state| state.last_seen_unix);
            }
            record.refresh_connection(false);

            // Capabilities belong to the logical device, taken from what the
            // peer advertised over whichever transport introduced it.
            if let Some((incoming, outgoing)) = capabilities.get(&id) {
                record.capabilities = relay_features_from_capabilities(incoming, outgoing);
            }

            if let Some(state) = battery.get(&id) {
                record.battery_percent = Some(state.current_charge);
                record.charging = Some(state.is_charging);
            }
            records.push(record);
        }
        drop(connections);
        records.sort_by(|a, b| a.id.cmp(&b.id));

        let policy = LocalFeaturePolicy {
            clipboard_enabled: self.clipboard_enabled(),
            remote_input_enabled: self.input_enabled(),
            remote_input_authorized: self.input_ready().await,
            has_configured_commands: !self.commands.snapshot().is_empty(),
        };
        RelayFabricSnapshot {
            devices: records,
            policy,
        }
    }

    pub(crate) async fn set_download_dir(&self, directory: std::path::PathBuf) {
        *self.download_dir.lock().await = Some(directory);
    }

    /// Transfers for one logical device.
    pub(crate) async fn transfers_for(
        &self,
        device_id: &str,
    ) -> Vec<crate::kdeconnect::files::Transfer> {
        self.transfers
            .lock()
            .await
            .for_device(device_id)
            .into_iter()
            .cloned()
            .collect()
    }

    /// Sends one file to a logical device.
    ///
    /// The route is decided first, then the policy: LAN keeps its existing
    /// behaviour with no size ceiling, while a remote route refuses anything
    /// over the 20 MiB limit **before** a byte moves. Starting a transfer and
    /// abandoning it partway would waste the user's data and time on a result
    /// that was knowable up front.
    ///
    /// Whichever transport is selected here owns the transfer for its lifetime;
    /// Relay does not migrate a payload mid-stream.
    #[cfg(feature = "kdeconnect-wan")]
    pub(crate) async fn send_file(
        self: &Arc<Self>,
        device_id: &str,
        path: &std::path::Path,
    ) -> Result<String> {
        use crate::kdeconnect::files::{
            check_sendable, generate_transfer_id, Transfer, TransferKey, TransferRejection,
            TransferState,
        };
        use crate::kdeconnect::wan::TransportKind;

        if self.trust.lock().await.get(device_id).is_none() {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(device_id, crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST)
            .await?;

        let filename = path
            .file_name()
            .and_then(|name| name.to_str())
            .context("file has no usable name")?
            .to_owned();
        let size = tokio::fs::metadata(path)
            .await
            .context("read the file size")?
            .len();

        let active = self.router.active_transport(device_id);
        let remote = active == Some(TransportKind::RelayWan);
        let transfer_id = generate_transfer_id();
        let key = TransferKey::new(device_id, &transfer_id);

        // No transport at all: nothing to announce over.
        if active.is_none() {
            self.transfers.lock().await.insert(Transfer {
                key: key.clone(),
                filename,
                total_bytes: size,
                state: TransferState::Failed {
                    reason: "This device is not connected.".to_owned(),
                },
            });
            self.emit_transfer(&key).await;
            return Ok(transfer_id);
        }

        // `remote` is what makes the size ceiling apply: LAN carries files of
        // any size, exactly as KDE Connect does, and the 20 MiB limit is a
        // Relay WAN policy alone.
        match check_sendable(Some(size), remote) {
            Ok(_) => {}
            Err(TransferRejection::RequiresLocalConnection { .. } | TransferRejection::UnknownSize) => {
                // A policy outcome, not a failure: recorded as its own state so
                // the UI can say "Local connection required" rather than
                // presenting it as a network error.
                self.transfers.lock().await.insert(Transfer {
                    key: key.clone(),
                    filename,
                    total_bytes: size,
                    state: TransferState::RequiresLocalConnection,
                });
                self.emit_transfer(&key).await;
                return Ok(transfer_id);
            }
            Err(other) => anyhow::bail!(other),
        }

        self.transfers.lock().await.insert(Transfer {
            key: key.clone(),
            filename: filename.clone(),
            total_bytes: size,
            state: TransferState::Preparing,
        });
        self.emit_transfer(&key).await;

        let inner = Arc::clone(self);
        let device_id = device_id.to_owned();
        let path = path.to_path_buf();
        tokio::spawn(async move {
            if let Err(error) = inner
                .stream_file_out(&device_id, &key, &path, &filename, size, remote)
                .await
            {
                tracing::warn!(
                    "[Relay Files] device={device_id} transfer={} failed: {error}",
                    key.transfer_id
                );
                inner.fail_transfer(&key, "the transfer could not be completed").await;
            }
        });
        Ok(transfer_id)
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn stream_file_out(
        self: &Arc<Self>,
        device_id: &str,
        key: &crate::kdeconnect::files::TransferKey,
        path: &std::path::Path,
        filename: &str,
        size: u64,
        remote: bool,
    ) -> Result<()> {
        use crate::kdeconnect::files::TransferState;
        use crate::kdeconnect::wan::{payload::WanPayloadTransferInfo, PayloadRequest};

        // The correlation id only means anything on WAN; LAN payload transfer
        // uses KDE's own port-based mechanism.
        let info = remote
            .then(|| WanPayloadTransferInfo::new(size))
            .transpose()
            .map_err(|error| anyhow::anyhow!(error))?;

        // A LAN listener must exist *before* the announcement goes out: the
        // packet carries the port the receiver dials back to, so binding it
        // afterwards would advertise a port nothing is listening on.
        let lan_listener = if remote {
            None
        } else {
            Some(crate::kdeconnect::files::lan_payload::PayloadListener::bind().await?)
        };

        let announcement = crate::kdeconnect::packet::ShareRequestBody::to_packet(
            filename,
            size,
            info.as_ref().map(|info| info.relay_payload_id.as_str()),
            lan_listener.as_ref().map(|listener| listener.port()),
        );
        self.router.send_packet(device_id, &announcement).await?;

        let mut file = tokio::fs::File::open(path).await.context("open the file to send")?;
        let links = self.router.links_for(device_id);
        let link = links.first().context("no transport available")?;

        // Progress is funnelled through a channel so the copy loop never awaits
        // event publication, and so the throttling lives in one place.
        let (progress_tx, mut progress_rx) = tokio::sync::mpsc::unbounded_channel::<u64>();
        let progress_inner = Arc::clone(self);
        let progress_key = key.clone();
        let progress_task = tokio::spawn(async move {
            while let Some(sent) = progress_rx.recv().await {
                let publish = progress_inner
                    .transfers
                    .lock()
                    .await
                    .advance(&progress_key, sent, false);
                if publish {
                    progress_inner.emit_transfer(&progress_key).await;
                }
            }
        });
        let on_progress_guard = progress_tx.clone();
        let mut on_progress = move |sent: u64| {
            let _ = progress_tx.send(sent);
        };
        let request = PayloadRequest {
            relay_payload_id: info
                .as_ref()
                .map(|info| info.relay_payload_id.as_str())
                .unwrap_or_default(),
            payload_size: size,
            source: &mut file,
            lan_listener,
            on_progress: &mut on_progress,
        };
        let outcome = link.send_payload(request).await;
        drop(on_progress_guard);
        let _ = progress_task.await;
        outcome?;

        self.transfers
            .lock()
            .await
            .finish(key, TransferState::Completed { total: size });
        self.emit_transfer(key).await;
        tracing::info!(
            "[Relay Files] device={device_id} transfer={} sent bytes={size}",
            key.transfer_id
        );
        Ok(())
    }

    /// Handles a `kdeconnect.share.request` announcing an incoming file.
    ///
    /// Registers the pending transfer; the bytes arrive separately on their own
    /// payload stream. Nothing is written to disk here.
    async fn handle_share_request(
        self: &Arc<Self>,
        device_id: &str,
        share: crate::kdeconnect::packet::ShareRequestBody,
    ) {
        use crate::kdeconnect::files::{sanitize_filename, Transfer, TransferKey, TransferState};

        if self.trust.lock().await.get(device_id).is_none() {
            tracing::warn!("[Relay Files] refused a file from untrusted device={device_id}");
            return;
        }
        let Some(size) = share.total_payload_size else {
            tracing::warn!(
                "[Relay Files] device={device_id} announced a file with no usable size; ignored"
            );
            return;
        };
        // The ceiling applies only to a Relay WAN announcement. A LAN sender may
        // offer a file of any size, exactly as KDE Connect does, so applying
        // this unconditionally would refuse ordinary local transfers.
        if share.relay_payload_id.is_some()
            && size > crate::kdeconnect::files::MAX_WAN_PAYLOAD_BYTES
        {
            tracing::warn!(
                "[Relay Files] device={device_id} announced {size} bytes, over the remote limit"
            );
            return;
        }

        let filename = sanitize_filename(&share.filename);
        let transfer_id = crate::kdeconnect::files::generate_transfer_id();
        let key = TransferKey::new(device_id, &transfer_id);
        self.transfers.lock().await.insert(Transfer {
            key: key.clone(),
            filename: filename.clone(),
            total_bytes: size,
            state: TransferState::Preparing,
        });

        tracing::info!(
            "[Relay Files] device={device_id} transfer={transfer_id} incoming file bytes={size}"
        );
        self.emit_transfer(&key).await;

        match (share.relay_payload_id, share.lan_port) {
            // Relay WAN: the sender opens a stream on the existing connection,
            // so all we can do is remember the correlation and wait for it.
            (Some(relay_payload_id), _) => {
                self.pending_payloads.lock().await.insert(
                    relay_payload_id,
                    PendingFile {
                        device_id: device_id.to_owned(),
                        transfer_id,
                        filename,
                        size,
                    },
                );
            }
            // KDE LAN: *we* dial back to the port the sender advertised.
            (None, Some(port)) => {
                let inner = Arc::clone(self);
                let device_id = device_id.to_owned();
                tokio::spawn(async move {
                    inner.fetch_lan_payload(&device_id, key, filename, size, port).await;
                });
            }
            (None, None) => {
                tracing::warn!(
                    "[Relay Files] device={device_id} announced a file with no payload transport"
                );
                self.fail_transfer(&key, "the sender offered no way to transfer the file").await;
            }
        }
    }

    /// Connects to a LAN sender's payload port and streams the file to disk.
    ///
    /// The address comes from the *existing control session*, never from the
    /// packet: a paired device may nominate a port, but it may not redirect
    /// Relay to some other host. The TLS handshake is pinned to that device's
    /// certificate, so a local process which merely guessed the port cannot
    /// deliver a file.
    async fn fetch_lan_payload(
        self: &Arc<Self>,
        device_id: &str,
        key: crate::kdeconnect::files::TransferKey,
        filename: String,
        size: u64,
        port: u16,
    ) {
        let Some(address) = self
            .devices
            .lock()
            .await
            .get(device_id)
            .map(|observed| observed.ip)
        else {
            self.fail_transfer(&key, "the sending device is no longer reachable").await;
            return;
        };
        let Some(peer_cert) = self
            .trust
            .lock()
            .await
            .get(device_id)
            .and_then(|device| device.certificate_der().ok())
        else {
            self.fail_transfer(&key, "the sending device is not paired").await;
            return;
        };

        let stream =
            match crate::kdeconnect::files::lan_payload::connect_to_payload(address, port).await {
                Ok(stream) => stream,
                Err(error) => {
                    tracing::warn!("[Relay Files] transfer={} payload connect failed: {error}", key.transfer_id);
                    self.fail_transfer(&key, "could not open the file connection").await;
                    return;
                }
            };
        // The receiver is the TLS client on a payload connection.
        let mut tls = match start_tls_as_client(&self.identity, stream, device_id, Some(&peer_cert))
            .await
        {
            Ok(tls) => tls,
            Err(error) => {
                tracing::warn!("[Relay Files] transfer={} payload TLS failed: {error}", key.transfer_id);
                self.fail_transfer(&key, "the file connection could not be secured").await;
                return;
            }
        };

        // No ceiling on LAN: the 20 MiB limit is a Relay WAN policy.
        self.receive_payload_stream(&key, &filename, size, None, &mut tls).await;
    }

    /// Streams an arriving payload to disk, correlated to its announcement.
    ///
    /// An id with no pending announcement is dropped: matching a `relayPayloadId`
    /// is never on its own sufficient reason to accept file content.
    #[cfg(feature = "kdeconnect-wan")]
    async fn handle_incoming_payload<R>(
        self: &Arc<Self>,
        relay_payload_id: &str,
        payload_size: u64,
        stream: &mut R,
    ) where
        R: tokio::io::AsyncRead + Unpin,
    {
        use crate::kdeconnect::files::TransferKey;

        let Some(pending) = self.pending_payloads.lock().await.remove(relay_payload_id) else {
            tracing::warn!("[Relay Files] dropped a payload with no matching announcement");
            return;
        };
        let key = TransferKey::new(&pending.device_id, &pending.transfer_id);
        if payload_size != pending.size {
            tracing::warn!(
                "[Relay Files] transfer={} declared {} but the stream declared {payload_size}",
                pending.transfer_id,
                pending.size
            );
            self.fail_transfer(&key, "declared size mismatch").await;
            return;
        }

        self.receive_payload_stream(
            &key,
            &pending.filename,
            payload_size,
            Some(crate::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES),
            stream,
        )
        .await;
    }

    /// Streams any payload source to disk, whatever transport produced it.
    ///
    /// This is the single receive path: LAN's pinned-TLS socket and WAN's Iroh
    /// stream both arrive here as `AsyncRead`, and share the same bounded
    /// copying, filename safety, temp-file/atomic finalize, progress throttling
    /// and terminal-state handling. The feature layer genuinely does not know
    /// which transport delivered the bytes.
    async fn receive_payload_stream<R>(
        self: &Arc<Self>,
        key: &crate::kdeconnect::files::TransferKey,
        filename: &str,
        payload_size: u64,
        limit: Option<u64>,
        stream: &mut R,
    ) where
        R: tokio::io::AsyncRead + Unpin,
    {
        use crate::kdeconnect::files::{receive::IncomingFile, TransferState};

        let directory = match self.download_dir.lock().await.clone() {
            Some(directory) => directory,
            None => {
                self.fail_transfer(key, "no download directory configured").await;
                return;
            }
        };
        let mut incoming = match IncomingFile::create(&directory, filename, payload_size, limit).await
        {
            Ok(incoming) => incoming,
            Err(error) => {
                tracing::warn!("[Relay Files] transfer={} could not start: {error}", key.transfer_id);
                self.fail_transfer(key, "could not create the destination file").await;
                return;
            }
        };

        // Progress is sampled into a channel rather than awaited inline, so the
        // copy loop never blocks on event emission.
        let (progress_tx, mut progress_rx) = tokio::sync::mpsc::unbounded_channel::<u64>();
        let progress_inner = Arc::clone(self);
        let progress_key = key.clone();
        let progress_task = tokio::spawn(async move {
            while let Some(written) = progress_rx.recv().await {
                let publish = progress_inner
                    .transfers
                    .lock()
                    .await
                    .advance(&progress_key, written, true);
                if publish {
                    progress_inner.emit_transfer(&progress_key).await;
                }
            }
        });

        let result = incoming
            .stream_from(stream, |written| {
                let _ = progress_tx.send(written);
            })
            .await;
        drop(progress_tx);
        let _ = progress_task.await;

        // A transfer cancelled while streaming must never later report success.
        if self.is_cancelled(key).await {
            incoming.cancel().await;
            return;
        }

        match result {
            Ok(()) => match incoming.finalize().await {
                Ok(_path) => {
                    tracing::info!(
                        "[Relay Files] device={} transfer={} completed bytes={payload_size}",
                        key.device_id,
                        key.transfer_id
                    );
                    self.transfers
                        .lock()
                        .await
                        .finish(key, TransferState::Completed { total: payload_size });
                    self.emit_transfer(key).await;
                }
                Err(error) => {
                    tracing::warn!("[Relay Files] transfer={} failed to finalize: {error}", key.transfer_id);
                    self.fail_transfer(key, "the file could not be completed").await;
                }
            },
            Err(error) => {
                tracing::warn!("[Relay Files] transfer={} failed: {error}", key.transfer_id);
                // Dropping `incoming` removes the partial file.
                self.fail_transfer(key, "the transfer ended early").await;
            }
        }
    }

    /// Cancels an active transfer.
    ///
    /// Marks it cancelled immediately so the streaming loop's completion check
    /// discards its output, drops any pending payload correlation so a late
    /// stream finds nothing to attach to, and lets the receiver's `Drop` remove
    /// the partial file. A cancelled transfer can never later become Completed.
    pub(crate) async fn cancel_transfer(&self, device_id: &str, transfer_id: &str) {
        use crate::kdeconnect::files::{TransferKey, TransferState};
        let key = TransferKey::new(device_id, transfer_id);
        {
            let mut transfers = self.transfers.lock().await;
            match transfers.get(&key) {
                // Cancelling something already finished would rewrite history.
                Some(transfer) if transfer.state.is_terminal() => return,
                None => return,
                _ => {}
            }
            transfers.finish(&key, TransferState::Cancelled);
        }
        // Any payload still on its way now has no announcement to bind to.
        self.pending_payloads
            .lock()
            .await
            .retain(|_, pending| pending.transfer_id != transfer_id);
        tracing::info!("[Relay Files] device={device_id} transfer={transfer_id} cancelled");
        self.emit_transfer(&key).await;
    }

    /// Whether a transfer has been cancelled, so a completing stream can be
    /// discarded rather than published.
    async fn is_cancelled(&self, key: &crate::kdeconnect::files::TransferKey) -> bool {
        matches!(
            self.transfers.lock().await.get(key).map(|t| &t.state),
            Some(crate::kdeconnect::files::TransferState::Cancelled)
        )
    }

    async fn fail_transfer(&self, key: &crate::kdeconnect::files::TransferKey, reason: &str) {
        self.transfers.lock().await.finish(
            key,
            crate::kdeconnect::files::TransferState::Failed {
                reason: reason.to_owned(),
            },
        );
        self.emit_transfer(key).await;
    }

    async fn emit_transfer(&self, key: &crate::kdeconnect::files::TransferKey) {
        let transfer = self.transfers.lock().await.get(key).cloned();
        if let Some(transfer) = transfer {
            let _ = self.event_tx.send(KdeConnectEvent::TransferChanged { transfer });
        }
    }

    pub(crate) fn set_clipboard_enabled(&self, enabled: bool) {
        self.clipboard_enabled
            .store(enabled, std::sync::atomic::Ordering::SeqCst);
    }

    pub(crate) fn clipboard_enabled(&self) -> bool {
        self.clipboard_enabled.load(std::sync::atomic::Ordering::SeqCst)
    }

    /// Applies an incoming clipboard packet, or explains why it was refused.
    ///
    /// Content never reaches the log -- only the device, the length and a short
    /// hash prefix, which is enough to correlate a send with its receive.
    async fn handle_clipboard(
        &self,
        device_id: &str,
        clipboard: crate::kdeconnect::packet::ClipboardBody,
    ) {
        use crate::kdeconnect::clipboard::{hash_prefix, ClipboardRejection};
        let now_ms = now_unix_millis();
        let trusted = self.trust.lock().await.get(device_id).is_some();
        let enabled = self.clipboard_enabled();
        let decision = {
            let mut guard = self.clipboard_guard.lock().await;
            guard.should_apply_remote(&clipboard.content, enabled, trusted, now_ms)
        };
        match decision {
            Ok(hash) => {
                tracing::info!(
                    "[Relay Clipboard] device={device_id} direction=in bytes={} hash={}",
                    clipboard.content.len(),
                    hash_prefix(hash)
                );
                // Marked *before* the event is emitted: the local watcher will
                // observe the resulting write, and must recognise it as ours.
                self.clipboard_guard
                    .lock()
                    .await
                    .note_handled(&clipboard.content, now_ms);
                let _ = self.event_tx.send(KdeConnectEvent::ClipboardReceived {
                    device_id: device_id.to_string(),
                    content: clipboard.content,
                    timestamp_ms: clipboard.timestamp.unwrap_or(now_ms),
                });
            }
            Err(ClipboardRejection::Duplicate) => {
                // Expected and benign: this is loop suppression working.
                tracing::debug!("[Relay Clipboard] device={device_id} direction=in ignored=duplicate");
            }
            Err(rejection) => {
                tracing::warn!(
                    "[Relay Clipboard] device={device_id} direction=in refused={rejection} bytes={}",
                    clipboard.content.len()
                );
            }
        }
    }

    /// Installs the remote-input backend, which only exists once the desktop
    /// user has approved an input session.
    pub(crate) async fn set_input_backend(
        &self,
        backend: Option<Arc<dyn crate::kdeconnect::input::RemoteInputBackend>>,
    ) {
        *self.input.lock().await = backend;
    }

    pub(crate) fn set_input_enabled(&self, enabled: bool) {
        self.input_enabled
            .store(enabled, std::sync::atomic::Ordering::SeqCst);
    }

    pub(crate) fn input_enabled(&self) -> bool {
        self.input_enabled.load(std::sync::atomic::Ordering::SeqCst)
    }

    pub(crate) async fn input_ready(&self) -> bool {
        self.input
            .lock()
            .await
            .as_ref()
            .is_some_and(|backend| backend.is_ready())
    }

    /// Decides whether `device_id` may inject input right now.
    ///
    /// All three conditions are required, and being paired is only one of them:
    /// a trusted phone still cannot touch the desktop unless the user switched
    /// the feature on *and* approved an OS-level input session. Transport is
    /// deliberately not consulted -- a WAN peer is already bound to a trusted
    /// KDE device id before any packet is dispatched, so it can neither gain nor
    /// lose permission by being remote.
    async fn remote_input_gate(
        &self,
        device_id: &str,
    ) -> Result<Arc<dyn crate::kdeconnect::input::RemoteInputBackend>, crate::kdeconnect::input::RemoteInputRejection>
    {
        use crate::kdeconnect::input::RemoteInputRejection;
        if self.trust.lock().await.get(device_id).is_none() {
            return Err(RemoteInputRejection::DeviceNotTrusted);
        }
        if !self.input_enabled() {
            return Err(RemoteInputRejection::Disabled);
        }
        let backend = self.input.lock().await.clone();
        match backend {
            Some(backend) if backend.is_ready() => Ok(backend),
            _ => Err(RemoteInputRejection::NoSession),
        }
    }

    /// The input queue for `device_id`, started on first use.
    async fn input_queue_for(
        &self,
        device_id: &str,
        backend: Arc<dyn crate::kdeconnect::input::RemoteInputBackend>,
    ) -> Arc<crate::kdeconnect::input::InputQueue> {
        let mut queues = self.input_queues.lock().await;
        queues
            .entry(device_id.to_owned())
            .or_insert_with(|| Arc::new(crate::kdeconnect::input::InputQueue::start(backend)))
            .clone()
    }

    /// Handles one `kdeconnect.mousepad.request`.
    ///
    /// Pointer motion arrives at touch-sample rates, so events are handed to a
    /// per-device queue that coalesces consecutive motion while preserving every
    /// click and keystroke in order. Injection happens on that queue's task, off
    /// the packet-dispatch path, so a slow compositor cannot stall the link.
    async fn handle_remote_input(
        self: &Arc<Self>,
        device_id: &str,
        request: crate::kdeconnect::packet::MousePadRequestBody,
    ) {
        let backend = match self.remote_input_gate(device_id).await {
            Ok(backend) => backend,
            Err(rejection) => {
                tracing::warn!("[Relay Input] device={device_id} refused: {rejection}");
                return;
            }
        };
        let events = crate::kdeconnect::input::events_for(&request);
        if events.is_empty() {
            return;
        }
        self.input_queue_for(device_id, backend)
            .await
            .submit(events)
            .await;
    }

    /// Answers one `kdeconnect.mpris.request` from `device_id`.
    ///
    /// Talking to D-Bus can block for as long as the slowest player takes to
    /// answer, so the work is moved onto its own task: the packet dispatcher
    /// must not stall a device's whole link (nor every other device) behind one
    /// unresponsive media player. The reply goes back over `reply`, the route
    /// the request arrived on, which is what makes this work identically on LAN
    /// and over Relay WAN with no transport-specific code.
    async fn handle_mpris_request(
        self: &Arc<Self>,
        device_id: &str,
        request: crate::kdeconnect::packet::MprisRequestBody,
        reply: &PacketReplyRoute,
    ) {
        let Some(media) = self.media.lock().await.clone() else {
            // No session bus: answer honestly with an empty list rather than
            // leaving the phone waiting for a reply that never comes.
            tracing::warn!(
                "[Relay MPRIS] device={device_id} route={} request arrived but media control is not available",
                reply.label()
            );
            if request.request_player_list {
                reply
                    .send(&crate::kdeconnect::packet::MprisBody::player_list(&[]))
                    .await;
            }
            return;
        };

        let route = reply.label();
        let reply = reply.clone();
        let device_id = device_id.to_owned();
        tokio::spawn(async move {
            if request.request_player_list {
                let players = media.players().await;
                let names: Vec<String> = players.iter().map(|p| p.name.clone()).collect();
                tracing::info!(
                    "[Relay MPRIS] device={device_id} route={route} playerList players={}",
                    names.len()
                );
                reply
                    .send(&crate::kdeconnect::packet::MprisBody::player_list(&names))
                    .await;
            }

            let Some(player_name) = request.player.clone() else {
                return;
            };

            for command in crate::kdeconnect::media::PlayerCommand::from_request(&request) {
                tracing::info!("[Relay MPRIS] device={device_id} route={route} command={command:?}");
                if let Err(error) = media.control(&player_name, command).await {
                    tracing::warn!("[Relay MPRIS] device={device_id} command failed: {error}");
                }
            }

            // Any request naming a player gets fresh state back, whether it
            // asked for it or not: the phone's UI has just acted and needs to
            // see the result, and upstream behaves the same way.
            match media.player(&player_name).await {
                Some(snapshot) => {
                    tracing::info!(
                        "[Relay MPRIS] device={device_id} route={route} state player={} playing={}",
                        snapshot.name,
                        snapshot.is_playing
                    );
                    reply.send(&snapshot.to_body().to_packet()).await
                }
                None => {
                    // The player disappeared (closed between request and
                    // reply). Re-advertise the list so the phone drops it
                    // instead of showing a player that is gone.
                    tracing::info!("[Relay MPRIS] device={device_id} route={route} addressed an unknown player");
                    let names: Vec<String> =
                        media.players().await.into_iter().map(|p| p.name).collect();
                    reply
                        .send(&crate::kdeconnect::packet::MprisBody::player_list(&names))
                        .await;
                }
            }
        });
    }

    /// Answers one `kdeconnect.runcommand.request` from `device_id`.
    ///
    /// Every execution is gated on the requesting *logical device* being
    /// trusted, on the id naming a configured entry, and on that entry being
    /// enabled -- see [`crate::kdeconnect::commands`]. The transport the request
    /// arrived on is deliberately not consulted: Relay WAN has already bound the
    /// connection to a trusted KDE device id, so it can neither add nor remove
    /// permission here.
    async fn handle_runcommand_request(
        self: &Arc<Self>,
        device_id: &str,
        request: crate::kdeconnect::packet::RunCommandRequestBody,
        reply: &PacketReplyRoute,
    ) {
        let trusted = self.trust.lock().await.get(device_id).is_some();
        if !trusted {
            tracing::warn!(
                "[Relay RunCommand] route={} refused a request from untrusted device={device_id}",
                reply.label()
            );
            return;
        }

        if request.request_command_list {
            let advertised = self.commands.advertised();
            tracing::info!(
                "[Relay RunCommand] device={device_id} route={} commandList commands={}",
                reply.label(),
                advertised.len()
            );
            reply
                .send(&crate::kdeconnect::packet::RunCommandListBody::to_packet(
                    &advertised,
                ))
                .await;
        }

        if request.setup {
            // Opening a settings window because a remote packet said so is a
            // surprising thing to do to the person at the keyboard, so Relay
            // acknowledges it in the log and does nothing else.
            tracing::info!("[Relay RunCommand] device={device_id} requested setup; ignored");
        }

        let Some(id) = request.key.as_deref() else {
            return;
        };
        match self.commands.resolve_for_execution(id, trusted) {
            Ok(entry) => {
                // Log the id and name only -- never the command line or its
                // output, which routinely carry paths and secrets.
                tracing::info!(
                    "[Relay RunCommand] device={device_id} route={} running id={} name={}",
                    reply.label(),
                    entry.id,
                    entry.name
                );
                let runner = self.command_runner.lock().await.clone();
                if let Err(error) = runner.spawn(&entry.command) {
                    tracing::warn!(
                        "[Relay RunCommand] device={device_id} id={} failed to start: {error}",
                        entry.id
                    );
                }
            }
            Err(rejection) => {
                tracing::warn!(
                    "[Relay RunCommand] device={device_id} route={} refused id={id}: {rejection}",
                    reply.label()
                );
            }
        }
    }

    /// Handles one KDE `NetworkPacket` that arrived over *any* transport.
    ///
    /// This is the single dispatch chain shared by the LAN reader task and the
    /// Relay WAN receive task, so a feature's behaviour never depends on which
    /// transport delivered its packet -- there is deliberately no `if wan {}`
    /// branch below. Anything replied to here goes back over `reply`, i.e. the
    /// same route the packet arrived on, which is also what keeps per-route
    /// liveness honest: a WAN pong must never be evidence that LAN is alive.
    ///
    /// Excluded on purpose and handled by the LAN reader alone: `kdeconnect.pair`
    /// (pairing is only ever performed over an authenticated LAN session) and
    /// `kdeconnect.relay.wan.identity` (WAN endpoint enrolment must be learned
    /// from a LAN link, never from a WAN peer describing itself).
    ///
    /// Returns `false` if no branch claimed the packet, so each caller can log
    /// the miss in its own terms.
    async fn handle_transport_packet(
        self: &Arc<Self>,
        device_id: &str,
        packet: &NetworkPacket,
        reply: &PacketReplyRoute,
    ) -> bool {
        let read_inner = self;
        let read_id: String = device_id.to_owned();
        if let Ok(battery) = packet.as_battery() {
            tracing::info!(
                "[KDE Connect][RX] type=kdeconnect.battery currentCharge={} isCharging={} thresholdEvent={:?}",
                battery.current_charge,
                battery.is_charging,
                battery.threshold_event
            );
            read_inner.battery.lock().await.insert(
                read_id.clone(),
                BatteryState {
                    current_charge: battery.current_charge,
                    is_charging: battery.is_charging,
                    threshold_event: battery.threshold_event,
                },
            );
            read_inner.emit_devices().await;
        } else if let Ok(report) = packet.as_connectivity_report() {
            let selected = report.selected_signal().map(|(_, signal)| {
                (signal.network_type.clone(), signal.signal_strength)
            });
            tracing::info!(
                "[KDE Connectivity] device={} signals={} selectedType={} selectedLevel={}",
                read_id,
                report.signal_strengths.len(),
                selected.as_ref().map(|(kind, _)| kind.as_str()).unwrap_or("Unknown"),
                selected.as_ref().map(|(_, level)| level.to_string()).unwrap_or_else(|| "unknown".to_string()),
            );
            read_inner.connectivity.lock().await.insert(
                read_id.clone(),
                ConnectivityState {
                    report,
                    stale: false,
                },
            );
            read_inner.emit_devices().await;
        } else if let Ok(clipboard) = packet.as_clipboard() {
            read_inner.handle_clipboard(&read_id, clipboard).await;
        } else if let Ok(ping) = packet.as_ping() {
            tracing::info!("[KDE Connect] Received ping from {read_id}");
            let _ = read_inner.event_tx.send(KdeConnectEvent::PingReceived {
                device_id: read_id.clone(),
                message: ping.message,
            });
        } else if let Ok(heartbeat) = packet.as_relay_ping() {
            // Relay-native heartbeat: echo a pong immediately and
            // record that this device is live right now, over
            // whichever transport delivered it.
            read_inner.record_heartbeat_seen(&read_id).await;
            reply
                .send(&RelayHeartbeatBody::pong(heartbeat.nonce, heartbeat.timestamp))
                .await;
        } else if let Ok(heartbeat) = packet.as_relay_pong() {
            read_inner.record_heartbeat_rtt(&read_id, heartbeat.timestamp).await;
        } else if let Ok(state) = packet.as_relay_device_state() {
            if state.is_request {
                reply.send(&read_inner.local_device_state_packet()).await;
            } else {
                read_inner.handle_relay_device_state(&read_id, state).await;
            }
        } else if let Ok(notif) = packet.as_notification() {
            let mut notifs_map = read_inner.notifications.lock().await;
            let list = notifs_map.entry(read_id.clone()).or_default();
            if notif.is_cancel {
                list.retain(|n| n.id != notif.id);
            } else {
                if let Some(existing) = list.iter_mut().find(|n| n.id == notif.id) {
                    existing.app_name =
                        notif.app_name.or(existing.app_name.clone());
                    existing.title = notif.title.or(existing.title.clone());
                    existing.text = notif.text.or(existing.text.clone());
                    existing.time = notif.time.or(existing.time.clone());
                    if let Some(c) = notif.is_clearable {
                        existing.is_clearable = c;
                    }
                    if let Some(s) = notif.silent {
                        existing.silent = s;
                    }
                } else {
                    list.push(KdeNotification {
                        id: notif.id,
                        app_name: notif.app_name,
                        title: notif.title,
                        text: notif.text,
                        time: notif.time,
                        is_clearable: notif.is_clearable.unwrap_or(true),
                        silent: notif.silent.unwrap_or(false),
                    });
                }
            }
            let current_notifs = list.clone();
            drop(notifs_map);
            let _ =
                read_inner
                    .event_tx
                    .send(KdeConnectEvent::NotificationsChanged {
                        device_id: read_id.clone(),
                        notifications: current_notifs,
                    });
        } else if packet.packet_type == crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES
        {
            tracing::info!(
                "[RelaySmsBridge] RECEIVE device={} packetType={}",
                read_id,
                packet.packet_type
            );
            match packet.as_sms_messages() {
                Ok(sms) => {
                    tracing::info!(
                        "[RelaySmsBridge] PARSE success device={} packetType={} messages={}",
                        read_id,
                        packet.packet_type,
                        sms.messages.len()
                    );
                    read_inner.merge_sms_messages(&read_id, sms.messages).await;
                }
                Err(error) => tracing::warn!(
                    "[RelaySmsBridge] PARSE failed device={} packetType={} reason={}",
                    read_id,
                    packet.packet_type,
                    error
                ),
            }
        } else if let Ok(request) = packet.as_mpris_request() {
            read_inner.handle_mpris_request(&read_id, request, reply).await;
        } else if let Ok(share) = packet.as_share_request() {
            read_inner.handle_share_request(&read_id, share).await;
        } else if let Ok(request) = packet.as_mousepad_request() {
            read_inner.handle_remote_input(&read_id, request).await;
        } else if let Ok(request) = packet.as_runcommand_request() {
            read_inner.handle_runcommand_request(&read_id, request, reply).await;
        } else if let Ok(telephony) = packet.as_telephony() {
            let event = crate::kdeconnect::KdeTelephonyEvent {
                event: telephony.event,
                is_cancel: telephony.is_cancel,
                phone_number: telephony.phone_number,
                contact_name: telephony.contact_name,
                phone_thumbnail: telephony.phone_thumbnail,
            };
            let _ = read_inner
                .event_tx
                .send(KdeConnectEvent::TelephonyReceived {
                    device_id: read_id.clone(),
                    event,
                });
        } else {
            return false;
        }
        true
    }

    async fn handle_relay_device_state(&self, device_id: &str, state: crate::kdeconnect::packet::RelayDeviceStateBody) {
        self.record_heartbeat_seen(device_id).await;
        if let Some(percent) = state.battery_percent.and_then(|value| i32::try_from(value).ok()) {
            self.battery.lock().await.insert(device_id.to_owned(), BatteryState {
                current_charge: percent,
                is_charging: state.charging.unwrap_or(false),
                threshold_event: None,
            });
        }
        self.emit_devices().await;
    }

    /// Binds the peer's Relay WAN `EndpointId` to its KDE device id, from a
    /// `kdeconnect.relay.wan.identity` packet received over an already-trusted
    /// LAN link. This is the one place `WanBindingRegistry` gets populated
    /// from real pairing state -- an `EndpointId` is never trusted just
    /// because a WAN peer claims a known device id (see
    /// `WanRuntime::negotiate_inbound`).
    #[cfg(feature = "kdeconnect-wan")]
    async fn register_wan_binding(
        &self,
        device_id: &str,
        display_name: &str,
        device_type: &str,
        identity: crate::kdeconnect::packet::RelayWanIdentityBody,
    ) {
        use crate::kdeconnect::wan::WanBinding;
        if self.trust.lock().await.get(device_id).is_none() {
            tracing::warn!("[KDE Connect] ignored Relay WAN identity from unpaired device {device_id}");
            return;
        }
        let Ok(endpoint_id) = identity.endpoint_id.parse::<iroh::EndpointId>() else {
            tracing::warn!(
                "[KDE Connect] rejected malformed Relay WAN endpoint id from {device_id}"
            );
            return;
        };
        if identity.kde_device_id != device_id {
            tracing::warn!(
                "[KDE Connect] Relay WAN identity kdeDeviceId mismatch: packet said {}, connection is {device_id}",
                identity.kde_device_id
            );
            return;
        }
        let (incoming, outgoing) = self
            .peer_capabilities
            .lock()
            .await
            .get(device_id)
            .cloned()
            .unwrap_or_default();
        let mut capabilities = incoming;
        capabilities.extend(outgoing);
        self.wan_bindings.upsert(WanBinding {
            kde_device_id: device_id.to_owned(),
            endpoint_id,
            display_name: display_name.to_owned(),
            device_type: device_type.to_owned(),
            capabilities,
            binding_version: 1,
            updated_at_unix: now_unix(),
            last_wan_connected_at_unix: None,
            last_transport: None,
        });
        let trust_changed = self
            .trust
            .lock()
            .await
            .set_wan_endpoint_id(device_id, identity.endpoint_id);
        if trust_changed {
            self.emit_trust().await;
        }
    }

    /// Lazily starts the Relay WAN runtime and its inbound accept loop. Never
    /// called from `LanInner::new`/`run` -- KDE LAN startup must never itself
    /// bind the Relay WAN Iroh endpoint (see
    /// `tests/kdeconnect_wan_isolation.rs`). Idempotent: a second call is a
    /// no-op once a runtime is already running.
    #[cfg(feature = "kdeconnect-wan")]
    pub async fn enable_wan(
        self: &Arc<Self>,
        config: crate::kdeconnect::wan::WanRuntimeConfig,
    ) -> Result<()> {
        if self.wan_runtime.lock().await.is_some() {
            return Ok(());
        }
        let runtime =
            Arc::new(crate::kdeconnect::wan::WanRuntime::start(config, self.wan_bindings.clone()).await?);
        *self.wan_runtime.lock().await = Some(runtime.clone());

        // A LAN session may have completed while the optional WAN endpoint was
        // starting. Advertise the stable endpoint on every already-trusted LAN
        // connection as well as on future connections below.
        let identity_packet = crate::kdeconnect::packet::RelayWanIdentityBody::new(
            runtime.endpoint_id().to_string(),
            self.identity.device_id.clone(),
        )
        .serialize();
        let existing_lan_senders: Vec<_> = {
            let trust = self.trust.lock().await;
            self.connections
                .lock()
                .await
                .iter()
                .filter(|(device_id, _)| trust.get(device_id).is_some())
                .map(|(_, connection)| connection.packets.clone())
                .collect()
        };
        for sender in existing_lan_senders {
            let _ = sender.send(identity_packet.clone()).await;
        }

        let sweep_inner = Arc::clone(self);
        let sweep_cancel = self.cancel.clone();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = sweep_cancel.cancelled() => break,
                    _ = tokio::time::sleep(ROUTE_SWEEP_INTERVAL) => {
                        // Both sweeps run on this fast cadence. Evicting a dead
                        // route is what makes the router pick the surviving one,
                        // so it must not wait for the next heartbeat probe.
                        sweep_inner.sweep_stale_routes().await;
                        sweep_inner.sweep_stale_wan_links().await;
                    }
                }
            }
        });

        // Application-level liveness is authoritative. A TCP writer can keep
        // accepting bytes after Wi-Fi disappears, so probe the selected route
        // and evict a route that has not produced a real pong/state packet.
        let heartbeat_inner = Arc::clone(self);
        let heartbeat_cancel = self.cancel.clone();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = heartbeat_cancel.cancelled() => break,
                    _ = tokio::time::sleep(HEARTBEAT_PROBE_INTERVAL) => {
                        let device_ids: Vec<_> = heartbeat_inner
                            .trust.lock().await.snapshot().into_iter()
                            .map(|device| device.device_id).collect();
                        for device_id in device_ids {
                            if heartbeat_inner.router.active_transport(&device_id).is_some() {
                                let nonce = uuid::Uuid::new_v4().to_string();
                                let ping = RelayHeartbeatBody::ping(nonce, now_unix_millis());
                                let _ = heartbeat_inner.router.send_packet(&device_id, &ping).await;
                            }
                        }
                        heartbeat_inner.sweep_stale_routes().await;
                    }
                }
            }
        });

        let inner = Arc::clone(self);
        let endpoint = runtime.endpoint();
        let cancel = self.cancel.clone();
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = cancel.cancelled() => break,
                    accepted = endpoint.accept() => {
                        let Ok(incoming) = accepted else { break };
                        let runtime = runtime.clone();
                        let inner = Arc::clone(&inner);
                        tokio::spawn(async move {
                            let Ok(connection) = incoming.await else { return };
                            match runtime.negotiate_inbound(connection).await {
                                Ok(link) => inner.adopt_wan_link(link).await,
                                Err(error) => tracing::info!("[Relay WAN] inbound connection rejected: {error}"),
                            }
                        });
                    }
                }
            }
        });
        Ok(())
    }

    /// A WAN device whose heartbeat hasn't been seen within
    /// [`HEARTBEAT_TIMEOUT_SECS`] is dropped from `wan_active` and
    /// unregistered from the router -- `connected`/`transport_kind` in the
    /// next `snapshot()` reflect this immediately, with no separate "mark
    /// offline" step required. The link's own receive loop still owns
    /// actually tearing down the Iroh connection when it next notices.
    #[cfg(feature = "kdeconnect-wan")]
    async fn sweep_stale_wan_links(&self) {
        use crate::kdeconnect::wan::TransportKind;
        let now = now_unix();
        let stale: Vec<String> = {
            let active = self.wan_active.lock().await;
            let route_last_seen = self.route_last_seen.lock().await;
            active
                .iter()
                .filter(|device_id| {
                    route_last_seen
                        .get(&(device_id.to_string(), TransportKind::RelayWan))
                        .copied()
                        .map_or(true, |last_seen| now - last_seen > HEARTBEAT_TIMEOUT_SECS)
                })
                .cloned()
                .collect()
        };
        if stale.is_empty() {
            return;
        }
        let mut active = self.wan_active.lock().await;
        for device_id in &stale {
            active.remove(device_id);
            self.wan_epoch.lock().await.remove(device_id);
            self.router.unregister(device_id, TransportKind::RelayWan);
            self.route_last_seen
                .lock()
                .await
                .remove(&(device_id.clone(), TransportKind::RelayWan));
        }
        drop(active);
        self.emit_devices().await;
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn sweep_stale_routes(&self) {
        use crate::kdeconnect::wan::TransportKind;
        let now = now_unix();
        let stale: Vec<(String, TransportKind)> = {
            let route_last_seen = self.route_last_seen.lock().await;
            let trusted = self.trust.lock().await.snapshot();
            let mut stale = Vec::new();
            for device in trusted {
                let transports = self.router.available_transports(&device.device_id);
                // A route with a live alternative is failed over quickly; the
                // last remaining route keeps the generous budget so a hiccup
                // does not present the device as Offline.
                let has_alternative = transports.len() > 1;
                let budget = if has_alternative {
                    FAILOVER_TIMEOUT_SECS
                } else {
                    HEARTBEAT_TIMEOUT_SECS
                };
                for kind in transports {
                    if route_last_seen
                        .get(&(device.device_id.clone(), kind))
                        .is_none_or(|last_seen| now - *last_seen > budget)
                    {
                        stale.push((device.device_id.clone(), kind));
                    }
                }
            }
            stale
        };
        for (device_id, kind) in stale {
            self.router.unregister(&device_id, kind);
            match kind {
                TransportKind::KdeLan => { self.connections.lock().await.remove(&device_id); }
                TransportKind::RelayWan => {
                    self.wan_active.lock().await.remove(&device_id);
                    self.wan_epoch.lock().await.remove(&device_id);
                }
            }
            self.route_last_seen.lock().await.remove(&(device_id.clone(), kind));
            tracing::warn!("[Relay WAN] removed stale {:?} route for {} after heartbeat timeout", kind, device_id);
        }
        if !self.router.available_transports("").is_empty() || !self.trust.lock().await.snapshot().is_empty() {
            self.emit_devices().await;
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn clear_wan_if_current(&self, device_id: &str, epoch: u64) -> bool {
        use crate::kdeconnect::wan::TransportKind;
        let is_current = {
            let mut epochs = self.wan_epoch.lock().await;
            if epochs.get(device_id).copied() == Some(epoch) {
                epochs.remove(device_id);
                true
            } else {
                false
            }
        };
        if !is_current {
            return false;
        }
        self.wan_active.lock().await.remove(device_id);
        self.router.unregister(device_id, TransportKind::RelayWan);
        self.route_last_seen
            .lock()
            .await
            .remove(&(device_id.to_owned(), TransportKind::RelayWan));
        self.emit_devices().await;
        true
    }

    /// Registers an accepted (inbound or outbound) [`WanLink`] with the
    /// transport router, marks its device live, and spawns the task that
    /// drains its packets into the same heartbeat/device-state handling LAN
    /// uses. A LAN link for the same device_id, if present, keeps priority
    /// (see `TransportKind::priority`) -- this never displaces it.
    #[cfg(feature = "kdeconnect-wan")]
    pub(crate) async fn adopt_wan_link(self: &Arc<Self>, link: crate::kdeconnect::wan::WanLink) {
        use crate::kdeconnect::wan::{TransportKind, TransportLink, WanIncomingEvent};
        let device_id = link.device_id().to_owned();

        // A WAN-only session never sees a `kdeconnect.identity` packet, so
        // without this the peer's capability lists would stay empty and every
        // capability-gated send (`ensure_peer_accepts`) would be refused
        // locally -- notifications and SMS would silently do nothing after a
        // desktop restart while the phone is on mobile data. The WAN hello
        // carries the same canonical lists the LAN identity packet does.
        let hello = link.remote_hello();
        if !hello.incoming_capabilities.is_empty() || !hello.outgoing_capabilities.is_empty() {
            let incoming = hello.incoming_capabilities.clone();
            let outgoing = hello.outgoing_capabilities.clone();
            tracing::info!(
                "[Relay WAN][CAPS] device={device_id} incoming={} outgoing={}",
                incoming.len(),
                outgoing.len()
            );
            let mut merged = incoming.clone();
            merged.extend(outgoing.clone());
            self.wan_bindings.set_capabilities(&device_id, merged);
            self.peer_capabilities
                .lock()
                .await
                .insert(device_id.clone(), (incoming, outgoing));
        } else {
            tracing::debug!(
                "[Relay WAN][CAPS] device={device_id} advertised no capability lists; \
                 keeping whatever LAN already taught us"
            );
        }

        let link = Arc::new(link);
        let epoch = self.conn_epoch.fetch_add(1, Ordering::Relaxed);
        self.router.register(link.clone());
        self.wan_active.lock().await.insert(device_id.clone());
        self.wan_epoch.lock().await.insert(device_id.clone(), epoch);
        self.record_route_seen(&device_id, TransportKind::RelayWan).await;
        self.record_heartbeat_seen(&device_id).await;
        self.emit_devices().await;

        let _ = link.send_packet(&RelayDeviceStateBody::new(RelayDeviceStateBody {
            is_request: true,
            ..Default::default()
        })).await;
        let _ = link.send_packet(&RelayHeartbeatBody::ping(
            uuid::Uuid::new_v4().to_string(), now_unix_millis()
        )).await;

        let inner = Arc::clone(self);
        tokio::spawn(async move {
            loop {
                match link.recv_incoming().await {
                    Some(WanIncomingEvent::Packet(packet)) => {
                        inner.record_route_seen(&device_id, TransportKind::RelayWan).await;
                        // Pairing is a LAN-only operation. A WAN peer is
                        // already authenticated by its bound EndpointId, so a
                        // pair packet here can only be an attempt to change
                        // trust over a transport that must never grant it.
                        if packet.packet_type == crate::kdeconnect::PACKET_TYPE_PAIR {
                            tracing::warn!(
                                "[Relay WAN] refused a {} packet from {device_id}: pairing is LAN-only",
                                packet.packet_type
                            );
                        } else if !inner
                            .handle_transport_packet(
                                &device_id,
                                &packet,
                                &PacketReplyRoute::Wan(
                                    Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>,
                                ),
                            )
                            .await
                        {
                            tracing::debug!(
                                "[Relay WAN] unhandled packet type over WAN: {}",
                                packet.packet_type
                            );
                        }
                    }
                    Some(WanIncomingEvent::Payload {
                        relay_payload_id,
                        payload_size,
                        mut stream,
                    }) => {
                        inner
                            .handle_incoming_payload(&relay_payload_id, payload_size, &mut stream)
                            .await;
                    }
                    None => break,
                }
            }
            inner.clear_wan_if_current(&device_id, epoch).await;
        });
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
            tracing::info!(
                "[KDE Connect] Pairing already requested by peer {device_id}, auto-accepting"
            );
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
        // Tell the peer while its route and trust record still exist. Once the
        // router registrations below are removed there is deliberately no way
        // to deliver another packet to this logical device.
        let _ = self
            .send_packet(device_id, &PairBody::unpair().serialize())
            .await;

        self.clear_forgotten_device(device_id).await;
        self.emit_trust().await;
        self.emit_devices().await;
        Ok(())
    }

    /// Removes every piece of runtime and persisted ownership for one logical
    /// device. Both a local Forget and a peer-originated unpair use the same
    /// teardown, so neither path can leave a reconnectable WAN binding or stale
    /// feature data behind.
    async fn clear_forgotten_device(&self, device_id: &str) {
        self.pairing.lock().await.remove(device_id);
        self.incoming.lock().await.remove(device_id);
        self.trust.lock().await.remove(device_id);
        self.devices.lock().await.remove(device_id);
        self.connections.lock().await.remove(device_id);
        self.battery.lock().await.remove(device_id);
        self.connectivity.lock().await.remove(device_id);
        self.clipboard.lock().await.remove(device_id);
        self.notifications.lock().await.remove(device_id);
        self.sms.lock().await.remove(device_id);
        self.peer_capabilities.lock().await.remove(device_id);
        self.heartbeat.lock().await.remove(device_id);
        self.last_connect.lock().await.remove(device_id);
        self.mismatches.lock().await.remove(device_id);
        self.input_queues.lock().await.remove(device_id);
        self.transfers.lock().await.remove_device(device_id);
        self.pending_payloads
            .lock()
            .await
            .retain(|_, pending| pending.device_id != device_id);

        // Everything that could let a forgotten device come back, or leave its
        // data behind, has to go with the trust record. Leaving the WAN binding
        // in particular would let the device reconnect over Iroh after the user
        // deliberately forgot it -- trust is what authorises that binding, so
        // removing one without the other is a security hole, not untidiness.
        #[cfg(feature = "kdeconnect-wan")]
        {
            use crate::kdeconnect::wan::TransportKind;
            self.wan_bindings.remove(device_id);
            self.wan_active.lock().await.remove(device_id);
            self.wan_epoch.lock().await.remove(device_id);
            self.router.unregister(device_id, TransportKind::KdeLan);
            self.router.unregister(device_id, TransportKind::RelayWan);
            self.route_last_seen
                .lock()
                .await
                .retain(|(id, _), _| id != device_id);
        }

        let _ = self.event_tx.send(KdeConnectEvent::NotificationsChanged {
            device_id: device_id.to_string(),
            notifications: Vec::new(),
        });
    }

    pub async fn send_ping(&self, device_id: &str, message: Option<String>) -> Result<()> {
        let is_paired = self.trust.lock().await.get(device_id).is_some();
        if !is_paired {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(device_id, crate::kdeconnect::PACKET_TYPE_PING)
            .await?;
        let pkt = PingBody::new(message).serialize();
        self.send_packet(device_id, &pkt).await
    }

    pub async fn find_phone(&self, device_id: &str) -> Result<()> {
        let is_paired = self.trust.lock().await.get(device_id).is_some();
        if !is_paired {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(
            device_id,
            crate::kdeconnect::PACKET_TYPE_FINDMYPHONE_REQUEST,
        )
        .await?;
        let pkt = FindMyPhoneBody::request().serialize();
        self.send_packet(device_id, &pkt).await
    }

    pub async fn send_clipboard(
        &self,
        device_id: &str,
        content: &str,
        timestamp_ms: i64,
    ) -> Result<()> {
        let is_paired = self.trust.lock().await.get(device_id).is_some();
        if !is_paired {
            anyhow::bail!("device not paired");
        }
        if !self.clipboard_enabled() {
            anyhow::bail!("clipboard sync is switched off");
        }
        if content.is_empty()
            || content.len() > crate::kdeconnect::clipboard::MAX_CLIPBOARD_BYTES
        {
            anyhow::bail!("clipboard content is empty or exceeds the size bound");
        }
        self.ensure_peer_accepts(device_id, crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT)
            .await?;
        self.clipboard
            .lock()
            .await
            .insert(device_id.to_string(), timestamp_ms);
        // Marked so the resulting remote write cannot come back as new content.
        self.clipboard_guard
            .lock()
            .await
            .note_handled(content, now_unix_millis());
        let pkt = ClipboardBody::connect(content, timestamp_ms).serialize();
        self.send_packet(device_id, &pkt).await
    }

    /// Sends a locally observed clipboard change to every trusted device that
    /// accepts clipboard packets.
    ///
    /// Delivery goes through the `TransportRouter`, so a Local device is reached
    /// over LAN and a Remote one over Relay WAN with no clipboard-specific
    /// transport handling. This previously wrote straight into the LAN
    /// connection map, which silently skipped every Remote device.
    ///
    /// Fan-out policy: this is only ever called for a *locally originated*
    /// clipboard change. Content that arrived from another device is applied
    /// locally and not re-broadcast -- re-broadcasting is what turns three
    /// paired devices into a clipboard storm. The guard below would catch the
    /// echo regardless, but not fanning out in the first place is what keeps
    /// the traffic proportional to the number of devices rather than its square.
    pub async fn send_clipboard_to_all_paired(
        &self,
        content: &str,
        timestamp_ms: i64,
    ) -> Result<()> {
        use crate::kdeconnect::clipboard::{hash_prefix, ClipboardRejection};
        let now_ms = now_unix_millis();
        let enabled = self.clipboard_enabled();
        let hash = {
            let mut guard = self.clipboard_guard.lock().await;
            match guard.should_send_local(content, enabled, now_ms) {
                Ok(hash) => hash,
                Err(ClipboardRejection::Duplicate) => {
                    // The local watcher saw the write Relay itself just made.
                    tracing::debug!("[Relay Clipboard] direction=out ignored=duplicate");
                    return Ok(());
                }
                Err(rejection) => {
                    tracing::warn!(
                        "[Relay Clipboard] direction=out refused={rejection} bytes={}",
                        content.len()
                    );
                    return Ok(());
                }
            }
        };

        let trusted = self.trust.lock().await.snapshot();
        let packet = ClipboardBody::connect(content, timestamp_ms);
        let mut sent = 0_usize;
        for device in trusted {
            if self
                .ensure_peer_accepts(
                    &device.device_id,
                    crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT,
                )
                .await
                .is_err()
            {
                continue;
            }
            #[cfg(feature = "kdeconnect-wan")]
            if self.router.send_packet(&device.device_id, &packet).await.is_ok() {
                sent += 1;
            }
            #[cfg(not(feature = "kdeconnect-wan"))]
            if self
                .send_packet(&device.device_id, &packet.serialize())
                .await
                .is_ok()
            {
                sent += 1;
            }
        }
        // Recorded once for the whole fan-out, so any device echoing it back is
        // recognised as ours.
        self.clipboard_guard.lock().await.note_handled(content, now_ms);
        tracing::info!(
            "[Relay Clipboard] direction=out devices={sent} bytes={} hash={}",
            content.len(),
            hash_prefix(hash)
        );
        Ok(())
    }

    pub async fn request_notifications(&self, device_id: &str) -> Result<()> {
        let is_paired = self.trust.lock().await.get(device_id).is_some();
        if !is_paired {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(
            device_id,
            crate::kdeconnect::PACKET_TYPE_NOTIFICATION_REQUEST,
        )
        .await?;
        let pkt = NotificationBody::request().serialize();
        self.send_packet(device_id, &pkt).await
    }

    async fn ensure_peer_accepts(&self, device_id: &str, packet_type: &str) -> Result<()> {
        let peer_capabilities = self.peer_capabilities.lock().await;
        let peer_accepts = peer_capabilities
            .get(device_id)
            .is_some_and(|(incoming, _)| {
                incoming.iter().any(|capability| capability == packet_type)
            });
        if !peer_accepts {
            anyhow::bail!("peer does not advertise support for {packet_type}");
        }
        Ok(())
    }

    /// Dismisses one notification on the device that produced it.
    ///
    /// `remote_notification_id` is only unique *within* `device_id` -- two phones
    /// may both be showing id `42` -- so the pair is the real key, and this
    /// method is the only way the rest of the app is allowed to dismiss. The
    /// packet goes out via `send_packet`, so the TransportRouter picks LAN or
    /// Relay WAN on its own; dismissal works identically while the device is
    /// Local or Remote.
    ///
    /// The local record is dropped optimistically so the UI updates without
    /// waiting for the phone's echo, and *only* the matching device's list is
    /// touched.
    pub async fn dismiss_notification(
        &self,
        device_id: &str,
        remote_notification_id: &str,
    ) -> Result<()> {
        if self.trust.lock().await.get(device_id).is_none() {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(
            device_id,
            crate::kdeconnect::PACKET_TYPE_NOTIFICATION_REQUEST,
        )
        .await?;

        let packet = NotificationBody::dismiss(remote_notification_id).serialize();
        self.send_packet(device_id, &packet).await?;

        let remaining = {
            let mut notifs = self.notifications.lock().await;
            let Some(list) = notifs.get_mut(device_id) else {
                return Ok(());
            };
            list.retain(|n| n.id != remote_notification_id);
            list.clone()
        };
        let _ = self.event_tx.send(KdeConnectEvent::NotificationsChanged {
            device_id: device_id.to_string(),
            notifications: remaining,
        });
        Ok(())
    }

    pub async fn get_notifications(&self, device_id: &str) -> Vec<KdeNotification> {
        self.notifications
            .lock()
            .await
            .get(device_id)
            .cloned()
            .unwrap_or_default()
    }

    pub async fn get_sms_conversations(&self, device_id: &str) -> Vec<KdeSmsConversation> {
        let sms = self.sms.lock().await;
        let Some(threads) = sms.get(device_id) else {
            return Vec::new();
        };
        let mut conversations: Vec<_> = threads
            .iter()
            .map(|(thread_id, messages)| {
                let latest = messages
                    .values()
                    .max_by_key(|message| (message.date, message.id))
                    .cloned();
                let participants = latest
                    .as_ref()
                    .map(|message| message.addresses.clone())
                    .unwrap_or_default();
                let unread_count = messages
                    .values()
                    .filter(|message| message.message_type == 1 && message.read == Some(false))
                    .count() as i32;
                KdeSmsConversation {
                    thread_id: *thread_id,
                    participants,
                    latest_message: latest,
                    unread_count,
                }
            })
            .collect();
        conversations.sort_by(|a, b| {
            b.latest_message
                .as_ref()
                .map(|m| (m.date, m.id))
                .cmp(&a.latest_message.as_ref().map(|m| (m.date, m.id)))
        });
        conversations
    }

    pub async fn get_sms_messages(&self, device_id: &str, thread_id: i64) -> Vec<SmsMessage> {
        let mut messages = self
            .sms
            .lock()
            .await
            .get(device_id)
            .and_then(|threads| threads.get(&thread_id))
            .map(|items| items.values().cloned().collect::<Vec<_>>())
            .unwrap_or_default();
        messages.sort_by_key(|message| (message.date, message.id));
        messages
    }

    pub async fn request_sms_conversations(&self, device_id: &str) -> Result<()> {
        if self.trust.lock().await.get(device_id).is_none() {
            tracing::warn!(
                "[RelaySmsBridge] SEND rejected device={} packetType={} reason=device-not-paired",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS
            );
            anyhow::bail!("device not paired");
        }
        if let Err(error) = self
            .ensure_peer_accepts(
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS,
            )
            .await
        {
            tracing::warn!(
                "[RelaySmsBridge] SEND rejected device={} packetType={} reason={}",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS,
                error
            );
            return Err(error);
        }
        let result = self
            .send_packet(
                device_id,
                &SmsRequestConversationsBody::request().serialize(),
            )
            .await;
        match &result {
            Ok(()) => tracing::info!(
                "[RelaySmsBridge] SEND queued device={} packetType={}",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS
            ),
            Err(error) => tracing::warn!(
                "[RelaySmsBridge] SEND rejected device={} packetType={} reason={}",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS,
                error
            ),
        }
        result
    }

    pub async fn request_sms_conversation(
        &self,
        device_id: &str,
        thread_id: i64,
        before: Option<i64>,
        limit: u16,
    ) -> Result<()> {
        if self.trust.lock().await.get(device_id).is_none() {
            tracing::warn!(
                "[RelaySmsBridge] SEND rejected device={} packetType={} threadId={} reason=device-not-paired",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATION,
                thread_id
            );
            anyhow::bail!("device not paired");
        }
        if let Err(error) = self
            .ensure_peer_accepts(
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATION,
            )
            .await
        {
            tracing::warn!(
                "[RelaySmsBridge] SEND rejected device={} packetType={} threadId={} reason={}",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATION,
                thread_id,
                error
            );
            return Err(error);
        }
        let result = self
            .send_packet(
                device_id,
                &SmsRequestConversationBody::request(thread_id, before, Some(limit.min(100)))
                    .serialize(),
            )
            .await;
        match &result {
            Ok(()) => tracing::info!(
                "[RelaySmsBridge] SEND queued device={} packetType={} threadId={}",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATION,
                thread_id
            ),
            Err(error) => tracing::warn!(
                "[RelaySmsBridge] SEND rejected device={} packetType={} threadId={} reason={}",
                device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATION,
                thread_id,
                error
            ),
        }
        result
    }

    pub async fn send_sms(
        &self,
        device_id: &str,
        addresses: Vec<String>,
        body: &str,
        sub_id: Option<i32>,
    ) -> Result<()> {
        if self.trust.lock().await.get(device_id).is_none() {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(device_id, crate::kdeconnect::PACKET_TYPE_SMS_REQUEST)
            .await?;
        let packet = crate::kdeconnect::packet::SmsRequestBody {
            addresses,
            message_body: body.to_string(),
            sub_id,
        }
        .to_packet();
        self.send_packet(device_id, &packet.serialize()).await
    }

    pub async fn send_mute_call(&self, device_id: &str) -> Result<()> {
        if self.trust.lock().await.get(device_id).is_none() {
            anyhow::bail!("device not paired");
        }
        self.ensure_peer_accepts(
            device_id,
            crate::kdeconnect::PACKET_TYPE_TELEPHONY_REQUEST_MUTE,
        )
        .await?;
        let packet = crate::kdeconnect::packet::TelephonyRequestMuteBody::request();
        self.send_packet(device_id, &packet.serialize()).await
    }

    async fn merge_sms_messages(&self, device_id: &str, messages: Vec<SmsMessage>) {
        let message_count = messages.len();
        let event_messages = messages.clone();
        {
            let mut sms = self.sms.lock().await;
            let threads = sms.entry(device_id.to_string()).or_default();
            for message in messages {
                threads
                    .entry(message.thread_id)
                    .or_default()
                    .insert(message.id, message);
            }
        }
        let conversations = self.get_sms_conversations(device_id).await;
        let conversation_count = conversations.len();
        let emitted = self
            .event_tx
            .send(KdeConnectEvent::SmsChanged {
                device_id: device_id.to_string(),
                conversations,
                messages: event_messages,
            })
            .is_ok();
        tracing::info!(
            "[RelaySmsBridge] EVENT SmsChanged device={} conversations={} messages={} emitted={}",
            device_id,
            conversation_count,
            message_count,
            emitted
        );
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
            wan_endpoint_id: None,
        });
        #[cfg(feature = "kdeconnect-wan")]
        if let Some(identity_packet) = self.local_wan_identity_packet().await {
            // Pairing can become trusted after the secure LAN link was already
            // installed. Re-advertise at that transition so enrollment does
            // not depend on a later reconnect or a second pairing.
            self.send_packet(device_id, &identity_packet.serialize()).await?;
            let request = RelayDeviceStateBody::new(RelayDeviceStateBody {
                is_request: true,
                ..Default::default()
            });
            self.send_packet(device_id, &request.serialize()).await?;
        }
        Ok(())
    }

    async fn send_packet(&self, device_id: &str, bytes: &[u8]) -> Result<()> {
        #[cfg(feature = "kdeconnect-wan")]
        {
            let packet = NetworkPacket::parse(bytes).context("invalid outbound KDE Connect packet")?;
            self.router.send_packet(device_id, &packet).await?;
            return Ok(());
        }
        #[cfg(not(feature = "kdeconnect-wan"))]
        {
        let connections = self.connections.lock().await;
        let conn = connections.get(device_id).context("no KDE Connect link")?;
        conn.packets
            .send(bytes.to_vec())
            .await
            .context("KDE Connect link closed")?;
        Ok(())
        }
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
        #[cfg(feature = "kdeconnect-wan")]
        if self.router.active_transport(device_id).is_some() {
            return Ok(());
        }
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
                self.clear_forgotten_device(device_id).await;
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
        // Already connected. The plaintext UDP identity is unauthenticated and
        // must never be written into `peer_capabilities` directly — but if it
        // advertises a capability set that differs from what we cached from the
        // last *secure* identity exchange, that's a signal worth treating as a
        // hint: re-run the TLS handshake so `finish_secure_link` can refresh the
        // authoritative cache from an authenticated source. Typical trigger:
        // the phone just got a permission granted/revoked and re-announced.
        let capabilities_changed = {
            let cached = inner.peer_capabilities.lock().await;
            match cached.get(&identity.device_id) {
                Some((cached_in, cached_out)) => {
                    !same_capability_set(cached_in, &identity.incoming_capabilities)
                        || !same_capability_set(cached_out, &identity.outgoing_capabilities)
                }
                // Connected without a cached entry shouldn't happen in practice;
                // don't force a refresh on a guess either way.
                None => false,
            }
        };
        if capabilities_changed {
            tracing::info!(
                "[KDE Connect] UDP identity from {} advertises different capabilities while \
                 already connected; scheduling a secure capability refresh",
                identity.device_id
            );
            let refresh_inner = Arc::clone(inner);
            let refresh_ip = addr.ip();
            let refresh_device_id = identity.device_id.clone();
            tokio::spawn(async move {
                if let Err(err) = outbound_connect(
                    refresh_inner,
                    refresh_ip,
                    tcp_port,
                    Some(refresh_device_id.clone()),
                )
                .await
                {
                    tracing::debug!(
                        "[KDE Connect] capability-refresh reconnect to {refresh_device_id} failed: {err:#}"
                    );
                }
            });
        }
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

/// Order-insensitive comparison of two capability lists.
fn same_capability_set(a: &[String], b: &[String]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let a_set: std::collections::HashSet<&str> = a.iter().map(String::as_str).collect();
    let b_set: std::collections::HashSet<&str> = b.iter().map(String::as_str).collect();
    a_set == b_set
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
            tracing::info!(
                "[KDE Connect] [E] TLS handshake as server succeeded with {ip}:{tcp_port}"
            );
            t
        }
        Err(e) => {
            tracing::warn!(
                "[KDE Connect] [E] TLS handshake as server failed with {ip}:{tcp_port}: {e:#}"
            );
            return Err(e);
        }
    };
    let expected_ver = match &expected_id {
        Some(id) => inner
            .devices
            .lock()
            .await
            .get(id)
            .map(|d| d.protocol_version),
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
    .await
    {
        Ok(Ok(l)) => l,
        Ok(Err(e)) => {
            tracing::warn!(
                "[KDE Connect] [G] Failed to read plaintext identity from {addr}: {e:#}"
            );
            return Err(e.into());
        }
        Err(_) => {
            tracing::warn!(
                "[KDE Connect] [G] Timed out waiting for plaintext identity from {addr}"
            );
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
    finish_secure_link(
        inner,
        tls,
        addr.ip(),
        Some(identity.device_id),
        Some(identity.protocol_version),
    )
    .await
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
    let my_identity_body = inner.identity.identity_packet(None);
    tracing::info!(
        "[KDE Connect][CAPS][TX] incoming={:?} outgoing={:?}",
        my_identity_body.incoming_capabilities,
        my_identity_body.outgoing_capabilities
    );
    tracing::info!(
        "[RelaySmsBridge] IDENTITY SEND device={} incomingMessages={} outgoingRequest={} outgoingConversations={} outgoingConversation={}",
        my_identity_body.device_id,
        my_identity_body.incoming_capabilities.iter().any(|item| item == crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES),
        my_identity_body.outgoing_capabilities.iter().any(|item| item == crate::kdeconnect::PACKET_TYPE_SMS_REQUEST),
        my_identity_body.outgoing_capabilities.iter().any(|item| item == crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS),
        my_identity_body.outgoing_capabilities.iter().any(|item| item == crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATION),
    );
    let my_identity = my_identity_body.to_packet().serialize();
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
    tracing::info!(
        "[KDE Connect][CAPS][RX] incoming={:?} outgoing={:?}",
        secure.incoming_capabilities,
        secure.outgoing_capabilities
    );

    inner.peer_capabilities.lock().await.insert(
        secure.device_id.clone(),
        (
            secure.incoming_capabilities.clone(),
            secure.outgoing_capabilities.clone(),
        ),
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
    let conn_epoch = inner.conn_epoch.fetch_add(1, Ordering::SeqCst) + 1;
    {
        let mut connections = inner.connections.lock().await;
        connections.insert(
            secure.device_id.clone(),
            Conn {
                packets: tx.clone(),
                peer_cert_der: peer_cert.clone(),
                name: secure.device_name.clone(),
                device_type: secure.device_type.clone(),
                protocol_version: secure.protocol_version,
                epoch: conn_epoch,
            },
        );
    }
    #[cfg(feature = "kdeconnect-wan")]
    inner.router.register(Arc::new(LanTransportLink {
        device_id: secure.device_id.clone(),
        packets: tx.clone(),
        identity: Arc::new(inner.identity.clone()),
        peer_cert: peer_cert.clone(),
    }));
    #[cfg(feature = "kdeconnect-wan")]
    inner
        .record_route_seen(&secure.device_id, crate::kdeconnect::wan::TransportKind::KdeLan)
        .await;
    #[cfg(feature = "kdeconnect-wan")]
    inner.record_heartbeat_seen(&secure.device_id).await;
    #[cfg(feature = "kdeconnect-wan")]
    if inner.trust.lock().await.get(&secure.device_id).is_some() {
        if let Some(identity_packet) = inner.local_wan_identity_packet().await {
            let _ = tx.send(identity_packet.serialize()).await;
        }
        let request = RelayDeviceStateBody::new(RelayDeviceStateBody {
            is_request: true,
            ..Default::default()
        });
        let _ = tx.send(request.serialize()).await;
    }
    tracing::info!(
        "[KDE Connect] [G6] secure link established with {}",
        secure.device_id
    );
    inner.emit_devices().await;

    // If paired on connect, request notifications once
    if inner.trust.lock().await.get(&secure.device_id).is_some()
        && inner
            .ensure_peer_accepts(
                &secure.device_id,
                crate::kdeconnect::PACKET_TYPE_NOTIFICATION_REQUEST,
            )
            .await
            .is_ok()
    {
        let _ = tx.send(NotificationBody::request().serialize()).await;
    }
    if inner.trust.lock().await.get(&secure.device_id).is_some()
        && inner
            .ensure_peer_accepts(
                &secure.device_id,
                crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS,
            )
            .await
            .is_ok()
    {
        let queued = tx
            .send(SmsRequestConversationsBody::request().serialize())
            .await
            .is_ok();
        tracing::info!(
            "[RelaySmsBridge] SEND auto-request device={} packetType={} queued={}",
            secure.device_id,
            crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS,
            queued
        );
    }

    let device_id = secure.device_id.clone();
    let writer_id = device_id.clone();
    let writer_cancel = inner.cancel.clone();
    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = writer_cancel.cancelled() => break,
                packet = rx.recv() => {
                    let Some(packet) = packet else { break };
                    let packet_type = NetworkPacket::parse(&packet).ok().map(|value| value.packet_type);
                    match writer.write_all(&packet).await {
                        Ok(()) => {
                            if let Some(packet_type) = packet_type.as_deref().filter(|value| value.starts_with("kdeconnect.sms.")) {
                                tracing::info!(
                                    "[RelaySmsBridge] TLS WRITE success device={} packetType={}",
                                    writer_id,
                                    packet_type
                                );
                            }
                        }
                        Err(error) => {
                            if let Some(packet_type) = packet_type.as_deref().filter(|value| value.starts_with("kdeconnect.sms.")) {
                                tracing::warn!(
                                    "[RelaySmsBridge] TLS WRITE failed device={} packetType={} reason={}",
                                    writer_id,
                                    packet_type,
                                    error
                                );
                            }
                            break;
                        }
                    }
                    if let Err(error) = writer.flush().await {
                        tracing::warn!("[KDE Connect] TLS flush failed for {}: {}", writer_id, error);
                        break;
                    }
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
                        #[cfg(feature = "kdeconnect-wan")]
                        read_inner
                            .record_route_seen(&read_id, crate::kdeconnect::wan::TransportKind::KdeLan)
                            .await;
                        tracing::info!("[KDE Connect][RX] type={}", packet.packet_type);
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
                        } else if let Ok(wan_identity) = packet.as_relay_wan_identity() {
                            #[cfg(feature = "kdeconnect-wan")]
                            {
                                read_inner
                                    .register_wan_binding(&read_id, &name, &device_type, wan_identity)
                                    .await;
                                // A binding changes diagnostics and future
                                // reachability even though it does not itself
                                // create a live WAN route.
                                read_inner.emit_devices().await;
                            }
                            #[cfg(not(feature = "kdeconnect-wan"))]
                            let _ = wan_identity;
                        } else if !read_inner
                            .handle_transport_packet(&read_id, &packet, &PacketReplyRoute::Lan(tx.clone()))
                            .await
                        {
                            tracing::debug!(
                                "[KDE Connect] Ignored unhandled packet type: {}",
                                packet.packet_type
                            );
                        }
                    }
                }
                Err(e) => {
                    tracing::info!("[KDE Connect] [J] Connection to {read_id} closed: {e:#}");
                    break;
                }
            }
        }
        // Only evict the Conn this reader task itself installed: if a newer
        // secure link has since replaced it (e.g. a capability-refresh
        // reconnect while this older connection was still tearing down),
        // that newer Conn must survive.
        let removed_current_lan = {
            let mut connections = read_inner.connections.lock().await;
            if connections
                .get(&read_id)
                .is_some_and(|conn| conn.epoch == conn_epoch)
            {
                connections.remove(&read_id);
                #[cfg(feature = "kdeconnect-wan")]
                read_inner
                    .router
                    .unregister(&read_id, crate::kdeconnect::wan::TransportKind::KdeLan);
                true
            } else {
                false
            }
        };
        #[cfg(feature = "kdeconnect-wan")]
        if removed_current_lan {
            read_inner.route_last_seen.lock().await.remove(&(
                read_id.clone(),
                crate::kdeconnect::wan::TransportKind::KdeLan,
            ));
        }
        #[cfg(not(feature = "kdeconnect-wan"))]
        let _ = removed_current_lan;
        if let Some(state) = read_inner.connectivity.lock().await.get_mut(&read_id) {
            state.stale = true;
        }
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
    use crate::kdeconnect::packet::RelayDeviceStateBody;
    use crate::kdeconnect::BatteryBody;
    use std::net::Ipv4Addr;

    #[cfg(feature = "kdeconnect-wan")]
    struct TestRoute {
        device_id: String,
        kind: crate::kdeconnect::wan::TransportKind,
    }

    #[cfg(feature = "kdeconnect-wan")]
    impl crate::kdeconnect::wan::TransportLink for TestRoute {
        fn device_id(&self) -> &str { &self.device_id }
        fn kind(&self) -> crate::kdeconnect::wan::TransportKind { self.kind }
        fn state(&self) -> crate::kdeconnect::wan::TransportState {
            match self.kind {
                crate::kdeconnect::wan::TransportKind::KdeLan => crate::kdeconnect::wan::TransportState::Local,
                crate::kdeconnect::wan::TransportKind::RelayWan => crate::kdeconnect::wan::TransportState::RemoteDirect,
            }
        }
        fn metadata(&self) -> crate::kdeconnect::wan::TransportMetadata {
            crate::kdeconnect::wan::TransportMetadata {
                kind: self.kind,
                state: self.state(),
                last_seen_unix: None,
                last_transition_reason: None,
            }
        }
        fn send_packet<'a>(&'a self, _: &'a NetworkPacket) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<()>> {
            Box::pin(async { Ok(()) })
        }
        fn send_payload<'a>(
            &'a self,
            _: crate::kdeconnect::wan::PayloadRequest<'a>,
        ) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<crate::kdeconnect::wan::PayloadOutcome>> {
            Box::pin(async { Ok(crate::kdeconnect::wan::PayloadOutcome::Sent) })
        }
        fn disconnect(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, ()> { Box::pin(async {}) }
        fn health(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, bool> { Box::pin(async { true }) }
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn superseded_wan_task_cannot_clear_its_replacement_route() {
        use crate::kdeconnect::wan::TransportKind;
        let inner = LanInner::new(
            crate::kdeconnect::LocalIdentity::generate("Relay").unwrap(),
            Vec::new(),
            LanConfig::default(),
            1716,
            tokio::sync::mpsc::unbounded_channel().0,
            tokio_util::sync::CancellationToken::new(),
        );
        let device_id = "phone".to_owned();
        inner.router.register(Arc::new(TestRoute {
            device_id: device_id.clone(),
            kind: TransportKind::RelayWan,
        }));
        inner.wan_active.lock().await.insert(device_id.clone());
        inner.wan_epoch.lock().await.insert(device_id.clone(), 2);

        assert!(!inner.clear_wan_if_current(&device_id, 1).await);
        assert_eq!(inner.router.active_transport(&device_id), Some(TransportKind::RelayWan));
        assert!(inner.wan_active.lock().await.contains(&device_id));

        assert!(inner.clear_wan_if_current(&device_id, 2).await);
        assert_eq!(inner.router.active_transport(&device_id), None);
        assert!(!inner.wan_active.lock().await.contains(&device_id));
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn persisted_trusted_endpoint_restores_wan_authentication_binding() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let endpoint_id = iroh::SecretKey::generate().public();
        let phone_id = phone_identity.device_id.clone();
        let inner = LanInner::new(
            relay_identity,
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.clone(),
                certificate_pem: phone_identity.certificate_pem,
                name: phone_identity.device_name,
                device_type: phone_identity.device_type,
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: Some(endpoint_id.to_string()),
            }],
            LanConfig::default(),
            1716,
            tokio::sync::mpsc::unbounded_channel().0,
            tokio_util::sync::CancellationToken::new(),
        );

        let restored = inner.wan_bindings.by_endpoint_id(&endpoint_id).unwrap();
        assert_eq!(restored.kde_device_id, phone_id);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn fresh_wan_traffic_cannot_keep_a_stale_lan_route_local() {
        use crate::kdeconnect::wan::{TransportKind, TransportState};

        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();
        let inner = LanInner::new(
            relay_identity,
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.clone(),
                certificate_pem: phone_identity.certificate_pem,
                name: phone_identity.device_name,
                device_type: phone_identity.device_type,
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: now_unix(),
                wan_endpoint_id: None,
            }],
            LanConfig { bind: BindMode::Any, allow_loopback: true },
            1716,
            tokio::sync::mpsc::unbounded_channel().0,
            tokio_util::sync::CancellationToken::new(),
        );

        inner.router.register(Arc::new(TestRoute { device_id: phone_id.clone(), kind: TransportKind::KdeLan }));
        inner.router.register(Arc::new(TestRoute { device_id: phone_id.clone(), kind: TransportKind::RelayWan }));
        inner.wan_active.lock().await.insert(phone_id.clone());
        inner.heartbeat.lock().await.insert(phone_id.clone(), HeartbeatState {
            last_rtt_ms: Some(10),
            last_seen_unix: Some(now_unix()),
        });
        inner.route_last_seen.lock().await.insert(
            (phone_id.clone(), TransportKind::KdeLan),
            now_unix() - HEARTBEAT_TIMEOUT_SECS - 1,
        );
        inner.route_last_seen.lock().await.insert(
            (phone_id.clone(), TransportKind::RelayWan),
            now_unix(),
        );

        inner.sweep_stale_routes().await;

        assert_eq!(inner.router.available_transports(&phone_id), vec![TransportKind::RelayWan]);
        assert_eq!(inner.router.snapshot(&phone_id).state, TransportState::RemoteDirect);
    }

    #[tokio::test]
    async fn sms_bulk_packet_can_exceed_the_identity_packet_limit() {
        let packet = NetworkPacket::new(
            crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES,
            serde_json::json!({
                "version": 2,
                "messages": [{
                    "_id": 1,
                    "thread_id": 2,
                    "body": "x".repeat(MAX_IDENTITY_PACKET_BYTES + 512),
                    "date": 3,
                    "type": 1,
                    "read": 1,
                    "addresses": []
                }]
            })
            .as_object()
            .unwrap()
            .clone(),
        )
        .serialize();
        assert!(packet.len() > MAX_IDENTITY_PACKET_BYTES);
        let mut reader = std::io::Cursor::new(packet);

        let line = read_line_bounded(&mut reader, MAX_PACKET_BYTES)
            .await
            .expect("bulk SMS packet must fit the runtime packet bound");
        assert_eq!(
            NetworkPacket::parse(&line).unwrap().packet_type,
            crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES,
        );
    }

    #[tokio::test]
    async fn merging_sms_constructs_a_counted_event_and_thread_state() {
        let (event_tx, mut event_rx) = mpsc::unbounded_channel();
        let inner = LanInner::new(
            LocalIdentity::generate("Relay test").unwrap(),
            Vec::new(),
            LanConfig {
                bind: BindMode::Loopback,
                allow_loopback: true,
            },
            MIN_TCP_PORT,
            event_tx,
            CancellationToken::new(),
        );
        let message = SmsMessage {
            id: 7,
            thread_id: 4_294_967_297,
            addresses: vec!["+15550100".into()],
            body: "test".into(),
            date: 1_700_000_000_000,
            message_type: 1,
            read: Some(false),
            sub_id: Some(1),
            event: None,
            attachments: Vec::new(),
        };

        inner
            .merge_sms_messages("phone-id", vec![message.clone()])
            .await;

        match event_rx.recv().await.expect("SmsChanged event") {
            KdeConnectEvent::SmsChanged {
                device_id,
                conversations,
                messages,
            } => {
                assert_eq!(device_id, "phone-id");
                assert_eq!(conversations.len(), 1);
                assert_eq!(conversations[0].thread_id, 4_294_967_297);
                assert_eq!(conversations[0].unread_count, 1);
                assert_eq!(messages, vec![message]);
            }
            event => panic!("unexpected event: {event:?}"),
        }
        assert_eq!(
            inner
                .get_sms_messages("phone-id", 4_294_967_297)
                .await
                .len(),
            1
        );
    }

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
            let (stream, peer_addr) =
                tokio::time::timeout(Duration::from_secs(2), listener.accept())
                    .await
                    .expect("R0: accept timeout")
                    .unwrap();
            tokio::time::timeout(
                Duration::from_secs(2),
                inbound_tcp(relay_inner_clone, stream, peer_addr),
            )
            .await
            .expect("Relay inbound_tcp timeout")
        });

        let (close_tx, close_rx) = tokio::sync::oneshot::channel();
        let phone_identity_clone = phone_identity.clone();
        let phone_task = tokio::spawn(async move {
            let mut stream = tokio::time::timeout(Duration::from_secs(2), TcpStream::connect(addr))
                .await
                .expect("K0: connect timeout")
                .unwrap();
            // Pre-TLS identity
            let pre_tls = phone_identity_clone
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();
            // TLS server
            eprintln!("[TEST] K1 TLS start as server");
            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_server(&phone_identity_clone, stream, None),
            )
            .await
            .expect("K1: TLS handshake timeout")
            .unwrap();
            eprintln!("[TEST] K1 TLS complete");

            eprintln!("[TEST] K2 secure identity serialize");
            let secure_id = phone_identity_clone
                .identity_packet(None)
                .to_packet()
                .serialize();

            eprintln!("[TEST] K3 secure identity write start");
            tls.write_all(&secure_id).await.unwrap();
            eprintln!("[TEST] K4 secure identity write complete");

            tls.flush().await.unwrap();
            eprintln!("[TEST] K5 flush complete");

            eprintln!("[TEST] K6 read Relay secure identity start");
            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("K6: read Relay secure identity timeout")
            .unwrap();
            eprintln!("[TEST] K7 read Relay secure identity complete");

            let remote_id = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();
            assert_eq!(remote_id.device_id, relay_id);
            assert_eq!(remote_id.protocol_version, PROTOCOL_VERSION);
            let _ = close_rx.await;
            Ok::<(), anyhow::Error>(())
        });

        let relay_res = relay_task.await.unwrap();
        assert!(relay_res.is_ok());

        assert!(relay_inner.connections.lock().await.contains_key(&phone_id));
        let _ = close_tx.send(());
        let phone_res = phone_task.await.unwrap();
        assert!(phone_res.is_ok());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn v8_secure_identity_exchange_outbound() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let phone_id = phone_identity.device_id.clone();
        let relay_id = relay_identity.device_id.clone();

        let (close_tx, close_rx) = tokio::sync::oneshot::channel();
        let phone_identity_clone = phone_identity.clone();
        let phone_id_clone = phone_id.clone();
        let phone_task = tokio::spawn(async move {
            let (mut stream, _) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
                .await
                .expect("K0: accept timeout")
                .unwrap();
            // Read pre-TLS identity from Relay
            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut stream, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("K0: read pre-TLS line timeout")
            .unwrap();
            let _relay_pre = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // Phone is TCP server -> acts as TLS client
            eprintln!("[TEST] K1 TLS start as client");
            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_client(&phone_identity_clone, stream, &relay_id, None),
            )
            .await
            .expect("K1: TLS client handshake timeout")
            .unwrap();
            eprintln!("[TEST] K1 TLS complete");

            eprintln!("[TEST] K2 secure identity serialize");
            let secure_id = phone_identity_clone
                .identity_packet(None)
                .to_packet()
                .serialize();

            eprintln!("[TEST] K3 secure identity write start");
            tls.write_all(&secure_id).await.unwrap();
            eprintln!("[TEST] K4 secure identity write complete");

            tls.flush().await.unwrap();
            eprintln!("[TEST] K5 flush complete");

            eprintln!("[TEST] K6 read Relay secure identity start");
            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("K6: read Relay secure identity timeout")
            .unwrap();
            eprintln!("[TEST] K7 read Relay secure identity complete");

            let remote_id = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();
            assert_eq!(remote_id.device_id, relay_id);
            assert_eq!(remote_id.protocol_version, PROTOCOL_VERSION);
            let _ = close_rx.await;
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

        let relay_res = relay_task.await.unwrap();
        assert!(relay_res.is_ok());
        let _ = close_tx.send(());
        let phone_res = phone_task.await.unwrap();
        assert!(phone_res.is_ok());
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
            let pre_tls = phone_identity
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();
            let mut tls = start_tls_as_server(&phone_identity, stream, None)
                .await
                .unwrap();
            // Send mismatching protocol version post-TLS
            let mut bad_body = phone_identity.identity_packet(None);
            bad_body.protocol_version = 7; // Downgrade
            tls.write_all(&bad_body.to_packet().serialize())
                .await
                .unwrap();
            tls.flush().await.unwrap();
        });

        let (relay_res, _) = tokio::join!(relay_task, phone_task);
        assert!(relay_res.unwrap().is_err());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn paired_secure_session_updates_battery_and_stale_on_disconnect() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let phone_id = phone_identity.device_id.clone();

        let (event_tx, _event_rx) = tokio::sync::mpsc::unbounded_channel();
        let relay_inner = LanInner::new(
            relay_identity.clone(),
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_identity.device_id.clone(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: phone_identity.device_name.clone(),
                device_type: phone_identity.device_type.clone(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_inner_clone = Arc::clone(&relay_inner);
        let relay_task = tokio::spawn(async move {
            let (stream, peer_addr) =
                tokio::time::timeout(Duration::from_secs(2), listener.accept())
                    .await
                    .expect("accept timeout")
                    .unwrap();
            inbound_tcp(relay_inner_clone, stream, peer_addr).await
        });

        let phone_identity_clone = phone_identity.clone();
        let (close_tx, close_rx) = tokio::sync::oneshot::channel();
        let phone_task = tokio::spawn(async move {
            let mut stream = tokio::time::timeout(Duration::from_secs(2), TcpStream::connect(addr))
                .await
                .expect("connect timeout")
                .unwrap();
            let pre_tls = phone_identity_clone
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_server(&phone_identity_clone, stream, None),
            )
            .await
            .expect("TLS handshake timeout")
            .unwrap();

            let secure_id = phone_identity_clone
                .identity_packet(None)
                .to_packet()
                .serialize();
            tls.write_all(&secure_id).await.unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // Send battery packet
            let battery_pkt = BatteryBody::new(85, true, None).to_packet().serialize();
            tls.write_all(&battery_pkt).await.unwrap();
            tls.flush().await.unwrap();

            // Wait for signal to disconnect
            let _ = close_rx.await;
            drop(tls);
            Ok::<(), anyhow::Error>(())
        });

        let relay_res = relay_task.await.unwrap();
        assert!(relay_res.is_ok());

        // Wait for battery update in snapshot
        let mut got_battery = false;
        for _ in 0..20 {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let snapshot = relay_inner.snapshot().await;
            if let Some(dev) = snapshot.iter().find(|d| d.device_id == phone_id) {
                if dev.connected
                    && dev.battery_percentage == Some(85)
                    && dev.battery_is_charging == Some(true)
                {
                    got_battery = true;
                    break;
                }
            }
        }
        assert!(
            got_battery,
            "Expected live battery state (85%, charging=true)"
        );

        // Now trigger disconnect
        let _ = close_tx.send(());
        let _ = phone_task.await;

        // Verify that after disconnect, device is not connected, but last known battery percentage is retained
        let mut got_disconnected = false;
        for _ in 0..20 {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let snapshot = relay_inner.snapshot().await;
            if let Some(dev) = snapshot.iter().find(|d| d.device_id == phone_id) {
                if !dev.connected && dev.battery_percentage == Some(85) {
                    got_disconnected = true;
                    break;
                }
            }
        }
        assert!(
            got_disconnected,
            "Expected disconnected state retaining last known battery"
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn malformed_battery_packet_ignored_and_valid_packet_applied() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let phone_id = phone_identity.device_id.clone();

        let (event_tx, _event_rx) = tokio::sync::mpsc::unbounded_channel();
        let relay_inner = LanInner::new(
            relay_identity.clone(),
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_identity.device_id.clone(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: phone_identity.device_name.clone(),
                device_type: phone_identity.device_type.clone(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_inner_clone = Arc::clone(&relay_inner);
        let relay_task = tokio::spawn(async move {
            let (stream, peer_addr) =
                tokio::time::timeout(Duration::from_secs(2), listener.accept())
                    .await
                    .expect("accept timeout")
                    .unwrap();
            inbound_tcp(relay_inner_clone, stream, peer_addr).await
        });

        let phone_identity_clone = phone_identity.clone();
        let phone_task = tokio::spawn(async move {
            let mut stream = tokio::time::timeout(Duration::from_secs(2), TcpStream::connect(addr))
                .await
                .expect("connect timeout")
                .unwrap();
            let pre_tls = phone_identity_clone
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_server(&phone_identity_clone, stream, None),
            )
            .await
            .expect("TLS handshake timeout")
            .unwrap();

            let secure_id = phone_identity_clone
                .identity_packet(None)
                .to_packet()
                .serialize();
            tls.write_all(&secure_id).await.unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // 1. Send malformed battery packet (e.g. out of range 200%)
            let bad_battery = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":200,"isCharging":false}}"#;
            let mut bad_with_newline = bad_battery.to_vec();
            bad_with_newline.push(b'\n');
            tls.write_all(&bad_with_newline).await.unwrap();
            tls.flush().await.unwrap();

            tokio::time::sleep(Duration::from_millis(50)).await;

            // 2. Send valid battery packet (42%)
            let valid_battery = BatteryBody::new(42, false, None).to_packet().serialize();
            tls.write_all(&valid_battery).await.unwrap();
            tls.flush().await.unwrap();

            tokio::time::sleep(Duration::from_millis(100)).await;
            Ok::<(), anyhow::Error>(())
        });

        let relay_res = relay_task.await.unwrap();
        assert!(relay_res.is_ok());
        let _ = phone_task.await;

        let snapshot = relay_inner.snapshot().await;
        let dev = snapshot.iter().find(|d| d.device_id == phone_id).unwrap();
        assert_eq!(dev.battery_percentage, Some(42));
        assert_eq!(dev.battery_is_charging, Some(false));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn unpair_clears_battery_state() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();

        let (event_tx, _event_rx) = tokio::sync::mpsc::unbounded_channel();
        let relay_inner = LanInner::new(
            relay_identity.clone(),
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.clone(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: phone_identity.device_name.clone(),
                device_type: phone_identity.device_type.clone(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        // Manually insert a battery state for this paired device
        relay_inner.battery.lock().await.insert(
            phone_id.clone(),
            BatteryState {
                current_charge: 90,
                is_charging: true,
                threshold_event: None,
            },
        );

        let snap_before = relay_inner.snapshot().await;
        assert_eq!(
            snap_before
                .iter()
                .find(|d| d.device_id == phone_id)
                .unwrap()
                .battery_percentage,
            Some(90)
        );

        // Unpair
        relay_inner.unpair(&phone_id).await.unwrap();

        let snap_after = relay_inner.snapshot().await;
        if let Some(dev) = snap_after.iter().find(|d| d.device_id == phone_id) {
            assert_eq!(dev.battery_percentage, None);
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    /// Builds a `LanInner` with `phone_id` already trusted, for tests that only
    /// need the packet-handling half and not a real socket.
    fn dispatch_harness(
        phone_id: &str,
    ) -> (
        Arc<LanInner>,
        tokio::sync::mpsc::UnboundedReceiver<KdeConnectEvent>,
    ) {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let (event_tx, event_rx) = tokio::sync::mpsc::unbounded_channel();
        let inner = LanInner::new(
            relay_identity,
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.to_owned(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: "Phone".into(),
                device_type: "phone".into(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Loopback,
                allow_loopback: true,
            },
            0,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );
        (inner, event_rx)
    }

    /// Every control-plane packet type that has to keep working while the phone
    /// is Remote. The WAN receive task and the LAN reader call the *same*
    /// `handle_transport_packet`, so proving the chain claims each type proves
    /// it for both transports at once -- there is no separate WAN dispatch to
    /// drift out of sync with this list.
    const CONTROL_PLANE_PACKET_TYPES: &[&str] = &[
        crate::kdeconnect::PACKET_TYPE_BATTERY,
        crate::kdeconnect::PACKET_TYPE_CONNECTIVITY_REPORT,
        crate::kdeconnect::PACKET_TYPE_CLIPBOARD,
        crate::kdeconnect::PACKET_TYPE_PING,
        crate::kdeconnect::PACKET_TYPE_NOTIFICATION,
        crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES,
        crate::kdeconnect::PACKET_TYPE_TELEPHONY,
        crate::kdeconnect::PACKET_TYPE_RELAY_PING,
        crate::kdeconnect::PACKET_TYPE_RELAY_PONG,
        crate::kdeconnect::PACKET_TYPE_RELAY_DEVICE_STATE,
    ];

    fn minimal_packet(packet_type: &str) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        match packet_type {
            t if t == crate::kdeconnect::PACKET_TYPE_BATTERY => {
                body.insert("currentCharge".into(), 42.into());
                body.insert("isCharging".into(), true.into());
            }
            t if t == crate::kdeconnect::PACKET_TYPE_CONNECTIVITY_REPORT => {
                body.insert("signalStrengths".into(), serde_json::json!({}));
            }
            t if t == crate::kdeconnect::PACKET_TYPE_CLIPBOARD => {
                body.insert("content".into(), "hello".into());
            }
            t if t == crate::kdeconnect::PACKET_TYPE_NOTIFICATION => {
                body.insert("id".into(), "notif-1".into());
                body.insert("appName".into(), "Messages".into());
                body.insert("title".into(), "Alice".into());
                body.insert("text".into(), "hi".into());
            }
            t if t == crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES => {
                body.insert("version".into(), 2.into());
                body.insert("messages".into(), serde_json::json!([]));
            }
            t if t == crate::kdeconnect::PACKET_TYPE_TELEPHONY => {
                body.insert("event".into(), "ringing".into());
            }
            t if t == crate::kdeconnect::PACKET_TYPE_RELAY_PING
                || t == crate::kdeconnect::PACKET_TYPE_RELAY_PONG =>
            {
                body.insert("nonce".into(), "nonce-1".into());
                body.insert("timestamp".into(), 1_700_000_000_000_i64.into());
            }
            _ => {}
        }
        NetworkPacket::new(packet_type, body)
    }

    /// Builds a `LanInner` trusting several phones at once, for the multi-device
    /// notification-ownership tests.
    fn multi_device_harness(
        device_ids: &[&str],
    ) -> (
        Arc<LanInner>,
        tokio::sync::mpsc::UnboundedReceiver<KdeConnectEvent>,
    ) {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let (event_tx, event_rx) = tokio::sync::mpsc::unbounded_channel();
        let trusted = device_ids
            .iter()
            .map(|device_id| {
                let peer = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
                crate::kdeconnect::TrustedDevice {
                    device_id: (*device_id).to_owned(),
                    certificate_pem: peer.certificate_pem,
                    name: (*device_id).to_owned(),
                    device_type: "phone".into(),
                    protocol_version: PROTOCOL_VERSION,
                    paired_at_unix: 123456,
                    wan_endpoint_id: None,
                }
            })
            .collect();
        let inner = LanInner::new(
            relay_identity,
            trusted,
            LanConfig {
                bind: BindMode::Loopback,
                allow_loopback: true,
            },
            0,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );
        (inner, event_rx)
    }

    fn notification_packet(id: &str, title: &str, is_cancel: bool) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        body.insert("id".into(), id.into());
        body.insert("appName".into(), "WhatsApp".into());
        body.insert("title".into(), title.into());
        body.insert("text".into(), "body text".into());
        if is_cancel {
            body.insert("isCancel".into(), true.into());
        }
        NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_NOTIFICATION, body)
    }

    /// Delivers `packet` as if it arrived from `device_id` over some transport.
    async fn deliver(inner: &Arc<LanInner>, device_id: &str, packet: &NetworkPacket) {
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        assert!(
            inner
                .handle_transport_packet(device_id, packet, &PacketReplyRoute::Lan(tx))
                .await
        );
    }

    const PHONE_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const PHONE_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const TABLET: &str = "cccccccccccccccccccccccccccccccc";

    // --- MPRIS / RunCommand over the shared dispatcher -------------------

    /// A media host with no session bus behind it, so packet handling can be
    /// tested end to end without a real player.
    struct FakeMediaHost {
        players: Vec<crate::kdeconnect::media::PlayerSnapshot>,
        controls: std::sync::Mutex<Vec<(String, crate::kdeconnect::media::PlayerCommand)>>,
    }

    impl FakeMediaHost {
        fn with(names: &[&str]) -> Arc<Self> {
            Arc::new(Self {
                players: names
                    .iter()
                    .map(|name| crate::kdeconnect::media::PlayerSnapshot {
                        name: (*name).to_owned(),
                        title: Some(format!("{name} track")),
                        artist: Some("Artist".into()),
                        is_playing: true,
                        can_play: true,
                        can_pause: true,
                        can_go_next: true,
                        can_go_previous: true,
                        can_seek: true,
                        volume: Some(50),
                        length_ms: Some(200_000),
                        position_ms: Some(1_000),
                        ..Default::default()
                    })
                    .collect(),
                controls: std::sync::Mutex::new(Vec::new()),
            })
        }
    }

    impl crate::kdeconnect::media::MediaPlayerHost for FakeMediaHost {
        fn players(
            &self,
        ) -> crate::kdeconnect::media::HostFuture<'_, Vec<crate::kdeconnect::media::PlayerSnapshot>>
        {
            Box::pin(async move { self.players.clone() })
        }
        fn player<'a>(
            &'a self,
            name: &'a str,
        ) -> crate::kdeconnect::media::HostFuture<
            'a,
            Option<crate::kdeconnect::media::PlayerSnapshot>,
        > {
            Box::pin(async move { self.players.iter().find(|p| p.name == name).cloned() })
        }
        fn control<'a>(
            &'a self,
            name: &'a str,
            command: crate::kdeconnect::media::PlayerCommand,
        ) -> crate::kdeconnect::media::HostFuture<'a, anyhow::Result<()>> {
            Box::pin(async move {
                if !self.players.iter().any(|p| p.name == name) {
                    anyhow::bail!("no such MPRIS player");
                }
                self.controls
                    .lock()
                    .unwrap()
                    .push((name.to_owned(), command));
                Ok(())
            })
        }
    }

    #[derive(Default)]
    struct FakeRunner {
        spawned: std::sync::Mutex<Vec<String>>,
        fail: bool,
    }

    impl crate::kdeconnect::commands::CommandRunner for FakeRunner {
        fn spawn(&self, command_line: &str) -> anyhow::Result<()> {
            self.spawned.lock().unwrap().push(command_line.to_owned());
            if self.fail {
                anyhow::bail!("simulated spawn failure");
            }
            Ok(())
        }
    }

    fn mpris_request(pairs: &[(&str, serde_json::Value)]) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        for (key, value) in pairs {
            body.insert((*key).to_owned(), value.clone());
        }
        NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_MPRIS_REQUEST, body)
    }

    fn runcommand_request(pairs: &[(&str, serde_json::Value)]) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        for (key, value) in pairs {
            body.insert((*key).to_owned(), value.clone());
        }
        NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_RUNCOMMAND_REQUEST, body)
    }

    /// Drains everything the handler replied with on a LAN route.
    async fn drain(rx: &mut tokio::sync::mpsc::Receiver<Vec<u8>>) -> Vec<NetworkPacket> {
        // The MPRIS handler answers from a spawned task, so give it a moment.
        let mut packets = Vec::new();
        for _ in 0..50 {
            while let Ok(bytes) = rx.try_recv() {
                packets.push(NetworkPacket::parse(&bytes).unwrap());
            }
            if !packets.is_empty() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
        while let Ok(bytes) = rx.try_recv() {
            packets.push(NetworkPacket::parse(&bytes).unwrap());
        }
        packets
    }

    #[tokio::test]
    async fn a_player_list_request_is_answered_over_the_route_it_arrived_on() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_media_host(FakeMediaHost::with(&["Lollypop", "Firefox"])).await;
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        let packet = mpris_request(&[("requestPlayerList", true.into())]);
        assert!(
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
                .await
        );

        let packets = drain(&mut rx).await;
        let list = packets
            .iter()
            .find(|p| p.body.contains_key("playerList"))
            .expect("a player list reply");
        let names: Vec<&str> = list.body["playerList"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(serde_json::Value::as_str)
            .collect();
        assert_eq!(names, vec!["Lollypop", "Firefox"]);
    }

    #[tokio::test]
    async fn each_playback_action_reaches_the_addressed_player_and_returns_fresh_state() {
        for (action, expected) in [
            ("Play", crate::kdeconnect::media::PlayerCommand::Play),
            ("Pause", crate::kdeconnect::media::PlayerCommand::Pause),
            ("PlayPause", crate::kdeconnect::media::PlayerCommand::PlayPause),
            ("Stop", crate::kdeconnect::media::PlayerCommand::Stop),
            ("Next", crate::kdeconnect::media::PlayerCommand::Next),
            ("Previous", crate::kdeconnect::media::PlayerCommand::Previous),
        ] {
            let (inner, _events) = multi_device_harness(&[PHONE_A]);
            let host = FakeMediaHost::with(&["Lollypop"]);
            inner.set_media_host(host.clone()).await;
            let (tx, mut rx) = tokio::sync::mpsc::channel(16);

            let packet = mpris_request(&[
                ("player", "Lollypop".into()),
                ("action", action.into()),
            ]);
            assert!(
                inner
                    .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
                    .await
            );

            let packets = drain(&mut rx).await;
            assert_eq!(
                host.controls.lock().unwrap().as_slice(),
                &[("Lollypop".to_owned(), expected)],
                "{action} did not reach the player"
            );
            // The phone always gets state back so its UI reflects the result.
            let state = packets
                .iter()
                .find(|p| p.body.get("player").and_then(serde_json::Value::as_str) == Some("Lollypop"))
                .expect("fresh player state");
            assert_eq!(
                state.body.get("title").and_then(serde_json::Value::as_str),
                Some("Lollypop track")
            );
        }
    }

    #[tokio::test]
    async fn a_request_for_an_unknown_player_re_advertises_the_list_instead_of_acting() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let host = FakeMediaHost::with(&["Lollypop"]);
        inner.set_media_host(host.clone()).await;
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        let packet = mpris_request(&[
            ("player", "APlayerThatClosed".into()),
            ("action", "Play".into()),
        ]);
        inner
            .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
            .await;

        let packets = drain(&mut rx).await;
        assert!(
            host.controls.lock().unwrap().is_empty(),
            "an unknown player must never be resolved to a different one"
        );
        assert!(packets.iter().any(|p| p.body.contains_key("playerList")));
    }

    #[tokio::test]
    async fn a_malformed_mpris_packet_is_not_claimed_by_the_dispatcher() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_media_host(FakeMediaHost::with(&["Lollypop"])).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        // Names a player but asks for nothing at all.
        let packet = mpris_request(&[("player", "Lollypop".into())]);
        assert!(
            !inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
                .await,
            "an instruction-free request must be reported unhandled, not acted on"
        );
    }

    #[tokio::test]
    async fn two_logical_devices_each_get_their_own_media_answer() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        inner.set_media_host(FakeMediaHost::with(&["Lollypop"])).await;
        let (tx_a, mut rx_a) = tokio::sync::mpsc::channel(16);
        let (tx_b, mut rx_b) = tokio::sync::mpsc::channel(16);

        let packet = mpris_request(&[("requestPlayerList", true.into())]);
        inner
            .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx_a))
            .await;
        inner
            .handle_transport_packet(PHONE_B, &packet, &PacketReplyRoute::Lan(tx_b))
            .await;

        // Each device's answer goes to that device's own route -- state is not
        // keyed by transport, and one device's request never steals another's
        // reply.
        assert!(drain(&mut rx_a).await.iter().any(|p| p.body.contains_key("playerList")));
        assert!(drain(&mut rx_b).await.iter().any(|p| p.body.contains_key("playerList")));
    }

    #[tokio::test]
    async fn media_requests_are_answered_even_with_no_session_bus() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        // No media host installed at all.
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        let packet = mpris_request(&[("requestPlayerList", true.into())]);
        inner
            .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
            .await;

        let packets = drain(&mut rx).await;
        let list = packets.iter().find(|p| p.body.contains_key("playerList")).unwrap();
        assert_eq!(list.body["playerList"].as_array().map(Vec::len), Some(0));
    }

    fn sample_commands() -> Vec<crate::kdeconnect::commands::RunCommandEntry> {
        vec![
            crate::kdeconnect::commands::RunCommandEntry {
                id: "cmd-enabled".into(),
                name: "Marker".into(),
                command: "touch /tmp/relay-marker".into(),
                enabled: true,
            },
            crate::kdeconnect::commands::RunCommandEntry {
                id: "cmd-disabled".into(),
                name: "Disabled".into(),
                command: "echo nope".into(),
                enabled: false,
            },
        ]
    }

    #[tokio::test]
    async fn only_enabled_commands_are_advertised_and_the_list_reaches_the_asking_device() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        let packet = runcommand_request(&[("requestCommandList", true.into())]);
        assert!(
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
                .await
        );

        let packets = drain(&mut rx).await;
        let list = packets.iter().find(|p| p.body.contains_key("commandList")).unwrap();
        // Upstream encodes the list as a JSON *string*, keyed by command id.
        let encoded = list.body["commandList"].as_str().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(encoded).unwrap();
        assert!(parsed.get("cmd-enabled").is_some());
        assert!(parsed.get("cmd-disabled").is_none(), "a disabled command must not be visible");
        assert_eq!(
            list.body.get("canAddCommand").and_then(serde_json::Value::as_bool),
            Some(false),
            "the phone must never be told it can define commands"
        );
    }

    #[tokio::test]
    async fn an_enabled_command_runs_the_locally_configured_line() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        let packet = runcommand_request(&[("key", "cmd-enabled".into())]);
        inner
            .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
            .await;

        assert_eq!(
            runner.spawned.lock().unwrap().as_slice(),
            ["touch /tmp/relay-marker"]
        );
    }

    #[tokio::test]
    async fn a_disabled_or_unknown_command_never_runs() {
        for key in ["cmd-disabled", "cmd-nonexistent", ""] {
            let (inner, _events) = multi_device_harness(&[PHONE_A]);
            inner.set_run_commands(sample_commands());
            let runner = Arc::new(FakeRunner::default());
            inner.set_command_runner(runner.clone()).await;
            let (tx, _rx) = tokio::sync::mpsc::channel(16);

            let packet = runcommand_request(&[("key", key.into())]);
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
                .await;

            assert!(runner.spawned.lock().unwrap().is_empty(), "{key} ran");
        }
    }

    #[tokio::test]
    async fn command_text_in_a_packet_is_never_executed() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        // Every shape a phone might try to smuggle a command line through.
        for packet in [
            runcommand_request(&[("key", "rm -rf ~".into())]),
            runcommand_request(&[("command", "rm -rf ~".into())]),
            runcommand_request(&[("key", "cmd-enabled; rm -rf ~".into())]),
            runcommand_request(&[
                ("key", "cmd-nonexistent".into()),
                ("command", "rm -rf ~".into()),
            ]),
        ] {
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx.clone()))
                .await;
        }

        assert!(
            runner.spawned.lock().unwrap().is_empty(),
            "remote command text must never reach the runner"
        );
    }

    #[tokio::test]
    async fn an_untrusted_device_can_neither_list_nor_run_commands() {
        // The harness trusts PHONE_A only.
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        let stranger = "dddddddddddddddddddddddddddddddd";
        inner
            .handle_transport_packet(
                stranger,
                &runcommand_request(&[("requestCommandList", true.into())]),
                &PacketReplyRoute::Lan(tx.clone()),
            )
            .await;
        inner
            .handle_transport_packet(
                stranger,
                &runcommand_request(&[("key", "cmd-enabled".into())]),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(runner.spawned.lock().unwrap().is_empty());
        assert!(
            rx.try_recv().is_err(),
            "an untrusted device must not even learn what commands exist"
        );
    }

    #[tokio::test]
    async fn a_spawn_failure_is_contained_and_the_link_keeps_working() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        inner
            .set_command_runner(Arc::new(FakeRunner {
                fail: true,
                ..Default::default()
            }))
            .await;
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        // The failing spawn must not unwind into the dispatcher...
        inner
            .handle_transport_packet(
                PHONE_A,
                &runcommand_request(&[("key", "cmd-enabled".into())]),
                &PacketReplyRoute::Lan(tx.clone()),
            )
            .await;

        // ...and the very next packet on the same route still works.
        assert!(
            inner
                .handle_transport_packet(
                    PHONE_A,
                    &runcommand_request(&[("requestCommandList", true.into())]),
                    &PacketReplyRoute::Lan(tx),
                )
                .await
        );
        assert!(drain(&mut rx).await.iter().any(|p| p.body.contains_key("commandList")));
    }

    #[tokio::test]
    async fn two_devices_get_independent_command_lists_and_execution_is_attributed() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;
        let (tx_a, mut rx_a) = tokio::sync::mpsc::channel(16);
        let (tx_b, mut rx_b) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &runcommand_request(&[("requestCommandList", true.into())]),
                &PacketReplyRoute::Lan(tx_a),
            )
            .await;
        inner
            .handle_transport_packet(
                PHONE_B,
                &runcommand_request(&[("key", "cmd-enabled".into())]),
                &PacketReplyRoute::Lan(tx_b),
            )
            .await;

        // A asked for a list and got one; B asked to run and got no list.
        assert!(drain(&mut rx_a).await.iter().any(|p| p.body.contains_key("commandList")));
        assert!(rx_b.try_recv().is_err());
        assert_eq!(runner.spawned.lock().unwrap().len(), 1);
    }

    /// A link registered at Relay WAN's real priority (15) that records what was
    /// sent over it, so the WAN route can be exercised without an Iroh
    /// connection. Behaviour under test is the dispatcher's, which is shared by
    /// both transports by construction.
    #[cfg(feature = "kdeconnect-wan")]
    struct RecordingWanLink {
        device_id: String,
        sent: std::sync::Mutex<Vec<NetworkPacket>>,
    }

    #[cfg(feature = "kdeconnect-wan")]
    impl crate::kdeconnect::wan::TransportLink for RecordingWanLink {
        fn device_id(&self) -> &str {
            &self.device_id
        }
        fn kind(&self) -> crate::kdeconnect::wan::TransportKind {
            crate::kdeconnect::wan::TransportKind::RelayWan
        }
        fn state(&self) -> crate::kdeconnect::wan::TransportState {
            crate::kdeconnect::wan::TransportState::RemoteDirect
        }
        fn metadata(&self) -> crate::kdeconnect::wan::TransportMetadata {
            crate::kdeconnect::wan::TransportMetadata {
                kind: self.kind(),
                state: self.state(),
                last_seen_unix: None,
                last_transition_reason: None,
            }
        }
        fn send_packet<'a>(
            &'a self,
            packet: &'a NetworkPacket,
        ) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<()>> {
            Box::pin(async move {
                self.sent.lock().unwrap().push(packet.clone());
                Ok(())
            })
        }
        fn send_payload<'a>(
            &'a self,
            _request: crate::kdeconnect::wan::PayloadRequest<'a>,
        ) -> crate::kdeconnect::wan::transport::LinkFuture<
            'a,
            Result<crate::kdeconnect::wan::PayloadOutcome>,
        > {
            Box::pin(async move { Ok(crate::kdeconnect::wan::PayloadOutcome::Sent) })
        }
        fn disconnect(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, ()> {
            Box::pin(async move {})
        }
        fn health(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, bool> {
            Box::pin(async move { true })
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    fn wan_route(device_id: &str) -> (Arc<RecordingWanLink>, PacketReplyRoute) {
        let link = Arc::new(RecordingWanLink {
            device_id: device_id.to_owned(),
            sent: std::sync::Mutex::new(Vec::new()),
        });
        let route = PacketReplyRoute::Wan(
            Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>
        );
        (link, route)
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn wan_sent(link: &Arc<RecordingWanLink>) -> Vec<NetworkPacket> {
        // The MPRIS handler replies from a spawned task.
        for _ in 0..50 {
            if !link.sent.lock().unwrap().is_empty() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
        link.sent.lock().unwrap().clone()
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn media_control_works_identically_when_the_request_arrives_over_relay_wan() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let host = FakeMediaHost::with(&["Lollypop"]);
        inner.set_media_host(host.clone()).await;
        let (link, route) = wan_route(PHONE_A);

        let packet = mpris_request(&[
            ("player", "Lollypop".into()),
            ("action", "PlayPause".into()),
        ]);
        assert!(inner.handle_transport_packet(PHONE_A, &packet, &route).await);

        let sent = wan_sent(&link).await;
        assert_eq!(
            host.controls.lock().unwrap().as_slice(),
            &[(
                "Lollypop".to_owned(),
                crate::kdeconnect::media::PlayerCommand::PlayPause
            )],
            "the same handler must drive the player regardless of transport"
        );
        assert!(
            sent.iter().any(|p| p.packet_type == crate::kdeconnect::PACKET_TYPE_MPRIS),
            "fresh state must come back over the WAN route it arrived on"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_run_command_executes_when_requested_over_relay_wan() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;
        let (link, route) = wan_route(PHONE_A);

        inner
            .handle_transport_packet(
                PHONE_A,
                &runcommand_request(&[("requestCommandList", true.into())]),
                &route,
            )
            .await;
        inner
            .handle_transport_packet(
                PHONE_A,
                &runcommand_request(&[("key", "cmd-enabled".into())]),
                &route,
            )
            .await;

        let sent = wan_sent(&link).await;
        assert!(sent.iter().any(|p| p.body.contains_key("commandList")));
        assert_eq!(
            runner.spawned.lock().unwrap().as_slice(),
            ["touch /tmp/relay-marker"]
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn relay_wan_does_not_widen_what_a_phone_may_run() {
        // Same refusals over WAN as over LAN: the transport is not part of the
        // permission decision.
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;

        let (_link, trusted_route) = wan_route(PHONE_A);
        for key in ["cmd-disabled", "cmd-nonexistent", "touch /tmp/relay-marker"] {
            inner
                .handle_transport_packet(
                    PHONE_A,
                    &runcommand_request(&[("key", key.into())]),
                    &trusted_route,
                )
                .await;
        }

        // And an untrusted device is refused over WAN too.
        let stranger = "dddddddddddddddddddddddddddddddd";
        let (stranger_link, stranger_route) = wan_route(stranger);
        inner
            .handle_transport_packet(
                stranger,
                &runcommand_request(&[("key", "cmd-enabled".into())]),
                &stranger_route,
            )
            .await;
        inner
            .handle_transport_packet(
                stranger,
                &runcommand_request(&[("requestCommandList", true.into())]),
                &stranger_route,
            )
            .await;

        assert!(runner.spawned.lock().unwrap().is_empty());
        assert!(stranger_link.sent.lock().unwrap().is_empty());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn lan_keeps_priority_over_wan_for_the_reply_when_both_routes_exist() {
        // The reply always goes back on the route the request arrived on, but
        // unsolicited sends go through the router, where LAN still wins.
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (link, _route) = wan_route(PHONE_A);
        inner.router.register(Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>);

        assert_eq!(
            inner.router.active_transport(PHONE_A),
            Some(TransportKind::RelayWan),
            "WAN carries the device while LAN is absent"
        );
        assert!(
            TransportKind::KdeLan.priority() > TransportKind::RelayWan.priority(),
            "LAN must outrank WAN once it returns"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    struct TestRouteLink {
        device_id: String,
        kind: crate::kdeconnect::wan::TransportKind,
    }

    #[cfg(feature = "kdeconnect-wan")]
    impl crate::kdeconnect::wan::TransportLink for TestRouteLink {
        fn device_id(&self) -> &str {
            &self.device_id
        }
        fn kind(&self) -> crate::kdeconnect::wan::TransportKind {
            self.kind
        }
        fn state(&self) -> crate::kdeconnect::wan::TransportState {
            crate::kdeconnect::wan::TransportState::Local
        }
        fn metadata(&self) -> crate::kdeconnect::wan::TransportMetadata {
            crate::kdeconnect::wan::TransportMetadata {
                kind: self.kind,
                state: self.state(),
                last_seen_unix: None,
                last_transition_reason: None,
            }
        }
        fn send_packet<'a>(
            &'a self,
            _packet: &'a NetworkPacket,
        ) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<()>> {
            Box::pin(async move { Ok(()) })
        }
        fn send_payload<'a>(
            &'a self,
            _request: crate::kdeconnect::wan::PayloadRequest<'a>,
        ) -> crate::kdeconnect::wan::transport::LinkFuture<'a, Result<crate::kdeconnect::wan::PayloadOutcome>> {
            Box::pin(async move { Ok(crate::kdeconnect::wan::PayloadOutcome::Sent) })
        }
        fn disconnect(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, ()> {
            Box::pin(async move {})
        }
        fn health(&self) -> crate::kdeconnect::wan::transport::LinkFuture<'_, bool> {
            Box::pin(async move { true })
        }
    }

    // --- File transfer -----------------------------------------------------

    fn share_packet(filename: &str, size: i64, relay_payload_id: Option<&str>) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        body.insert("filename".into(), filename.into());
        body.insert("totalPayloadSize".into(), size.into());
        body.insert("numberOfFiles".into(), 1.into());
        if let Some(id) = relay_payload_id {
            let mut info = serde_json::Map::new();
            info.insert("relayPayloadId".into(), id.into());
            info.insert("payloadSize".into(), size.into());
            body.insert("payloadTransferInfo".into(), serde_json::Value::Object(info));
        }
        NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST, body)
    }

    async fn transfer_events(
        events: &mut tokio::sync::mpsc::UnboundedReceiver<KdeConnectEvent>,
    ) -> Vec<crate::kdeconnect::files::Transfer> {
        let mut seen = Vec::new();
        while let Ok(event) = events.try_recv() {
            if let KdeConnectEvent::TransferChanged { transfer } = event {
                seen.push(transfer);
            }
        }
        seen
    }

    #[tokio::test]
    async fn an_announced_file_registers_a_transfer_for_its_own_device() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("photo.jpg", 1024, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        let seen = transfer_events(&mut events).await;
        assert_eq!(seen.len(), 1);
        assert_eq!(seen[0].filename, "photo.jpg");
        assert_eq!(seen[0].total_bytes, 1024);
        assert_eq!(seen[0].key.device_id, PHONE_A);
        assert!(inner.transfers_for(PHONE_B).await.is_empty(), "scoped to its device");
    }

    #[tokio::test]
    async fn an_untrusted_device_cannot_announce_a_file() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                "dddddddddddddddddddddddddddddddd",
                &share_packet("evil.bin", 10, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(transfer_events(&mut events).await.is_empty());
    }

    #[tokio::test]
    async fn an_oversized_announcement_is_refused_without_registering_a_transfer() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let over = (crate::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES + 1) as i64;

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("huge.bin", over, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(transfer_events(&mut events).await.is_empty());
        assert!(inner.transfers_for(PHONE_A).await.is_empty());
    }

    #[tokio::test]
    async fn an_unknown_size_announcement_is_ignored() {
        // Android sends -1 when the ContentResolver cannot report a size.
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("mystery.bin", -1, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(transfer_events(&mut events).await.is_empty());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn an_announced_payload_streams_to_disk_and_completes() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        let body = vec![7_u8; 4096];
        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("data.bin", body.len() as i64, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        let mut source = std::io::Cursor::new(body.clone());
        inner
            .handle_incoming_payload("payload-1", body.len() as u64, &mut source)
            .await;

        let seen = transfer_events(&mut events).await;
        let last = seen.last().expect("a terminal event");
        assert_eq!(
            last.state,
            crate::kdeconnect::files::TransferState::Completed { total: 4096 }
        );
        assert_eq!(tokio::fs::read(dir.path().join("data.bin")).await.unwrap(), body);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_payload_with_no_announcement_is_dropped_without_writing_anything() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;

        let mut source = std::io::Cursor::new(vec![1_u8; 100]);
        inner.handle_incoming_payload("never-announced", 100, &mut source).await;

        let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
        assert!(
            entries.next_entry().await.unwrap().is_none(),
            "matching a payload id alone must never be enough to accept content"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_duplicate_payload_id_is_only_honoured_once() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("once.bin", 10, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        let mut first = std::io::Cursor::new(vec![1_u8; 10]);
        inner.handle_incoming_payload("payload-1", 10, &mut first).await;
        let mut second = std::io::Cursor::new(vec![2_u8; 10]);
        inner.handle_incoming_payload("payload-1", 10, &mut second).await;

        // The announcement is consumed by the first stream; the replay writes
        // nothing, so only one file exists.
        let mut count = 0;
        let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
        while entries.next_entry().await.unwrap().is_some() {
            count += 1;
        }
        assert_eq!(count, 1);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_stream_that_contradicts_its_announcement_fails_without_a_file() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("x.bin", 100, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        let mut source = std::io::Cursor::new(vec![0_u8; 40]);
        inner.handle_incoming_payload("payload-1", 40, &mut source).await;

        let seen = transfer_events(&mut events).await;
        assert!(matches!(
            seen.last().unwrap().state,
            crate::kdeconnect::files::TransferState::Failed { .. }
        ));
        let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
        assert!(entries.next_entry().await.unwrap().is_none());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_traversing_filename_lands_inside_the_download_directory() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("../../../etc/passwd", 4, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;
        let mut source = std::io::Cursor::new(b"nope".to_vec());
        inner.handle_incoming_payload("payload-1", 4, &mut source).await;

        assert!(dir.path().join("passwd").exists(), "must be confined to the directory");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn an_oversized_file_is_refused_before_sending_when_the_route_is_remote() {
        use crate::kdeconnect::files::TransferState;
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (link, _route) = wan_route(PHONE_A);
        inner
            .router
            .register(Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (vec![crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST.to_owned()], vec![]),
        );

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("huge.bin");
        // Sparse file: the size is what matters, not the bytes.
        let file = std::fs::File::create(&path).unwrap();
        file.set_len(crate::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES + 1).unwrap();
        drop(file);

        inner.send_file(PHONE_A, &path).await.unwrap();

        let seen = transfer_events(&mut events).await;
        assert_eq!(
            seen.last().unwrap().state,
            TransferState::RequiresLocalConnection,
            "an oversized remote file is a policy outcome, not a network error"
        );
        assert!(
            link.sent.lock().unwrap().is_empty(),
            "not a single packet may go out for a file that cannot be sent"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_file_at_exactly_the_limit_is_announced_over_a_remote_route() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (link, _route) = wan_route(PHONE_A);
        inner
            .router
            .register(Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (vec![crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST.to_owned()], vec![]),
        );

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("exact.bin");
        std::fs::write(&path, b"small").unwrap();

        inner.send_file(PHONE_A, &path).await.unwrap();
        for _ in 0..50 {
            if !link.sent.lock().unwrap().is_empty() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }

        let sent = link.sent.lock().unwrap().clone();
        let announcement = sent
            .iter()
            .find(|packet| packet.packet_type == crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST)
            .expect("the file must be announced");
        // The WAN correlation id must be present so the receiver can match the
        // payload stream to this announcement.
        assert!(
            announcement.body["payloadTransferInfo"]["relayPayloadId"].is_string(),
            "a remote announcement carries its payload id"
        );
    }

    // --- Device Fabric ------------------------------------------------------

    #[cfg(feature = "kdeconnect-wan")]
    async fn fabric_of(inner: &Arc<LanInner>, device_id: &str) -> crate::kdeconnect::fabric::RelayDeviceRecord {
        inner
            .device_fabric()
            .await
            .devices
            .into_iter()
            .find(|record| record.id == device_id)
            .expect("device should be in the fabric")
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn one_device_reachable_over_both_routes_appears_exactly_once() {
        use crate::kdeconnect::fabric::RelayConnectionState;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;

        let fabric = inner.device_fabric().await.devices;

        assert_eq!(fabric.len(), 1, "LAN and WAN are routes, not devices");
        assert_eq!(fabric[0].id, PHONE_A);
        assert!(fabric[0].routes.wan_available);
        // LAN wins for the reported state whenever it is healthy.
        assert_eq!(fabric[0].connection, RelayConnectionState::Local);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn route_registration_order_does_not_change_the_result() {
        use crate::kdeconnect::wan::TransportKind;
        let (first, _e1) = multi_device_harness(&[PHONE_A]);
        with_route(&first, PHONE_A, TransportKind::KdeLan).await;
        with_route(&first, PHONE_A, TransportKind::RelayWan).await;

        let (second, _e2) = multi_device_harness(&[PHONE_A]);
        with_route(&second, PHONE_A, TransportKind::RelayWan).await;
        with_route(&second, PHONE_A, TransportKind::KdeLan).await;

        assert_eq!(first.device_fabric().await.devices.len(), 1);
        assert_eq!(second.device_fabric().await.devices.len(), 1);
        assert_eq!(
            fabric_of(&first, PHONE_A).await.routes.wan_available,
            fabric_of(&second, PHONE_A).await.routes.wan_available
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_trusted_device_with_no_route_is_offline_but_still_present() {
        use crate::kdeconnect::fabric::RelayConnectionState;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);

        let fabric = inner.device_fabric().await.devices;

        assert_eq!(fabric.len(), 1, "a trusted device stays visible while offline");
        assert!(fabric[0].trusted, "trust is independent of connectivity");
        assert_eq!(fabric[0].connection, RelayConnectionState::Offline);
        assert_eq!(fabric[0].last_seen(), None);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn devices_are_independent_of_one_another() {
        use crate::kdeconnect::fabric::RelayConnectionState;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B, TABLET]);
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;
        with_route(&inner, PHONE_B, TransportKind::RelayWan).await;

        let fabric = inner.device_fabric().await.devices;
        assert_eq!(fabric.len(), 3);

        // One device on LAN, another on WAN, a third offline -- all at once.
        assert_eq!(fabric_of(&inner, PHONE_B).await.connection, RelayConnectionState::RemoteDirect);
        assert_eq!(fabric_of(&inner, TABLET).await.connection, RelayConnectionState::Offline);

        // Phone A losing LAN must not disturb the others.
        inner.router.unregister(PHONE_A, TransportKind::KdeLan);
        assert_eq!(fabric_of(&inner, PHONE_A).await.connection, RelayConnectionState::Offline);
        assert_eq!(fabric_of(&inner, PHONE_B).await.connection, RelayConnectionState::RemoteDirect);
        assert_eq!(fabric_of(&inner, TABLET).await.connection, RelayConnectionState::Offline);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn capabilities_belong_to_the_device_and_are_isolated_per_device() {
        use crate::kdeconnect::fabric::RelayFeature;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A, TABLET]);
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;
        with_route(&inner, TABLET, TransportKind::KdeLan).await;

        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (
                vec![
                    crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS.to_owned(),
                    crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST.to_owned(),
                ],
                vec![crate::kdeconnect::PACKET_TYPE_NOTIFICATION.to_owned()],
            ),
        );
        inner.peer_capabilities.lock().await.insert(
            TABLET.to_owned(),
            (vec![crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST.to_owned()], vec![]),
        );

        let phone = fabric_of(&inner, PHONE_A).await;
        let tablet = fabric_of(&inner, TABLET).await;

        assert!(phone.supports(RelayFeature::Messages));
        assert!(phone.supports(RelayFeature::Notifications));
        assert!(
            !tablet.supports(RelayFeature::Messages),
            "one device lacking SMS must not borrow another's capability"
        );
        assert!(tablet.supports(RelayFeature::Files), "and keeps its own");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn capabilities_survive_a_route_change_because_they_belong_to_the_device() {
        use crate::kdeconnect::fabric::RelayFeature;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;
        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (
                vec![crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS.to_owned()],
                vec![],
            ),
        );
        assert!(fabric_of(&inner, PHONE_A).await.supports(RelayFeature::Messages));

        // Go Remote: the capability set must be unchanged.
        inner.router.unregister(PHONE_A, TransportKind::KdeLan);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;

        let remote = fabric_of(&inner, PHONE_A).await;
        assert!(remote.connection.is_remote());
        assert!(
            remote.supports(RelayFeature::Messages),
            "going Remote must not strip a capability"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn battery_state_is_reported_against_its_own_device() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;
        inner.battery.lock().await.insert(
            PHONE_A.to_owned(),
            BatteryState { current_charge: 58, is_charging: true, threshold_event: None },
        );

        assert_eq!(fabric_of(&inner, PHONE_A).await.battery_percent, Some(58));
        assert_eq!(fabric_of(&inner, PHONE_A).await.charging, Some(true));
        assert_eq!(fabric_of(&inner, PHONE_B).await.battery_percent, None);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn the_snapshot_carries_the_local_policy_so_availability_is_answered_once() {
        use crate::kdeconnect::fabric::{FeatureAvailability, RelayFeature};
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;
        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (
                vec![
                    crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT.to_owned(),
                    crate::kdeconnect::PACKET_TYPE_SMS_REQUEST_CONVERSATIONS.to_owned(),
                ],
                vec![crate::kdeconnect::PACKET_TYPE_RUNCOMMAND_REQUEST.to_owned()],
            ),
        );

        inner.set_clipboard_enabled(false);
        let snapshot = inner.device_fabric().await;
        assert!(!snapshot.policy.clipboard_enabled);
        let device = snapshot.get(PHONE_A).expect("device is in the fabric");
        // Switched off locally is Disabled, which is a different answer from a
        // peer that cannot do it at all.
        assert_eq!(
            device.availability(RelayFeature::Clipboard, &snapshot.policy),
            FeatureAvailability::Disabled
        );
        // Nothing configured yet is its own state, so the UI can explain it.
        assert_eq!(
            device.availability(RelayFeature::Commands, &snapshot.policy),
            FeatureAvailability::NotConfigured
        );
        assert_eq!(
            device.availability(RelayFeature::Messages, &snapshot.policy),
            FeatureAvailability::Available
        );

        inner.set_clipboard_enabled(true);
        let snapshot = inner.device_fabric().await;
        assert_eq!(
            snapshot
                .get(PHONE_A)
                .unwrap()
                .availability(RelayFeature::Clipboard, &snapshot.policy),
            FeatureAvailability::Available
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_device_change_emits_one_event_carrying_both_views() {
        use crate::kdeconnect::fabric::RelayConnectionState;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;

        inner.emit_devices().await;

        let event = events.recv().await.expect("one event");
        let KdeConnectEvent::DevicesChanged { devices, fabric } = event else {
            panic!("expected DevicesChanged");
        };
        // One change, one event: the legacy snapshot and the fabric describe the
        // same moment rather than arriving separately and disagreeing.
        assert_eq!(devices.len(), 1);
        assert_eq!(fabric.devices.len(), 1);
        assert_eq!(fabric.devices[0].id, PHONE_A);
        assert_eq!(fabric.devices[0].connection, RelayConnectionState::RemoteDirect);
        assert!(events.try_recv().is_err(), "and no second event follows");
    }

    // --- Forget -------------------------------------------------------------

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn forgetting_a_device_removes_its_wan_binding_so_it_cannot_reconnect() {
        use crate::kdeconnect::wan::{TransportKind, WanBinding};
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;

        let endpoint = iroh::SecretKey::generate().public();
        inner.wan_bindings.upsert(WanBinding {
            kde_device_id: PHONE_A.to_owned(),
            endpoint_id: endpoint,
            display_name: "Phone A".into(),
            device_type: "phone".into(),
            capabilities: Vec::new(),
            binding_version: 1,
            updated_at_unix: 0,
            last_wan_connected_at_unix: None,
            last_transport: None,
        });
        assert!(inner.wan_bindings.by_kde_device_id(PHONE_A).is_some());

        let _ = inner.unpair(PHONE_A).await;

        assert!(
            inner.wan_bindings.by_kde_device_id(PHONE_A).is_none(),
            "a forgotten device must not keep a binding it could reconnect through"
        );
        assert!(
            inner.wan_bindings.by_endpoint_id(&endpoint).is_none(),
            "and the endpoint must no longer resolve to any device"
        );
        assert!(inner.router.available_transports(PHONE_A).is_empty());
        assert!(inner.trust.lock().await.get(PHONE_A).is_none());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn forgetting_one_device_leaves_every_other_device_untouched() {
        use crate::kdeconnect::wan::{TransportKind, WanBinding};
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;
        with_route(&inner, PHONE_B, TransportKind::RelayWan).await;

        let keep = iroh::SecretKey::generate().public();
        inner.wan_bindings.upsert(WanBinding {
            kde_device_id: PHONE_B.to_owned(),
            endpoint_id: keep,
            display_name: "Phone B".into(),
            device_type: "phone".into(),
            capabilities: Vec::new(),
            binding_version: 1,
            updated_at_unix: 0,
            last_wan_connected_at_unix: None,
            last_transport: None,
        });
        inner.battery.lock().await.insert(
            PHONE_B.to_owned(),
            BatteryState { current_charge: 71, is_charging: false, threshold_event: None },
        );

        let _ = inner.unpair(PHONE_A).await;

        let fabric = inner.device_fabric().await.devices;
        assert_eq!(fabric.len(), 1, "only the forgotten device disappears");
        assert_eq!(fabric[0].id, PHONE_B);
        assert!(inner.wan_bindings.by_kde_device_id(PHONE_B).is_some());
        assert_eq!(fabric[0].battery_percent, Some(71));
        assert!(!inner.router.available_transports(PHONE_B).is_empty());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn forgetting_a_device_clears_its_feature_state_only() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        for device in [PHONE_A, PHONE_B] {
            inner
                .handle_transport_packet(
                    device,
                    &notification_packet("n1", "hi", false),
                    &PacketReplyRoute::Lan(tx.clone()),
                )
                .await;
            inner
                .handle_transport_packet(
                    device,
                    &share_packet("x.bin", 100, Some(&format!("payload-{device}"))),
                    &PacketReplyRoute::Lan(tx.clone()),
                )
                .await;
        }
        assert_eq!(inner.transfers_for(PHONE_A).await.len(), 1);
        assert_eq!(inner.transfers_for(PHONE_B).await.len(), 1);

        let _ = inner.unpair(PHONE_A).await;

        assert!(inner.get_notifications(PHONE_A).await.is_empty());
        assert!(inner.transfers_for(PHONE_A).await.is_empty());
        // The other device keeps everything.
        assert_eq!(inner.get_notifications(PHONE_B).await.len(), 1);
        assert_eq!(inner.transfers_for(PHONE_B).await.len(), 1);
    }

    // --- KDE LAN payload transport (real sockets + real TLS) ---------------

    /// Runs one full LAN payload exchange over loopback with real pinned TLS,
    /// returning what landed on disk.
    ///
    /// This is the actual protocol: the sender binds a listener and is the TLS
    /// *server*, the receiver dials back and is the TLS *client*, and both pin
    /// the other's certificate.
    async fn lan_payload_round_trip(
        sender_identity: &LocalIdentity,
        receiver_identity: &LocalIdentity,
        sender_pin: Vec<u8>,
        receiver_pin: Vec<u8>,
        body: Vec<u8>,
        filename: &str,
    ) -> Result<(std::path::PathBuf, tempfile::TempDir)> {
        use crate::kdeconnect::files::{lan_payload, receive::IncomingFile};

        let listener = lan_payload::PayloadListener::bind().await?;
        let port = listener.port();
        let size = body.len() as u64;

        let sender_identity = sender_identity.clone();
        let send = tokio::spawn(async move {
            let stream = listener.accept().await?;
            let mut tls = start_tls_as_server(&sender_identity, stream, Some(&receiver_pin)).await?;
            let mut source = std::io::Cursor::new(body);
            lan_payload::stream_payload(&mut source, &mut tls, size, |_| {}).await?;
            tokio::io::AsyncWriteExt::shutdown(&mut tls).await.ok();
            Ok::<_, anyhow::Error>(())
        });

        let dir = tempfile::tempdir()?;
        let stream =
            lan_payload::connect_to_payload(std::net::IpAddr::from([127, 0, 0, 1]), port).await?;
        let mut tls = start_tls_as_client(
            receiver_identity,
            stream,
            &sender_identity_device_id(&sender_pin),
            Some(&sender_pin),
        )
        .await?;
        let mut incoming = IncomingFile::create(dir.path(), filename, size, None).await?;
        incoming.stream_from(&mut tls, |_| {}).await?;
        let path = incoming.finalize().await?;
        send.await??;
        Ok((path, dir))
    }

    /// The pinned certificate is matched by bytes, so any stable name works for
    /// the TLS SNI field in these tests.
    fn sender_identity_device_id(_pin: &[u8]) -> String {
        "lan-payload-peer".to_string()
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_large_lan_announcement_is_accepted_while_the_same_size_over_wan_is_not() {
        let over = (crate::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES + 1) as i64;

        // LAN: announced with a port, no relayPayloadId -- must be accepted.
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let mut lan = share_packet("big.bin", over, None);
        let mut info = serde_json::Map::new();
        info.insert("port".into(), 1739.into());
        lan.body.insert("payloadTransferInfo".into(), serde_json::Value::Object(info));
        inner
            .handle_transport_packet(PHONE_A, &lan, &PacketReplyRoute::Lan(tx))
            .await;
        assert_eq!(
            inner.transfers_for(PHONE_A).await.len(),
            1,
            "a large local file must be accepted"
        );

        // WAN: the same size with a relayPayloadId must be refused.
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("big.bin", over, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;
        assert!(inner.transfers_for(PHONE_A).await.is_empty());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_lan_payload_streams_over_real_pinned_tls_byte_for_byte() {
        let sender = LocalIdentity::generate("Sender").unwrap();
        let receiver = LocalIdentity::generate("Receiver").unwrap();
        let sender_cert = sender.certificate_der().unwrap().as_ref().to_vec();
        let receiver_cert = receiver.certificate_der().unwrap().as_ref().to_vec();

        // Multiple chunks plus a partial one.
        let body: Vec<u8> = (0..(64 * 1024 * 2 + 913)).map(|i| (i % 251) as u8).collect();

        let (path, _dir) = lan_payload_round_trip(
            &sender,
            &receiver,
            sender_cert,
            receiver_cert,
            body.clone(),
            "report.pdf",
        )
        .await
        .unwrap();

        assert_eq!(tokio::fs::read(&path).await.unwrap(), body);
        assert_eq!(path.file_name().unwrap(), "report.pdf");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_lan_payload_larger_than_the_wan_limit_transfers_fine() {
        // 21 MiB: over the Relay WAN ceiling, which must not apply on LAN.
        let sender = LocalIdentity::generate("Sender").unwrap();
        let receiver = LocalIdentity::generate("Receiver").unwrap();
        let size = 21 * 1024 * 1024;
        let body = vec![0x5A_u8; size];

        let (path, _dir) = lan_payload_round_trip(
            &sender,
            &receiver,
            sender.certificate_der().unwrap().as_ref().to_vec(),
            receiver.certificate_der().unwrap().as_ref().to_vec(),
            body,
            "large.bin",
        )
        .await
        .unwrap();

        assert_eq!(
            tokio::fs::metadata(&path).await.unwrap().len(),
            size as u64,
            "LAN carries files of any size"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn zero_and_single_byte_lan_payloads_round_trip() {
        for body in [Vec::new(), vec![0x42_u8]] {
            let sender = LocalIdentity::generate("Sender").unwrap();
            let receiver = LocalIdentity::generate("Receiver").unwrap();
            let expected = body.clone();
            let (path, _dir) = lan_payload_round_trip(
                &sender,
                &receiver,
                sender.certificate_der().unwrap().as_ref().to_vec(),
                receiver.certificate_der().unwrap().as_ref().to_vec(),
                body,
                "edge.bin",
            )
            .await
            .unwrap();
            assert_eq!(tokio::fs::read(&path).await.unwrap(), expected);
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_payload_connection_from_the_wrong_peer_is_refused_by_tls() {
        // An impostor that knows the port but is not the paired device.
        let sender = LocalIdentity::generate("Sender").unwrap();
        let receiver = LocalIdentity::generate("Receiver").unwrap();
        let impostor = LocalIdentity::generate("Impostor").unwrap();

        let result = lan_payload_round_trip(
            &sender,
            // The receiver presents the impostor's identity, while the sender
            // still pins the real receiver's certificate.
            &impostor,
            sender.certificate_der().unwrap().as_ref().to_vec(),
            receiver.certificate_der().unwrap().as_ref().to_vec(),
            vec![1_u8; 1024],
            "x.bin",
        )
        .await;

        assert!(
            result.is_err(),
            "knowing the payload port must never be enough to deliver a file"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_receiver_that_pins_the_wrong_sender_refuses_the_payload() {
        let sender = LocalIdentity::generate("Sender").unwrap();
        let receiver = LocalIdentity::generate("Receiver").unwrap();
        let other = LocalIdentity::generate("Other").unwrap();

        let result = lan_payload_round_trip(
            &sender,
            &receiver,
            // Receiver expects `other`'s certificate, but `sender` answers.
            other.certificate_der().unwrap().as_ref().to_vec(),
            receiver.certificate_der().unwrap().as_ref().to_vec(),
            vec![1_u8; 1024],
            "x.bin",
        )
        .await;

        assert!(result.is_err(), "an unexpected sender certificate must fail the handshake");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_lan_payload_that_stops_early_leaves_no_finished_file() {
        use crate::kdeconnect::files::{lan_payload, receive::IncomingFile};
        let sender = LocalIdentity::generate("Sender").unwrap();
        let receiver = LocalIdentity::generate("Receiver").unwrap();
        let sender_cert = sender.certificate_der().unwrap().as_ref().to_vec();
        let receiver_cert = receiver.certificate_der().unwrap().as_ref().to_vec();

        let listener = lan_payload::PayloadListener::bind().await.unwrap();
        let port = listener.port();

        let send = tokio::spawn(async move {
            let stream = listener.accept().await.unwrap();
            let mut tls = start_tls_as_server(&sender, stream, Some(&receiver_cert)).await.unwrap();
            // Announce 10 KiB but deliver 1 KiB, then hang up.
            tokio::io::AsyncWriteExt::write_all(&mut tls, &vec![7_u8; 1024]).await.unwrap();
            tokio::io::AsyncWriteExt::shutdown(&mut tls).await.ok();
        });

        let dir = tempfile::tempdir().unwrap();
        let stream = lan_payload::connect_to_payload(std::net::IpAddr::from([127, 0, 0, 1]), port)
            .await
            .unwrap();
        let mut tls =
            start_tls_as_client(&receiver, stream, "peer", Some(&sender_cert)).await.unwrap();
        let mut incoming = IncomingFile::create(dir.path(), "short.bin", 10_240, None).await.unwrap();
        let error = incoming.stream_from(&mut tls, |_| {}).await.unwrap_err();
        drop(incoming);
        send.await.unwrap();

        assert!(error.to_string().contains("ended after 1024 of 10240"));
        let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
        assert!(
            entries.next_entry().await.unwrap().is_none(),
            "a broken LAN transfer must leave the directory clean"
        );
    }

    // --- Route policy and cancellation -------------------------------------

    /// Registers a link of the given kind so route policy can be exercised.
    #[cfg(feature = "kdeconnect-wan")]
    async fn with_route(
        inner: &Arc<LanInner>,
        device_id: &str,
        kind: crate::kdeconnect::wan::TransportKind,
    ) {
        if kind == crate::kdeconnect::wan::TransportKind::KdeLan {
            let (packets, _rx) = tokio::sync::mpsc::channel(1);
            inner.connections.lock().await.insert(
                device_id.to_owned(),
                Conn {
                    packets,
                    peer_cert_der: Vec::new(),
                    name: device_id.to_owned(),
                    device_type: "phone".into(),
                    protocol_version: PROTOCOL_VERSION,
                    epoch: 1,
                },
            );
        }
        inner.router.register(Arc::new(TestRouteLink {
            device_id: device_id.to_owned(),
            kind,
        }));
        // Only *adds* the share capability. Registering a route must not look
        // like a capability reset, or tests would mask real capability loss.
        let mut capabilities = inner.peer_capabilities.lock().await;
        let entry = capabilities
            .entry(device_id.to_owned())
            .or_insert_with(|| (Vec::new(), Vec::new()));
        let share = crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST.to_owned();
        if !entry.0.contains(&share) {
            entry.0.push(share);
        }
    }

    fn file_of(dir: &std::path::Path, name: &str, size: u64) -> std::path::PathBuf {
        let path = dir.join(name);
        let file = std::fs::File::create(&path).unwrap();
        file.set_len(size).unwrap();
        path
    }

    #[cfg(feature = "kdeconnect-wan")]
    async fn state_of(
        inner: &Arc<LanInner>,
        device_id: &str,
        transfer_id: &str,
    ) -> crate::kdeconnect::files::TransferState {
        inner
            .transfers
            .lock()
            .await
            .get(&crate::kdeconnect::files::TransferKey::new(device_id, transfer_id))
            .map(|transfer| transfer.state.clone())
            .expect("transfer should exist")
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_large_file_is_accepted_over_lan_because_the_limit_is_wan_only() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;

        let dir = tempfile::tempdir().unwrap();
        // 25 MiB: comfortably over the Relay WAN ceiling.
        let path = file_of(dir.path(), "big.bin", 25 * 1024 * 1024);

        let transfer_id = inner.send_file(PHONE_A, &path).await.unwrap();

        assert_ne!(
            state_of(&inner, PHONE_A, &transfer_id).await,
            crate::kdeconnect::files::TransferState::RequiresLocalConnection,
            "LAN must carry files of any size; the 20 MiB cap is a WAN policy"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn the_same_large_file_is_refused_when_only_wan_is_available() {
        use crate::kdeconnect::files::TransferState;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;

        let dir = tempfile::tempdir().unwrap();
        let path = file_of(dir.path(), "big.bin", 25 * 1024 * 1024);

        let transfer_id = inner.send_file(PHONE_A, &path).await.unwrap();

        assert_eq!(
            state_of(&inner, PHONE_A, &transfer_id).await,
            TransferState::RequiresLocalConnection
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn lan_is_preferred_over_wan_when_both_routes_are_available() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;

        // A file over the WAN ceiling proves LAN was chosen: had WAN been
        // selected this would have been refused outright.
        let dir = tempfile::tempdir().unwrap();
        let path = file_of(dir.path(), "big.bin", 25 * 1024 * 1024);
        let transfer_id = inner.send_file(PHONE_A, &path).await.unwrap();

        assert_ne!(
            state_of(&inner, PHONE_A, &transfer_id).await,
            crate::kdeconnect::files::TransferState::RequiresLocalConnection,
            "a local file must never be relayed over the Internet"
        );
        assert_eq!(inner.router.active_transport(PHONE_A), Some(TransportKind::KdeLan));
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_small_file_is_accepted_on_either_route() {
        use crate::kdeconnect::files::TransferState;
        use crate::kdeconnect::wan::TransportKind;
        for kind in [TransportKind::KdeLan, TransportKind::RelayWan] {
            let (inner, _events) = multi_device_harness(&[PHONE_A]);
            with_route(&inner, PHONE_A, kind).await;
            let dir = tempfile::tempdir().unwrap();
            let path = file_of(dir.path(), "small.bin", 2 * 1024 * 1024);

            let transfer_id = inner.send_file(PHONE_A, &path).await.unwrap();
            assert_ne!(
                state_of(&inner, PHONE_A, &transfer_id).await,
                TransferState::RequiresLocalConnection,
                "{kind:?} should accept 2 MiB"
            );
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn the_remote_boundary_holds_exactly_at_twenty_mebibytes() {
        use crate::kdeconnect::files::TransferState;
        use crate::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES;
        use crate::kdeconnect::wan::TransportKind;

        for (size, refused) in [(MAX_WAN_PAYLOAD_BYTES, false), (MAX_WAN_PAYLOAD_BYTES + 1, true)] {
            let (inner, _events) = multi_device_harness(&[PHONE_A]);
            with_route(&inner, PHONE_A, TransportKind::RelayWan).await;
            let dir = tempfile::tempdir().unwrap();
            let path = file_of(dir.path(), "edge.bin", size);

            let transfer_id = inner.send_file(PHONE_A, &path).await.unwrap();
            let state = state_of(&inner, PHONE_A, &transfer_id).await;
            assert_eq!(
                state == TransferState::RequiresLocalConnection,
                refused,
                "{size} bytes over WAN"
            );
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_disconnected_device_reports_unavailable_rather_than_a_size_error() {
        use crate::kdeconnect::files::TransferState;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (vec![crate::kdeconnect::PACKET_TYPE_SHARE_REQUEST.to_owned()], vec![]),
        );
        let dir = tempfile::tempdir().unwrap();
        let path = file_of(dir.path(), "x.bin", 100);

        let transfer_id = inner.send_file(PHONE_A, &path).await.unwrap();

        assert!(matches!(
            state_of(&inner, PHONE_A, &transfer_id).await,
            TransferState::Failed { .. }
        ));
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_retry_creates_a_new_transfer_and_re_runs_route_selection() {
        use crate::kdeconnect::files::TransferState;
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        with_route(&inner, PHONE_A, TransportKind::RelayWan).await;

        let dir = tempfile::tempdir().unwrap();
        let path = file_of(dir.path(), "big.bin", 25 * 1024 * 1024);

        // Remote: refused for its size.
        let first = inner.send_file(PHONE_A, &path).await.unwrap();
        assert_eq!(
            state_of(&inner, PHONE_A, &first).await,
            TransferState::RequiresLocalConnection
        );

        // LAN comes back; retrying re-evaluates the route rather than reusing
        // the old decision.
        with_route(&inner, PHONE_A, TransportKind::KdeLan).await;
        let second = inner.send_file(PHONE_A, &path).await.unwrap();

        assert_ne!(first, second, "a retry is a new transfer, not a resumed one");
        assert_ne!(
            state_of(&inner, PHONE_A, &second).await,
            TransferState::RequiresLocalConnection
        );
        // The original attempt keeps its own outcome.
        assert_eq!(
            state_of(&inner, PHONE_A, &first).await,
            TransferState::RequiresLocalConnection
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn cancelling_marks_the_transfer_and_drops_its_pending_payload() {
        use crate::kdeconnect::files::TransferState;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("x.bin", 1_000, Some("payload-1")),
                &PacketReplyRoute::Lan(tx),
            )
            .await;
        let transfer_id = inner.transfers_for(PHONE_A).await[0].key.transfer_id.clone();

        inner.cancel_transfer(PHONE_A, &transfer_id).await;

        assert_eq!(state_of(&inner, PHONE_A, &transfer_id).await, TransferState::Cancelled);
        assert!(
            inner.pending_payloads.lock().await.is_empty(),
            "a cancelled transfer must not still be waiting for bytes"
        );

        // A payload arriving afterwards has nothing to attach to and writes
        // nothing.
        let mut source = std::io::Cursor::new(vec![0_u8; 1_000]);
        inner.handle_incoming_payload("payload-1", 1_000, &mut source).await;
        assert_eq!(
            state_of(&inner, PHONE_A, &transfer_id).await,
            TransferState::Cancelled,
            "a cancelled transfer must never become Completed"
        );
        let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
        assert!(entries.next_entry().await.unwrap().is_none());
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn cancelling_a_finished_transfer_does_not_rewrite_its_outcome() {
        use crate::kdeconnect::files::{Transfer, TransferKey, TransferState};
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let key = TransferKey::new(PHONE_A, "t1");
        inner.transfers.lock().await.insert(Transfer {
            key: key.clone(),
            filename: "x.bin".into(),
            total_bytes: 10,
            state: TransferState::Completed { total: 10 },
        });

        inner.cancel_transfer(PHONE_A, "t1").await;

        assert_eq!(
            state_of(&inner, PHONE_A, "t1").await,
            TransferState::Completed { total: 10 }
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn an_announcement_offering_no_payload_transport_fails_cleanly() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let dir = tempfile::tempdir().unwrap();
        inner.set_download_dir(dir.path().to_path_buf()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        // Neither a relayPayloadId nor a LAN port.
        inner
            .handle_transport_packet(
                PHONE_A,
                &share_packet("x.bin", 100, None),
                &PacketReplyRoute::Lan(tx),
            )
            .await;
        tokio::time::sleep(Duration::from_millis(50)).await;

        let transfers = inner.transfers_for(PHONE_A).await;
        assert!(matches!(
            transfers[0].state,
            crate::kdeconnect::files::TransferState::Failed { .. }
        ));
    }

    // --- Clipboard ---------------------------------------------------------

    fn clipboard_packet(content: &str, timestamp_ms: i64) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        body.insert("content".into(), content.into());
        body.insert("timestamp".into(), timestamp_ms.into());
        NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT, body)
    }

    async fn clipboard_events(
        events: &mut tokio::sync::mpsc::UnboundedReceiver<KdeConnectEvent>,
    ) -> Vec<(String, String)> {
        let mut received = Vec::new();
        while let Ok(event) = events.try_recv() {
            if let KdeConnectEvent::ClipboardReceived { device_id, content, .. } = event {
                received.push((device_id, content));
            }
        }
        received
    }

    #[tokio::test]
    async fn an_incoming_clipboard_packet_is_applied_once() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let packet = clipboard_packet("hello", now_unix_millis());

        assert!(
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx.clone()))
                .await
        );
        // The same packet again -- a retransmit or a reconnect replay.
        inner
            .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
            .await;

        let applied = clipboard_events(&mut events).await;
        assert_eq!(applied.len(), 1, "a duplicate packet must be idempotent");
        assert_eq!(applied[0], (PHONE_A.to_owned(), "hello".to_owned()));
    }

    #[tokio::test]
    async fn a_remote_clipboard_value_is_not_echoed_back_out() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        inner
            .handle_transport_packet(
                PHONE_A,
                &clipboard_packet("hello", now_unix_millis()),
                &PacketReplyRoute::Lan(tx),
            )
            .await;
        assert_eq!(clipboard_events(&mut events).await.len(), 1);

        // The desktop's own clipboard watcher now observes that write. Sending
        // it back out is exactly the loop this must prevent.
        inner
            .send_clipboard_to_all_paired("hello", now_unix_millis())
            .await
            .unwrap();

        let guard_blocked = {
            let mut guard = inner.clipboard_guard.lock().await;
            guard
                .should_send_local("hello", true, now_unix_millis())
                .is_err()
        };
        assert!(guard_blocked, "the echo must still be suppressed afterwards");
    }

    #[tokio::test]
    async fn an_untrusted_device_cannot_write_the_clipboard() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                "dddddddddddddddddddddddddddddddd",
                &clipboard_packet("hello", now_unix_millis()),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(clipboard_events(&mut events).await.is_empty());
    }

    #[tokio::test]
    async fn disabling_sync_blocks_an_incoming_clipboard_from_overwriting_the_local_one() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        inner.set_clipboard_enabled(false);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &clipboard_packet("hello", now_unix_millis()),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(
            clipboard_events(&mut events).await.is_empty(),
            "a disabled clipboard must not be overwritten from outside"
        );
    }

    #[tokio::test]
    async fn disabling_sync_blocks_sending_even_to_a_paired_device() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_clipboard_enabled(false);

        // Succeeds as a no-op rather than erroring: the user switched it off.
        inner
            .send_clipboard_to_all_paired("hello", now_unix_millis())
            .await
            .unwrap();
        assert!(
            inner.send_clipboard(PHONE_A, "hello", now_unix_millis()).await.is_err(),
            "an explicit single-device send must refuse while sync is off"
        );
    }

    #[tokio::test]
    async fn an_oversized_clipboard_packet_is_rejected_before_it_reaches_the_clipboard() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let huge = "x".repeat(crate::kdeconnect::clipboard::MAX_CLIPBOARD_BYTES + 1);
        let packet = clipboard_packet(&huge, now_unix_millis());

        // Refused while parsing, so the dispatcher never claims it.
        assert!(packet.as_clipboard().is_err());
        inner
            .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
            .await;
        assert!(
            clipboard_events(&mut events).await.is_empty(),
            "the local clipboard must be preserved"
        );
    }

    #[tokio::test]
    async fn unicode_and_multiline_clipboard_content_is_applied_intact() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let text = "line one\nline two\t日本語 — 🎉\nhttps://example.com/a?b=c";

        inner
            .handle_transport_packet(
                PHONE_A,
                &clipboard_packet(text, now_unix_millis()),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert_eq!(clipboard_events(&mut events).await[0].1, text);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn clipboard_arriving_over_relay_wan_behaves_identically_to_lan() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A]);
        let (_link, route) = wan_route(PHONE_A);

        inner
            .handle_transport_packet(
                PHONE_A,
                &clipboard_packet("from wan", now_unix_millis()),
                &route,
            )
            .await;

        let applied = clipboard_events(&mut events).await;
        assert_eq!(applied.len(), 1);
        assert_eq!(applied[0].1, "from wan");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_local_copy_fans_out_to_a_remote_device_over_wan() {
        // The old implementation wrote straight into the LAN connection map, so
        // a Remote device silently received nothing.
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (link, _route) = wan_route(PHONE_A);
        inner
            .router
            .register(Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        inner.peer_capabilities.lock().await.insert(
            PHONE_A.to_owned(),
            (
                vec![crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT.to_owned()],
                vec![],
            ),
        );

        inner
            .send_clipboard_to_all_paired("hello wan", now_unix_millis())
            .await
            .unwrap();

        let sent = link.sent.lock().unwrap().clone();
        assert!(
            sent.iter().any(|packet| packet.packet_type
                == crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT),
            "a Remote device must receive the clipboard over WAN"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_remote_origin_value_is_not_fanned_out_to_the_other_devices() {
        // Three devices: one echo must not become a broadcast to the rest.
        let (inner, mut events) = multi_device_harness(&[PHONE_A, PHONE_B, TABLET]);
        let (link_b, _rb) = wan_route(PHONE_B);
        let (link_t, _rt) = wan_route(TABLET);
        inner
            .router
            .register(Arc::clone(&link_b) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        inner
            .router
            .register(Arc::clone(&link_t) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        for device in [PHONE_B, TABLET] {
            inner.peer_capabilities.lock().await.insert(
                device.to_owned(),
                (
                    vec![crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT.to_owned()],
                    vec![],
                ),
            );
        }

        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        inner
            .handle_transport_packet(
                PHONE_A,
                &clipboard_packet("from phone a", now_unix_millis()),
                &PacketReplyRoute::Lan(tx),
            )
            .await;
        assert_eq!(clipboard_events(&mut events).await.len(), 1, "applied locally once");

        // Even if a fan-out were attempted for that value, the guard stops it.
        inner
            .send_clipboard_to_all_paired("from phone a", now_unix_millis())
            .await
            .unwrap();

        for (name, link) in [("phone-b", &link_b), ("tablet", &link_t)] {
            assert!(
                link.sent.lock().unwrap().is_empty(),
                "{name} must not receive a rebroadcast of another device's clipboard"
            );
        }
    }

    // --- Remote input ------------------------------------------------------

    /// Records what would have been injected instead of touching the desktop.
    #[derive(Default)]
    struct RecordingInput {
        events: std::sync::Mutex<Vec<crate::kdeconnect::input::InputEvent>>,
        ready: bool,
        fail: bool,
    }

    impl crate::kdeconnect::input::RemoteInputBackend for RecordingInput {
        fn is_ready(&self) -> bool {
            self.ready
        }
        fn dispatch<'a>(
            &'a self,
            events: &'a [crate::kdeconnect::input::InputEvent],
        ) -> crate::kdeconnect::input::InputFuture<'a, Result<()>> {
            Box::pin(async move {
                self.events.lock().unwrap().extend_from_slice(events);
                if self.fail {
                    anyhow::bail!("simulated input backend failure");
                }
                Ok(())
            })
        }
    }

    fn mousepad_request(pairs: &[(&str, serde_json::Value)]) -> NetworkPacket {
        let mut body = serde_json::Map::new();
        for (key, value) in pairs {
            body.insert((*key).to_owned(), value.clone());
        }
        NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_MOUSEPAD_REQUEST, body)
    }

    async fn injected(backend: &Arc<RecordingInput>) -> Vec<crate::kdeconnect::input::InputEvent> {
        for _ in 0..50 {
            if !backend.events.lock().unwrap().is_empty() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
        backend.events.lock().unwrap().clone()
    }

    /// Enabled + authorised + trusted: the only state that injects anything.
    async fn armed_input(inner: &Arc<LanInner>) -> Arc<RecordingInput> {
        let backend = Arc::new(RecordingInput { ready: true, ..Default::default() });
        inner.set_input_enabled(true);
        inner
            .set_input_backend(Some(
                Arc::clone(&backend) as Arc<dyn crate::kdeconnect::input::RemoteInputBackend>
            ))
            .await;
        backend
    }

    #[tokio::test]
    async fn pointer_motion_reaches_the_backend_when_fully_authorised() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let backend = armed_input(&inner).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        let packet = mousepad_request(&[("dx", 5.0.into()), ("dy", (-2.0).into())]);
        assert!(
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx))
                .await
        );

        assert_eq!(
            injected(&backend).await,
            vec![crate::kdeconnect::input::InputEvent::PointerMotion { dx: 5.0, dy: -2.0 }]
        );
    }

    #[tokio::test]
    async fn a_trusted_device_injects_nothing_while_remote_input_is_switched_off() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let backend = Arc::new(RecordingInput { ready: true, ..Default::default() });
        inner
            .set_input_backend(Some(
                Arc::clone(&backend) as Arc<dyn crate::kdeconnect::input::RemoteInputBackend>
            ))
            .await;
        inner.set_input_enabled(false); // the default

        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        inner
            .handle_transport_packet(
                PHONE_A,
                &mousepad_request(&[("singleclick", true.into())]),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(
            backend.events.lock().unwrap().is_empty(),
            "pairing must never by itself grant input control"
        );
    }

    #[tokio::test]
    async fn nothing_is_injected_without_an_authorised_session() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        // Enabled, but the user never approved an OS input session.
        inner.set_input_enabled(true);
        let backend = Arc::new(RecordingInput { ready: false, ..Default::default() });
        inner
            .set_input_backend(Some(
                Arc::clone(&backend) as Arc<dyn crate::kdeconnect::input::RemoteInputBackend>
            ))
            .await;

        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        inner
            .handle_transport_packet(
                PHONE_A,
                &mousepad_request(&[("dx", 5.0.into()), ("dy", 5.0.into())]),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(backend.events.lock().unwrap().is_empty());
        assert!(!inner.input_ready().await);
    }

    #[tokio::test]
    async fn an_untrusted_device_can_never_inject_input() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let backend = armed_input(&inner).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                "dddddddddddddddddddddddddddddddd",
                &mousepad_request(&[("dx", 5.0.into()), ("dy", 5.0.into())]),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(backend.events.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_malformed_input_packet_injects_nothing() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let backend = armed_input(&inner).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        for packet in [
            mousepad_request(&[("dx", 99_999.0.into()), ("dy", 0.0.into())]),
            mousepad_request(&[("specialKey", 999.into())]),
            mousepad_request(&[("ctrl", true.into())]),
            mousepad_request(&[]),
        ] {
            inner
                .handle_transport_packet(PHONE_A, &packet, &PacketReplyRoute::Lan(tx.clone()))
                .await;
        }

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(
            backend.events.lock().unwrap().is_empty(),
            "an unintelligible packet must move nothing"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn remote_input_works_over_relay_wan_under_the_same_gate() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let backend = armed_input(&inner).await;
        let (_link, route) = wan_route(PHONE_A);

        inner
            .handle_transport_packet(
                PHONE_A,
                &mousepad_request(&[("singleclick", true.into())]),
                &route,
            )
            .await;

        let events = injected(&backend).await;
        assert_eq!(events.len(), 2, "a click is a press and a release");
        // Being Remote grants nothing extra and costs nothing: identical gate.
        let (inner2, _events2) = multi_device_harness(&[PHONE_A]);
        let blocked = Arc::new(RecordingInput { ready: true, ..Default::default() });
        inner2
            .set_input_backend(Some(
                Arc::clone(&blocked) as Arc<dyn crate::kdeconnect::input::RemoteInputBackend>
            ))
            .await;
        let (_link2, route2) = wan_route(PHONE_A);
        inner2
            .handle_transport_packet(
                PHONE_A,
                &mousepad_request(&[("singleclick", true.into())]),
                &route2,
            )
            .await;
        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(
            blocked.events.lock().unwrap().is_empty(),
            "WAN must not bypass the enable switch"
        );
    }

    #[tokio::test]
    async fn two_devices_inject_independently() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        let backend = armed_input(&inner).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &mousepad_request(&[("dx", 1.0.into()), ("dy", 0.0.into())]),
                &PacketReplyRoute::Lan(tx.clone()),
            )
            .await;
        inner
            .handle_transport_packet(
                PHONE_B,
                &mousepad_request(&[("rightclick", true.into())]),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        let events = injected(&backend).await;
        assert!(events.iter().any(|e| matches!(e, crate::kdeconnect::input::InputEvent::PointerMotion { .. })));
        assert!(events.iter().any(|e| matches!(
            e,
            crate::kdeconnect::input::InputEvent::PointerButton {
                button: crate::kdeconnect::input::PointerButton::Right,
                ..
            }
        )));
    }

    #[tokio::test]
    async fn a_backend_failure_does_not_take_the_link_down() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let backend = Arc::new(RecordingInput { ready: true, fail: true, ..Default::default() });
        inner.set_input_enabled(true);
        inner
            .set_input_backend(Some(
                Arc::clone(&backend) as Arc<dyn crate::kdeconnect::input::RemoteInputBackend>
            ))
            .await;
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &mousepad_request(&[("dx", 3.0.into()), ("dy", 3.0.into())]),
                &PacketReplyRoute::Lan(tx.clone()),
            )
            .await;
        tokio::time::sleep(Duration::from_millis(60)).await;

        // The very next packet on the same route still works.
        let ping = minimal_packet(crate::kdeconnect::PACKET_TYPE_RELAY_PING);
        assert!(
            inner
                .handle_transport_packet(PHONE_A, &ping, &PacketReplyRoute::Lan(tx))
                .await
        );
        assert!(rx.try_recv().is_ok(), "the link must still answer after a backend failure");
    }

    // --- Local -> Remote handoff timing -----------------------------------

    #[cfg(feature = "kdeconnect-wan")]
    async fn set_route_seen(inner: &Arc<LanInner>, device_id: &str, kind: crate::kdeconnect::wan::TransportKind, at: i64) {
        inner
            .route_last_seen
            .lock()
            .await
            .insert((device_id.to_owned(), kind), at);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_silent_lan_route_fails_over_to_wan_within_the_failover_budget() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (lan, _lan_route) = wan_route(PHONE_A); // stands in as a registered link
        let (wan, _wan_route) = wan_route(PHONE_A);
        inner.router.register(Arc::new(TestRouteLink { device_id: PHONE_A.to_owned(), kind: TransportKind::KdeLan }));
        inner.router.register(Arc::clone(&wan) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        drop(lan);

        let now = now_unix();
        // LAN last heard from just past the failover budget; WAN is healthy.
        set_route_seen(&inner, PHONE_A, TransportKind::KdeLan, now - FAILOVER_TIMEOUT_SECS - 1).await;
        set_route_seen(&inner, PHONE_A, TransportKind::RelayWan, now).await;

        inner.sweep_stale_routes().await;

        assert_eq!(
            inner.router.active_transport(PHONE_A),
            Some(TransportKind::RelayWan),
            "with WAN healthy, a silent LAN route must fail over on the short budget"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_silent_lan_route_is_kept_below_the_failover_budget() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.router.register(Arc::new(TestRouteLink { device_id: PHONE_A.to_owned(), kind: TransportKind::KdeLan }));
        let (wan, _wan_route) = wan_route(PHONE_A);
        inner.router.register(Arc::clone(&wan) as Arc<dyn crate::kdeconnect::wan::TransportLink>);

        let now = now_unix();
        // One missed probe must not cause a failover, or routes would flap.
        set_route_seen(&inner, PHONE_A, TransportKind::KdeLan, now - FAILOVER_TIMEOUT_SECS + 2).await;
        set_route_seen(&inner, PHONE_A, TransportKind::RelayWan, now).await;

        inner.sweep_stale_routes().await;

        assert_eq!(
            inner.router.active_transport(PHONE_A),
            Some(TransportKind::KdeLan),
            "LAN still within budget must keep priority"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_sole_route_keeps_the_generous_budget_rather_than_going_offline_early() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.router.register(Arc::new(TestRouteLink { device_id: PHONE_A.to_owned(), kind: TransportKind::KdeLan }));

        let now = now_unix();
        // Past the failover budget but well inside the sole-route budget.
        set_route_seen(&inner, PHONE_A, TransportKind::KdeLan, now - FAILOVER_TIMEOUT_SECS - 5).await;

        inner.sweep_stale_routes().await;

        assert_eq!(
            inner.router.active_transport(PHONE_A),
            Some(TransportKind::KdeLan),
            "dropping the only route shows the device Offline; that needs the long budget"
        );

        // ...and it is still dropped once the sole-route budget really expires.
        set_route_seen(&inner, PHONE_A, TransportKind::KdeLan, now - HEARTBEAT_TIMEOUT_SECS - 1).await;
        inner.sweep_stale_routes().await;
        assert_eq!(inner.router.active_transport(PHONE_A), None);
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn lan_returning_takes_priority_back_from_wan_immediately() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (wan, _wan_route) = wan_route(PHONE_A);
        inner.router.register(Arc::clone(&wan) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        assert_eq!(inner.router.active_transport(PHONE_A), Some(TransportKind::RelayWan));

        // LAN comes back; no sweep, no timer, no re-pair -- priority decides.
        inner.router.register(Arc::new(TestRouteLink { device_id: PHONE_A.to_owned(), kind: TransportKind::KdeLan }));

        assert_eq!(inner.router.active_transport(PHONE_A), Some(TransportKind::KdeLan));
        assert_eq!(inner.router.available_transports(PHONE_A).len(), 2, "one logical device, two routes");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn changing_the_command_list_pushes_it_to_already_connected_devices() {
        // A phone asks for the list only when its plugin starts, so a command
        // added later has to be pushed or it stays invisible until reconnect.
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        let (link_a, _route_a) = wan_route(PHONE_A);
        let (link_b, _route_b) = wan_route(PHONE_B);
        inner.router.register(Arc::clone(&link_a) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        inner.router.register(Arc::clone(&link_b) as Arc<dyn crate::kdeconnect::wan::TransportLink>);

        inner.set_run_commands(sample_commands());

        for link in [&link_a, &link_b] {
            let sent = wan_sent(link).await;
            let list = sent
                .iter()
                .find(|packet| packet.body.contains_key("commandList"))
                .expect("every connected device must be told the list changed");
            let encoded = list.body["commandList"].as_str().unwrap();
            let parsed: serde_json::Value = serde_json::from_str(encoded).unwrap();
            assert!(parsed.get("cmd-enabled").is_some());
            assert!(parsed.get("cmd-disabled").is_none());
        }
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn removing_a_command_pushes_the_shortened_list_too() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        let (link, _route) = wan_route(PHONE_A);
        inner.router.register(Arc::clone(&link) as Arc<dyn crate::kdeconnect::wan::TransportLink>);

        inner.set_run_commands(sample_commands());
        let _ = wan_sent(&link).await;
        link.sent.lock().unwrap().clear();

        inner.set_run_commands(vec![]);

        let sent = wan_sent(&link).await;
        let list = sent
            .iter()
            .find(|packet| packet.body.contains_key("commandList"))
            .expect("revoking a command must reach the phone, not just the local registry");
        let parsed: serde_json::Value =
            serde_json::from_str(list.body["commandList"].as_str().unwrap()).unwrap();
        assert_eq!(parsed.as_object().map(|o| o.len()), Some(0));
    }

    #[tokio::test]
    async fn a_setup_request_never_runs_anything() {
        let (inner, _events) = multi_device_harness(&[PHONE_A]);
        inner.set_run_commands(sample_commands());
        let runner = Arc::new(FakeRunner::default());
        inner.set_command_runner(runner.clone()).await;
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        inner
            .handle_transport_packet(
                PHONE_A,
                &runcommand_request(&[("setup", true.into())]),
                &PacketReplyRoute::Lan(tx),
            )
            .await;

        assert!(runner.spawned.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn notifications_from_three_devices_are_all_retained_and_filter_per_device() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B, TABLET]);

        deliver(&inner, PHONE_A, &notification_packet("n1", "From A", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("n2", "From B", false)).await;
        deliver(&inner, TABLET, &notification_packet("n3", "From Tablet", false)).await;

        let a = inner.get_notifications(PHONE_A).await;
        let b = inner.get_notifications(PHONE_B).await;
        let tablet = inner.get_notifications(TABLET).await;

        assert_eq!(a.len(), 1);
        assert_eq!(a[0].title.as_deref(), Some("From A"));
        assert_eq!(b.len(), 1);
        assert_eq!(b[0].title.as_deref(), Some("From B"));
        assert_eq!(tablet.len(), 1);
        assert_eq!(tablet[0].title.as_deref(), Some("From Tablet"));
    }

    #[tokio::test]
    async fn the_same_remote_notification_id_on_two_devices_does_not_collide() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);

        // Both phones legitimately use id "42" for unrelated notifications.
        deliver(&inner, PHONE_A, &notification_packet("42", "Alice", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("42", "Bob", false)).await;

        let a = inner.get_notifications(PHONE_A).await;
        let b = inner.get_notifications(PHONE_B).await;
        assert_eq!(a.len(), 1);
        assert_eq!(b.len(), 1);
        assert_eq!(a[0].title.as_deref(), Some("Alice"));
        assert_eq!(b[0].title.as_deref(), Some("Bob"), "B must not be overwritten by A");
    }

    #[tokio::test]
    async fn updating_a_notification_on_one_device_leaves_the_same_id_on_another_untouched() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        deliver(&inner, PHONE_A, &notification_packet("42", "Alice", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("42", "Bob", false)).await;

        deliver(&inner, PHONE_A, &notification_packet("42", "Alice edited", false)).await;

        assert_eq!(
            inner.get_notifications(PHONE_A).await[0].title.as_deref(),
            Some("Alice edited")
        );
        assert_eq!(
            inner.get_notifications(PHONE_B).await[0].title.as_deref(),
            Some("Bob")
        );
        assert_eq!(inner.get_notifications(PHONE_A).await.len(), 1, "update, not append");
    }

    #[tokio::test]
    async fn cancelling_a_notification_on_one_device_leaves_the_same_id_on_another_alive() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        deliver(&inner, PHONE_A, &notification_packet("42", "Alice", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("42", "Bob", false)).await;

        deliver(&inner, PHONE_A, &notification_packet("42", "Alice", true)).await;

        assert!(inner.get_notifications(PHONE_A).await.is_empty());
        assert_eq!(
            inner.get_notifications(PHONE_B).await.len(),
            1,
            "a cancel from A must never dismiss B's notification with the same id"
        );
    }

    #[tokio::test]
    async fn unpairing_one_device_never_clears_another_devices_notifications() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        deliver(&inner, PHONE_A, &notification_packet("n1", "Alice", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("n2", "Bob", false)).await;

        let _ = inner.unpair(PHONE_A).await;

        assert!(inner.get_notifications(PHONE_A).await.is_empty());
        assert_eq!(
            inner.get_notifications(PHONE_B).await.len(),
            1,
            "unpairing A must not touch B's notification store"
        );
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn a_local_to_remote_transition_neither_clears_nor_duplicates_notifications() {
        use crate::kdeconnect::wan::TransportKind;
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        deliver(&inner, PHONE_A, &notification_packet("n1", "Alice", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("n2", "Bob", false)).await;

        // Wi-Fi drops: the LAN route for A goes away and WAN becomes authoritative.
        // Notifications belong to the logical device, not to the route.
        inner.router.unregister(PHONE_A, TransportKind::KdeLan);
        inner.record_route_seen(PHONE_A, TransportKind::RelayWan).await;

        assert_eq!(inner.get_notifications(PHONE_A).await.len(), 1);

        // The same notification arriving again over the new route must update in
        // place, not become a second copy.
        deliver(&inner, PHONE_A, &notification_packet("n1", "Alice", false)).await;
        assert_eq!(
            inner.get_notifications(PHONE_A).await.len(),
            1,
            "a route change must not duplicate a notification"
        );

        // Wi-Fi returns.
        inner.record_route_seen(PHONE_A, TransportKind::KdeLan).await;
        assert_eq!(inner.get_notifications(PHONE_A).await.len(), 1);
        assert_eq!(inner.get_notifications(PHONE_B).await.len(), 1);
    }

    #[tokio::test]
    async fn dismiss_targets_only_the_originating_device_and_refuses_an_unpaired_one() {
        let (inner, mut events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        deliver(&inner, PHONE_A, &notification_packet("42", "Alice", false)).await;
        deliver(&inner, PHONE_B, &notification_packet("42", "Bob", false)).await;
        while events.try_recv().is_ok() {}

        // Both phones advertise the notification-request capability.
        for device_id in [PHONE_A, PHONE_B] {
            inner.peer_capabilities.lock().await.insert(
                device_id.to_owned(),
                (
                    vec![crate::kdeconnect::PACKET_TYPE_NOTIFICATION_REQUEST.to_owned()],
                    vec![],
                ),
            );
        }

        // No transport is registered, so the send fails and nothing is removed --
        // dismissal must never drop the local record on a failed send.
        assert!(inner.dismiss_notification(PHONE_A, "42").await.is_err());
        assert_eq!(inner.get_notifications(PHONE_A).await.len(), 1);

        // An unknown device is refused outright rather than falling back to
        // "dismiss id 42 wherever it is found".
        assert!(inner.dismiss_notification("zzzz", "42").await.is_err());
        assert_eq!(inner.get_notifications(PHONE_B).await.len(), 1);
    }

    #[tokio::test]
    async fn the_shared_dispatch_chain_claims_every_control_plane_packet_type() {
        let phone_id = "a".repeat(32);
        let (inner, _events) = dispatch_harness(&phone_id);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let reply = PacketReplyRoute::Lan(tx);

        for packet_type in CONTROL_PLANE_PACKET_TYPES {
            let packet = minimal_packet(packet_type);
            assert!(
                inner
                    .handle_transport_packet(&phone_id, &packet, &reply)
                    .await,
                "{packet_type} was not claimed by the shared dispatch chain, so it would be \
                 silently dropped on whichever transport delivered it"
            );
        }
    }

    #[tokio::test]
    async fn an_unknown_packet_type_is_reported_unhandled_rather_than_swallowed() {
        let phone_id = "a".repeat(32);
        let (inner, _events) = dispatch_harness(&phone_id);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        let packet = NetworkPacket::new("kdeconnect.something.unknown", serde_json::Map::new());
        assert!(
            !inner
                .handle_transport_packet(&phone_id, &packet, &PacketReplyRoute::Lan(tx))
                .await
        );
    }

    #[tokio::test]
    async fn a_relay_ping_is_answered_on_the_route_it_arrived_on() {
        let phone_id = "a".repeat(32);
        let (inner, _events) = dispatch_harness(&phone_id);
        let (tx, mut rx) = tokio::sync::mpsc::channel(16);

        let ping = minimal_packet(crate::kdeconnect::PACKET_TYPE_RELAY_PING);
        assert!(
            inner
                .handle_transport_packet(&phone_id, &ping, &PacketReplyRoute::Lan(tx))
                .await
        );

        let replied = rx.try_recv().expect("a pong must go back on the same route");
        let parsed = NetworkPacket::parse(&replied).unwrap();
        assert_eq!(parsed.packet_type, crate::kdeconnect::PACKET_TYPE_RELAY_PONG);
        let pong = parsed.as_relay_pong().unwrap();
        assert_eq!(pong.nonce, "nonce-1", "the pong must echo the ping's nonce");
    }

    #[tokio::test]
    async fn a_notification_arriving_over_any_transport_reaches_the_notification_event() {
        let phone_id = "a".repeat(32);
        let (inner, mut events) = dispatch_harness(&phone_id);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);

        let packet = minimal_packet(crate::kdeconnect::PACKET_TYPE_NOTIFICATION);
        assert!(
            inner
                .handle_transport_packet(&phone_id, &packet, &PacketReplyRoute::Lan(tx))
                .await
        );

        let event = events.try_recv().expect("a NotificationsChanged event");
        match event {
            KdeConnectEvent::NotificationsChanged {
                device_id,
                notifications,
            } => {
                assert_eq!(device_id, phone_id);
                assert_eq!(notifications.len(), 1);
                assert_eq!(notifications[0].id, "notif-1");
                assert_eq!(notifications[0].title.as_deref(), Some("Alice"));
            }
            other => panic!("unexpected event: {other:?}"),
        }
    }

    #[tokio::test]
    async fn sms_messages_arriving_over_any_transport_are_merged_not_duplicated() {
        let phone_id = "a".repeat(32);
        let (inner, _events) = dispatch_harness(&phone_id);
        let (tx, _rx) = tokio::sync::mpsc::channel(16);
        let reply = PacketReplyRoute::Lan(tx);

        let mut body = serde_json::Map::new();
        body.insert("version".into(), 2.into());
        body.insert(
            "messages".into(),
            serde_json::json!([{
                "_id": 7,
                "thread_id": 3,
                "body": "hello",
                "address": "+15550000",
                "date": 1_700_000_000_000_i64,
                "type": 1,
                "read": 1,
                "addresses": [{"address": "+15550000"}],
            }]),
        );
        let packet = NetworkPacket::new(crate::kdeconnect::PACKET_TYPE_SMS_MESSAGES, body);

        // Deliver the same message twice, as a LAN session followed by a WAN
        // session re-sending its backlog would.
        assert!(inner.handle_transport_packet(&phone_id, &packet, &reply).await);
        assert!(inner.handle_transport_packet(&phone_id, &packet, &reply).await);

        let messages = inner.get_sms_messages(&phone_id, 3).await;
        assert_eq!(messages.len(), 1, "the same message must not be stored twice");
        assert_eq!(messages[0].body, "hello");
    }

    #[cfg(feature = "kdeconnect-wan")]
    #[tokio::test]
    async fn identical_sms_thread_ids_are_scoped_to_their_originating_device() {
        let (inner, _events) = multi_device_harness(&[PHONE_A, PHONE_B]);
        let message_for = |id, body: &str| SmsMessage {
            id,
            thread_id: 42,
            addresses: vec!["+15550100".into()],
            body: body.into(),
            date: id,
            message_type: 1,
            read: Some(false),
            sub_id: None,
            event: None,
            attachments: Vec::new(),
        };

        inner
            .merge_sms_messages(PHONE_A, vec![message_for(1, "from A")])
            .await;
        inner
            .merge_sms_messages(PHONE_B, vec![message_for(1, "from B")])
            .await;
        inner
            .merge_sms_messages(PHONE_A, vec![message_for(2, "A updated")])
            .await;

        let a = inner.get_sms_messages(PHONE_A, 42).await;
        let b = inner.get_sms_messages(PHONE_B, 42).await;
        assert_eq!(a.iter().map(|message| message.body.as_str()).collect::<Vec<_>>(), ["from A", "A updated"]);
        assert_eq!(b.iter().map(|message| message.body.as_str()).collect::<Vec<_>>(), ["from B"]);

        let (link_a, _) = wan_route(PHONE_A);
        let (link_b, _) = wan_route(PHONE_B);
        inner.router.register(Arc::clone(&link_a) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        inner.router.register(Arc::clone(&link_b) as Arc<dyn crate::kdeconnect::wan::TransportLink>);
        for device_id in [PHONE_A, PHONE_B] {
            inner.peer_capabilities.lock().await.insert(
                device_id.to_owned(),
                (vec![crate::kdeconnect::PACKET_TYPE_SMS_REQUEST.to_owned()], Vec::new()),
            );
        }

        inner
            .send_sms(PHONE_B, vec!["+15550100".into()], "reply to B", None)
            .await
            .unwrap();
        assert!(link_a.sent.lock().unwrap().is_empty(), "reply must not be routed through phone A");
        let sent_b = link_b.sent.lock().unwrap();
        assert_eq!(sent_b.len(), 1);
        assert_eq!(sent_b[0].packet_type, crate::kdeconnect::PACKET_TYPE_SMS_REQUEST);
        assert_eq!(sent_b[0].body["messageBody"], "reply to B");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn relay_heartbeat_and_device_state_round_trip_over_the_selected_route() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();

        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();

        let (event_tx, _event_rx) = tokio::sync::mpsc::unbounded_channel();
        let relay_inner = LanInner::new(
            relay_identity.clone(),
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.clone(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: phone_identity.device_name.clone(),
                device_type: phone_identity.device_type.clone(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            port,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_inner_clone = Arc::clone(&relay_inner);
        let relay_task = tokio::spawn(async move {
            let (stream, addr) = listener.accept().await.unwrap();
            inbound_tcp(relay_inner_clone, stream, addr).await
        });

        let phone_identity_clone = phone_identity.clone();
        let phone_task = tokio::spawn(async move {
            let mut stream = TcpStream::connect(SocketAddr::from(([127, 0, 0, 1], port)))
                .await
                .unwrap();
            let pre_tls = phone_identity_clone
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_server(&phone_identity_clone, stream, None),
            )
            .await
            .expect("TLS handshake timeout")
            .unwrap();

            let secure_identity = phone_identity_clone.identity_packet(None);
            let secure_id = secure_identity.to_packet().serialize();
            tls.write_all(&secure_id).await.unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // Phone sends a relay heartbeat ping; the desktop must echo a pong
            // with the same nonce.
            let ping = RelayHeartbeatBody::ping("phone-nonce", 1_000).serialize();
            tls.write_all(&ping).await.unwrap();
            tls.flush().await.unwrap();

            let mut got_pong = false;
            for _ in 0..10 {
                if let Ok(Ok(l)) = tokio::time::timeout(
                    Duration::from_millis(500),
                    read_line_bounded(&mut tls, MAX_PACKET_BYTES),
                )
                .await
                {
                    if let Ok(pkt) = NetworkPacket::parse(&l) {
                        if let Ok(pong) = pkt.as_relay_pong() {
                            assert_eq!(pong.nonce, "phone-nonce");
                            got_pong = true;
                            break;
                        }
                    }
                }
            }
            assert!(got_pong, "expected a relay pong echoing the ping's nonce");

            // Phone also sends a device_state packet -- the desktop must
            // accept it without erroring the connection (checked below via
            // `last_seen_unix` and continued connectivity).
            let state = RelayDeviceStateBody::new(RelayDeviceStateBody {
                device_name: Some("Pixel".into()),
                device_class: Some("phone".into()),
                os: Some("android".into()),
                timestamp: Some(2_000),
                ..Default::default()
            })
            .serialize();
            tls.write_all(&state).await.unwrap();
            tls.flush().await.unwrap();
            // Stay connected well past the assertions below -- the test must
            // observe `connected == true` while this link is still live, not
            // race the socket closing at task-end.
            tokio::time::sleep(Duration::from_secs(2)).await;
            Ok::<(), anyhow::Error>(())
        });

        tokio::time::sleep(Duration::from_millis(200)).await;

        // The desktop can also originate a heartbeat over the same route.
        relay_inner
            .router
            .send_packet(&phone_id, &RelayHeartbeatBody::ping("desktop-nonce", 3_000))
            .await
            .unwrap();

        tokio::time::sleep(Duration::from_millis(300)).await;

        let snapshot = relay_inner.snapshot().await;
        let device = snapshot.iter().find(|d| d.device_id == phone_id).unwrap();
        assert!(device.connected);
        assert!(
            device.last_seen_unix.is_some(),
            "relay ping/pong/device_state traffic must update last_seen_unix"
        );
        #[cfg(feature = "kdeconnect-wan")]
        assert_eq!(device.transport_kind, Some(crate::kdeconnect::wan::TransportKind::KdeLan));

        let _ = relay_task.await;
        let _ = phone_task.await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn paired_secure_session_ping_and_find_phone() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();

        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();

        let (event_tx, mut event_rx) = tokio::sync::mpsc::unbounded_channel();
        let relay_inner = LanInner::new(
            relay_identity.clone(),
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.clone(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: phone_identity.device_name.clone(),
                device_type: phone_identity.device_type.clone(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            port,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_inner_clone = Arc::clone(&relay_inner);
        let relay_task = tokio::spawn(async move {
            let (stream, addr) = listener.accept().await.unwrap();
            inbound_tcp(relay_inner_clone, stream, addr).await
        });

        let phone_identity_clone = phone_identity.clone();
        let phone_task = tokio::spawn(async move {
            let mut stream = TcpStream::connect(SocketAddr::from(([127, 0, 0, 1], port)))
                .await
                .unwrap();

            let pre_tls = phone_identity_clone
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_server(&phone_identity_clone, stream, None),
            )
            .await
            .expect("TLS handshake timeout")
            .unwrap();

            let mut secure_identity = phone_identity_clone.identity_packet(None);
            // This test peer acts as Android, which accepts these desktop
            // requests; LocalIdentity itself models a Relay desktop.
            secure_identity
                .incoming_capabilities
                .push(crate::kdeconnect::PACKET_TYPE_FINDMYPHONE_REQUEST.to_string());
            let secure_id = secure_identity.to_packet().serialize();
            tls.write_all(&secure_id).await.unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // 1. Phone sends Ping packet to Relay
            let ping_pkt = PingBody::new(Some("Hello Ping".into())).serialize();
            tls.write_all(&ping_pkt).await.unwrap();
            tls.flush().await.unwrap();

            // 2. Read packet sent from Relay (notification request on connect, or find phone / ping from Relay)
            let mut found_find_phone = false;
            for _ in 0..5 {
                if let Ok(Ok(l)) = tokio::time::timeout(
                    Duration::from_millis(500),
                    read_line_bounded(&mut tls, MAX_PACKET_BYTES),
                )
                .await
                {
                    if let Ok(pkt) = NetworkPacket::parse(&l) {
                        if pkt.packet_type == crate::kdeconnect::PACKET_TYPE_FINDMYPHONE_REQUEST {
                            found_find_phone = true;
                            break;
                        }
                    }
                }
            }
            assert!(found_find_phone);
            Ok::<(), anyhow::Error>(())
        });

        // Wait for connection to establish
        tokio::time::sleep(Duration::from_millis(200)).await;

        // Relay sends Find Phone to Phone
        relay_inner.find_phone(&phone_id).await.unwrap();

        // Check if Relay received Ping event
        let mut got_ping = false;
        while let Ok(event) = event_rx.try_recv() {
            if let KdeConnectEvent::PingReceived { device_id, message } = event {
                if device_id == phone_id && message.as_deref() == Some("Hello Ping") {
                    got_ping = true;
                }
            }
        }
        assert!(got_ping);

        let _ = relay_task.await;
        let _ = phone_task.await;
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn paired_secure_session_clipboard_and_notifications() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();

        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();

        let (event_tx, mut event_rx) = tokio::sync::mpsc::unbounded_channel();
        let relay_inner = LanInner::new(
            relay_identity.clone(),
            vec![crate::kdeconnect::TrustedDevice {
                device_id: phone_id.clone(),
                certificate_pem: phone_identity.certificate_pem.clone(),
                name: phone_identity.device_name.clone(),
                device_type: phone_identity.device_type.clone(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 123456,
                wan_endpoint_id: None,
            }],
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            port,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        let relay_inner_clone = Arc::clone(&relay_inner);
        let relay_task = tokio::spawn(async move {
            let (stream, addr) = listener.accept().await.unwrap();
            inbound_tcp(relay_inner_clone, stream, addr).await
        });

        let phone_identity_clone = phone_identity.clone();
        let phone_task = tokio::spawn(async move {
            let mut stream = TcpStream::connect(SocketAddr::from(([127, 0, 0, 1], port)))
                .await
                .unwrap();

            let pre_tls = phone_identity_clone
                .identity_packet(Some(1716))
                .to_packet()
                .serialize();
            stream.write_all(&pre_tls).await.unwrap();
            stream.flush().await.unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_server(&phone_identity_clone, stream, None),
            )
            .await
            .expect("TLS handshake timeout")
            .unwrap();

            let mut secure_identity = phone_identity_clone.identity_packet(None);
            secure_identity
                .incoming_capabilities
                .push(crate::kdeconnect::PACKET_TYPE_NOTIFICATION_REQUEST.to_string());
            let secure_id = secure_identity.to_packet().serialize();
            tls.write_all(&secure_id).await.unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // 1. Phone sends Clipboard packet
            let cb_pkt =
                ClipboardBody::connect("Relay clipboard test 123", 2_000_000_000_000).serialize();
            tls.write_all(&cb_pkt).await.unwrap();
            tls.flush().await.unwrap();

            // 2. Phone sends Notification packet
            let notif_json = br#"{"id":100,"type":"kdeconnect.notification","body":{"id":"msg1","appName":"Messages","title":"Mom","text":"Dinner ready"}}"#;
            let mut notif_line = notif_json.to_vec();
            notif_line.push(b'\n');
            tls.write_all(&notif_line).await.unwrap();
            tls.flush().await.unwrap();

            tokio::time::sleep(Duration::from_millis(100)).await;

            // 3. Phone cancels Notification
            let cancel_json = br#"{"id":101,"type":"kdeconnect.notification","body":{"id":"msg1","isCancel":true}}"#;
            let mut cancel_line = cancel_json.to_vec();
            cancel_line.push(b'\n');
            tls.write_all(&cancel_line).await.unwrap();
            tls.flush().await.unwrap();

            tokio::time::sleep(Duration::from_millis(100)).await;
            Ok::<(), anyhow::Error>(())
        });

        // Wait for connection to establish and packets to process
        tokio::time::sleep(Duration::from_millis(400)).await;

        let mut got_clipboard = false;
        while let Ok(event) = event_rx.try_recv() {
            if let KdeConnectEvent::ClipboardReceived {
                device_id,
                content,
                timestamp_ms,
            } = event
            {
                if device_id == phone_id
                    && content == "Relay clipboard test 123"
                    && timestamp_ms == 2_000_000_000_000
                {
                    got_clipboard = true;
                }
            }
        }
        assert!(got_clipboard);

        let notifs = relay_inner.get_notifications(&phone_id).await;
        // Notification msg1 was added then cancelled, so notifs should be empty
        assert!(notifs.is_empty());

        let _ = relay_task.await;
        let _ = phone_task.await;
    }

    #[test]
    fn same_capability_set_is_order_insensitive() {
        let a = vec![
            "kdeconnect.ping".to_string(),
            "kdeconnect.sms.request".to_string(),
        ];
        let b = vec![
            "kdeconnect.sms.request".to_string(),
            "kdeconnect.ping".to_string(),
        ];
        assert!(same_capability_set(&a, &b));

        let c = vec!["kdeconnect.ping".to_string()];
        assert!(!same_capability_set(&a, &c));

        let empty: Vec<String> = Vec::new();
        assert!(same_capability_set(&empty, &empty));
    }

    #[tokio::test]
    async fn rate_ok_gates_rapid_repeated_calls_for_the_same_device() {
        let (event_tx, _event_rx) = tokio::sync::mpsc::unbounded_channel();
        let inner = LanInner::new(
            crate::kdeconnect::LocalIdentity::generate("Relay").unwrap(),
            Vec::new(),
            LanConfig {
                bind: BindMode::Any,
                allow_loopback: true,
            },
            1716,
            event_tx,
            tokio_util::sync::CancellationToken::new(),
        );

        // handle_udp calls rate_ok unconditionally before ever reaching the
        // capability-refresh logic, so this same cooldown already protects the
        // new code path against a UDP identity storm re-triggering a secure
        // handshake many times a second.
        assert!(rate_ok(&inner, "phone-a").await, "first call should pass");
        assert!(
            !rate_ok(&inner, "phone-a").await,
            "immediate repeat within the cooldown should be gated"
        );
        assert!(
            rate_ok(&inner, "phone-b").await,
            "a different device_id must not share phone-a's cooldown"
        );

        tokio::time::sleep(CONNECT_COOLDOWN + Duration::from_millis(50)).await;
        assert!(
            rate_ok(&inner, "phone-a").await,
            "call after the cooldown elapses should pass again"
        );
    }

    /// Reproduces the exact scenario from the capability-refresh bug report: a
    /// phone that is already connected re-broadcasts a plaintext UDP identity
    /// advertising a different capability set (e.g. SEND_SMS was just granted,
    /// so `kdeconnect.sms.request` newly appears). Before the fix, `handle_udp`
    /// returned immediately for any already-connected peer and `peer_capabilities`
    /// stayed stale forever. This drives `handle_udp` directly with a synthetic
    /// UDP datagram and asserts the cache is refreshed via a real secure
    /// (TLS-authenticated) reconnect -- never by trusting the UDP payload
    /// directly -- and that the stale first connection's reader-task cleanup
    /// cannot evict the newer connection the refresh installs.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn capability_refresh_completes_end_to_end_and_survives_stale_reader_cleanup() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();
        let relay_id = relay_identity.device_id.clone();

        // Must be inside KDE Connect's advertised TCP range, but below 1739 --
        // that is where payload listeners start, and one may hold 1740.
        let listener = TcpListener::bind("127.0.0.1:1718").await.unwrap();
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

        let phone_identity_clone = phone_identity.clone();
        let (hold_tx, hold_rx) = tokio::sync::oneshot::channel::<()>();
        let (closed_tx, closed_rx) = tokio::sync::oneshot::channel::<()>();
        let (go_tx, go_rx) = tokio::sync::oneshot::channel::<()>();
        let phone_task = tokio::spawn(async move {
            // Phase 1: initial secure link, phone advertises capability set A.
            let (mut stream, _) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
                .await
                .expect("phase1 accept timeout")
                .unwrap();
            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut stream, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("phase1 read pre-TLS timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_client(&phone_identity_clone, stream, &relay_id, None),
            )
            .await
            .expect("phase1 TLS timeout")
            .unwrap();

            let mut body_a = phone_identity_clone.identity_packet(None);
            body_a.incoming_capabilities = vec!["kdeconnect.ping".to_string()];
            body_a.outgoing_capabilities = vec!["kdeconnect.ping".to_string()];
            tls.write_all(&body_a.to_packet().serialize())
                .await
                .unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("phase1 read relay secure identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // Phase 2: accept the capability-refresh reconnect, advertise B.
            let (mut stream2, _) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
                .await
                .expect("phase2 accept timeout")
                .unwrap();
            let line2 = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut stream2, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("phase2 read pre-TLS timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line2).unwrap().as_identity().unwrap();

            let mut tls2 = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_client(&phone_identity_clone, stream2, &relay_id, None),
            )
            .await
            .expect("phase2 TLS timeout")
            .unwrap();

            let mut body_b = phone_identity_clone.identity_packet(None);
            body_b.incoming_capabilities = vec!["kdeconnect.sms.request".to_string()];
            body_b.outgoing_capabilities = vec!["kdeconnect.sms.request".to_string()];
            tls2.write_all(&body_b.to_packet().serialize())
                .await
                .unwrap();
            tls2.flush().await.unwrap();

            let line3 = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls2, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("phase2 read relay secure identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line3).unwrap().as_identity().unwrap();

            // The newer (phase 2) connection is now fully established. Close the
            // STALE phase-1 connection to exercise the reader-task cleanup race:
            // its closing must not evict the newer Conn the refresh just installed.
            // `tls2` is deliberately kept alive (not dropped) until the test signals
            // it's done asserting, so the phase-2 connection can't be mistaken for
            // closed by its own reader task while the assertion is still pending.
            let _ = hold_rx.await;
            drop(tls);
            let _ = closed_tx.send(());
            let _ = go_rx.await;
            drop(tls2);

            Ok::<(), anyhow::Error>(())
        });

        let relay_res = tokio::time::timeout(
            Duration::from_secs(2),
            outbound_connect(
                Arc::clone(&relay_inner),
                addr.ip(),
                addr.port(),
                Some(phone_id.clone()),
            ),
        )
        .await
        .expect("relay initial outbound_connect timeout");
        assert!(relay_res.is_ok(), "{relay_res:?}");

        let snapshot_a = relay_inner.snapshot().await;
        let dev_a = snapshot_a
            .iter()
            .find(|d| d.device_id == phone_id)
            .expect("phone present in snapshot after phase1");
        assert_eq!(
            dev_a.incoming_capabilities,
            vec!["kdeconnect.ping".to_string()]
        );

        let first_epoch = {
            let connections = relay_inner.connections.lock().await;
            connections
                .get(&phone_id)
                .expect("phase1 Conn present")
                .epoch
        };

        // Fire a synthetic UDP identity broadcast advertising DIFFERENT
        // capabilities while already connected -- the exact scenario `handle_udp`
        // used to silently drop.
        let mut udp_identity = phone_identity.identity_packet(Some(addr.port()));
        udp_identity.incoming_capabilities = vec!["kdeconnect.sms.request".to_string()];
        udp_identity.outgoing_capabilities = vec!["kdeconnect.sms.request".to_string()];
        let datagram = udp_identity.to_packet().serialize();

        let probe_udp = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let fake_udp_src = SocketAddr::new(addr.ip(), 0);
        handle_udp(&relay_inner, &probe_udp, &datagram, fake_udp_src)
            .await
            .expect("handle_udp must not error on a capability-change datagram");

        // Poll until the background refresh reconnect completes.
        let mut refreshed = false;
        for _ in 0..40 {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let snapshot = relay_inner.snapshot().await;
            if let Some(dev) = snapshot.iter().find(|d| d.device_id == phone_id) {
                if dev.incoming_capabilities == vec!["kdeconnect.sms.request".to_string()] {
                    refreshed = true;
                    break;
                }
            }
        }
        assert!(
            refreshed,
            "expected peer_capabilities to refresh to the newly-advertised set"
        );

        let second_epoch = {
            let connections = relay_inner.connections.lock().await;
            connections
                .get(&phone_id)
                .expect("refreshed Conn present")
                .epoch
        };
        assert_ne!(
            first_epoch, second_epoch,
            "the refresh must install a new Conn via a real secure handshake, not mutate the old one in place"
        );

        // Let the stale phase-1 connection close and its reader task run its cleanup,
        // while the phase-2 connection is deliberately still held open on the phone
        // side (see `go_rx` above) so this assertion can't race its own teardown.
        let _ = hold_tx.send(());
        let _ = closed_rx.await;
        tokio::time::sleep(Duration::from_millis(200)).await;

        let connections = relay_inner.connections.lock().await;
        let entry = connections
            .get(&phone_id)
            .expect("the refreshed connection must survive the stale reader's cleanup");
        assert_eq!(
            entry.epoch, second_epoch,
            "the newer connection must not be evicted by the older connection's teardown"
        );
        drop(connections);

        let _ = go_tx.send(());
        let _ = phone_task.await.unwrap();
    }

    /// Companion to the refresh test above: when the UDP identity advertises the
    /// SAME capability set already cached, no secure reconnect should be
    /// attempted at all -- guards against a handshake storm on every routine
    /// UDP re-broadcast from an already-connected peer.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn capability_refresh_is_skipped_when_udp_identity_capabilities_are_unchanged() {
        let relay_identity = crate::kdeconnect::LocalIdentity::generate("Relay").unwrap();
        let phone_identity = crate::kdeconnect::LocalIdentity::generate("Phone").unwrap();
        let phone_id = phone_identity.device_id.clone();
        let relay_id = relay_identity.device_id.clone();

        let listener = TcpListener::bind("127.0.0.1:1719").await.unwrap();
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

        let phone_identity_clone = phone_identity.clone();
        let (go_tx, go_rx) = tokio::sync::oneshot::channel::<()>();
        let (result_tx, result_rx) = tokio::sync::oneshot::channel::<bool>();
        let phone_task = tokio::spawn(async move {
            let (mut stream, _) = tokio::time::timeout(Duration::from_secs(2), listener.accept())
                .await
                .expect("accept timeout")
                .unwrap();
            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut stream, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read pre-TLS timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            let mut tls = tokio::time::timeout(
                Duration::from_secs(2),
                start_tls_as_client(&phone_identity_clone, stream, &relay_id, None),
            )
            .await
            .expect("TLS timeout")
            .unwrap();

            let mut body = phone_identity_clone.identity_packet(None);
            body.incoming_capabilities = vec!["kdeconnect.ping".to_string()];
            body.outgoing_capabilities = vec!["kdeconnect.ping".to_string()];
            tls.write_all(&body.to_packet().serialize()).await.unwrap();
            tls.flush().await.unwrap();

            let line = tokio::time::timeout(
                Duration::from_secs(2),
                read_line_bounded(&mut tls, MAX_IDENTITY_PACKET_BYTES),
            )
            .await
            .expect("read relay secure identity timeout")
            .unwrap();
            let _ = NetworkPacket::parse(&line).unwrap().as_identity().unwrap();

            // No second connection should ever arrive. Prove it rather than assume
            // it: keep accepting with a bounded timeout and report if anything shows up.
            let second_connection_arrived =
                tokio::time::timeout(Duration::from_millis(600), listener.accept())
                    .await
                    .is_ok();

            let _ = result_tx.send(second_connection_arrived);

            // `tls` (and thus this connection) is deliberately kept alive until the
            // test signals it's done asserting on `connections`, so the entry can't
            // be mistaken for closed by its own reader task mid-assertion.
            let _ = go_rx.await;
            drop(tls);
        });

        let relay_res = tokio::time::timeout(
            Duration::from_secs(2),
            outbound_connect(
                Arc::clone(&relay_inner),
                addr.ip(),
                addr.port(),
                Some(phone_id.clone()),
            ),
        )
        .await
        .expect("relay initial outbound_connect timeout");
        assert!(relay_res.is_ok(), "{relay_res:?}");

        let first_epoch = {
            let connections = relay_inner.connections.lock().await;
            connections.get(&phone_id).expect("Conn present").epoch
        };

        // Same capability set as the initial secure identity -- must be a no-op.
        let mut udp_identity = phone_identity.identity_packet(Some(addr.port()));
        udp_identity.incoming_capabilities = vec!["kdeconnect.ping".to_string()];
        udp_identity.outgoing_capabilities = vec!["kdeconnect.ping".to_string()];
        let datagram = udp_identity.to_packet().serialize();

        let probe_udp = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let fake_udp_src = SocketAddr::new(addr.ip(), 0);
        handle_udp(&relay_inner, &probe_udp, &datagram, fake_udp_src)
            .await
            .expect("handle_udp must not error");

        let second_connection_arrived = result_rx.await.unwrap();
        assert!(
            !second_connection_arrived,
            "an unchanged capability set must not trigger a secure reconnect"
        );

        let epoch_after = {
            let connections = relay_inner.connections.lock().await;
            connections
                .get(&phone_id)
                .expect("Conn still present")
                .epoch
        };
        assert_eq!(
            first_epoch, epoch_after,
            "the original connection must be untouched when nothing changed"
        );

        let _ = go_tx.send(());
        let _ = phone_task.await.unwrap();
    }
}
