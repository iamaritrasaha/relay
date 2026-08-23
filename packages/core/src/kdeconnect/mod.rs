//! KDE Connect compatibility protocol (discovery, pairing, unpair).
//!
//! This module is a separate trust namespace. A successful KDE Connect pair
//! never produces a RelayId and never consults Relay-native trust records.

mod capabilities;
pub mod clipboard;
pub mod commands;
pub mod fabric;
pub mod files;
pub mod input;
pub mod media;
mod identity;
mod lan;
mod packet;
mod pairing;
#[cfg(feature = "kdeconnect-wan")]
pub mod wan;
pub mod wallpaper_cache;

pub use capabilities::{
    canonical_incoming_capabilities, canonical_outgoing_capabilities, PACKET_TYPE_BATTERY,
    PACKET_TYPE_CLIPBOARD, PACKET_TYPE_CLIPBOARD_CONNECT, PACKET_TYPE_CONNECTIVITY_REPORT,
    PACKET_TYPE_FINDMYPHONE_REQUEST, PACKET_TYPE_IDENTITY, PACKET_TYPE_NOTIFICATION,
    PACKET_TYPE_NOTIFICATION_REQUEST, PACKET_TYPE_PAIR, PACKET_TYPE_PING,
    PACKET_TYPE_RELAY_DEVICE_STATE, PACKET_TYPE_RELAY_WALLPAPER, PACKET_TYPE_RELAY_PING, PACKET_TYPE_RELAY_PONG,
    PACKET_TYPE_MOUSEPAD_REQUEST, PACKET_TYPE_MPRIS, PACKET_TYPE_MPRIS_REQUEST, PACKET_TYPE_SHARE_REQUEST,
    PACKET_TYPE_RELAY_WAN_IDENTITY,
    PACKET_TYPE_RUNCOMMAND, PACKET_TYPE_RUNCOMMAND_REQUEST,
    PACKET_TYPE_SMS_MESSAGES, PACKET_TYPE_SMS_REQUEST,
    PACKET_TYPE_SMS_REQUEST_CONVERSATION, PACKET_TYPE_SMS_REQUEST_CONVERSATIONS,
    PACKET_TYPE_TELEPHONY, PACKET_TYPE_TELEPHONY_REQUEST_MUTE,
};
pub use identity::LocalIdentity;
use media::MediaPlayerHost as _;
pub use lan::{
    BatteryState, BindMode, ConnectivityState, DeviceTable, LanConfig, ObservedDevice,
    MAX_TCP_PORT, MIN_TCP_PORT, UDP_PORT,
};
pub use packet::{
    filter_device_name, is_valid_device_id, BatteryBody, ClipboardBody, ConnectivityReportBody,
    ConnectivitySignal, FindMyPhoneBody, IdentityBody, NetworkPacket, NotificationBody,
    PacketError, PairBody, PingBody, RelayDeviceStateBody, RelayWallpaperBody, RelayHeartbeatBody,
    MousePadRequestBody, MprisBody, ShareRequestBody, MprisRequestBody, RelayWanIdentityBody, RunCommandListBody,
    RunCommandRequestBody, SmsAttachmentMetadata, SmsMessage, SmsMessagesBody, SmsRequestBody,
    SmsRequestConversationBody, SmsRequestConversationsBody, TelephonyBody,
    TelephonyRequestMuteBody, PROTOCOL_VERSION,
};
pub use pairing::{
    compute_verification_key, extract_public_key_der, PairState, PairingEffect, PairingFailReason,
    PairingSession,
};

use crate::relay::RelayId;
use anyhow::Result;
use lan::LanInner;
use std::sync::Arc;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrustedDevice {
    pub device_id: String,
    pub certificate_pem: String,
    pub name: String,
    pub device_type: String,
    pub protocol_version: i64,
    pub paired_at_unix: i64,
    /// Relay WAN EndpointId learned over an authenticated, already-paired LAN
    /// session. Persisted with the KDE trust record so a desktop restart does
    /// not forget how to authenticate the same phone on mobile data.
    pub wan_endpoint_id: Option<String>,
}

