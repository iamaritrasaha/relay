//! The boundary between the continuity protocol and the platform.
//!
//! The core never calls an Android API, reads a clipboard, or touches a
//! telephony service. It emits [`ContinuityHostRequest`]s that the app layer
//! fulfils and answers on a oneshot, mirroring how the existing HTTP server
//! hands `PrepareUpload` decisions back to Dart. That keeps every platform
//! integration replaceable by a fake in tests.

use tokio::sync::oneshot;

use super::protocol::{
    CallActionOutcome, CallActionRequest, CallState, CapabilityManifest, ClipboardUpdate,
    ContinuityErrorPayload, NotificationEvent, NotificationRemoval, SmsConversationsPage,
    SmsConversationsRequest, SmsMessage, SmsMessagesPage, SmsMessagesRequest, SmsSendOutcome,
    SmsSendRequest, BatteryState,
};

/// Work the *remote* peer asked this device to perform.
///
/// Every variant is already authorized when it is emitted: the session checked
/// the proven RelayId, the trust record, and the local capability grant.
#[derive(Debug)]
pub enum ContinuityHostRequest {
    /// Write text the peer shared into the local clipboard.
    ApplyClipboard {
        remote_relay_id: String,
        update: ClipboardUpdate,
        reply: oneshot::Sender<()>,
    },
    /// Dismiss a local notification the peer cleared on its mirror.
    DismissNotification {
        remote_relay_id: String,
        key: String,
        reply: oneshot::Sender<()>,
    },
    ListConversations {
        remote_relay_id: String,
        request: SmsConversationsRequest,
        reply: oneshot::Sender<Result<SmsConversationsPage, ContinuityErrorPayload>>,
    },
    ListMessages {
        remote_relay_id: String,
        request: SmsMessagesRequest,
        reply: oneshot::Sender<Result<SmsMessagesPage, ContinuityErrorPayload>>,
    },
    SendSms {
        remote_relay_id: String,
        request: SmsSendRequest,
        reply: oneshot::Sender<SmsSendOutcome>,
    },
    CallAction {
        remote_relay_id: String,
        request: CallActionRequest,
        reply: oneshot::Sender<CallActionOutcome>,
    },
}

impl ContinuityHostRequest {
    pub fn remote_relay_id(&self) -> &str {
        match self {
            Self::ApplyClipboard {
                remote_relay_id, ..
            }
            | Self::DismissNotification {
                remote_relay_id, ..
            }
            | Self::ListConversations {
                remote_relay_id, ..
            }
            | Self::ListMessages {
                remote_relay_id, ..
            }
            | Self::SendSms {
                remote_relay_id, ..
            }
            | Self::CallAction {
                remote_relay_id, ..
            } => remote_relay_id,
        }
    }
}

/// Why a continuity session ended. Surfaced so the UI can distinguish "the
/// peer went away" from "you have not enabled anything".
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ContinuitySessionEnd {
    Closed,
    Cancelled,
    NotTrusted,
    Blocked,
    ProtocolViolation { detail: String },
    TransportFailed { detail: String },
}

/// Everything the app observes about continuity.
#[derive(Clone, Debug)]
pub enum ContinuityEvent {
    /// A trusted, authenticated peer has an open continuity session.
    SessionEstablished {
        remote_relay_id: String,
        /// Whether the transport chose a direct path. Presentation only.
        direct_path: bool,
        /// Whether this session runs over the local network rather than through
        /// the Anywhere transport. Presentation only, and derived from the path
        /// the transport actually used — never claimed by a peer.
        local_path: bool,
    },
    SessionEnded {
        remote_relay_id: String,
        reason: ContinuitySessionEnd,
    },
    /// The peer advertised what it can do.
    ManifestReceived {
        remote_relay_id: String,
        manifest: CapabilityManifest,
    },
    /// The peer asked us to stream these capabilities.
    PeerSubscribed {
        remote_relay_id: String,
        capabilities: Vec<super::protocol::ContinuityCapability>,
    },
    BatteryChanged {
        remote_relay_id: String,
        state: BatteryState,
    },
    /// Peer clipboard content that the mode says must be confirmed rather than
    /// applied silently.
    ClipboardOffered {
        remote_relay_id: String,
        update: ClipboardUpdate,
    },
    NotificationPosted {
        remote_relay_id: String,
        event: NotificationEvent,
    },
    NotificationRemoved {
        remote_relay_id: String,
        removal: NotificationRemoval,
    },
    ConversationsPage {
        remote_relay_id: String,
        page: SmsConversationsPage,
    },
    MessagesPage {
        remote_relay_id: String,
        page: SmsMessagesPage,
    },
    MessageReceived {
        remote_relay_id: String,
        message: SmsMessage,
    },
    SmsSendCompleted {
        remote_relay_id: String,
        request_id: String,
        outcome: SmsSendOutcome,
    },
    CallStateChanged {
        remote_relay_id: String,
        state: CallState,
    },
    CallActionCompleted {
        remote_relay_id: String,
        request_id: String,
        outcome: CallActionOutcome,
    },
    /// The peer refused something we asked for, or told us it could not comply.
    PeerError {
        remote_relay_id: String,
        error: ContinuityErrorPayload,
    },
}

pub type ContinuityEventSink = std::sync::Arc<dyn Fn(ContinuityEvent) + Send + Sync>;
