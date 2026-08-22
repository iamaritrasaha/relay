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
    NotificationBody, PairBody, PingBody, SmsMessage, SmsRequestConversationBody,
    SmsRequestConversationsBody, MAX_IDENTITY_PACKET_BYTES, MAX_PACKET_BYTES, PROTOCOL_VERSION,
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
                battery_percentage: b.map(|s| s.current_charge),
                battery_is_charging: b.map(|s| s.is_charging),
                network_type: selected.map(|signal| signal.network_type.clone()),
                signal_level: selected.map(|signal| signal.signal_strength as i32),
                connectivity_stale: connectivity.is_some_and(|state| state.stale),
                incoming_capabilities: inc,
                outgoing_capabilities: out_caps,
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
                battery_percentage: b.map(|s| s.current_charge),
                battery_is_charging: b.map(|s| s.is_charging),
                network_type: selected.map(|signal| signal.network_type.clone()),
                signal_level: selected.map(|signal| signal.signal_strength as i32),
                connectivity_stale: connectivity.is_some_and(|state| state.stale),
                incoming_capabilities: inc,
                outgoing_capabilities: out_caps,
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
        if let Some(session) = self.pairing.lock().await.get_mut(device_id) {
            session.local_cancel();
        }
        self.incoming.lock().await.remove(device_id);
        self.trust.lock().await.remove(device_id);
        self.battery.lock().await.remove(device_id);
        self.connectivity.lock().await.remove(device_id);
        self.clipboard.lock().await.remove(device_id);
        self.notifications.lock().await.remove(device_id);
        self.sms.lock().await.remove(device_id);
        self.peer_capabilities.lock().await.remove(device_id);
        let _ = self.event_tx.send(KdeConnectEvent::NotificationsChanged {
            device_id: device_id.to_string(),
            notifications: Vec::new(),
        });
        let _ = self
            .send_packet(device_id, &PairBody::unpair().serialize())
            .await;
        self.emit_trust().await;
        self.emit_devices().await;
        Ok(())
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
        self.ensure_peer_accepts(device_id, crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT)
            .await?;
        self.clipboard
            .lock()
            .await
            .insert(device_id.to_string(), timestamp_ms);
        let pkt = ClipboardBody::connect(content, timestamp_ms).serialize();
        self.send_packet(device_id, &pkt).await
    }

    pub async fn send_clipboard_to_all_paired(
        &self,
        content: &str,
        timestamp_ms: i64,
    ) -> Result<()> {
        let trusted = self.trust.lock().await.snapshot();
        let pkt = ClipboardBody::connect(content, timestamp_ms).serialize();
        let connections = self.connections.lock().await;
        let peer_capabilities = self.peer_capabilities.lock().await;
        for t in trusted {
            let peer_accepts_clipboard =
                peer_capabilities
                    .get(&t.device_id)
                    .is_some_and(|(incoming, _)| {
                        incoming.iter().any(|capability| {
                            capability == crate::kdeconnect::PACKET_TYPE_CLIPBOARD_CONNECT
                        })
                    });
            if peer_accepts_clipboard {
                if let Some(conn) = connections.get(&t.device_id) {
                    let _ = conn.packets.send(pkt.clone()).await;
                    self.clipboard
                        .lock()
                        .await
                        .insert(t.device_id, timestamp_ms);
                }
            }
        }
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
                        } else if let Ok(battery) = packet.as_battery() {
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
                            let now_ms = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .map(|d| d.as_millis() as i64)
                                .unwrap_or(0);
                            let ts = clipboard.timestamp.unwrap_or(now_ms);
                            let mut cb_map = read_inner.clipboard.lock().await;
                            let prev_ts = cb_map.get(&read_id).copied().unwrap_or(0);
                            if ts >= prev_ts {
                                cb_map.insert(read_id.clone(), ts);
                                drop(cb_map);
                                let _ =
                                    read_inner
                                        .event_tx
                                        .send(KdeConnectEvent::ClipboardReceived {
                                            device_id: read_id.clone(),
                                            content: clipboard.content,
                                            timestamp_ms: ts,
                                        });
                            }
                        } else if let Ok(ping) = packet.as_ping() {
                            tracing::info!("[KDE Connect] Received ping from {read_id}");
                            let _ = read_inner.event_tx.send(KdeConnectEvent::PingReceived {
                                device_id: read_id.clone(),
                                message: ping.message,
                            });
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
        {
            let mut connections = read_inner.connections.lock().await;
            if connections
                .get(&read_id)
                .is_some_and(|conn| conn.epoch == conn_epoch)
            {
                connections.remove(&read_id);
            }
        }
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
    use crate::kdeconnect::BatteryBody;
    use std::net::Ipv4Addr;

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

        let listener = TcpListener::bind("127.0.0.1:1740").await.unwrap();
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

        let listener = TcpListener::bind("127.0.0.1:1741").await.unwrap();
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
