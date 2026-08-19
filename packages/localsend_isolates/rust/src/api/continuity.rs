//! Product-facing Relay Continuity API.
//!
//! Flutter never touches transport internals here: there is no endpoint, no
//! stream, no TLS and no proof material in this surface. The app configures
//! what it is willing to share, hands over the secret material the platform
//! stores already hold, and then exchanges typed events.
//!
//! Authorization is not re-implemented in this file. Every payload still goes
//! through `localsend::continuity`, which requires a proven
//! `AuthenticatedRelaySession`, an explicit trust record and an explicit
//! per-capability grant.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use flutter_rust_bridge::frb;
use localsend::anywhere::{
    connect_continuity, spawn_link, AnywhereIdentity, PathPreference, RelayAddressV1,
};
use localsend::continuity::{
    capability_entry, clipboard_fingerprint, now_ms, BatteryState, CallAction, CallActionOutcome,
    CallActionRequest, CallActionResult, CallPhase, CallState, CapabilityGrant, CapabilityManifest,
    CapabilityState, ChargingState, ClipboardMode, ClipboardUpdate, ContinuityCapability,
    ContinuityErrorPayload, ContinuityEvent, ContinuityEventSink, ContinuityHostRequest,
    ContinuityPayload, ContinuityPermissions, ContinuitySessionConfig, ContinuitySessionEnd,
    ContinuitySessionHandle, DevicePlatform, NotificationDismissRequest, NotificationEvent,
    NotificationRemoval, SharedPermissions, SmsConversation, SmsConversationsPage,
    SmsConversationsRequest, SmsDirection, SmsMessage, SmsMessagesPage, SmsMessagesRequest,
    SmsSendOutcome, SmsSendRequest,
};
use localsend::relay::{RelayId, TrustDirectory, TrustRecord};
use tokio::sync::{mpsc, oneshot, RwLock};
use tokio_util::sync::CancellationToken;

use crate::frb_generated::StreamSink;

// ------------------------------------------------------------------ trust

/// The app's view of which devices the user has explicitly trusted.
///
/// This is a lookup table, never written from the network. Adding a RelayId
/// here is the persisted result of a user action in the pairing UI.
#[frb(ignore)]
#[derive(Default)]
struct AppTrustDirectory {
    trusted: std::sync::RwLock<HashSet<String>>,
    blocked: std::sync::RwLock<HashSet<String>>,
}

impl TrustDirectory for AppTrustDirectory {
    fn lookup(&self, relay_id: &RelayId) -> TrustRecord {
        let hex = relay_id.as_hex();
        if self
            .blocked
            .read()
            .map(|set| set.contains(&hex))
            .unwrap_or(false)
        {
            return TrustRecord::Blocked;
        }
        if self
            .trusted
            .read()
            .map(|set| set.contains(&hex))
            .unwrap_or(false)
        {
            return TrustRecord::Trusted;
        }
        TrustRecord::Unknown
    }
}

// ---------------------------------------------------------------- runtime

#[frb(ignore)]
enum PendingReply {
    Ack(oneshot::Sender<()>),
    Conversations(oneshot::Sender<Result<SmsConversationsPage, ContinuityErrorPayload>>),
    Messages(oneshot::Sender<Result<SmsMessagesPage, ContinuityErrorPayload>>),
    SmsSend(oneshot::Sender<SmsSendOutcome>),
    CallAction(oneshot::Sender<CallActionOutcome>),
}

#[frb(ignore)]
struct ContinuityRuntime {
    permissions: SharedPermissions,
    trust: Arc<AppTrustDirectory>,
    manifest: Mutex<CapabilityManifest>,
    links: Mutex<HashMap<String, ContinuitySessionHandle>>,
    dialers: Mutex<HashMap<String, CancellationToken>>,
    events: Mutex<Option<StreamSink<RsContinuityEvent>>>,
    host_sink: Mutex<Option<StreamSink<RsContinuityHostRequest>>>,
    pending: Mutex<HashMap<u64, PendingReply>>,
    next_request_id: AtomicU64,
    host_tx: mpsc::Sender<ContinuityHostRequest>,
}

fn runtime() -> &'static Arc<ContinuityRuntime> {
    static RUNTIME: OnceLock<Arc<ContinuityRuntime>> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        let (host_tx, host_rx) = mpsc::channel(64);
        let runtime = Arc::new(ContinuityRuntime {
            permissions: Arc::new(RwLock::new(ContinuityPermissions::new())),
            trust: Arc::new(AppTrustDirectory::default()),
            manifest: Mutex::new(CapabilityManifest {
                device_label: "Relay".to_owned(),
                platform: DevicePlatform::Unknown,
                entries: Vec::new(),
            }),
            links: Mutex::new(HashMap::new()),
            dialers: Mutex::new(HashMap::new()),
            events: Mutex::new(None),
            host_sink: Mutex::new(None),
            pending: Mutex::new(HashMap::new()),
            next_request_id: AtomicU64::new(1),
            host_tx,
        });
        spawn_host_pump(runtime.clone(), host_rx);
        runtime
    })
}

