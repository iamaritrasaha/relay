//! KDE Connect compatibility surface for Relay Linux.
//!
//! Isolated from RelayId / LocalSend trust. Pairing here never authenticates a
//! Relay-native peer.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use relay_core::kdeconnect::{
    BindMode, DeviceSnapshot, KdeConnectConfig, KdeConnectEvent, KdeConnectHandle, KdeNotification,
    KdeSmsConversation, KdeTelephonyEvent, LanConfig, LocalIdentity, SmsAttachmentMetadata,
    SmsMessage, TrustedDevice,
};
use relay_core::kdeconnect::commands::RunCommandEntry;
use relay_core::kdeconnect::fabric::{
    FeatureAvailability, LocalFeaturePolicy, RelayConnectionState, RelayDeviceClass,
    RelayDeviceRecord, RelayFabricSnapshot, RelayFeature,
};
use relay_core::kdeconnect::wan::{TransportKind, TransportState, WanIdentity, WanRuntimeConfig};

use crate::frb_generated::StreamSink;

pub struct RsKdeConnectIdentity {
    pub device_id: String,
    pub device_name: String,
    pub certificate_pem: String,
    pub private_key_pem: String,
    pub wan_secret_key: Vec<u8>,
}

pub struct RsKdeConnectTrustedDevice {
    pub device_id: String,
    pub certificate_pem: String,
    pub name: String,
    pub device_type: String,
    pub protocol_version: i64,
    pub paired_at_unix: i64,
    pub wan_endpoint_id: Option<String>,
}

pub struct RsKdeConnectDevice {
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
    pub transport_kind: Option<String>,
    pub transport_state: String,
    pub last_rtt_ms: Option<i64>,
    pub last_seen_unix: Option<i64>,
}

/// How a logical device is reachable right now, as the core derived it.
///
/// Mirrors `relay_core::kdeconnect::fabric::RelayConnectionState` one-for-one so
/// the product never re-derives reachability from a display string. `Offline` is
/// a real answer, not a fallback for "unknown".
pub enum RsRelayConnectionState {
    Offline,
    Local,
    RemoteDirect,
    RemoteRelay,
    Reconnecting,
}

/// Physical form factor, already normalised by the core.
pub enum RsRelayDeviceClass {
    Desktop,
    Laptop,
    Phone,
    Tablet,
    Tv,
    Other,
}

/// A feature Relay can offer for a device.
pub enum RsRelayFeature {
    Notifications,
    Messages,
    Media,
    Commands,
    RemoteInput,
    Clipboard,
    Files,
    Battery,
    Ping,
}

/// Whether a feature can be used with a device right now, and if not, why.
pub enum RsFeatureAvailability {
    Available,
    Unsupported,
    NotConnected,
    Disabled,
    NeedsPermission,
    NotConfigured,
}

/// One feature's availability for one device.
pub struct RsRelayFeatureState {
    pub feature: RsRelayFeature,
    pub availability: RsFeatureAvailability,
}

/// One logical Relay device, as the Device Fabric knows it.
///
/// This is the product's device identity: LAN and Relay WAN are routes recorded
/// against it, never separate devices. Nothing route-private crosses here --
/// no secret key, no certificate, no filesystem path. The WAN `EndpointId`
/// itself is deliberately absent; only whether a binding exists is exposed,
/// because that is the whole of what the product needs to reason about.
pub struct RsRelayDevice {
    /// The stable logical id (the KDE device id, reused as the compatibility key).
    pub device_id: String,
    pub display_name: String,
    pub device_class: RsRelayDeviceClass,
    /// Peer-reported platform string, e.g. "android".
    pub platform: Option<String>,
    pub platform_version: Option<String>,
    pub relay_version: Option<String>,
    /// Trust persists across restarts and is independent of connectivity.
    pub trusted: bool,
    pub connection_state: RsRelayConnectionState,
    pub lan_available: bool,
    pub wan_available: bool,
    /// Whether a WAN binding exists at all, i.e. whether remote reachability is
    /// even possible. Distinct from [`Self::wan_available`], which is about now.
    pub wan_bound: bool,
    /// "direct" or "relay" while a WAN route is up; absent otherwise.
    pub wan_path: Option<String>,
    /// Unix seconds of the last authenticated activity on each route, kept
    /// apart so WAN traffic cannot make a dead LAN link look alive.
    pub lan_last_seen_unix: Option<i64>,
    pub wan_last_seen_unix: Option<i64>,
    /// The most recent genuine activity on any route.
    pub last_seen_unix: Option<i64>,
    pub battery_percent: Option<i32>,
    pub charging: Option<bool>,
    /// Everything the peer advertised, independent of the current route.
    pub capabilities: Vec<RsRelayFeature>,
    /// The availability of every feature, already answered by the core's single
    /// rule so no screen has to reimplement the policy.
    pub feature_availability: Vec<RsRelayFeatureState>,
}

