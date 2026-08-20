//! KDE Connect compatibility surface for Relay Linux.
//!
//! Isolated from RelayId / LocalSend trust. Pairing here never authenticates a
//! Relay-native peer.

use std::sync::Arc;

use flutter_rust_bridge::frb;
use relay_core::kdeconnect::{
    BindMode, DeviceSnapshot, KdeConnectConfig, KdeConnectEvent, KdeConnectHandle, KdeNotification,
    LanConfig, LocalIdentity, TrustedDevice,
};

use crate::frb_generated::StreamSink;

pub struct RsKdeConnectIdentity {
    pub device_id: String,
    pub device_name: String,
    pub certificate_pem: String,
    pub private_key_pem: String,
}

pub struct RsKdeConnectTrustedDevice {
    pub device_id: String,
    pub certificate_pem: String,
    pub name: String,
    pub device_type: String,
    pub protocol_version: i64,
    pub paired_at_unix: i64,
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

pub enum RsKdeConnectEvent {
    DevicesChanged {
        devices: Vec<RsKdeConnectDevice>,
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
}

pub fn kdeconnect_generate_identity(device_name: String) -> anyhow::Result<RsKdeConnectIdentity> {
    let identity = LocalIdentity::generate(&device_name)?;
    Ok(identity.into())
}

pub async fn start_kdeconnect(
    identity: RsKdeConnectIdentity,
    trusted: Vec<RsKdeConnectTrustedDevice>,
) -> anyhow::Result<RsKdeConnect> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    let handle = KdeConnectHandle::start(KdeConnectConfig {
        identity: identity.try_into()?,
        trusted: trusted.into_iter().map(Into::into).collect(),
        lan: LanConfig {
            bind: BindMode::Any,
            allow_loopback: false,
        },
    })
    .await?;
    Ok(RsKdeConnect {
        handle: Arc::new(handle),
    })
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

    pub async fn get_notifications(&self, device_id: String) -> Vec<RsKdeNotification> {
        self.handle
            .get_notifications(&device_id)
            .await
            .into_iter()
            .map(Into::into)
            .collect()
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
            KdeConnectEvent::DevicesChanged { devices } => RsKdeConnectEvent::DevicesChanged {
                devices: devices.into_iter().map(Into::into).collect(),
            },
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
        }
    }
}

#[frb(ignore)]
pub fn _keep_frb_imports() {}
