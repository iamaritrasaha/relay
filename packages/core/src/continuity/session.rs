//! One continuity session over one authenticated, encrypted stream.
//!
//! The stream is generic over [`AsyncRead`] + [`AsyncWrite`], so the same loop
//! runs over an Iroh + inner-TLS stream in production and over an in-process
//! duplex pipe in tests. Constructing a session *requires* an
//! [`AuthenticatedRelaySession`]; there is no entry point that accepts an
//! unauthenticated peer.

use std::collections::HashSet;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{mpsc, oneshot, RwLock};
use tokio_util::sync::CancellationToken;

use super::authz::{authorize_capability, authorize_session, ContinuityAuthorization};
use super::codec::{read_envelope, write_envelope, ContinuityCodecError};
use super::host::{
    ContinuityEvent, ContinuityEventSink, ContinuityHostRequest, ContinuitySessionEnd,
};
use super::permission::ContinuityPermissions;
use super::protocol::*;
use super::replay::{ActionAdmission, ReplayGuard};
use crate::relay::{AuthenticatedRelaySession, PathDescriptor, TrustDirectory};

/// How many recoverable protocol errors one peer may cause before the session
/// is torn down. Bounds the work a misbehaving peer can force.
const MAX_RECOVERABLE_ERRORS: u32 = 16;

pub type SharedTrust = Arc<dyn TrustDirectory + Send + Sync>;
pub type SharedPermissions = Arc<RwLock<ContinuityPermissions>>;

/// A handle the app uses to push locally originated payloads into a session.
#[derive(Clone)]
pub struct ContinuitySessionHandle {
    remote_relay_id: String,
    outbound: mpsc::Sender<ContinuityPayload>,
}

impl ContinuitySessionHandle {
    pub fn remote_relay_id(&self) -> &str {
        &self.remote_relay_id
    }

    /// Queues a payload. Authorization and subscription filtering happen inside
    /// the session loop, never at the call site, so a new caller cannot forget
    /// them.
    pub async fn publish(&self, payload: ContinuityPayload) -> bool {
        self.outbound.send(payload).await.is_ok()
    }

    pub fn try_publish(&self, payload: ContinuityPayload) -> bool {
        self.outbound.try_send(payload).is_ok()
    }
}

pub struct ContinuitySessionConfig {
    pub local_manifest: CapabilityManifest,
    pub trust: SharedTrust,
    pub permissions: SharedPermissions,
    pub events: ContinuityEventSink,
    pub host: mpsc::Sender<ContinuityHostRequest>,
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or_default()
}

fn is_direct(path: &PathDescriptor) -> bool {
    !matches!(path, PathDescriptor::IrohRelay { .. })
}

/// Creates the outbound channel and the handle the app publishes through.
pub fn session_channel(
    remote_relay_id: &str,
    capacity: usize,
) -> (ContinuitySessionHandle, mpsc::Receiver<ContinuityPayload>) {
    let (sender, receiver) = mpsc::channel(capacity);
    (
        ContinuitySessionHandle {
            remote_relay_id: remote_relay_id.to_owned(),
            outbound: sender,
        },
        receiver,
    )
}

struct SessionState {
    local_relay_id: String,
    remote_relay_id: String,
    peer_subscriptions: HashSet<ContinuityCapability>,
    replay: ReplayGuard,
    recoverable_errors: u32,
    /// Fingerprint of the clipboard content most recently received from, or
    /// sent to, this peer. Suppresses the A -> B -> A echo.
    last_clipboard_fingerprint: Option<String>,
}