/// The whole fabric as one consistent observation.
pub struct RsRelayDeviceFabric {
    pub devices: Vec<RsRelayDevice>,
    /// The id of the device a single-device surface should present, chosen by
    /// the core's deterministic rule. Null when there is nothing to show.
    pub primary_device_id: Option<String>,
    pub clipboard_enabled: bool,
    pub remote_input_enabled: bool,
    pub remote_input_authorized: bool,
    pub has_configured_commands: bool,
}

pub struct RsKdeNotification {
    pub id: String,
    pub app_name: Option<String>,
    pub title: Option<String>,
    pub text: Option<String>,
    pub time: Option<String>,
    pub is_clearable: bool,
    pub silent: bool,
}

pub struct RsKdeTelephonyEvent {
    pub event: String,
    pub is_cancel: bool,
    pub phone_number: Option<String>,
    pub contact_name: Option<String>,
    pub phone_thumbnail: Option<String>,
}

pub struct RsKdeSmsAttachment {
    pub part_id: String,
    pub mime_type: Option<String>,
    pub unique_identifier: Option<String>,
}

pub struct RsKdeSmsMessage {
    pub id: i64,
    pub thread_id: i64,
    pub addresses: Vec<String>,
    pub body: String,
    pub date: i64,
    pub message_type: i32,
    pub read: Option<bool>,
    /// Which SIM the message belongs to. Carried through so a reply goes out on
    /// the same subscription the thread is already on, which matters on the
    /// dual-SIM phones this is most often used with.
    pub sub_id: Option<i32>,
    pub attachments: Vec<RsKdeSmsAttachment>,
}

pub struct RsKdeSmsConversation {
    pub thread_id: i64,
    pub participants: Vec<String>,
    pub latest_message: Option<RsKdeSmsMessage>,
    pub unread_count: i32,
}

pub enum RsKdeConnectEvent {
    DevicesChanged {
        devices: Vec<RsKdeConnectDevice>,
        /// The Device Fabric as of the same observation. This is the
        /// authoritative product device model; `devices` remains for the
        /// discovery/pairing surface, which sees untrusted peers the fabric
        /// deliberately does not contain.
        fabric: RsRelayDeviceFabric,
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
        devices: Vec<RsKdeConnectTrustedDevice>,
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
        notifications: Vec<RsKdeNotification>,
    },
    SmsChanged {
        device_id: String,
        conversations: Vec<RsKdeSmsConversation>,
        messages: Vec<RsKdeSmsMessage>,
    },
    TelephonyReceived {
        device_id: String,
        event: RsKdeTelephonyEvent,
    },
    /// A file transfer changed state or made progress.
    TransferChanged { transfer: RsTransfer },
}

/// One file transfer, scoped to the logical device it belongs to.
#[derive(Clone, Debug, PartialEq)]
pub struct RsTransfer {
    pub device_id: String,
    pub transfer_id: String,
    pub filename: String,
    pub total_bytes: u64,
    pub transferred_bytes: u64,
    /// One of: preparing, sending, receiving, completed, failed, cancelled,
    /// requiresLocalConnection.
    pub state: String,
    /// 0.0 to 1.0.
    pub progress: f64,
    pub error: Option<String>,
}

impl From<relay_core::kdeconnect::files::Transfer> for RsTransfer {
    fn from(value: relay_core::kdeconnect::files::Transfer) -> Self {
        use relay_core::kdeconnect::files::TransferState;
        let progress = value.state.progress();
        let (state, transferred, error) = match &value.state {
            TransferState::Preparing => ("preparing", 0, None),
            TransferState::Sending { transferred, .. } => ("sending", *transferred, None),
            TransferState::Receiving { transferred, .. } => ("receiving", *transferred, None),
            TransferState::Completed { total } => ("completed", *total, None),
            TransferState::Failed { reason } => ("failed", 0, Some(reason.clone())),
            TransferState::Cancelled => ("cancelled", 0, None),
            TransferState::RequiresLocalConnection => ("requiresLocalConnection", 0, None),
        };
        Self {
            device_id: value.key.device_id,
            transfer_id: value.key.transfer_id,
            filename: value.filename,
            total_bytes: value.total_bytes,
            transferred_bytes: transferred,
            state: state.to_owned(),
            progress,
            error,
        }
    }
}

