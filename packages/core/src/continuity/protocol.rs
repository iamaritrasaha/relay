//! Versioned Relay Continuity wire protocol (v1).
//!
//! One envelope type carries every continuity capability. There is deliberately
//! no generic "command" payload: every remote-triggerable action is a distinct
//! strongly typed struct with explicit bounds. Nothing here can name a method,
//! a path, an Android intent, or an executable.
//!
//! Authorization is **never** derived from anything in this module. The
//! `sender_relay_id` field is an echo used only for defence-in-depth
//! cross-checking against the proven
//! [`crate::relay::AuthenticatedRelaySession`]; it is not an identity.

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Declares a string-valued enum with a forward-compatible `Unknown` fallback.
///
/// `#[serde(other)]` is not available on plain externally-tagged unit enums, and
/// hard-failing an entire envelope because a newer peer named one extra state
/// would make the protocol brittle. Unknown values decode to the `Unknown`
/// variant, which is never authorized and never dispatched.
macro_rules! wire_enum {
    (
        $(#[$meta:meta])*
        pub enum $name:ident {
            $($(#[$vmeta:meta])* $variant:ident => $text:literal,)+
            _ => $unknown_text:literal,
        }
    ) => {
        $(#[$meta])*
        #[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
        pub enum $name {
            $($(#[$vmeta])* $variant,)+
            /// Forward-compatibility fallback. Never authorized, never dispatched.
            Unknown,
        }

        impl $name {
            pub fn as_str(self) -> &'static str {
                match self {
                    $(Self::$variant => $text,)+
                    Self::Unknown => $unknown_text,
                }
            }

            fn from_wire(value: &str) -> Self {
                match value {
                    $($text => Self::$variant,)+
                    _ => Self::Unknown,
                }
            }
        }

        impl Serialize for $name {
            fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
                serializer.serialize_str(self.as_str())
            }
        }

        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
                let value = std::borrow::Cow::<'de, str>::deserialize(deserializer)?;
                Ok(Self::from_wire(value.as_ref()))
            }
        }
    };
}

/// Wire version. A peer that does not send exactly this is rejected.
pub const CONTINUITY_PROTOCOL_VERSION: u16 = 1;

/// Hard cap on one encoded envelope, enforced before any allocation.
pub const MAX_ENVELOPE_BYTES: usize = 256 * 1024;
/// Cap on synchronised clipboard text.
pub const MAX_CLIPBOARD_TEXT_BYTES: usize = 64 * 1024;
/// Cap on a mirrored notification title.
pub const MAX_NOTIFICATION_TITLE_BYTES: usize = 512;
/// Cap on a mirrored notification body.
pub const MAX_NOTIFICATION_BODY_BYTES: usize = 4 * 1024;
/// Cap on an application label.
pub const MAX_APP_LABEL_BYTES: usize = 256;
/// Cap on any opaque stable key (notification key, conversation id, ...).
pub const MAX_KEY_BYTES: usize = 256;
/// Cap on an SMS body, both inbound mirror and outbound request.
pub const MAX_SMS_BODY_BYTES: usize = 4 * 1024;
/// Cap on a phone number / short code as transported.
pub const MAX_ADDRESS_BYTES: usize = 64;
/// Cap on a resolved contact display name.
pub const MAX_DISPLAY_NAME_BYTES: usize = 128;
/// Cap on recipients of one outbound message.
pub const MAX_RECIPIENTS: usize = 10;
/// Cap on any requested or returned page.
pub const MAX_PAGE_SIZE: u32 = 100;
/// Cap on a device label.
pub const MAX_DEVICE_LABEL_BYTES: usize = 128;
/// Cap on a free-text limitation reason.
pub const MAX_REASON_BYTES: usize = 256;
/// Cap on advertised capability entries in one manifest.
pub const MAX_MANIFEST_ENTRIES: usize = 32;
/// Cap on a message id.
pub const MAX_MESSAGE_ID_BYTES: usize = 64;
/// How far a privileged action request may be from local time and still be
/// honoured, in milliseconds. Bounds replay of `*ActionRequest` payloads.
pub const MAX_ACTION_SKEW_MS: u64 = 120_000;

wire_enum! {
    /// The continuity capabilities a device can advertise.
    ///
    /// `Unknown` exists so a newer peer's manifest does not fail to parse; an
    /// `Unknown` capability is never authorized and never dispatched.
    pub enum ContinuityCapability {
        /// Session-level control traffic (manifest, subscribe, heartbeat, errors).
        /// Always permitted on an authenticated session; carries no user data.
        Session => "session",
        Battery => "battery",
        Clipboard => "clipboard",
        Notifications => "notifications",
        Messages => "messages",
        Phone => "phone",
        _ => "unknown",
    }
}

impl ContinuityCapability {
    /// Capabilities a user can grant. `Session` is excluded because it is not a
    /// user-facing permission, and `Unknown` because it is never grantable.
    pub const GRANTABLE: [ContinuityCapability; 5] = [
        Self::Battery,
        Self::Clipboard,
        Self::Notifications,
        Self::Messages,
        Self::Phone,
    ];

    pub fn is_grantable(self) -> bool {
        Self::GRANTABLE.contains(&self)
    }
}

/// What a device can currently do for one capability.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum CapabilityState {
    /// Implemented, permitted, and usable right now.
    Available,
    /// Implemented, but a platform permission or role has not been granted yet.
    PermissionRequired { reason: String },
    /// Implemented and usable, but the platform restricts it in a way the user
    /// must be told about truthfully.
    Limited { reason: String },
    /// Not usable on this device/installation.
    Unavailable { reason: String },
}

impl CapabilityState {
    pub fn is_available(&self) -> bool {
        matches!(self, Self::Available | Self::Limited { .. })
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::Available => "available",
            Self::PermissionRequired { .. } => "permission_required",
            Self::Limited { .. } => "limited",
            Self::Unavailable { .. } => "unavailable",
        }
    }

    fn reason(&self) -> Option<&str> {
        match self {
            Self::Available => None,
            Self::PermissionRequired { reason }
            | Self::Limited { reason }
            | Self::Unavailable { reason } => Some(reason),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CapabilityEntry {
    pub capability: ContinuityCapability,
    #[serde(flatten)]
    pub state: CapabilityState,
}

/// What one device advertises to an authenticated peer.
///
/// A manifest only ever describes the *sender's* own installation. It never
/// grants the receiver anything.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CapabilityManifest {
    pub device_label: String,
    pub platform: DevicePlatform,
    pub entries: Vec<CapabilityEntry>,
}

impl CapabilityManifest {
    pub fn state_of(&self, capability: ContinuityCapability) -> Option<&CapabilityState> {
        self.entries
            .iter()
            .find(|entry| entry.capability == capability)
            .map(|entry| &entry.state)
    }
}

wire_enum! {
    pub enum DevicePlatform {
        Android => "android",
        Linux => "linux",
        Windows => "windows",
        Macos => "macos",
        Ios => "ios",
        _ => "unknown",
    }
}

wire_enum! {
    /// Charge state as reported by the platform. `Unknown` is transported honestly
    /// rather than being smoothed into a plausible-looking value.
    pub enum ChargingState {
        Discharging => "discharging",
        Charging => "charging",
        Full => "full",
        NotCharging => "not_charging",
        _ => "unknown",
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BatteryState {
    /// `None` when the platform did not report a level. Never synthesised.
    pub percentage: Option<u8>,
    pub charging: ChargingState,
}

/// Coarse device state that is cheap and non-sensitive.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct DeviceState {
    pub label: String,
    pub platform: DevicePlatform,
}

/// Origin of a clipboard payload, used for loop suppression.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ClipboardUpdate {
    pub text: String,
    /// SHA-256 (lowercase hex) of the exact text. Receivers compare this before
    /// applying, and never re-broadcast content whose fingerprint they just
    /// received.
    pub content_fingerprint: String,
    /// Relay id of the device the content *originally* came from. Carried so a
    /// three-device topology still terminates. Advisory metadata only.
    pub origin_relay_id: String,
    /// True when the local user explicitly pushed this, rather than an
    /// automatic sync.
    pub explicit: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct NotificationEvent {
    /// Stable per-notification identity on the source device.
    pub key: String,
    pub app_label: String,
    pub title: Option<String>,
    pub body: Option<String>,
    pub posted_at_ms: u64,
    /// Whether the source device considers this dismissible.
    pub clearable: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct NotificationRemoval {
    pub key: String,
}

/// Ask the source device to dismiss a mirrored notification.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct NotificationDismissRequest {
    pub key: String,
    pub issued_at_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsConversation {
    pub conversation_id: String,
    /// Locally resolved display name where Contacts permission allows it.
    /// Never a contacts-database export: only participants of this thread.
    pub display_name: Option<String>,
    pub addresses: Vec<String>,
    pub snippet: Option<String>,
    pub last_message_at_ms: u64,
    pub unread: bool,
}

wire_enum! {
    pub enum SmsDirection {
        Incoming => "incoming",
        Outgoing => "outgoing",
        _ => "unknown",
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsMessage {
    pub conversation_id: String,
    /// Source-device-local message id. Stable only within that device; it is
    /// never treated as cross-device identity.
    pub message_id: String,
    pub direction: SmsDirection,
    pub address: Option<String>,
    pub body: String,
    pub sent_at_ms: u64,
    pub read: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsConversationsRequest {
    pub limit: u32,
    /// Cursor: return conversations older than this timestamp.
    pub before_ms: Option<u64>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsConversationsPage {
    pub conversations: Vec<SmsConversation>,
    pub has_more: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsMessagesRequest {
    pub conversation_id: String,
    pub limit: u32,
    pub before_ms: Option<u64>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsMessagesPage {
    pub conversation_id: String,
    pub messages: Vec<SmsMessage>,
    pub has_more: bool,
}

/// A request to send a message from the remote device.
///
/// The `request_id` makes the send idempotent: the executing device records it
/// and returns the original result rather than sending twice after a reconnect.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsSendRequest {
    pub request_id: String,
    /// Existing thread to reply into, when known.
    pub conversation_id: Option<String>,
    pub recipients: Vec<String>,
    pub body: String,
    pub issued_at_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum SmsSendOutcome {
    Sent { message_id: Option<String> },
    Duplicate,
    Rejected { reason: String },
    Failed { reason: String },
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SmsSendResult {
    pub request_id: String,
    #[serde(flatten)]
    pub outcome: SmsSendOutcome,
}

wire_enum! {
    pub enum CallPhase {
        Idle => "idle",
        Ringing => "ringing",
        Dialing => "dialing",
        Active => "active",
        Ended => "ended",
        _ => "unknown",
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CallState {
    pub phase: CallPhase,
    /// Only populated when the platform actually exposed it under a granted
    /// permission. Never inferred.
    pub address: Option<String>,
    pub display_name: Option<String>,
    /// Milliseconds since the call became `Active`, when the platform reports it.
    pub active_duration_ms: Option<u64>,
    pub changed_at_ms: u64,
}

wire_enum! {
    pub enum CallAction {
        Dial => "dial",
        Answer => "answer",
        Reject => "reject",
        HangUp => "hang_up",
        _ => "unknown",
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CallActionRequest {
    pub request_id: String,
    pub action: CallAction,
    /// Required for [`CallAction::Dial`], forbidden otherwise.
    pub address: Option<String>,
    pub issued_at_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum CallActionOutcome {
    Accepted,
    Duplicate,
    Rejected { reason: String },
    Unsupported { reason: String },
    Failed { reason: String },
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CallActionResult {
    pub request_id: String,
    #[serde(flatten)]
    pub outcome: CallActionOutcome,
}

/// A structured error returned to the peer instead of dropping the session.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ContinuityErrorPayload {
    pub code: ContinuityErrorCode,
    pub detail: String,
}

wire_enum! {
    pub enum ContinuityErrorCode {
        /// The capability is not enabled for this peer on this device.
        NotAuthorized => "not_authorized",
        /// The capability exists but the platform permission is missing.
        PermissionRequired => "permission_required",
        /// The capability is not implemented on this platform.
        Unsupported => "unsupported",
        /// The envelope failed validation (bounds, shape, version).
        Malformed => "malformed",
        /// The request was a replay or was outside the freshness window.
        Stale => "stale",
        /// A transient failure in the underlying platform provider.
        ProviderFailure => "provider_failure",
        _ => "unknown",
    }
}

/// Every message body the protocol can carry.
///
/// Externally tagged by `type`. Adding a variant is a protocol change; a peer
/// that sends an unrecognised `type` receives a
/// [`ContinuityErrorCode::Malformed`] reply and the session continues.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContinuityPayload {
    /// Sender advertises its own capabilities.
    Manifest(CapabilityManifest),
    /// Ask the peer to (re)send its manifest.
    ManifestRequest,
    /// Ask the peer to start streaming these capabilities to us.
    Subscribe { capabilities: Vec<ContinuityCapability> },
    Unsubscribe { capabilities: Vec<ContinuityCapability> },
    Heartbeat,

    Battery(BatteryState),
    DeviceState(DeviceState),

    ClipboardUpdate(ClipboardUpdate),

    Notification(NotificationEvent),
    NotificationRemoved(NotificationRemoval),
    NotificationDismiss(NotificationDismissRequest),

    SmsConversationsRequest(SmsConversationsRequest),
    SmsConversationsPage(SmsConversationsPage),
    SmsMessagesRequest(SmsMessagesRequest),
    SmsMessagesPage(SmsMessagesPage),
    SmsMessage(SmsMessage),
    SmsSendRequest(SmsSendRequest),
    SmsSendResult(SmsSendResult),

    CallState(CallState),
    CallActionRequest(CallActionRequest),
    CallActionResult(CallActionResult),

    Error(ContinuityErrorPayload),
}

impl ContinuityPayload {
    /// The capability this payload belongs to. Used to check the envelope's
    /// declared capability against its actual body, so a peer cannot smuggle a
    /// `Messages` body under a `Battery` label to dodge authorization.
    pub fn capability(&self) -> ContinuityCapability {
        match self {
            Self::Manifest(_)
            | Self::ManifestRequest
            | Self::Subscribe { .. }
            | Self::Unsubscribe { .. }
            | Self::Heartbeat
            | Self::DeviceState(_)
            | Self::Error(_) => ContinuityCapability::Session,
            Self::Battery(_) => ContinuityCapability::Battery,
            Self::ClipboardUpdate(_) => ContinuityCapability::Clipboard,
            Self::Notification(_) | Self::NotificationRemoved(_) | Self::NotificationDismiss(_) => {
                ContinuityCapability::Notifications
            }
            Self::SmsConversationsRequest(_)
            | Self::SmsConversationsPage(_)
            | Self::SmsMessagesRequest(_)
            | Self::SmsMessagesPage(_)
            | Self::SmsMessage(_)
            | Self::SmsSendRequest(_)
            | Self::SmsSendResult(_) => ContinuityCapability::Messages,
            Self::CallState(_) | Self::CallActionRequest(_) | Self::CallActionResult(_) => {
                ContinuityCapability::Phone
            }
        }
    }

    /// Whether this payload asks the receiver to *do* something privileged on
    /// behalf of the sender. Those are the payloads subject to freshness and
    /// idempotency checks.
    pub fn is_action_request(&self) -> bool {
        matches!(
            self,
            Self::SmsSendRequest(_) | Self::CallActionRequest(_) | Self::NotificationDismiss(_)
        )
    }

    /// The instant the sender claims it issued a privileged action.
    pub fn issued_at_ms(&self) -> Option<u64> {
        match self {
            Self::SmsSendRequest(request) => Some(request.issued_at_ms),
            Self::CallActionRequest(request) => Some(request.issued_at_ms),
            Self::NotificationDismiss(request) => Some(request.issued_at_ms),
            _ => None,
        }
    }

    /// The idempotency key of a privileged action.
    pub fn action_request_id(&self) -> Option<&str> {
        match self {
            Self::SmsSendRequest(request) => Some(&request.request_id),
            Self::CallActionRequest(request) => Some(&request.request_id),
            Self::NotificationDismiss(request) => Some(&request.key),
            _ => None,
        }
    }
}

/// The single wire container.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ContinuityEnvelopeV1 {
    pub protocol_version: u16,
    pub message_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub correlation_id: Option<String>,
    /// Echo of the sender's Relay id.
    ///
    /// **This is not an identity.** The receiver's only legitimate use is to
    /// verify it equals the already-proven remote id of the authenticated
    /// session; a mismatch is a protocol error.
    pub sender_relay_id: String,
    pub capability: ContinuityCapability,
    pub timestamp_ms: u64,
    pub payload: ContinuityPayload,
}

#[derive(Clone, Debug, Eq, PartialEq, Error)]
pub enum ContinuityProtocolError {
    #[error("unsupported continuity protocol version")]
    UnsupportedVersion,
    #[error("continuity envelope field '{field}' exceeds its bound")]
    FieldTooLong { field: &'static str },
    #[error("continuity envelope field '{field}' is empty")]
    FieldEmpty { field: &'static str },
    #[error("continuity envelope declared capability does not match its payload")]
    CapabilityMismatch,
    #[error("continuity envelope names an unknown capability")]
    UnknownCapability,
    #[error("continuity envelope field '{field}' is out of range")]
    OutOfRange { field: &'static str },
    #[error("continuity envelope sender does not match the authenticated session")]
    SenderMismatch,
}

fn bound(field: &'static str, value: &str, max: usize) -> Result<(), ContinuityProtocolError> {
    if value.len() > max {
        return Err(ContinuityProtocolError::FieldTooLong { field });
    }
    Ok(())
}

fn non_empty(field: &'static str, value: &str, max: usize) -> Result<(), ContinuityProtocolError> {
    if value.is_empty() {
        return Err(ContinuityProtocolError::FieldEmpty { field });
    }
    bound(field, value, max)
}

fn bound_opt(
    field: &'static str,
    value: Option<&String>,
    max: usize,
) -> Result<(), ContinuityProtocolError> {
    match value {
        Some(value) => bound(field, value, max),
        None => Ok(()),
    }
}

fn bound_state(state: &CapabilityState) -> Result<(), ContinuityProtocolError> {
    match state.reason() {
        Some(reason) => bound("capability_state.reason", reason, MAX_REASON_BYTES),
        None => Ok(()),
    }
}

impl ContinuityEnvelopeV1 {
    /// Full structural and bounds validation.
    ///
    /// Called on every decoded envelope *before* the payload reaches any
    /// dispatcher, and on every envelope this device encodes, so a local bug
    /// cannot emit something a peer must reject.
    pub fn validate(&self) -> Result<(), ContinuityProtocolError> {
        if self.protocol_version != CONTINUITY_PROTOCOL_VERSION {
            return Err(ContinuityProtocolError::UnsupportedVersion);
        }
        non_empty("message_id", &self.message_id, MAX_MESSAGE_ID_BYTES)?;
        bound_opt(
            "correlation_id",
            self.correlation_id.as_ref(),
            MAX_MESSAGE_ID_BYTES,
        )?;
        non_empty("sender_relay_id", &self.sender_relay_id, 64)?;
        if self.capability == ContinuityCapability::Unknown {
            return Err(ContinuityProtocolError::UnknownCapability);
        }
        if self.capability != self.payload.capability() {
            return Err(ContinuityProtocolError::CapabilityMismatch);
        }
        validate_payload(&self.payload)
    }

    /// Defence in depth: the echoed sender must equal the proven remote id.
    pub fn check_sender(&self, proven_remote_relay_id: &str) -> Result<(), ContinuityProtocolError> {
        if self.sender_relay_id == proven_remote_relay_id {
            Ok(())
        } else {
            Err(ContinuityProtocolError::SenderMismatch)
        }
    }
}

fn validate_payload(payload: &ContinuityPayload) -> Result<(), ContinuityProtocolError> {
    match payload {
        ContinuityPayload::ManifestRequest | ContinuityPayload::Heartbeat => Ok(()),
        ContinuityPayload::Manifest(manifest) => {
            non_empty(
                "manifest.device_label",
                &manifest.device_label,
                MAX_DEVICE_LABEL_BYTES,
            )?;
            if manifest.entries.len() > MAX_MANIFEST_ENTRIES {
                return Err(ContinuityProtocolError::FieldTooLong {
                    field: "manifest.entries",
                });
            }
            for entry in &manifest.entries {
                bound_state(&entry.state)?;
            }
            Ok(())
        }
        ContinuityPayload::Subscribe { capabilities }
        | ContinuityPayload::Unsubscribe { capabilities } => {
            if capabilities.len() > MAX_MANIFEST_ENTRIES {
                return Err(ContinuityProtocolError::FieldTooLong {
                    field: "subscribe.capabilities",
                });
            }
            Ok(())
        }
        ContinuityPayload::Battery(state) => match state.percentage {
            Some(percentage) if percentage > 100 => Err(ContinuityProtocolError::OutOfRange {
                field: "battery.percentage",
            }),
            _ => Ok(()),
        },
        ContinuityPayload::DeviceState(state) => {
            non_empty("device_state.label", &state.label, MAX_DEVICE_LABEL_BYTES)
        }
        ContinuityPayload::ClipboardUpdate(update) => {
            bound("clipboard.text", &update.text, MAX_CLIPBOARD_TEXT_BYTES)?;
            non_empty("clipboard.content_fingerprint", &update.content_fingerprint, 64)?;
            non_empty("clipboard.origin_relay_id", &update.origin_relay_id, 64)
        }
        ContinuityPayload::Notification(event) => {
            non_empty("notification.key", &event.key, MAX_KEY_BYTES)?;
            non_empty("notification.app_label", &event.app_label, MAX_APP_LABEL_BYTES)?;
            bound_opt(
                "notification.title",
                event.title.as_ref(),
                MAX_NOTIFICATION_TITLE_BYTES,
            )?;
            bound_opt(
                "notification.body",
                event.body.as_ref(),
                MAX_NOTIFICATION_BODY_BYTES,
            )
        }
        ContinuityPayload::NotificationRemoved(removal) => {
            non_empty("notification_removed.key", &removal.key, MAX_KEY_BYTES)
        }
        ContinuityPayload::NotificationDismiss(request) => {
            non_empty("notification_dismiss.key", &request.key, MAX_KEY_BYTES)
        }
        ContinuityPayload::SmsConversationsRequest(request) => check_page_limit(request.limit),
        ContinuityPayload::SmsConversationsPage(page) => {
            if page.conversations.len() as u32 > MAX_PAGE_SIZE {
                return Err(ContinuityProtocolError::OutOfRange {
                    field: "sms_conversations_page.conversations",
                });
            }
            for conversation in &page.conversations {
                validate_conversation(conversation)?;
            }
            Ok(())
        }
        ContinuityPayload::SmsMessagesRequest(request) => {
            non_empty(
                "sms_messages_request.conversation_id",
                &request.conversation_id,
                MAX_KEY_BYTES,
            )?;
            check_page_limit(request.limit)
        }
        ContinuityPayload::SmsMessagesPage(page) => {
            non_empty(
                "sms_messages_page.conversation_id",
                &page.conversation_id,
                MAX_KEY_BYTES,
            )?;
            if page.messages.len() as u32 > MAX_PAGE_SIZE {
                return Err(ContinuityProtocolError::OutOfRange {
                    field: "sms_messages_page.messages",
                });
            }
            for message in &page.messages {
                validate_sms_message(message)?;
            }
            Ok(())
        }
        ContinuityPayload::SmsMessage(message) => validate_sms_message(message),
        ContinuityPayload::SmsSendRequest(request) => {
            non_empty(
                "sms_send_request.request_id",
                &request.request_id,
                MAX_MESSAGE_ID_BYTES,
            )?;
            bound_opt(
                "sms_send_request.conversation_id",
                request.conversation_id.as_ref(),
                MAX_KEY_BYTES,
            )?;
            if request.recipients.is_empty() {
                return Err(ContinuityProtocolError::FieldEmpty {
                    field: "sms_send_request.recipients",
                });
            }
            if request.recipients.len() > MAX_RECIPIENTS {
                return Err(ContinuityProtocolError::FieldTooLong {
                    field: "sms_send_request.recipients",
                });
            }
            for recipient in &request.recipients {
                non_empty("sms_send_request.recipient", recipient, MAX_ADDRESS_BYTES)?;
            }
            non_empty("sms_send_request.body", &request.body, MAX_SMS_BODY_BYTES)
        }
        ContinuityPayload::SmsSendResult(result) => {
            non_empty(
                "sms_send_result.request_id",
                &result.request_id,
                MAX_MESSAGE_ID_BYTES,
            )?;
            match &result.outcome {
                SmsSendOutcome::Sent { message_id } => {
                    bound_opt("sms_send_result.message_id", message_id.as_ref(), MAX_KEY_BYTES)
                }
                SmsSendOutcome::Rejected { reason } | SmsSendOutcome::Failed { reason } => {
                    bound("sms_send_result.reason", reason, MAX_REASON_BYTES)
                }
                SmsSendOutcome::Duplicate => Ok(()),
            }
        }
        ContinuityPayload::CallState(state) => {
            bound_opt("call_state.address", state.address.as_ref(), MAX_ADDRESS_BYTES)?;
            bound_opt(
                "call_state.display_name",
                state.display_name.as_ref(),
                MAX_DISPLAY_NAME_BYTES,
            )
        }
        ContinuityPayload::CallActionRequest(request) => {
            non_empty(
                "call_action_request.request_id",
                &request.request_id,
                MAX_MESSAGE_ID_BYTES,
            )?;
            match request.action {
                CallAction::Unknown => Err(ContinuityProtocolError::OutOfRange {
                    field: "call_action_request.action",
                }),
                CallAction::Dial => match request.address.as_deref() {
                    Some(address) => {
                        non_empty("call_action_request.address", address, MAX_ADDRESS_BYTES)
                    }
                    None => Err(ContinuityProtocolError::FieldEmpty {
                        field: "call_action_request.address",
                    }),
                },
                // Answer/Reject/HangUp act on the current call only. Carrying an
                // address there would imply a target the receiver must not honour.
                _ => match request.address {
                    Some(_) => Err(ContinuityProtocolError::OutOfRange {
                        field: "call_action_request.address",
                    }),
                    None => Ok(()),
                },
            }
        }
        ContinuityPayload::CallActionResult(result) => {
            non_empty(
                "call_action_result.request_id",
                &result.request_id,
                MAX_MESSAGE_ID_BYTES,
            )?;
            match &result.outcome {
                CallActionOutcome::Rejected { reason }
                | CallActionOutcome::Unsupported { reason }
                | CallActionOutcome::Failed { reason } => {
                    bound("call_action_result.reason", reason, MAX_REASON_BYTES)
                }
                CallActionOutcome::Accepted | CallActionOutcome::Duplicate => Ok(()),
            }
        }
        ContinuityPayload::Error(error) => bound("error.detail", &error.detail, MAX_REASON_BYTES),
    }
}

fn check_page_limit(limit: u32) -> Result<(), ContinuityProtocolError> {
    if limit == 0 || limit > MAX_PAGE_SIZE {
        return Err(ContinuityProtocolError::OutOfRange { field: "page.limit" });
    }
    Ok(())
}

fn validate_conversation(conversation: &SmsConversation) -> Result<(), ContinuityProtocolError> {
    non_empty(
        "sms_conversation.conversation_id",
        &conversation.conversation_id,
        MAX_KEY_BYTES,
    )?;
    bound_opt(
        "sms_conversation.display_name",
        conversation.display_name.as_ref(),
        MAX_DISPLAY_NAME_BYTES,
    )?;
    if conversation.addresses.len() > MAX_RECIPIENTS {
        return Err(ContinuityProtocolError::FieldTooLong {
            field: "sms_conversation.addresses",
        });
    }
    for address in &conversation.addresses {
        bound("sms_conversation.address", address, MAX_ADDRESS_BYTES)?;
    }
    bound_opt(
        "sms_conversation.snippet",
        conversation.snippet.as_ref(),
        MAX_SMS_BODY_BYTES,
    )
}

fn validate_sms_message(message: &SmsMessage) -> Result<(), ContinuityProtocolError> {
    non_empty(
        "sms_message.conversation_id",
        &message.conversation_id,
        MAX_KEY_BYTES,
    )?;
    non_empty("sms_message.message_id", &message.message_id, MAX_KEY_BYTES)?;
    bound_opt("sms_message.address", message.address.as_ref(), MAX_ADDRESS_BYTES)?;
    bound("sms_message.body", &message.body, MAX_SMS_BODY_BYTES)
}