/// Runs one continuity session to completion.
///
/// Returns the reason the session ended. Errors are reported through the return
/// value rather than by panicking, and no remote input can panic this loop.
pub async fn run_session<S>(
    stream: S,
    session: AuthenticatedRelaySession,
    config: ContinuitySessionConfig,
    mut outbound: mpsc::Receiver<ContinuityPayload>,
    cancel: CancellationToken,
) -> ContinuitySessionEnd
where
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    let remote_relay_id = session.remote_relay_id().as_hex();
    let local_relay_id = session.local_relay_id().as_hex();

    // Coarse gate first: an authenticated but untrusted peer never reaches a
    // capability dispatcher, even for `Session` traffic.
    match authorize_session(&session, &config.trust) {
        ContinuityAuthorization::Allowed => {}
        ContinuityAuthorization::DeniedBlocked => {
            (config.events)(ContinuityEvent::SessionEnded {
                remote_relay_id,
                reason: ContinuitySessionEnd::Blocked,
            });
            return ContinuitySessionEnd::Blocked;
        }
        _ => {
            (config.events)(ContinuityEvent::SessionEnded {
                remote_relay_id,
                reason: ContinuitySessionEnd::NotTrusted,
            });
            return ContinuitySessionEnd::NotTrusted;
        }
    }

    let (mut reader, mut writer) = tokio::io::split(stream);
    let mut state = SessionState {
        local_relay_id: local_relay_id.clone(),
        remote_relay_id: remote_relay_id.clone(),
        peer_subscriptions: HashSet::new(),
        replay: ReplayGuard::new(),
        recoverable_errors: 0,
        last_clipboard_fingerprint: None,
    };

    (config.events)(ContinuityEvent::SessionEstablished {
        remote_relay_id: remote_relay_id.clone(),
        direct_path: is_direct(session.path()),
    });

    // Advertise, then ask for what this device is allowed to consume.
    let granted = {
        let permissions = config.permissions.read().await;
        permissions.for_device(&remote_relay_id).granted_capabilities()
    };
    if let Err(error) = send(
        &mut writer,
        &state,
        ContinuityPayload::Manifest(config.local_manifest.clone()),
    )
    .await
    {
        return end_with(&config, &remote_relay_id, transport_end(error));
    }
    if let Err(error) = send(
        &mut writer,
        &state,
        ContinuityPayload::Subscribe {
            capabilities: granted,
        },
    )
    .await
    {
        return end_with(&config, &remote_relay_id, transport_end(error));
    }

    let reason = loop {
        tokio::select! {
            _ = cancel.cancelled() => break ContinuitySessionEnd::Cancelled,
            payload = outbound.recv() => {
                let Some(payload) = payload else {
                    break ContinuitySessionEnd::Closed;
                };
                match handle_outbound(&mut writer, &mut state, &session, &config, payload).await {
                    Ok(()) => {}
                    Err(error) => break transport_end(error),
                }
            }
            incoming = read_envelope(&mut reader) => {
                match incoming {
                    Ok(envelope) => {
                        match handle_inbound(&mut writer, &mut state, &session, &config, envelope).await {
                            Ok(Some(end)) => break end,
                            Ok(None) => {}
                            Err(error) => break transport_end(error),
                        }
                    }
                    Err(error) if error.is_recoverable() => {
                        state.recoverable_errors += 1;
                        let detail = error.to_string();
                        if state.recoverable_errors > MAX_RECOVERABLE_ERRORS {
                            break ContinuitySessionEnd::ProtocolViolation { detail };
                        }
                        // A frame we could not size or parse leaves the stream
                        // position untrustworthy, so oversized frames are fatal
                        // even though the category is "recoverable".
                        if matches!(error, ContinuityCodecError::FrameTooLarge { .. }) {
                            break ContinuitySessionEnd::ProtocolViolation { detail };
                        }
                        let reply = error_payload(ContinuityErrorCode::Malformed, &detail);
                        if let Err(error) = send(&mut writer, &state, reply).await {
                            break transport_end(error);
                        }
                    }
                    Err(ContinuityCodecError::Closed) => break ContinuitySessionEnd::Closed,
                    Err(error) => break transport_end(error),
                }
            }
        }
    };

    (config.events)(ContinuityEvent::SessionEnded {
        remote_relay_id,
        reason: reason.clone(),
    });
    reason
}

fn end_with(
    config: &ContinuitySessionConfig,
    remote_relay_id: &str,
    reason: ContinuitySessionEnd,
) -> ContinuitySessionEnd {
    (config.events)(ContinuityEvent::SessionEnded {
        remote_relay_id: remote_relay_id.to_owned(),
        reason: reason.clone(),
    });
    reason
}

fn transport_end(error: ContinuityCodecError) -> ContinuitySessionEnd {
    match error {
        ContinuityCodecError::Closed => ContinuitySessionEnd::Closed,
        other => ContinuitySessionEnd::TransportFailed {
            detail: other.to_string(),
        },
    }
}

fn error_payload(code: ContinuityErrorCode, detail: &str) -> ContinuityPayload {
    let mut detail = detail.to_owned();
    detail.truncate(MAX_REASON_BYTES);
    ContinuityPayload::Error(ContinuityErrorPayload { code, detail })
}