pub fn kdeconnect_generate_identity(device_name: String) -> anyhow::Result<RsKdeConnectIdentity> {
    let identity = LocalIdentity::generate(&device_name)?;
    let wan_identity = WanIdentity::generate();
    let mut identity: RsKdeConnectIdentity = identity.into();
    identity.wan_secret_key = wan_identity.secret_bytes().to_vec();
    Ok(identity)
}

pub fn kdeconnect_generate_wan_secret() -> Vec<u8> {
    WanIdentity::generate().secret_bytes().to_vec()
}

pub async fn start_kdeconnect(
    identity: RsKdeConnectIdentity,
    trusted: Vec<RsKdeConnectTrustedDevice>,
    run_commands: Vec<RsRunCommand>,
) -> anyhow::Result<RsKdeConnect> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    let wan_identity = WanIdentity::from_bytes(&identity.wan_secret_key)?;
    let kde_device_id = identity.device_id.clone();
    let device_name = identity.device_name.clone();
    let handle = KdeConnectHandle::start(KdeConnectConfig {
        identity: identity.try_into()?,
        trusted: trusted.into_iter().map(Into::into).collect(),
        lan: LanConfig {
            bind: BindMode::Any,
            allow_loopback: false,
        },
        // Seeded here rather than set after start: a phone asks for the command
        // list once when its plugin starts, and it connects fast enough to beat
        // a post-start call -- it would then cache an empty list until the next
        // reconnect.
        run_commands: run_commands.into_iter().map(Into::into).collect(),
    })
    .await?;
    handle.enable_wan(WanRuntimeConfig {
        identity: wan_identity,
        kde_device_id,
        device_name,
        device_type: "desktop".to_owned(),
        app_version: env!("CARGO_PKG_VERSION").to_owned(),
        capability_digest: relay_core::kdeconnect::canonical_incoming_capabilities().join("\n"),
    }).await?;
    // Media control is best-effort: a machine with no D-Bus session bus still
    // runs Relay, just without MPRIS. Failing the whole KDE runtime over it
    // would take LAN and WAN down with it.
    #[cfg(all(target_os = "linux", feature = "mpris"))]
    if let Err(error) = handle.enable_media().await {
        tracing::warn!("[Relay MPRIS] media control unavailable: {error}");
    }
    Ok(RsKdeConnect {
        handle: Arc::new(handle),
    })
}

/// One entry in the desktop's RunCommand allow-list.
///
/// `id` is generated once and persisted, so a phone's cached id stays valid
/// across restarts. The phone can only ever name an id -- it never supplies
/// `command`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RsRunCommand {
    pub id: String,
    pub name: String,
    pub command: String,
    pub enabled: bool,
}

impl From<RunCommandEntry> for RsRunCommand {
    fn from(value: RunCommandEntry) -> Self {
        Self {
            id: value.id,
            name: value.name,
            command: value.command,
            enabled: value.enabled,
        }
    }
}

impl From<RsRunCommand> for RunCommandEntry {
    fn from(value: RsRunCommand) -> Self {
        Self {
            id: value.id,
            name: value.name,
            command: value.command,
            enabled: value.enabled,
        }
    }
}

/// Generates a stable id for a newly created command, so Dart never has to
/// invent one and every entry is identified the same way.
pub fn kdeconnect_new_run_command_id() -> String {
    RunCommandEntry::new(String::new(), String::new(), false).id
}

pub struct RsKdeConnect {
    handle: Arc<KdeConnectHandle>,
}

impl RsKdeConnect {
    pub async fn listen(&self, sink: StreamSink<RsKdeConnectEvent>) {
        loop {
            let Some(event) = self.handle.recv().await else {
                break;
            };
            if let KdeConnectEvent::SmsChanged {
                device_id,
                conversations,
                messages,
            } = &event
            {
                tracing::info!(
                    "[RelaySmsBridge] FFI event device={} conversations={} messages={}",
                    device_id,
                    conversations.len(),
                    messages.len()
                );
            }
            if sink.add(event.into()).is_err() {
                break;
            }
        }
    }