/// Forwards authorized host work to Dart and remembers where the answer goes.
fn spawn_host_pump(runtime: Arc<ContinuityRuntime>, mut host_rx: mpsc::Receiver<ContinuityHostRequest>) {
    tokio::spawn(async move {
        while let Some(request) = host_rx.recv().await {
            let request_id = runtime.next_request_id.fetch_add(1, Ordering::SeqCst);
            let remote = request.remote_relay_id().to_owned();
            let (pending, wire) = split_host_request(request_id, remote, request);
            runtime
                .pending
                .lock()
                .map(|mut map| map.insert(request_id, pending))
                .ok();
            let delivered = runtime
                .host_sink
                .lock()
                .ok()
                .and_then(|slot| slot.as_ref().map(|sink| sink.add(wire).is_ok()))
                .unwrap_or(false);
            if !delivered {
                // Nothing is listening: drop the reply channel so the session
                // answers the peer with a provider failure instead of hanging.
                runtime.pending.lock().map(|mut map| map.remove(&request_id)).ok();
            }
        }
    });
}

fn split_host_request(
    request_id: u64,
    remote: String,
    request: ContinuityHostRequest,
) -> (PendingReply, RsContinuityHostRequest) {
    match request {
        ContinuityHostRequest::ApplyClipboard { update, reply, .. } => (
            PendingReply::Ack(reply),
            RsContinuityHostRequest::ApplyClipboard {
                request_id,
                remote_relay_id: remote,
                text: update.text,
            },
        ),
        ContinuityHostRequest::DismissNotification { key, reply, .. } => (
            PendingReply::Ack(reply),
            RsContinuityHostRequest::DismissNotification {
                request_id,
                remote_relay_id: remote,
                key,
            },
        ),
        ContinuityHostRequest::ListConversations { request, reply, .. } => (
            PendingReply::Conversations(reply),
            RsContinuityHostRequest::ListConversations {
                request_id,
                remote_relay_id: remote,
                limit: request.limit,
                before_ms: request.before_ms,
            },
        ),
        ContinuityHostRequest::ListMessages { request, reply, .. } => (
            PendingReply::Messages(reply),
            RsContinuityHostRequest::ListMessages {
                request_id,
                remote_relay_id: remote,
                conversation_id: request.conversation_id,
                limit: request.limit,
                before_ms: request.before_ms,
            },
        ),
        ContinuityHostRequest::SendSms { request, reply, .. } => (
            PendingReply::SmsSend(reply),
            RsContinuityHostRequest::SendSms {
                request_id,
                remote_relay_id: remote,
                conversation_id: request.conversation_id,
                recipients: request.recipients,
                body: request.body,
            },
        ),
        ContinuityHostRequest::CallAction { request, reply, .. } => (
            PendingReply::CallAction(reply),
            RsContinuityHostRequest::CallAction {
                request_id,
                remote_relay_id: remote,
                action: map_action_out(request.action),
                address: request.address,
            },
        ),
    }
}

fn take_pending(request_id: u64) -> Option<PendingReply> {
    runtime()
        .pending
        .lock()
        .ok()
        .and_then(|mut map| map.remove(&request_id))
}

// ------------------------------------------------------------- wire types

#[derive(Clone, Copy, Debug)]
pub enum RsContinuityCapability {
    Battery,
    Clipboard,
    Notifications,
    Messages,
    Phone,
}

impl From<RsContinuityCapability> for ContinuityCapability {
    fn from(value: RsContinuityCapability) -> Self {
        match value {
            RsContinuityCapability::Battery => Self::Battery,
            RsContinuityCapability::Clipboard => Self::Clipboard,
            RsContinuityCapability::Notifications => Self::Notifications,
            RsContinuityCapability::Messages => Self::Messages,
            RsContinuityCapability::Phone => Self::Phone,
        }
    }
}

fn map_capability_in(capability: ContinuityCapability) -> Option<RsContinuityCapability> {
    match capability {
        ContinuityCapability::Battery => Some(RsContinuityCapability::Battery),
        ContinuityCapability::Clipboard => Some(RsContinuityCapability::Clipboard),
        ContinuityCapability::Notifications => Some(RsContinuityCapability::Notifications),
        ContinuityCapability::Messages => Some(RsContinuityCapability::Messages),
        ContinuityCapability::Phone => Some(RsContinuityCapability::Phone),
        ContinuityCapability::Session | ContinuityCapability::Unknown => None,
    }
}

/// Capability state as the UI must render it. `Limited` and `PermissionRequired`
/// carry the exact platform reason so the app never has to invent one.
#[derive(Clone, Debug)]
pub enum RsCapabilityState {
    Available,
    PermissionRequired { reason: String },
    Limited { reason: String },
    Unavailable { reason: String },
}

impl From<RsCapabilityState> for CapabilityState {
    fn from(value: RsCapabilityState) -> Self {
        match value {
            RsCapabilityState::Available => Self::Available,
            RsCapabilityState::PermissionRequired { reason } => Self::PermissionRequired { reason },
            RsCapabilityState::Limited { reason } => Self::Limited { reason },
            RsCapabilityState::Unavailable { reason } => Self::Unavailable { reason },
        }
    }
}

fn map_state_in(state: &CapabilityState) -> RsCapabilityState {
    match state {
        CapabilityState::Available => RsCapabilityState::Available,
        CapabilityState::PermissionRequired { reason } => RsCapabilityState::PermissionRequired {
            reason: reason.clone(),
        },
        CapabilityState::Limited { reason } => RsCapabilityState::Limited {
            reason: reason.clone(),
        },
        CapabilityState::Unavailable { reason } => RsCapabilityState::Unavailable {
            reason: reason.clone(),
        },
    }
}