fn envelope_for(state: &SessionState, payload: ContinuityPayload) -> ContinuityEnvelopeV1 {
    ContinuityEnvelopeV1 {
        protocol_version: CONTINUITY_PROTOCOL_VERSION,
        message_id: uuid::Uuid::new_v4().to_string(),
        correlation_id: None,
        sender_relay_id: state.local_relay_id.clone(),
        capability: payload.capability(),
        timestamp_ms: now_ms(),
        payload,
    }
}

async fn send<W>(
    writer: &mut W,
    state: &SessionState,
    payload: ContinuityPayload,
) -> Result<(), ContinuityCodecError>
where
    W: AsyncWrite + Unpin,
{
    write_envelope(writer, &envelope_for(state, payload)).await
}

/// Applies authorization and subscription filtering to a locally originated
/// payload before it can reach the wire.
async fn handle_outbound<W>(
    writer: &mut W,
    state: &mut SessionState,
    session: &AuthenticatedRelaySession,
    config: &ContinuitySessionConfig,
    payload: ContinuityPayload,
) -> Result<(), ContinuityCodecError>
where
    W: AsyncWrite + Unpin,
{
    let capability = payload.capability();
    if capability != ContinuityCapability::Session {
        let permissions = config.permissions.read().await;
        if !authorize_capability(session, &config.trust, &permissions, capability).is_allowed() {
            return Ok(());
        }
        drop(permissions);
        // Streamed state is only pushed to a peer that asked for it. Replies and
        // requests are not subscription-gated.
        if is_streamed(&payload) && !state.peer_subscriptions.contains(&capability) {
            return Ok(());
        }
    }

    if let ContinuityPayload::ClipboardUpdate(update) = &payload {
        // Do not echo back content this peer just gave us.
        if state.last_clipboard_fingerprint.as_deref() == Some(update.content_fingerprint.as_str())
        {
            return Ok(());
        }
        if update.origin_relay_id == state.remote_relay_id {
            return Ok(());
        }
        state.last_clipboard_fingerprint = Some(update.content_fingerprint.clone());
    }

    send(writer, state, payload).await
}

/// Whether a payload is unsolicited state that requires a subscription.
fn is_streamed(payload: &ContinuityPayload) -> bool {
    matches!(
        payload,
        ContinuityPayload::Battery(_)
            | ContinuityPayload::ClipboardUpdate(_)
            | ContinuityPayload::Notification(_)
            | ContinuityPayload::NotificationRemoved(_)
            | ContinuityPayload::SmsMessage(_)
            | ContinuityPayload::CallState(_)
    )
}

/// Returns `Ok(Some(end))` when the session must terminate.
async fn handle_inbound<W>(
    writer: &mut W,
    state: &mut SessionState,
    session: &AuthenticatedRelaySession,
    config: &ContinuitySessionConfig,
    envelope: ContinuityEnvelopeV1,
) -> Result<Option<ContinuitySessionEnd>, ContinuityCodecError>
where
    W: AsyncWrite + Unpin,
{
    // Defence in depth. The proven identity already came from the handshake; a
    // disagreeing echo means the peer is not speaking this protocol honestly.
    if envelope.check_sender(&state.remote_relay_id).is_err() {
        return Ok(Some(ContinuitySessionEnd::ProtocolViolation {
            detail: "envelope sender did not match the authenticated peer".to_owned(),
        }));
    }
    if !state.replay.accept_envelope(&envelope.message_id) {
        return Ok(None);
    }

    let capability = envelope.capability;
    let authorization = {
        let permissions = config.permissions.read().await;
        authorize_capability(session, &config.trust, &permissions, capability)
    };
    match authorization {
        ContinuityAuthorization::Allowed => {}
        ContinuityAuthorization::DeniedBlocked => {
            return Ok(Some(ContinuitySessionEnd::Blocked));
        }
        ContinuityAuthorization::DeniedNotTrusted => {
            return Ok(Some(ContinuitySessionEnd::NotTrusted));
        }
        ContinuityAuthorization::DeniedUnknownCapability => {
            send(
                writer,
                state,
                error_payload(ContinuityErrorCode::Unsupported, "unknown capability"),
            )
            .await?;
            return Ok(None);
        }
        ContinuityAuthorization::DeniedNotEnabled { capability } => {
            send(
                writer,
                state,
                error_payload(
                    ContinuityErrorCode::NotAuthorized,
                    &format!("{} is not enabled for this device", capability.as_str()),
                ),
            )
            .await?;
            return Ok(None);
        }
    }

    // Privileged actions get freshness and idempotency on top of authorization.
    if envelope.payload.is_action_request() {
        let issued = envelope.payload.issued_at_ms().unwrap_or_default();
        let request_id = envelope.payload.action_request_id().unwrap_or_default().to_owned();
        match state.replay.admit_action(&request_id, issued, now_ms()) {
            ActionAdmission::Fresh => {
                state.replay.record_action(&request_id);
            }
            ActionAdmission::Duplicate => {
                let reply = duplicate_reply(&envelope.payload, &request_id);
                if let Some(reply) = reply {
                    send(writer, state, reply).await?;
                }
                return Ok(None);
            }
            ActionAdmission::Stale => {
                send(
                    writer,
                    state,
                    error_payload(
                        ContinuityErrorCode::Stale,
                        "action request was outside the freshness window",
                    ),
                )
                .await?;
                return Ok(None);
            }
        }
    }

    dispatch(writer, state, config, envelope).await
}