    pub async fn snapshot(&self) -> Vec<RsKdeConnectDevice> {
        self.handle
            .snapshot()
            .await
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// The Device Fabric: the authoritative product device model.
    ///
    /// One record per trusted logical device, with LAN and Relay WAN recorded
    /// as routes against it. Normally the UI receives this on the
    /// `DevicesChanged` event; this call exists for the initial read, before
    /// any event has arrived.
    pub async fn device_fabric(&self) -> RsRelayDeviceFabric {
        self.handle.device_fabric().await.into()
    }

    pub async fn request_pair(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.request_pair(&device_id).await
    }

    pub async fn accept_pair(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.accept_pair(&device_id).await
    }

    pub async fn reject_pair(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.reject_pair(&device_id).await
    }

    pub async fn unpair(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.unpair(&device_id).await
    }

    pub async fn send_ping(
        &self,
        device_id: String,
        message: Option<String>,
    ) -> anyhow::Result<()> {
        self.handle.send_ping(&device_id, message).await
    }

    pub async fn send_relay_ping(&self, device_id: String) -> anyhow::Result<()> {
        self.handle
            .send_relay_ping(&device_id, &uuid::Uuid::new_v4().to_string())
            .await
    }

    pub async fn request_relay_device_state(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.request_relay_device_state(&device_id).await
    }

    pub async fn find_phone(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.find_phone(&device_id).await
    }

    pub async fn send_clipboard(
        &self,
        device_id: String,
        content: String,
        timestamp_ms: i64,
    ) -> anyhow::Result<()> {
        self.handle
            .send_clipboard(&device_id, &content, timestamp_ms)
            .await
    }

    pub async fn send_clipboard_to_all_paired(
        &self,
        content: String,
        timestamp_ms: i64,
    ) -> anyhow::Result<()> {
        self.handle
            .send_clipboard_to_all_paired(&content, timestamp_ms)
            .await
    }

    pub async fn request_notifications(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.request_notifications(&device_id).await
    }

    /// Dismisses one notification on the logical device that produced it.
    ///
    /// Both arguments are required: a remote notification id is unique only
    /// within its own device, so dismissing by id alone would be ambiguous
    /// across simultaneously connected phones.
    pub async fn dismiss_notification(
        &self,
        device_id: String,
        remote_notification_id: String,
    ) -> anyhow::Result<()> {
        self.handle
            .dismiss_notification(&device_id, &remote_notification_id)
            .await
    }

    /// Sets where received files are written.
    pub async fn set_download_dir(&self, directory: String) {
        self.handle.set_download_dir(std::path::PathBuf::from(directory)).await;
    }

    /// Sends one file to a device. Returns the transfer id; progress arrives as
    /// `TransferChanged` events.
    ///
    /// A file too large for the current remote route resolves to the
    /// `requiresLocalConnection` state rather than an error — nothing failed,
    /// the file simply needs a local network.
    pub async fn send_file(&self, device_id: String, path: String) -> anyhow::Result<String> {
        self.handle.send_file(&device_id, std::path::Path::new(&path)).await
    }

    /// Cancels an in-flight transfer. Idempotent; a transfer that already
    /// finished keeps its outcome.
    pub async fn cancel_transfer(&self, device_id: String, transfer_id: String) {
        self.handle.cancel_transfer(&device_id, &transfer_id).await;
    }

    pub async fn transfers_for(&self, device_id: String) -> Vec<RsTransfer> {
        self.handle
            .transfers_for(&device_id)
            .await
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Whether clipboard sync is switched on for this desktop.
    pub fn clipboard_enabled(&self) -> bool {
        self.handle.clipboard_enabled()
    }

    /// Turns clipboard sync on or off. When off nothing is transmitted and an
    /// incoming clipboard does not overwrite the local one.
    pub fn set_clipboard_enabled(&self, enabled: bool) {
        self.handle.set_clipboard_enabled(enabled);
    }

    /// Whether remote input is switched on for this desktop.
    pub fn remote_input_enabled(&self) -> bool {
        self.handle.remote_input_enabled()
    }

    pub fn set_remote_input_enabled(&self, enabled: bool) {
        self.handle.set_remote_input_enabled(enabled);
    }

    /// Whether an OS-level input session is currently authorised.
    pub async fn remote_input_ready(&self) -> bool {
        self.handle.remote_input_ready().await
    }

    /// Asks the desktop for permission to inject input.
    ///
    /// Raises the compositor's own approval dialog, so it must only be called
    /// from a deliberate user action in Settings -- never at startup, and never
    /// because a phone sent something.
    pub async fn authorize_remote_input(&self) -> anyhow::Result<()> {
        #[cfg(all(target_os = "linux", feature = "remote-input"))]
        {
            return self.handle.authorize_remote_input().await;
        }
        #[cfg(not(all(target_os = "linux", feature = "remote-input")))]
        {
            anyhow::bail!("remote input is not supported on this platform")
        }
    }

    pub async fn revoke_remote_input(&self) {
        self.handle.revoke_remote_input().await;
    }

    /// Replaces the RunCommand allow-list. Effective immediately for every
    /// connected device, over both LAN and Relay WAN.
    pub fn set_run_commands(&self, commands: Vec<RsRunCommand>) {
        self.handle
            .set_run_commands(commands.into_iter().map(Into::into).collect());
    }

    pub fn run_commands(&self) -> Vec<RsRunCommand> {
        self.handle.run_commands().into_iter().map(Into::into).collect()
    }

    pub async fn get_notifications(&self, device_id: String) -> Vec<RsKdeNotification> {
        self.handle
            .get_notifications(&device_id)
            .await
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub async fn get_sms_conversations(&self, device_id: String) -> Vec<RsKdeSmsConversation> {
        self.handle
            .get_sms_conversations(&device_id)
            .await
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub async fn get_sms_messages(
        &self,
        device_id: String,
        thread_id: i64,
    ) -> Vec<RsKdeSmsMessage> {
        self.handle
            .get_sms_messages(&device_id, thread_id)
            .await
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub async fn request_sms_conversations(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.request_sms_conversations(&device_id).await
    }

    pub async fn request_sms_conversation(
        &self,
        device_id: String,
        thread_id: i64,
        before: Option<i64>,
    ) -> anyhow::Result<()> {
        self.handle
            .request_sms_conversation(&device_id, thread_id, before, 50)
            .await
    }

    pub async fn send_sms(
        &self,
        device_id: String,
        addresses: Vec<String>,
        body: String,
        sub_id: Option<i32>,
    ) -> anyhow::Result<()> {
        self.handle
            .send_sms(&device_id, addresses, &body, sub_id)
            .await
    }

    pub async fn mute_call(&self, device_id: String) -> anyhow::Result<()> {
        self.handle.send_mute_call(&device_id).await
    }

    pub fn stop(&self) {
        self.handle.stop();
    }
}

impl From<LocalIdentity> for RsKdeConnectIdentity {
    fn from(value: LocalIdentity) -> Self {
        Self {
            device_id: value.device_id,
            device_name: value.device_name,
            certificate_pem: value.certificate_pem,
            private_key_pem: value.private_key_pem,
            wan_secret_key: Vec::new(),
        }
    }
}

impl TryFrom<RsKdeConnectIdentity> for LocalIdentity {
    type Error = anyhow::Error;

    fn try_from(value: RsKdeConnectIdentity) -> anyhow::Result<Self> {
        LocalIdentity::from_persisted(
            value.device_id,
            value.device_name,
            value.certificate_pem,
            value.private_key_pem,
        )
    }
}

impl From<TrustedDevice> for RsKdeConnectTrustedDevice {
    fn from(value: TrustedDevice) -> Self {
        Self {
            device_id: value.device_id,
            certificate_pem: value.certificate_pem,
            name: value.name,
            device_type: value.device_type,
            protocol_version: value.protocol_version,
            paired_at_unix: value.paired_at_unix,
            wan_endpoint_id: value.wan_endpoint_id,
        }
    }
}

impl From<RsKdeConnectTrustedDevice> for TrustedDevice {
    fn from(value: RsKdeConnectTrustedDevice) -> Self {
        Self {
            device_id: value.device_id,
            certificate_pem: value.certificate_pem,
            name: value.name,
            device_type: value.device_type,
            protocol_version: value.protocol_version,
            paired_at_unix: value.paired_at_unix,
            wan_endpoint_id: value.wan_endpoint_id,
        }
    }
}

impl From<DeviceSnapshot> for RsKdeConnectDevice {
    fn from(value: DeviceSnapshot) -> Self {
        Self {
            device_id: value.device_id,
            name: value.name,
            device_type: value.device_type,
            ip: value.ip,
            port: value.port,
            paired: value.paired,
            connected: value.connected,
            incoming_pair: value.incoming_pair,
            identity_mismatch: value.identity_mismatch,
            battery_percentage: value.battery_percentage,
            battery_is_charging: value.battery_is_charging,
            network_type: value.network_type,
            signal_level: value.signal_level,
            connectivity_stale: value.connectivity_stale,
            incoming_capabilities: value.incoming_capabilities,
            outgoing_capabilities: value.outgoing_capabilities,
            transport_kind: value.transport_kind.map(|kind| match kind {
                TransportKind::KdeLan => "kdeLan".to_owned(),
                TransportKind::RelayWan => "relayWan".to_owned(),
            }),
            transport_state: match value.transport_state {
                TransportState::Offline => "offline",
                TransportState::Local => "local",
                TransportState::RemoteDirect => "remoteDirect",
                TransportState::RemoteRelay => "remoteRelay",
                TransportState::Reconnecting => "reconnecting",
            }.to_owned(),
            last_rtt_ms: value.last_rtt_ms,
            last_seen_unix: value.last_seen_unix,
        }
    }
}

impl From<SmsAttachmentMetadata> for RsKdeSmsAttachment {
    fn from(value: SmsAttachmentMetadata) -> Self {
        Self {
            part_id: value.part_id,
            mime_type: value.mime_type,
            unique_identifier: value.unique_identifier,
        }
    }
}

impl From<SmsMessage> for RsKdeSmsMessage {
    fn from(value: SmsMessage) -> Self {
        Self {
            id: value.id,
            thread_id: value.thread_id,
            addresses: value.addresses,
            body: value.body,
            date: value.date,
            message_type: value.message_type,
            read: value.read,
            sub_id: value.sub_id,
            attachments: value.attachments.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<KdeSmsConversation> for RsKdeSmsConversation {
    fn from(value: KdeSmsConversation) -> Self {
        Self {
            thread_id: value.thread_id,
            participants: value.participants,
            latest_message: value.latest_message.map(Into::into),
            unread_count: value.unread_count,
        }
    }
}

impl From<KdeNotification> for RsKdeNotification {
    fn from(value: KdeNotification) -> Self {
        Self {
            id: value.id,
            app_name: value.app_name,
            title: value.title,
            text: value.text,
            time: value.time,
            is_clearable: value.is_clearable,
            silent: value.silent,
        }
    }
}

impl From<KdeConnectEvent> for RsKdeConnectEvent {
    fn from(value: KdeConnectEvent) -> Self {
        match value {
            KdeConnectEvent::DevicesChanged { devices, fabric } => {
                RsKdeConnectEvent::DevicesChanged {
                    devices: devices.into_iter().map(Into::into).collect(),
                    fabric: fabric.into(),
                }
            }
            KdeConnectEvent::IncomingPair { device_id, name } => {
                RsKdeConnectEvent::IncomingPair { device_id, name }
            }
            KdeConnectEvent::PairingFailed { device_id, reason } => {
                RsKdeConnectEvent::PairingFailed { device_id, reason }
            }
            KdeConnectEvent::TrustChanged { devices } => RsKdeConnectEvent::TrustChanged {
                devices: devices.into_iter().map(Into::into).collect(),
            },
            KdeConnectEvent::PingReceived { device_id, message } => {
                RsKdeConnectEvent::PingReceived { device_id, message }
            }
            KdeConnectEvent::ClipboardReceived {
                device_id,
                content,
                timestamp_ms,
            } => RsKdeConnectEvent::ClipboardReceived {
                device_id,
                content,
                timestamp_ms,
            },
            KdeConnectEvent::NotificationsChanged {
                device_id,
                notifications,
            } => RsKdeConnectEvent::NotificationsChanged {
                device_id,
                notifications: notifications.into_iter().map(Into::into).collect(),
            },
            KdeConnectEvent::SmsChanged {
                device_id,
                conversations,
                messages,
            } => RsKdeConnectEvent::SmsChanged {
                device_id,
                conversations: conversations.into_iter().map(Into::into).collect(),
                messages: messages.into_iter().map(Into::into).collect(),
            },
            KdeConnectEvent::TelephonyReceived { device_id, event } => {
                RsKdeConnectEvent::TelephonyReceived {
                    device_id,
                    event: event.into(),
                }
            }
            KdeConnectEvent::TransferChanged { transfer } => RsKdeConnectEvent::TransferChanged {
                transfer: transfer.into(),
            },
        }
    }
}

impl From<KdeTelephonyEvent> for RsKdeTelephonyEvent {
    fn from(value: KdeTelephonyEvent) -> Self {
        Self {
            event: value.event,
            is_cancel: value.is_cancel,
            phone_number: value.phone_number,
            contact_name: value.contact_name,
            phone_thumbnail: value.phone_thumbnail,
        }
    }
}


impl From<RelayConnectionState> for RsRelayConnectionState {
    fn from(value: RelayConnectionState) -> Self {
        match value {
            RelayConnectionState::Offline => RsRelayConnectionState::Offline,
            RelayConnectionState::Local => RsRelayConnectionState::Local,
            RelayConnectionState::RemoteDirect => RsRelayConnectionState::RemoteDirect,
            RelayConnectionState::RemoteRelay => RsRelayConnectionState::RemoteRelay,
            RelayConnectionState::Reconnecting => RsRelayConnectionState::Reconnecting,
        }
    }
}

impl From<RelayDeviceClass> for RsRelayDeviceClass {
    fn from(value: RelayDeviceClass) -> Self {
        match value {
            RelayDeviceClass::Desktop => RsRelayDeviceClass::Desktop,
            RelayDeviceClass::Laptop => RsRelayDeviceClass::Laptop,
            RelayDeviceClass::Phone => RsRelayDeviceClass::Phone,
            RelayDeviceClass::Tablet => RsRelayDeviceClass::Tablet,
            RelayDeviceClass::Tv => RsRelayDeviceClass::Tv,
            RelayDeviceClass::Other => RsRelayDeviceClass::Other,
        }
    }
}

impl From<RelayFeature> for RsRelayFeature {
    fn from(value: RelayFeature) -> Self {
        match value {
            RelayFeature::Notifications => RsRelayFeature::Notifications,
            RelayFeature::Messages => RsRelayFeature::Messages,
            RelayFeature::Media => RsRelayFeature::Media,
            RelayFeature::Commands => RsRelayFeature::Commands,
            RelayFeature::RemoteInput => RsRelayFeature::RemoteInput,
            RelayFeature::Clipboard => RsRelayFeature::Clipboard,
            RelayFeature::Files => RsRelayFeature::Files,
            RelayFeature::Battery => RsRelayFeature::Battery,
            RelayFeature::Ping => RsRelayFeature::Ping,
        }
    }
}

impl From<FeatureAvailability> for RsFeatureAvailability {
    fn from(value: FeatureAvailability) -> Self {
        match value {
            FeatureAvailability::Available => RsFeatureAvailability::Available,
            FeatureAvailability::Unsupported => RsFeatureAvailability::Unsupported,
            FeatureAvailability::NotConnected => RsFeatureAvailability::NotConnected,
            FeatureAvailability::Disabled => RsFeatureAvailability::Disabled,
            FeatureAvailability::NeedsPermission => RsFeatureAvailability::NeedsPermission,
            FeatureAvailability::NotConfigured => RsFeatureAvailability::NotConfigured,
        }
    }
}

/// Maps one fabric record for the product layer.
///
/// Takes the policy explicitly rather than reading it again: availability is a
/// function of both, and the two must come from the same observation.
#[frb(ignore)]
fn relay_device_from_record(record: &RelayDeviceRecord, policy: &LocalFeaturePolicy) -> RsRelayDevice {
    RsRelayDevice {
        device_id: record.id.clone(),
        display_name: record.display_name.clone(),
        device_class: record.class.into(),
        platform: record.platform.clone(),
        platform_version: record.platform_version.clone(),
        relay_version: record.relay_version.clone(),
        trusted: record.trusted,
        connection_state: record.connection.into(),
        lan_available: record.routes.lan_available,
        wan_available: record.routes.wan_available,
        wan_bound: record.routes.wan_bound,
        // Only meaningful while a WAN route is actually up; a remembered
        // binding is not a path.
        wan_path: record.routes.wan_available.then(|| {
            if record.routes.wan_relayed { "relay" } else { "direct" }.to_owned()
        }),
        lan_last_seen_unix: record.routes.lan_last_seen,
        wan_last_seen_unix: record.routes.wan_last_seen,
        last_seen_unix: record.last_seen(),
        battery_percent: record.battery_percent,
        charging: record.charging,
        capabilities: record.capabilities.iter().copied().map(Into::into).collect(),
        feature_availability: record
            .availability_map(policy)
            .into_iter()
            .map(|(feature, availability)| RsRelayFeatureState {
                feature: feature.into(),
                availability: availability.into(),
            })
            .collect(),
    }
}

impl From<RelayFabricSnapshot> for RsRelayDeviceFabric {
    fn from(value: RelayFabricSnapshot) -> Self {
        // The primary is chosen by the core's rule, not by whichever device the
        // UI happened to iterate first. Pinning is a presentation preference and
        // is applied on the Dart side, over this default.
        let primary_device_id = value.primary(None).map(|device| device.id.clone());
        Self {
            devices: value
                .devices
                .iter()
                .map(|record| relay_device_from_record(record, &value.policy))
                .collect(),
            primary_device_id,
            clipboard_enabled: value.policy.clipboard_enabled,
            remote_input_enabled: value.policy.remote_input_enabled,
            remote_input_authorized: value.policy.remote_input_authorized,
            has_configured_commands: value.policy.has_configured_commands,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn phone_record() -> RelayDeviceRecord {
        let mut record =
            RelayDeviceRecord::remembered("phone-a", "Galaxy M14", RelayDeviceClass::Phone);
        record.capabilities = [RelayFeature::Messages, RelayFeature::Clipboard]
            .into_iter()
            .collect();
        record.routes.wan_available = true;
        record.routes.wan_bound = true;
        record.routes.wan_relayed = true;
        record.routes.wan_last_seen = Some(1_700_000_000);
        record.battery_percent = Some(58);
        record.charging = Some(false);
        record.refresh_connection(false);
        record
    }

    #[test]
    fn a_fabric_record_crosses_the_bridge_without_losing_its_connection_state() {
        let snapshot = RelayFabricSnapshot {
            devices: vec![phone_record()],
            policy: LocalFeaturePolicy {
                clipboard_enabled: true,
                ..LocalFeaturePolicy::default()
            },
        };
        let fabric: RsRelayDeviceFabric = snapshot.into();

        assert_eq!(fabric.devices.len(), 1, "LAN and WAN are routes, not devices");
        let device = &fabric.devices[0];
        assert_eq!(device.device_id, "phone-a");
        assert!(matches!(device.device_class, RsRelayDeviceClass::Phone));
        assert!(matches!(
            device.connection_state,
            RsRelayConnectionState::RemoteRelay
        ));
        assert_eq!(device.wan_path.as_deref(), Some("relay"));
        assert!(device.wan_bound);
        assert!(!device.lan_available);
        assert_eq!(device.last_seen_unix, Some(1_700_000_000));
        assert_eq!(device.battery_percent, Some(58));
        assert_eq!(fabric.primary_device_id.as_deref(), Some("phone-a"));
    }

    #[test]
    fn every_feature_crosses_with_the_answer_the_core_gave() {
        let record = phone_record();
        let policy = LocalFeaturePolicy::default();
        let fabric: RsRelayDeviceFabric = RelayFabricSnapshot {
            devices: vec![record.clone()],
            policy,
        }
        .into();

        let states = &fabric.devices[0].feature_availability;
        assert_eq!(states.len(), RelayFeature::ALL.len(), "no feature is dropped");

        let availability = |wanted: RelayFeature| {
            states
                .iter()
                .find(|state| {
                    std::mem::discriminant(&state.feature)
                        == std::mem::discriminant(&RsRelayFeature::from(wanted))
                })
                .map(|state| std::mem::discriminant(&state.availability))
                .expect("feature present")
        };
        // Advertised and connected.
        assert_eq!(
            availability(RelayFeature::Messages),
            std::mem::discriminant(&RsFeatureAvailability::Available)
        );
        // Advertised, connected, but switched off locally -- not the same thing
        // as a peer that cannot do it.
        assert_eq!(
            availability(RelayFeature::Clipboard),
            std::mem::discriminant(&RsFeatureAvailability::Disabled)
        );
        // Never advertised.
        assert_eq!(
            availability(RelayFeature::Files),
            std::mem::discriminant(&RsFeatureAvailability::Unsupported)
        );
    }

    #[test]
    fn a_wan_binding_without_a_live_route_reports_no_path() {
        let mut record = phone_record();
        record.routes.wan_available = false;
        record.refresh_connection(false);
        let fabric: RsRelayDeviceFabric = RelayFabricSnapshot {
            devices: vec![record],
            policy: LocalFeaturePolicy::default(),
        }
        .into();

        let device = &fabric.devices[0];
        // Remembered reachability is not current reachability.
        assert!(device.wan_bound);
        assert_eq!(device.wan_path, None);
        assert!(matches!(device.connection_state, RsRelayConnectionState::Offline));
    }

    #[test]
    fn sms_changed_crosses_the_bridge_without_narrowing_or_dropping_lists() {
        let message = SmsMessage {
            id: 9_223_372_036,
            thread_id: 4_294_967_297,
            addresses: vec!["+15550100".into()],
            body: "test".into(),
            date: 1_700_000_000_000,
            message_type: 1,
            read: Some(true),
            sub_id: Some(2),
            event: None,
            attachments: Vec::new(),
        };
        let event = KdeConnectEvent::SmsChanged {
            device_id: "phone-id".into(),
            conversations: vec![KdeSmsConversation {
                thread_id: message.thread_id,
                participants: message.addresses.clone(),
                latest_message: Some(message.clone()),
                unread_count: 0,
            }],
            messages: vec![message],
        };

        match RsKdeConnectEvent::from(event) {
            RsKdeConnectEvent::SmsChanged {
                device_id,
                conversations,
                messages,
            } => {
                assert_eq!(device_id, "phone-id");
                assert_eq!(conversations.len(), 1);
                assert_eq!(conversations[0].thread_id, 4_294_967_297);
                assert_eq!(messages.len(), 1);
                assert_eq!(messages[0].id, 9_223_372_036);
                assert_eq!(messages[0].date, 1_700_000_000_000);
            }
            _ => panic!("expected SmsChanged"),
        }
    }
}

#[frb(ignore)]
pub fn _keep_frb_imports() {}