#[derive(Clone, Debug)]
pub struct RsCapabilityEntry {
    pub capability: RsContinuityCapability,
    pub state: RsCapabilityState,
}

#[derive(Clone, Debug)]
pub struct RsCapabilityManifest {
    pub device_label: String,
    pub platform: String,
    pub entries: Vec<RsCapabilityEntry>,
}

#[derive(Clone, Copy, Debug)]
pub enum RsChargingState {
    Discharging,
    Charging,
    Full,
    NotCharging,
    Unknown,
}

impl From<RsChargingState> for ChargingState {
    fn from(value: RsChargingState) -> Self {
        match value {
            RsChargingState::Discharging => Self::Discharging,
            RsChargingState::Charging => Self::Charging,
            RsChargingState::Full => Self::Full,
            RsChargingState::NotCharging => Self::NotCharging,
            RsChargingState::Unknown => Self::Unknown,
        }
    }
}

fn map_charging_in(state: ChargingState) -> RsChargingState {
    match state {
        ChargingState::Discharging => RsChargingState::Discharging,
        ChargingState::Charging => RsChargingState::Charging,
        ChargingState::Full => RsChargingState::Full,
        ChargingState::NotCharging => RsChargingState::NotCharging,
        ChargingState::Unknown => RsChargingState::Unknown,
    }
}

#[derive(Clone, Copy, Debug)]
pub enum RsClipboardMode {
    Off,
    Ask,
    Automatic,
}