impl TrustedDevice {
    pub fn certificate_der(&self) -> Result<Vec<u8>> {
        rustls::pki_types::pem::PemObject::from_pem_slice(self.certificate_pem.as_bytes())
            .map(|der: rustls::pki_types::CertificateDer<'static>| der.as_ref().to_vec())
            .map_err(|e| anyhow::anyhow!("trusted device certificate: {e}"))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeviceSnapshot {
    pub device_id: String,
    pub name: String,
    pub device_type: String,
    pub ip: Option<String>,
    pub port: Option<u16>,
    pub paired: bool,
    pub connected: bool,
    pub incoming_pair: bool,
    pub identity_mismatch: bool,
    pub battery_percentage: Option<i32>,
    pub battery_is_charging: Option<bool>,
    pub network_type: Option<String>,
    pub signal_level: Option<i32>,
    pub connectivity_stale: bool,
    pub incoming_capabilities: Vec<String>,
    pub outgoing_capabilities: Vec<String>,
    /// Which transport is currently authoritative for this device, derived
    /// live from the same connection state as `connected` -- never a cached
    /// "last known" value. `RelayWan` state distinguishes a direct Iroh path
    /// from a relayed one (`TransportState::RemoteDirect` /
    /// `RemoteRelay`). Only populated when the `kdeconnect-wan` feature is
    /// compiled in.
    #[cfg(feature = "kdeconnect-wan")]
    pub transport_kind: Option<wan::TransportKind>,
    #[cfg(feature = "kdeconnect-wan")]
    pub transport_state: wan::TransportState,
    /// Round-trip time of the last successful `kdeconnect.relay.ping` /
    /// `kdeconnect.relay.pong` exchange, and when any relay packet was last
    /// received, over whichever transport is currently authoritative.
    pub last_rtt_ms: Option<i64>,
    pub last_seen_unix: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KdeNotification {
    pub id: String,
    pub app_name: Option<String>,
    pub title: Option<String>,
    pub text: Option<String>,
    pub time: Option<String>,
    pub is_clearable: bool,
    pub silent: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KdeSmsConversation {
    pub thread_id: i64,
    pub participants: Vec<String>,
    pub latest_message: Option<SmsMessage>,
    pub unread_count: i32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KdeTelephonyEvent {
    pub event: String,
    pub is_cancel: bool,
    pub phone_number: Option<String>,
    pub contact_name: Option<String>,
    pub phone_thumbnail: Option<String>,
}

#[derive(Clone, Debug)]
pub enum KdeConnectEvent {
    DevicesChanged {
        devices: Vec<DeviceSnapshot>,
        /// The Device Fabric as of the same observation.
        ///
        /// Carried on the existing event rather than emitted as a second one:
        /// every change that alters the fabric already produces exactly one
        /// `DevicesChanged`, so this keeps the coalescing that already exists
        /// instead of doubling the traffic to the UI.
        fabric: fabric::RelayFabricSnapshot,
    },
    IncomingPair {
        device_id: String,
        name: String,
    },
    PairingFailed {
        device_id: String,
        reason: String,
    },
    TrustChanged {
        devices: Vec<TrustedDevice>,
    },
    PingReceived {
        device_id: String,
        message: Option<String>,
    },
    ClipboardReceived {
        device_id: String,
        content: String,
        timestamp_ms: i64,
    },
    NotificationsChanged {
        device_id: String,
        notifications: Vec<KdeNotification>,
    },
    SmsChanged {
        device_id: String,
        conversations: Vec<KdeSmsConversation>,
        messages: Vec<SmsMessage>,
    },
    TelephonyReceived {
        device_id: String,
        event: KdeTelephonyEvent,
    },
    /// A file transfer changed state or made progress.
    TransferChanged {
        transfer: files::Transfer,
    },
    /// A peer's wallpaper preview was received and validated. Purely
    /// decorative -- feeds the hero's phone silhouette, nothing else.
    WallpaperChanged {
        device_id: String,
        path: String,
    },
}

pub struct KdeConnectConfig {
    pub identity: LocalIdentity,
    pub trusted: Vec<TrustedDevice>,
    pub lan: LanConfig,
    /// The RunCommand allow-list, seeded *before* the LAN loop starts
    /// accepting connections. Setting it afterwards races the first phone to
    /// connect: its plugin asks for the list once at startup, and an answer of
    /// "no commands" gets cached until it reconnects.
    pub run_commands: Vec<commands::RunCommandEntry>,
}

pub struct KdeConnectHandle {
    inner: Arc<LanInner>,
    event_rx: tokio::sync::Mutex<mpsc::UnboundedReceiver<KdeConnectEvent>>,
}

impl KdeConnectHandle {
    pub async fn start(config: KdeConnectConfig) -> Result<Self> {
        identity::install_crypto_provider();
        let udp = lan::bind_udp(config.lan.bind)?;
        let (listener, tcp_port) = lan::bind_tcp(config.lan.bind).await?;
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let cancel = CancellationToken::new();
        let inner = LanInner::new(
            config.identity,
            config.trusted,
            config.lan,
            tcp_port,
            event_tx,
            cancel.clone(),
        );
        inner.commands.replace(config.run_commands);
        let runner = Arc::clone(&inner);
        tokio::spawn(async move {
            lan::run(runner, listener, udp).await;
        });
        Ok(Self {
            inner,
            event_rx: tokio::sync::Mutex::new(event_rx),
        })
    }

    pub fn device_id(&self) -> &str {
        &self.inner.identity.device_id
    }

    pub fn tcp_port(&self) -> u16 {
        self.inner.tcp_port
    }

    pub async fn snapshot(&self) -> Vec<DeviceSnapshot> {
        self.inner.snapshot().await
    }

    pub async fn trusted_devices(&self) -> Vec<TrustedDevice> {
        self.inner.trusted_devices().await
    }

    pub async fn recv(&self) -> Option<KdeConnectEvent> {
        self.event_rx.lock().await.recv().await
    }

    pub async fn connect_to(&self, ip: std::net::IpAddr, port: u16) -> Result<()> {
        lan::connect_to(Arc::clone(&self.inner), ip, port).await
    }

    pub async fn request_pair(&self, device_id: &str) -> Result<()> {
        self.inner.request_pair(device_id).await
    }

    pub async fn accept_pair(&self, device_id: &str) -> Result<()> {
        self.inner.accept_pair(device_id).await
    }

    pub async fn reject_pair(&self, device_id: &str) -> Result<()> {
        self.inner.reject_pair(device_id).await
    }

    pub async fn unpair(&self, device_id: &str) -> Result<()> {
        self.inner.unpair(device_id).await
    }

    pub async fn send_ping(&self, device_id: &str, message: Option<String>) -> Result<()> {
        self.inner.send_ping(device_id, message).await
    }

    pub async fn find_phone(&self, device_id: &str) -> Result<()> {
        self.inner.find_phone(device_id).await
    }

    pub async fn send_clipboard(
        &self,
        device_id: &str,
        content: &str,
        timestamp_ms: i64,
    ) -> Result<()> {
        self.inner
            .send_clipboard(device_id, content, timestamp_ms)
            .await
    }

    pub async fn send_clipboard_to_all_paired(
        &self,
        content: &str,
        timestamp_ms: i64,
    ) -> Result<()> {
        self.inner
            .send_clipboard_to_all_paired(content, timestamp_ms)
            .await
    }

    pub async fn request_notifications(&self, device_id: &str) -> Result<()> {
        self.inner.request_notifications(device_id).await
    }

    /// Dismisses one notification on the logical device that produced it. The
    /// `(device_id, remote_notification_id)` pair is the key -- the same remote
    /// id on another device is a different notification and is unaffected.
    pub async fn dismiss_notification(
        &self,
        device_id: &str,
        remote_notification_id: &str,
    ) -> Result<()> {
        self.inner
            .dismiss_notification(device_id, remote_notification_id)
            .await
    }

    pub async fn get_notifications(&self, device_id: &str) -> Vec<KdeNotification> {
        self.inner.get_notifications(device_id).await
    }

    pub async fn get_sms_conversations(&self, device_id: &str) -> Vec<KdeSmsConversation> {
        self.inner.get_sms_conversations(device_id).await
    }
    pub async fn get_sms_messages(&self, device_id: &str, thread_id: i64) -> Vec<SmsMessage> {
        self.inner.get_sms_messages(device_id, thread_id).await
    }
    pub async fn request_sms_conversations(&self, device_id: &str) -> Result<()> {
        self.inner.request_sms_conversations(device_id).await
    }
    pub async fn request_sms_conversation(
        &self,
        device_id: &str,
        thread_id: i64,
        before: Option<i64>,
        limit: u16,
    ) -> Result<()> {
        self.inner
            .request_sms_conversation(device_id, thread_id, before, limit)
            .await
    }

    pub async fn send_sms(
        &self,
        device_id: &str,
        addresses: Vec<String>,
        body: &str,
        sub_id: Option<i32>,
    ) -> Result<()> {
        self.inner.send_sms(device_id, addresses, body, sub_id).await
    }

    pub async fn send_mute_call(&self, device_id: &str) -> Result<()> {
        self.inner.send_mute_call(device_id).await
    }

    /// Starts MPRIS media support by connecting to the D-Bus session bus.
    ///
    /// Opt-in and fallible on purpose: a machine with no session bus (a headless
    /// service, a container) simply runs without media control, and media
    /// requests are answered with an empty player list instead of hanging.
    #[cfg(all(target_os = "linux", feature = "mpris"))]
    pub async fn enable_media(&self) -> Result<()> {
        let host = media::dbus::DbusMediaPlayerHost::connect().await?;
        let players = host.players().await.len();
        self.inner.set_media_host(Arc::new(host)).await;
        tracing::info!("[Relay MPRIS] media control enabled; {players} player(s) on the session bus");
        Ok(())
    }

    /// Sets where received files are written. Until this is set, incoming files
    /// are refused rather than guessed at.
    pub async fn set_download_dir(&self, directory: std::path::PathBuf) {
        self.inner.set_download_dir(directory).await;
    }

    /// Sends one file to a logical device.
    ///
    /// Returns the transfer id immediately; progress arrives as
    /// [`KdeConnectEvent::TransferChanged`]. A file too large for the current
    /// remote route resolves to [`files::TransferState::RequiresLocalConnection`]
    /// rather than an error, because nothing went wrong -- it is a policy
    /// outcome the UI should phrase as "Local connection required".
    #[cfg(feature = "kdeconnect-wan")]
    pub async fn send_file(&self, device_id: &str, path: &std::path::Path) -> Result<String> {
        self.inner.send_file(device_id, path).await
    }

    #[cfg(feature = "kdeconnect-wan")]
    pub async fn send_wallpaper(
        &self,
        device_id: &str,
        path: &std::path::Path,
        hash: &str,
        width: u32,
        height: u32,
    ) -> Result<()> {
        self.inner
            .send_wallpaper(device_id, path, hash, width, height)
            .await
    }

    /// Sets where an incoming peer wallpaper preview is cached. Until this is
    /// set, a received preview is validated but dropped rather than written
    /// anywhere -- same "no directory, no write" discipline as file receipt.
    pub fn set_wallpaper_cache_dir(&self, directory: std::path::PathBuf) {
        self.inner.wallpaper_cache.set_base_dir(directory);
    }

    /// The last successfully validated wallpaper preview cached for a device,
    /// if any. Used to seed the hero on device selection, before the next
    /// `WallpaperChanged` event arrives.
    pub fn wallpaper_preview_path(&self, device_id: &str) -> Option<std::path::PathBuf> {
        self.inner.wallpaper_cache.path_for(device_id)
    }

    /// Cancels an in-flight transfer. Idempotent, and never resurrects a
    /// transfer that already finished.
    pub async fn cancel_transfer(&self, device_id: &str, transfer_id: &str) {
        self.inner.cancel_transfer(device_id, transfer_id).await;
    }

    /// The Device Fabric: one authoritative record per trusted logical device,
    /// with the local feature policy that was in force when it was read.
    ///
    /// A device reachable over both LAN and WAN appears once, with both routes
    /// recorded against it -- never as two entries.
    pub async fn device_fabric(&self) -> fabric::RelayFabricSnapshot {
        self.inner.device_fabric().await
    }

    /// Transfers belonging to one logical device.
    pub async fn transfers_for(&self, device_id: &str) -> Vec<files::Transfer> {
        self.inner.transfers_for(device_id).await
    }

    /// Turns clipboard sync on or off for this desktop.
    ///
    /// When off, nothing is transmitted *and* an incoming clipboard packet does
    /// not overwrite the local clipboard -- pairing alone never implies consent
    /// to share the clipboard in either direction.
    pub fn set_clipboard_enabled(&self, enabled: bool) {
        self.inner.set_clipboard_enabled(enabled);
    }

    pub fn clipboard_enabled(&self) -> bool {
        self.inner.clipboard_enabled()
    }

    /// Turns remote input on or off. Off by default and never implied by
    /// pairing: a paired phone still needs this *and* an authorised OS input
    /// session before a single event is injected.
    pub fn set_remote_input_enabled(&self, enabled: bool) {
        self.inner.set_input_enabled(enabled);
    }

    pub fn remote_input_enabled(&self) -> bool {
        self.inner.input_enabled()
    }

    /// Whether an authorised input session currently exists.
    pub async fn remote_input_ready(&self) -> bool {
        self.inner.input_ready().await
    }

    /// Requests an OS-level remote-input session.
    ///
    /// This is what raises the desktop's own approval dialog, so it must only
    /// ever run in response to a deliberate action by the person at the
    /// keyboard -- never at startup, and never because a phone asked.
    #[cfg(all(target_os = "linux", feature = "remote-input"))]
    pub async fn authorize_remote_input(&self) -> Result<()> {
        let backend = input::portal::PortalRemoteInputBackend::start().await?;
        self.inner.set_input_backend(Some(Arc::new(backend))).await;
        tracing::info!("[Relay Input] remote-input session authorised");
        Ok(())
    }

    /// Drops the input session. The OS-level grant is released and every later
    /// packet is refused until the user authorises again.
    pub async fn revoke_remote_input(&self) {
        self.inner.set_input_backend(None).await;
        tracing::info!("[Relay Input] remote-input session revoked");
    }

    /// Installs the desktop's RunCommand allow-list. The phone can only ever
    /// trigger entries from this list, by id -- see [`commands`].
    pub fn set_run_commands(&self, entries: Vec<commands::RunCommandEntry>) {
        self.inner.set_run_commands(entries);
    }

    pub fn run_commands(&self) -> Vec<commands::RunCommandEntry> {
        self.inner.commands.snapshot()
    }

    pub fn stop(&self) {
        self.inner.cancel.cancel();
    }

    /// Opt-in: starts the Relay WAN runtime (binding the Iroh endpoint) and
    /// its inbound accept loop. Never called implicitly by `start` -- see
    /// `tests/kdeconnect_wan_isolation.rs`. Safe to call multiple times.
    #[cfg(feature = "kdeconnect-wan")]
    pub async fn enable_wan(&self, config: wan::WanRuntimeConfig) -> Result<()> {
        self.inner.enable_wan(config).await
    }

    /// Sends a Relay-native heartbeat ping to `device_id` over whichever
    /// transport is currently authoritative (LAN preferred, then WAN).
    #[cfg(feature = "kdeconnect-wan")]
    pub async fn send_relay_ping(&self, device_id: &str, nonce: &str) -> Result<()> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_millis() as i64)
            .unwrap_or(0);
        let packet = packet::RelayHeartbeatBody::ping(nonce, timestamp);
        self.inner.router.send_packet(device_id, &packet).await?;
        Ok(())
    }

    #[cfg(feature = "kdeconnect-wan")]
    pub async fn request_relay_device_state(&self, device_id: &str) -> Result<()> {
        let packet = packet::RelayDeviceStateBody::new(packet::RelayDeviceStateBody {
            is_request: true,
            ..Default::default()
        });
        self.inner.router.send_packet(device_id, &packet).await?;
        Ok(())
    }
}

impl Drop for KdeConnectHandle {
    fn drop(&mut self) {
        self.inner.cancel.cancel();
    }
}

/// KDE Connect pairing cannot authenticate a Relay-native peer, and a RelayId
/// cannot be derived from a KDE Connect deviceId.
pub fn relay_trust_cannot_authenticate_kdeconnect(
    relay_id: &RelayId,
    kdeconnect_device_id: &str,
) -> bool {
    relay_id.as_hex() != kdeconnect_device_id.to_ascii_uppercase()
        && RelayId::from_expected_canonical_hex(kdeconnect_device_id).is_err()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::relay::RelayId;
    use std::time::Duration;

    #[test]
    fn localsend_packet_is_not_kdeconnect_identity() {
        let packet = br#"{"alias":"Phone","version":"2.1","deviceType":"mobile","fingerprint":"ABCD","port":53317,"protocol":"https"}"#;
        assert!(NetworkPacket::parse(packet)
            .ok()
            .and_then(|p| p.as_identity().ok())
            .is_none());
    }

    #[test]
    fn relay_native_trust_cannot_authenticate_kdeconnect_peer() {
        let identity = RelayIdentity::generate();
        let relay_id = RelayId::from_local_identity(&identity).unwrap();
        let kde_id = "a".repeat(32);
        assert!(relay_trust_cannot_authenticate_kdeconnect(
            &relay_id, &kde_id
        ));
        assert!(RelayId::from_expected_canonical_hex(&kde_id).is_err());
    }

    #[tokio::test]
    async fn persisted_paired_identity_is_paired_after_restart() {
        let identity = LocalIdentity::generate("Relay").unwrap();
        let peer = LocalIdentity::generate("Phone").unwrap();
        let handle = KdeConnectHandle::start(KdeConnectConfig {
            identity,
            trusted: vec![TrustedDevice {
                device_id: peer.device_id.clone(),
                certificate_pem: peer.certificate_pem,
                name: "Phone".into(),
                device_type: "phone".into(),
                protocol_version: PROTOCOL_VERSION,
                paired_at_unix: 1,
                wan_endpoint_id: None,
            }],
            lan: LanConfig {
                bind: BindMode::Loopback,
                allow_loopback: true,
            },
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        let snap = handle.snapshot().await;
        assert_eq!(snap.len(), 1);
        assert_eq!(snap[0].device_id, peer.device_id);
        assert!(snap[0].paired);
        assert!(!snap[0].connected);
        handle.stop();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    #[ignore]
    async fn loopback_pair_reject_accept_persist_unpair() {
        let alice_id = LocalIdentity::generate("Alice").unwrap();
        let bob_id = LocalIdentity::generate("Bob").unwrap();
        let lan = LanConfig {
            bind: BindMode::Loopback,
            allow_loopback: true,
        };
        let mut alice = KdeConnectHandle::start(KdeConnectConfig {
            identity: alice_id.clone(),
            trusted: vec![],
            lan: lan.clone(),
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        let mut bob = KdeConnectHandle::start(KdeConnectConfig {
            identity: bob_id.clone(),
            trusted: vec![],
            lan,
            run_commands: Vec::new(),
        })
        .await
        .unwrap();

        bob.connect_to(
            std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
            alice.tcp_port(),
        )
        .await
        .unwrap();
        let alice_peer = wait_for_device(&mut bob, alice_id.device_id.as_str()).await;
        assert!(!alice_peer.paired);

        bob.request_pair(&alice_id.device_id).await.unwrap();
        wait_incoming(&mut alice, &bob_id.device_id).await;
        alice.reject_pair(&bob_id.device_id).await.unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(alice.trusted_devices().await.is_empty());
        assert!(bob.trusted_devices().await.is_empty());

        bob.request_pair(&alice_id.device_id).await.unwrap();
        wait_incoming(&mut alice, &bob_id.device_id).await;
        alice.accept_pair(&bob_id.device_id).await.unwrap();
        wait_paired(&mut bob, &alice_id.device_id).await;
        assert_eq!(alice.trusted_devices().await.len(), 1);
        assert_eq!(bob.trusted_devices().await.len(), 1);

        let trusted = alice.trusted_devices().await;
        alice.stop();
        bob.stop();
        drop(alice);
        drop(bob);
        tokio::time::sleep(Duration::from_millis(200)).await;

        let lan = LanConfig {
            bind: BindMode::Loopback,
            allow_loopback: true,
        };
        let mut alice = KdeConnectHandle::start(KdeConnectConfig {
            identity: alice_id.clone(),
            trusted,
            lan: lan.clone(),
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        let mut bob = KdeConnectHandle::start(KdeConnectConfig {
            identity: bob_id.clone(),
            trusted: vec![],
            lan,
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        bob.connect_to(
            std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
            alice.tcp_port(),
        )
        .await
        .unwrap();
        let restarted = wait_for_device(&mut bob, alice_id.device_id.as_str()).await;
        assert!(
            alice
                .snapshot()
                .await
                .iter()
                .any(|d| d.device_id == bob_id.device_id && d.paired)
                || restarted.connected
        );
        let alice_view = wait_for_device(&mut alice, bob_id.device_id.as_str()).await;
        assert!(alice_view.paired);
        assert!(!alice_view.incoming_pair);

        alice.unpair(&bob_id.device_id).await.unwrap();
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(alice.trusted_devices().await.is_empty());
        alice.stop();
        bob.stop();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    #[ignore]
    async fn unpaired_certificate_is_not_silently_trusted_and_mismatch_is_rejected() {
        let alice_id = LocalIdentity::generate("Alice").unwrap();
        let bob_id = LocalIdentity::generate("Bob").unwrap();
        let lan = LanConfig {
            bind: BindMode::Loopback,
            allow_loopback: true,
        };
        let mut alice = KdeConnectHandle::start(KdeConnectConfig {
            identity: alice_id.clone(),
            trusted: vec![],
            lan: lan.clone(),
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        let mut bob = KdeConnectHandle::start(KdeConnectConfig {
            identity: bob_id.clone(),
            trusted: vec![],
            lan: lan.clone(),
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        bob.connect_to(
            std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
            alice.tcp_port(),
        )
        .await
        .unwrap();
        wait_for_device(&mut bob, alice_id.device_id.as_str()).await;
        assert!(alice.trusted_devices().await.is_empty());

        bob.request_pair(&alice_id.device_id).await.unwrap();
        wait_incoming(&mut alice, &bob_id.device_id).await;
        alice.accept_pair(&bob_id.device_id).await.unwrap();
        wait_paired(&mut bob, &alice_id.device_id).await;
        let mut trusted = alice.trusted_devices().await;
        trusted[0].certificate_pem = LocalIdentity::generate("Impostor").unwrap().certificate_pem;
        alice.stop();
        bob.stop();
        drop(alice);
        drop(bob);
        tokio::time::sleep(Duration::from_millis(200)).await;

        let mut alice = KdeConnectHandle::start(KdeConnectConfig {
            identity: alice_id.clone(),
            trusted,
            lan: lan.clone(),
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        let mut bob = KdeConnectHandle::start(KdeConnectConfig {
            identity: bob_id.clone(),
            trusted: vec![],
            lan,
            run_commands: Vec::new(),
        })
        .await
        .unwrap();
        let _ = bob
            .connect_to(
                std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
                alice.tcp_port(),
            )
            .await;
        tokio::time::sleep(Duration::from_millis(400)).await;
        let view = alice
            .snapshot()
            .await
            .into_iter()
            .find(|d| d.device_id == bob_id.device_id);
        if let Some(view) = view {
            assert!(view.identity_mismatch || !view.connected);
        }
        alice.stop();
        bob.stop();
    }

    async fn wait_for_device(handle: &mut KdeConnectHandle, device_id: &str) -> DeviceSnapshot {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
        loop {
            if let Some(device) = handle
                .snapshot()
                .await
                .into_iter()
                .find(|d| d.device_id == device_id)
            {
                return device;
            }
            let remain = deadline.saturating_duration_since(tokio::time::Instant::now());
            tokio::select! {
                _ = tokio::time::sleep(remain) => panic!("timed out waiting for {device_id}"),
                event = handle.recv() => { let _ = event; }
            }
        }
    }

    async fn wait_incoming(handle: &mut KdeConnectHandle, device_id: &str) {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
        loop {
            if handle
                .snapshot()
                .await
                .iter()
                .any(|d| d.device_id == device_id && d.incoming_pair)
            {
                return;
            }
            let remain = deadline.saturating_duration_since(tokio::time::Instant::now());
            tokio::select! {
                _ = tokio::time::sleep(remain) => panic!("timed out waiting for incoming pair from {device_id}"),
                event = handle.recv() => { let _ = event; }
            }
        }
    }

    async fn wait_paired(handle: &mut KdeConnectHandle, device_id: &str) {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
        loop {
            if handle
                .snapshot()
                .await
                .iter()
                .any(|d| d.device_id == device_id && d.paired)
            {
                return;
            }
            let remain = deadline.saturating_duration_since(tokio::time::Instant::now());
            tokio::select! {
                _ = tokio::time::sleep(remain) => panic!("timed out waiting to pair {device_id}"),
                event = handle.recv() => { let _ = event; }
            }
        }
    }
}