fn duplicate_reply(payload: &ContinuityPayload, request_id: &str) -> Option<ContinuityPayload> {
    match payload {
        ContinuityPayload::SmsSendRequest(_) => {
            Some(ContinuityPayload::SmsSendResult(SmsSendResult {
                request_id: request_id.to_owned(),
                outcome: SmsSendOutcome::Duplicate,
            }))
        }
        ContinuityPayload::CallActionRequest(_) => {
            Some(ContinuityPayload::CallActionResult(CallActionResult {
                request_id: request_id.to_owned(),
                outcome: CallActionOutcome::Duplicate,
            }))
        }
        _ => None,
    }
}

async fn dispatch<W>(
    writer: &mut W,
    state: &mut SessionState,
    config: &ContinuitySessionConfig,
    envelope: ContinuityEnvelopeV1,
) -> Result<Option<ContinuitySessionEnd>, ContinuityCodecError>
where
    W: AsyncWrite + Unpin,
{
    let remote = state.remote_relay_id.clone();
    let events = &config.events;
    match envelope.payload {
        ContinuityPayload::Heartbeat => {}
        ContinuityPayload::ManifestRequest => {
            send(
                writer,
                state,
                ContinuityPayload::Manifest(config.local_manifest.clone()),
            )
            .await?;
        }
        ContinuityPayload::Manifest(manifest) => {
            events(ContinuityEvent::ManifestReceived {
                remote_relay_id: remote,
                manifest,
            });
        }
        ContinuityPayload::Subscribe { capabilities } => {
            for capability in &capabilities {
                if capability.is_grantable() {
                    state.peer_subscriptions.insert(*capability);
                }
            }
            events(ContinuityEvent::PeerSubscribed {
                remote_relay_id: remote,
                capabilities,
            });
        }
        ContinuityPayload::Unsubscribe { capabilities } => {
            for capability in &capabilities {
                state.peer_subscriptions.remove(capability);
            }
        }
        ContinuityPayload::DeviceState(_) => {}
        ContinuityPayload::Battery(battery) => {
            events(ContinuityEvent::BatteryChanged {
                remote_relay_id: remote,
                state: battery,
            });
        }
        ContinuityPayload::ClipboardUpdate(update) => {
            // Remember the fingerprint first: whether or not the user applies it,
            // this content must not travel back to its sender.
            state.last_clipboard_fingerprint = Some(update.content_fingerprint.clone());
            let mode = {
                let permissions = config.permissions.read().await;
                permissions.for_device(&remote).clipboard_mode
            };
            if mode.allows_automatic_apply() && !update.explicit {
                request_host(config, |reply| ContinuityHostRequest::ApplyClipboard {
                    remote_relay_id: remote.clone(),
                    update: update.clone(),
                    reply,
                })
                .await;
            } else if mode.is_enabled() {
                // Explicit shares and "ask" mode both surface for confirmation.
                events(ContinuityEvent::ClipboardOffered {
                    remote_relay_id: remote,
                    update,
                });
            }
        }
        ContinuityPayload::Notification(event) => {
            events(ContinuityEvent::NotificationPosted {
                remote_relay_id: remote,
                event,
            });
        }
        ContinuityPayload::NotificationRemoved(removal) => {
            events(ContinuityEvent::NotificationRemoved {
                remote_relay_id: remote,
                removal,
            });
        }
        ContinuityPayload::NotificationDismiss(request) => {
            request_host(config, |reply| ContinuityHostRequest::DismissNotification {
                remote_relay_id: remote.clone(),
                key: request.key.clone(),
                reply,
            })
            .await;
        }
        ContinuityPayload::SmsConversationsRequest(request) => {
            let outcome = ask_host(config, |reply| ContinuityHostRequest::ListConversations {
                remote_relay_id: remote.clone(),
                request,
                reply,
            })
            .await;
            let payload = match outcome {
                Some(Ok(page)) => ContinuityPayload::SmsConversationsPage(page),
                Some(Err(error)) => ContinuityPayload::Error(error),
                None => error_payload(
                    ContinuityErrorCode::ProviderFailure,
                    "the messages provider did not answer",
                ),
            };
            send(writer, state, payload).await?;
        }
        ContinuityPayload::SmsMessagesRequest(request) => {
            let outcome = ask_host(config, |reply| ContinuityHostRequest::ListMessages {
                remote_relay_id: remote.clone(),
                request,
                reply,
            })
            .await;
            let payload = match outcome {
                Some(Ok(page)) => ContinuityPayload::SmsMessagesPage(page),
                Some(Err(error)) => ContinuityPayload::Error(error),
                None => error_payload(
                    ContinuityErrorCode::ProviderFailure,
                    "the messages provider did not answer",
                ),
            };
            send(writer, state, payload).await?;
        }
        ContinuityPayload::SmsConversationsPage(page) => {
            events(ContinuityEvent::ConversationsPage {
                remote_relay_id: remote,
                page,
            });
        }
        ContinuityPayload::SmsMessagesPage(page) => {
            events(ContinuityEvent::MessagesPage {
                remote_relay_id: remote,
                page,
            });
        }
        ContinuityPayload::SmsMessage(message) => {
            events(ContinuityEvent::MessageReceived {
                remote_relay_id: remote,
                message,
            });
        }
        ContinuityPayload::SmsSendRequest(request) => {
            let request_id = request.request_id.clone();
            let outcome = ask_host(config, |reply| ContinuityHostRequest::SendSms {
                remote_relay_id: remote.clone(),
                request,
                reply,
            })
            .await
            .unwrap_or(SmsSendOutcome::Failed {
                reason: "the messages provider did not answer".to_owned(),
            });
            send(
                writer,
                state,
                ContinuityPayload::SmsSendResult(SmsSendResult {
                    request_id,
                    outcome,
                }),
            )
            .await?;
        }
        ContinuityPayload::SmsSendResult(result) => {
            events(ContinuityEvent::SmsSendCompleted {
                remote_relay_id: remote,
                request_id: result.request_id,
                outcome: result.outcome,
            });
        }
        ContinuityPayload::CallState(call) => {
            events(ContinuityEvent::CallStateChanged {
                remote_relay_id: remote,
                state: call,
            });
        }
        ContinuityPayload::CallActionRequest(request) => {
            let request_id = request.request_id.clone();
            let outcome = ask_host(config, |reply| ContinuityHostRequest::CallAction {
                remote_relay_id: remote.clone(),
                request,
                reply,
            })
            .await
            .unwrap_or(CallActionOutcome::Failed {
                reason: "the telephony provider did not answer".to_owned(),
            });
            send(
                writer,
                state,
                ContinuityPayload::CallActionResult(CallActionResult {
                    request_id,
                    outcome,
                }),
            )
            .await?;
        }
        ContinuityPayload::CallActionResult(result) => {
            events(ContinuityEvent::CallActionCompleted {
                remote_relay_id: remote,
                request_id: result.request_id,
                outcome: result.outcome,
            });
        }
        ContinuityPayload::Error(error) => {
            events(ContinuityEvent::PeerError {
                remote_relay_id: remote,
                error,
            });
        }
    }
    Ok(None)
}

/// Fire-and-forget host work.
async fn request_host<F>(config: &ContinuitySessionConfig, build: F)
where
    F: FnOnce(oneshot::Sender<()>) -> ContinuityHostRequest,
{
    let (reply, wait) = oneshot::channel();
    if config.host.send(build(reply)).await.is_ok() {
        let _ = wait.await;
    }
}

/// Host work whose answer goes back on the wire.
async fn ask_host<T, F>(config: &ContinuitySessionConfig, build: F) -> Option<T>
where
    F: FnOnce(oneshot::Sender<T>) -> ContinuityHostRequest,
{
    let (reply, wait) = oneshot::channel();
    if config.host.send(build(reply)).await.is_err() {
        return None;
    }
    wait.await.ok()
}