impl From<RsClipboardMode> for ClipboardMode {
    fn from(value: RsClipboardMode) -> Self {
        match value {
            RsClipboardMode::Off => Self::Off,
            RsClipboardMode::Ask => Self::Ask,
            RsClipboardMode::Automatic => Self::Automatic,
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub enum RsCallPhase {
    Idle,
    Ringing,
    Dialing,
    Active,
    Ended,
    Unknown,
}

impl From<RsCallPhase> for CallPhase {
    fn from(value: RsCallPhase) -> Self {
        match value {
            RsCallPhase::Idle => Self::Idle,
            RsCallPhase::Ringing => Self::Ringing,
            RsCallPhase::Dialing => Self::Dialing,
            RsCallPhase::Active => Self::Active,
            RsCallPhase::Ended => Self::Ended,
            RsCallPhase::Unknown => Self::Unknown,
        }
    }
}

fn map_phase_in(phase: CallPhase) -> RsCallPhase {
    match phase {
        CallPhase::Idle => RsCallPhase::Idle,
        CallPhase::Ringing => RsCallPhase::Ringing,
        CallPhase::Dialing => RsCallPhase::Dialing,
        CallPhase::Active => RsCallPhase::Active,
        CallPhase::Ended => RsCallPhase::Ended,
        CallPhase::Unknown => RsCallPhase::Unknown,
    }
}

#[derive(Clone, Copy, Debug)]
pub enum RsCallAction {
    Dial,
    Answer,
    Reject,
    HangUp,
}

impl From<RsCallAction> for CallAction {
    fn from(value: RsCallAction) -> Self {
        match value {
            RsCallAction::Dial => Self::Dial,
            RsCallAction::Answer => Self::Answer,
            RsCallAction::Reject => Self::Reject,
            RsCallAction::HangUp => Self::HangUp,
        }
    }
}

fn map_action_out(action: CallAction) -> RsCallAction {
    match action {
        CallAction::Dial => RsCallAction::Dial,
        CallAction::Answer => RsCallAction::Answer,
        CallAction::Reject => RsCallAction::Reject,
        // A request that failed validation never reaches here; treat anything
        // unexpected as the least privileged action.
        CallAction::HangUp | CallAction::Unknown => RsCallAction::HangUp,
    }
}

#[derive(Clone, Debug)]
pub struct RsSmsConversation {
    pub conversation_id: String,
    pub display_name: Option<String>,
    pub addresses: Vec<String>,
    pub snippet: Option<String>,
    pub last_message_at_ms: u64,
    pub unread: bool,
}

#[derive(Clone, Debug)]
pub struct RsSmsMessage {
    pub conversation_id: String,
    pub message_id: String,
    pub outgoing: bool,
    pub address: Option<String>,
    pub body: String,
    pub sent_at_ms: u64,
    pub read: bool,
}

#[derive(Clone, Debug)]
pub struct RsCallState {
    pub phase: RsCallPhase,
    pub address: Option<String>,
    pub display_name: Option<String>,
    pub active_duration_ms: Option<u64>,
}

/// Work a trusted peer asked this device to perform, after authorization.
#[derive(Clone, Debug)]
pub enum RsContinuityHostRequest {
    ApplyClipboard {
        request_id: u64,
        remote_relay_id: String,
        text: String,
    },
    DismissNotification {
        request_id: u64,
        remote_relay_id: String,
        key: String,
    },
    ListConversations {
        request_id: u64,
        remote_relay_id: String,
        limit: u32,
        before_ms: Option<u64>,
    },
    ListMessages {
        request_id: u64,
        remote_relay_id: String,
        conversation_id: String,
        limit: u32,
        before_ms: Option<u64>,
    },
    SendSms {
        request_id: u64,
        remote_relay_id: String,
        conversation_id: Option<String>,
        recipients: Vec<String>,
        body: String,
    },
    CallAction {
        request_id: u64,
        remote_relay_id: String,
        action: RsCallAction,
        address: Option<String>,
    },
}

#[derive(Clone, Debug)]
pub enum RsContinuityEvent {
    SessionEstablished {
        remote_relay_id: String,
        direct_path: bool,
    },
    SessionEnded {
        remote_relay_id: String,
        reason: String,
    },
    ManifestReceived {
        remote_relay_id: String,
        manifest: RsCapabilityManifest,
    },
    BatteryChanged {
        remote_relay_id: String,
        percentage: Option<u32>,
        charging: RsChargingState,
    },
    ClipboardOffered {
        remote_relay_id: String,
        text: String,
        explicit: bool,
    },
    NotificationPosted {
        remote_relay_id: String,
        key: String,
        app_label: String,
        title: Option<String>,
        body: Option<String>,
        posted_at_ms: u64,
        clearable: bool,
    },
    NotificationRemoved {
        remote_relay_id: String,
        key: String,
    },
    ConversationsPage {
        remote_relay_id: String,
        conversations: Vec<RsSmsConversation>,
        has_more: bool,
    },
    MessagesPage {
        remote_relay_id: String,
        conversation_id: String,
        messages: Vec<RsSmsMessage>,
        has_more: bool,
    },
    MessageReceived {
        remote_relay_id: String,
        message: RsSmsMessage,
    },
    SmsSendCompleted {
        remote_relay_id: String,
        request_id: String,
        sent: bool,
        detail: Option<String>,
    },
    CallStateChanged {
        remote_relay_id: String,
        state: RsCallState,
    },
    CallActionCompleted {
        remote_relay_id: String,
        request_id: String,
        accepted: bool,
        detail: Option<String>,
    },
    PeerError {
        remote_relay_id: String,
        code: String,
        detail: String,
    },
}

fn map_message(message: SmsMessage) -> RsSmsMessage {
    RsSmsMessage {
        conversation_id: message.conversation_id,
        message_id: message.message_id,
        outgoing: matches!(message.direction, SmsDirection::Outgoing),
        address: message.address,
        body: message.body,
        sent_at_ms: message.sent_at_ms,
        read: message.read,
    }
}

fn map_conversation(conversation: SmsConversation) -> RsSmsConversation {
    RsSmsConversation {
        conversation_id: conversation.conversation_id,
        display_name: conversation.display_name,
        addresses: conversation.addresses,
        snippet: conversation.snippet,
        last_message_at_ms: conversation.last_message_at_ms,
        unread: conversation.unread,
    }
}

fn map_end(reason: &ContinuitySessionEnd) -> String {
    match reason {
        ContinuitySessionEnd::Closed => "closed".to_owned(),
        ContinuitySessionEnd::Cancelled => "cancelled".to_owned(),
        ContinuitySessionEnd::NotTrusted => "not_trusted".to_owned(),
        ContinuitySessionEnd::Blocked => "blocked".to_owned(),
        ContinuitySessionEnd::ProtocolViolation { .. } => "protocol_violation".to_owned(),
        ContinuitySessionEnd::TransportFailed { .. } => "transport_failed".to_owned(),
    }
}

fn map_event(event: ContinuityEvent) -> Option<RsContinuityEvent> {
    Some(match event {
        ContinuityEvent::SessionEstablished {
            remote_relay_id,
            direct_path,
        } => RsContinuityEvent::SessionEstablished {
            remote_relay_id,
            direct_path,
        },
        ContinuityEvent::SessionEnded {
            remote_relay_id,
            reason,
        } => RsContinuityEvent::SessionEnded {
            remote_relay_id,
            reason: map_end(&reason),
        },
        ContinuityEvent::ManifestReceived {
            remote_relay_id,
            manifest,
        } => RsContinuityEvent::ManifestReceived {
            remote_relay_id,
            manifest: RsCapabilityManifest {
                device_label: manifest.device_label,
                platform: manifest.platform.as_str().to_owned(),
                entries: manifest
                    .entries
                    .into_iter()
                    .filter_map(|entry| {
                        map_capability_in(entry.capability).map(|capability| RsCapabilityEntry {
                            capability,
                            state: map_state_in(&entry.state),
                        })
                    })
                    .collect(),
            },
        },
        ContinuityEvent::PeerSubscribed { .. } => return None,
        ContinuityEvent::BatteryChanged {
            remote_relay_id,
            state,
        } => RsContinuityEvent::BatteryChanged {
            remote_relay_id,
            percentage: state.percentage.map(u32::from),
            charging: map_charging_in(state.charging),
        },
        ContinuityEvent::ClipboardOffered {
            remote_relay_id,
            update,
        } => RsContinuityEvent::ClipboardOffered {
            remote_relay_id,
            text: update.text,
            explicit: update.explicit,
        },
        ContinuityEvent::NotificationPosted {
            remote_relay_id,
            event,
        } => RsContinuityEvent::NotificationPosted {
            remote_relay_id,
            key: event.key,
            app_label: event.app_label,
            title: event.title,
            body: event.body,
            posted_at_ms: event.posted_at_ms,
            clearable: event.clearable,
        },
        ContinuityEvent::NotificationRemoved {
            remote_relay_id,
            removal,
        } => RsContinuityEvent::NotificationRemoved {
            remote_relay_id,
            key: removal.key,
        },
        ContinuityEvent::ConversationsPage {
            remote_relay_id,
            page,
        } => RsContinuityEvent::ConversationsPage {
            remote_relay_id,
            conversations: page.conversations.into_iter().map(map_conversation).collect(),
            has_more: page.has_more,
        },
        ContinuityEvent::MessagesPage {
            remote_relay_id,
            page,
        } => RsContinuityEvent::MessagesPage {
            remote_relay_id,
            conversation_id: page.conversation_id,
            messages: page.messages.into_iter().map(map_message).collect(),
            has_more: page.has_more,
        },
        ContinuityEvent::MessageReceived {
            remote_relay_id,
            message,
        } => RsContinuityEvent::MessageReceived {
            remote_relay_id,
            message: map_message(message),
        },
        ContinuityEvent::SmsSendCompleted {
            remote_relay_id,
            request_id,
            outcome,
        } => {
            let (sent, detail) = match outcome {
                SmsSendOutcome::Sent { .. } => (true, None),
                SmsSendOutcome::Duplicate => (true, Some("duplicate".to_owned())),
                SmsSendOutcome::Rejected { reason } | SmsSendOutcome::Failed { reason } => {
                    (false, Some(reason))
                }
            };
            RsContinuityEvent::SmsSendCompleted {
                remote_relay_id,
                request_id,
                sent,
                detail,
            }
        }
        ContinuityEvent::CallStateChanged {
            remote_relay_id,
            state,
        } => RsContinuityEvent::CallStateChanged {
            remote_relay_id,
            state: RsCallState {
                phase: map_phase_in(state.phase),
                address: state.address,
                display_name: state.display_name,
                active_duration_ms: state.active_duration_ms,
            },
        },
        ContinuityEvent::CallActionCompleted {
            remote_relay_id,
            request_id,
            outcome,
        } => {
            let (accepted, detail) = match outcome {
                CallActionOutcome::Accepted => (true, None),
                CallActionOutcome::Duplicate => (true, Some("duplicate".to_owned())),
                CallActionOutcome::Rejected { reason }
                | CallActionOutcome::Unsupported { reason }
                | CallActionOutcome::Failed { reason } => (false, Some(reason)),
            };
            RsContinuityEvent::CallActionCompleted {
                remote_relay_id,
                request_id,
                accepted,
                detail,
            }
        }
        ContinuityEvent::PeerError {
            remote_relay_id,
            error,
        } => RsContinuityEvent::PeerError {
            remote_relay_id,
            code: error.code.as_str().to_owned(),
            detail: error.detail,
        },
    })
}

fn event_sink() -> ContinuityEventSink {
    Arc::new(move |event| {
        if let Some(mapped) = map_event(event) {
            if let Ok(slot) = runtime().events.lock() {
                if let Some(sink) = slot.as_ref() {
                    let _ = sink.add(mapped);
                }
            }
        }
    })
}

fn session_config() -> ContinuitySessionConfig {
    let runtime = runtime();
    ContinuitySessionConfig {
        local_manifest: runtime
            .manifest
            .lock()
            .map(|manifest| manifest.clone())
            .unwrap_or_else(|_| CapabilityManifest {
                device_label: "Relay".to_owned(),
                platform: DevicePlatform::Unknown,
                entries: Vec::new(),
            }),
        trust: runtime.trust.clone(),
        permissions: runtime.permissions.clone(),
        events: event_sink(),
        host: runtime.host_tx.clone(),
    }
}

// ------------------------------------------------------------- public API

/// Registers the continuity event stream. Called once, at app start.
pub fn continuity_events(sink: StreamSink<RsContinuityEvent>) {
    if let Ok(mut slot) = runtime().events.lock() {
        *slot = Some(sink);
    }
}

/// Registers the stream of authorized work a peer asks this device to perform.
pub fn continuity_host_requests(sink: StreamSink<RsContinuityHostRequest>) {
    if let Ok(mut slot) = runtime().host_sink.lock() {
        *slot = Some(sink);
    }
}

/// Publishes what this installation can actually do.
///
/// The app computes these states from real platform permission checks; nothing
/// here invents availability.
#[frb(sync)]
pub fn continuity_set_local_capabilities(
    device_label: String,
    platform: String,
    entries: Vec<RsCapabilityEntry>,
) {
    let manifest = CapabilityManifest {
        device_label,
        platform: match platform.as_str() {
            "android" => DevicePlatform::Android,
            "linux" => DevicePlatform::Linux,
            "windows" => DevicePlatform::Windows,
            "macos" => DevicePlatform::Macos,
            "ios" => DevicePlatform::Ios,
            _ => DevicePlatform::Unknown,
        },
        entries: entries
            .into_iter()
            .map(|entry| capability_entry(entry.capability.into(), entry.state.into()))
            .collect(),
    };
    if let Ok(mut slot) = runtime().manifest.lock() {
        *slot = manifest;
    }
}

/// Replaces the trusted/blocked device sets from persisted user decisions.
#[frb(sync)]
pub fn continuity_set_device_trust(trusted: Vec<String>, blocked: Vec<String>) {
    let runtime = runtime();
    if let Ok(mut set) = runtime.trust.trusted.write() {
        *set = trusted.into_iter().collect();
    }
    if let Ok(mut set) = runtime.trust.blocked.write() {
        *set = blocked.into_iter().collect();
    }
}

/// Enables one capability for one device. This is the user consent point;
/// pairing never calls it implicitly.
pub async fn continuity_enable_capability(relay_id: String, capability: RsContinuityCapability) {
    let mut permissions = runtime().permissions.write().await;
    permissions.set_grant(&relay_id, capability.into(), CapabilityGrant::Granted);
}

pub async fn continuity_disable_capability(relay_id: String, capability: RsContinuityCapability) {
    let mut permissions = runtime().permissions.write().await;
    permissions.set_grant(&relay_id, capability.into(), CapabilityGrant::Denied);
}

pub async fn continuity_set_clipboard_mode(relay_id: String, mode: RsClipboardMode) {
    let mut permissions = runtime().permissions.write().await;
    permissions.set_clipboard_mode(&relay_id, mode.into());
}

/// Serialises the permission store so the app can persist it verbatim.
pub async fn continuity_export_permissions() -> String {
    let permissions = runtime().permissions.read().await;
    serde_json::to_string(&*permissions).unwrap_or_else(|_| "{}".to_owned())
}

/// Restores a previously exported permission store. Malformed input leaves the
/// store empty (all denied) rather than partially applied.
pub async fn continuity_import_permissions(json: String) -> bool {
    match serde_json::from_str::<ContinuityPermissions>(&json) {
        Ok(restored) => {
            *runtime().permissions.write().await = restored;
            true
        }
        Err(_) => false,
    }
}

/// Whether any device has any continuity capability enabled.
///
/// Android uses this to decide whether a background service should exist at
/// all: a fresh install answers `false`.
pub async fn continuity_any_capability_enabled() -> bool {
    runtime().permissions.read().await.any_capability_enabled()
}

/// Whether a live, authenticated continuity session exists with a device.
/// A stored Relay address alone never makes this true.
#[frb(sync)]
pub fn continuity_is_connected(relay_id: String) -> bool {
    runtime()
        .links
        .lock()
        .map(|links| links.contains_key(&relay_id))
        .unwrap_or(false)
}

#[frb(sync)]
pub fn continuity_connected_devices() -> Vec<String> {
    runtime()
        .links
        .lock()
        .map(|links| links.keys().cloned().collect())
        .unwrap_or_default()
}

/// Opens and maintains an outbound continuity link to one paired device.
///
/// The Relay private key comes from the platform secret store and is wiped
/// here. No routing key is needed: continuity rides the endpoint the Anywhere
/// listener already bound, so there is one routing identity per device.
pub async fn continuity_connect_device(
    mut private_key_pem: Vec<u8>,
    relay_id: String,
    remote_address: String,
) -> anyhow::Result<()> {
    let identity = AnywhereIdentity::load(&mut private_key_pem, &relay_id);
    private_key_pem.fill(0);
    let identity = identity?;
    let remote = RelayAddressV1::decode(&remote_address)?;
    let remote_relay_id = remote.claimed_relay_id.clone();

    let state = runtime();
    let cancel = CancellationToken::new();
    {
        let mut dialers = state
            .dialers
            .lock()
            .map_err(|_| anyhow::anyhow!("continuity dialer state is unavailable"))?;
        if let Some(existing) = dialers.insert(remote_relay_id.clone(), cancel.clone()) {
            existing.cancel();
        }
    }

    // Continuity never binds its own Iroh endpoint: it rides the one the
    // Anywhere listener already owns, so a device has a single routing identity
    // and a single socket.
    let endpoint = crate::api::relay_anywhere::anywhere_listener_endpoint()
        .ok_or_else(|| anyhow::anyhow!("the Relay listener must be running before continuity connects"))?;

    tokio::spawn(async move {
        let runtime = runtime();
        let mut backoff = std::time::Duration::from_secs(2);
        loop {
            if cancel.is_cancelled() {
                break;
            }
            match connect_continuity(&endpoint, &remote, &identity, PathPreference::Auto).await {
                Ok((session, stream)) => {
                    backoff = std::time::Duration::from_secs(2);
                    let link = spawn_link(stream, session, session_config(), cancel.child_token());
                    runtime
                        .links
                        .lock()
                        .map(|mut links| {
                            links.insert(remote_relay_id.clone(), link.handle().clone())
                        })
                        .ok();
                    let end = link.shutdown().await;
                    runtime
                        .links
                        .lock()
                        .map(|mut links| links.remove(&remote_relay_id))
                        .ok();
                    // A refusal is a decision, not a fault: stop dialing.
                    if matches!(
                        end,
                        ContinuitySessionEnd::NotTrusted
                            | ContinuitySessionEnd::Blocked
                            | ContinuitySessionEnd::Cancelled
                    ) {
                        break;
                    }
                }
                Err(error) => {
                    tracing::debug!("continuity dial failed: {}", error.category());
                }
            }
            tokio::select! {
                _ = cancel.cancelled() => break,
                _ = tokio::time::sleep(backoff) => {}
            }
            backoff = (backoff * 2).min(std::time::Duration::from_secs(60));
        }
        runtime.dialers.lock().map(|mut d| d.remove(&remote_relay_id)).ok();
    });
    Ok(())
}

/// Stops the continuity link with one device without affecting others.
#[frb(sync)]
pub fn continuity_disconnect_device(relay_id: String) {
    if let Ok(mut dialers) = runtime().dialers.lock() {
        if let Some(cancel) = dialers.remove(&relay_id) {
            cancel.cancel();
        }
    }
}

/// Stops every continuity link. Called when the user turns continuity off, and
/// on app shutdown.
#[frb(sync)]
pub fn continuity_disconnect_all() {
    if let Ok(mut dialers) = runtime().dialers.lock() {
        for (_, cancel) in dialers.drain() {
            cancel.cancel();
        }
    }
}

async fn publish_all(payload: ContinuityPayload) {
    let handles: Vec<ContinuitySessionHandle> = runtime()
        .links
        .lock()
        .map(|links| links.values().cloned().collect())
        .unwrap_or_default();
    for handle in handles {
        handle.publish(payload.clone()).await;
    }
}

async fn publish_to(relay_id: &str, payload: ContinuityPayload) -> bool {
    let handle = runtime()
        .links
        .lock()
        .ok()
        .and_then(|links| links.get(relay_id).cloned());
    match handle {
        Some(handle) => handle.publish(payload).await,
        None => false,
    }
}

/// Publishes local battery state. Call only on a meaningful change.
pub async fn continuity_publish_battery(percentage: Option<u32>, charging: RsChargingState) {
    publish_all(ContinuityPayload::Battery(BatteryState {
        percentage: percentage.map(|value| value.min(100) as u8),
        charging: charging.into(),
    }))
    .await;
}

/// Shares local clipboard text. `explicit` marks a user-initiated share, which
/// is surfaced for confirmation on the peer even in Ask mode.
pub async fn continuity_share_clipboard(text: String, explicit: bool, origin_relay_id: String) {
    let fingerprint = clipboard_fingerprint(&text);
    publish_all(ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
        text,
        content_fingerprint: fingerprint,
        origin_relay_id,
        explicit,
    }))
    .await;
}

pub async fn continuity_publish_notification(
    key: String,
    app_label: String,
    title: Option<String>,
    body: Option<String>,
    posted_at_ms: u64,
    clearable: bool,
) {
    publish_all(ContinuityPayload::Notification(NotificationEvent {
        key,
        app_label,
        title,
        body,
        posted_at_ms,
        clearable,
    }))
    .await;
}

pub async fn continuity_publish_notification_removed(key: String) {
    publish_all(ContinuityPayload::NotificationRemoved(NotificationRemoval {
        key,
    }))
    .await;
}

pub async fn continuity_publish_call_state(
    phase: RsCallPhase,
    address: Option<String>,
    display_name: Option<String>,
    active_duration_ms: Option<u64>,
) {
    publish_all(ContinuityPayload::CallState(CallState {
        phase: phase.into(),
        address,
        display_name,
        active_duration_ms,
        changed_at_ms: now_ms(),
    }))
    .await;
}

/// Streams one newly received message to peers that mirror this device.
pub async fn continuity_publish_incoming_message(
    conversation_id: String,
    message_id: String,
    address: Option<String>,
    body: String,
    sent_at_ms: u64,
) {
    publish_all(ContinuityPayload::SmsMessage(SmsMessage {
        conversation_id,
        message_id,
        direction: SmsDirection::Incoming,
        address,
        body,
        sent_at_ms,
        read: false,
    }))
    .await;
}

pub async fn continuity_request_conversations(
    relay_id: String,
    limit: u32,
    before_ms: Option<u64>,
) -> bool {
    publish_to(
        &relay_id,
        ContinuityPayload::SmsConversationsRequest(SmsConversationsRequest {
            limit: limit.clamp(1, 100),
            before_ms,
        }),
    )
    .await
}

pub async fn continuity_request_messages(
    relay_id: String,
    conversation_id: String,
    limit: u32,
    before_ms: Option<u64>,
) -> bool {
    publish_to(
        &relay_id,
        ContinuityPayload::SmsMessagesRequest(SmsMessagesRequest {
            conversation_id,
            limit: limit.clamp(1, 100),
            before_ms,
        }),
    )
    .await
}

/// Asks a peer to send a message. `request_id` makes the send idempotent, so a
/// retry after a reconnect is answered rather than sent twice.
pub async fn continuity_send_sms(
    relay_id: String,
    request_id: String,
    conversation_id: Option<String>,
    recipients: Vec<String>,
    body: String,
) -> bool {
    publish_to(
        &relay_id,
        ContinuityPayload::SmsSendRequest(SmsSendRequest {
            request_id,
            conversation_id,
            recipients,
            body,
            issued_at_ms: now_ms(),
        }),
    )
    .await
}

pub async fn continuity_call_action(
    relay_id: String,
    request_id: String,
    action: RsCallAction,
    address: Option<String>,
) -> bool {
    publish_to(
        &relay_id,
        ContinuityPayload::CallActionRequest(CallActionRequest {
            request_id,
            action: action.into(),
            // Only a dial names a number; everything else acts on the current call.
            address: matches!(action, RsCallAction::Dial).then_some(address).flatten(),
            issued_at_ms: now_ms(),
        }),
    )
    .await
}

pub async fn continuity_dismiss_remote_notification(relay_id: String, key: String) -> bool {
    publish_to(
        &relay_id,
        ContinuityPayload::NotificationDismiss(NotificationDismissRequest {
            key,
            issued_at_ms: now_ms(),
        }),
    )
    .await
}

// ------------------------------------------------------ host request answers

#[frb(sync)]
pub fn continuity_answer_ack(request_id: u64) {
    if let Some(PendingReply::Ack(reply)) = take_pending(request_id) {
        let _ = reply.send(());
    }
}

#[frb(sync)]
pub fn continuity_answer_conversations(
    request_id: u64,
    conversations: Vec<RsSmsConversation>,
    has_more: bool,
) {
    if let Some(PendingReply::Conversations(reply)) = take_pending(request_id) {
        let _ = reply.send(Ok(SmsConversationsPage {
            conversations: conversations
                .into_iter()
                .map(|conversation| SmsConversation {
                    conversation_id: conversation.conversation_id,
                    display_name: conversation.display_name,
                    addresses: conversation.addresses,
                    snippet: conversation.snippet,
                    last_message_at_ms: conversation.last_message_at_ms,
                    unread: conversation.unread,
                })
                .collect(),
            has_more,
        }));
    }
}

#[frb(sync)]
pub fn continuity_answer_messages(
    request_id: u64,
    conversation_id: String,
    messages: Vec<RsSmsMessage>,
    has_more: bool,
) {
    if let Some(PendingReply::Messages(reply)) = take_pending(request_id) {
        let _ = reply.send(Ok(SmsMessagesPage {
            conversation_id,
            messages: messages
                .into_iter()
                .map(|message| SmsMessage {
                    conversation_id: message.conversation_id,
                    message_id: message.message_id,
                    direction: if message.outgoing {
                        SmsDirection::Outgoing
                    } else {
                        SmsDirection::Incoming
                    },
                    address: message.address,
                    body: message.body,
                    sent_at_ms: message.sent_at_ms,
                    read: message.read,
                })
                .collect(),
            has_more,
        }));
    }
}

/// Reports that a capability could not be served, with an honest reason.
#[frb(sync)]
pub fn continuity_answer_unavailable(request_id: u64, permission_required: bool, detail: String) {
    let code = if permission_required {
        localsend::continuity::ContinuityErrorCode::PermissionRequired
    } else {
        localsend::continuity::ContinuityErrorCode::Unsupported
    };
    let error = ContinuityErrorPayload {
        code,
        detail: detail.clone(),
    };
    match take_pending(request_id) {
        Some(PendingReply::Conversations(reply)) => {
            let _ = reply.send(Err(error));
        }
        Some(PendingReply::Messages(reply)) => {
            let _ = reply.send(Err(error));
        }
        Some(PendingReply::SmsSend(reply)) => {
            let _ = reply.send(SmsSendOutcome::Rejected { reason: detail });
        }
        Some(PendingReply::CallAction(reply)) => {
            let _ = reply.send(CallActionOutcome::Unsupported { reason: detail });
        }
        Some(PendingReply::Ack(reply)) => {
            let _ = reply.send(());
        }
        None => {}
    }
}

#[frb(sync)]
pub fn continuity_answer_sms_sent(request_id: u64, message_id: Option<String>) {
    if let Some(PendingReply::SmsSend(reply)) = take_pending(request_id) {
        let _ = reply.send(SmsSendOutcome::Sent { message_id });
    }
}

#[frb(sync)]
pub fn continuity_answer_sms_failed(request_id: u64, reason: String) {
    if let Some(PendingReply::SmsSend(reply)) = take_pending(request_id) {
        let _ = reply.send(SmsSendOutcome::Failed { reason });
    }
}

#[frb(sync)]
pub fn continuity_answer_call_action(request_id: u64, accepted: bool, reason: String) {
    if let Some(PendingReply::CallAction(reply)) = take_pending(request_id) {
        let outcome = if accepted {
            CallActionOutcome::Accepted
        } else {
            CallActionOutcome::Unsupported { reason }
        };
        let _ = reply.send(outcome);
    }
}

/// Unused import guard: `CallActionResult` is part of the protocol surface the
/// session answers with, and is referenced here so the import documents intent.
#[allow(dead_code)]
fn _protocol_surface(result: CallActionResult) -> String {
    result.request_id
}

/// Accept configuration for the Anywhere listener.
///
/// Returns `None` when no device has any capability enabled, so a fresh install
/// — or a user who only transfers files — never serves the continuity protocol
/// at all.
pub(crate) async fn listener_accept_config(
) -> Option<localsend::anywhere::listener::ContinuityAcceptConfig> {
    if !runtime().permissions.read().await.any_capability_enabled() {
        return None;
    }
    let (links_tx, mut links_rx) = mpsc::channel::<ContinuitySessionHandle>(8);
    tokio::spawn(async move {
        while let Some(handle) = links_rx.recv().await {
            let remote = handle.remote_relay_id().to_owned();
            runtime()
                .links
                .lock()
                .map(|mut links| links.insert(remote, handle))
                .ok();
        }
    });
    Some(localsend::anywhere::listener::ContinuityAcceptConfig {
        session_config: Arc::new(session_config),
        links: links_tx,
    })
}
