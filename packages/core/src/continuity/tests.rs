//! Continuity protocol, authorization and session tests.
//!
//! The session tests run a real [`run_session`] loop on both ends of an
//! in-process duplex pipe, so protocol behaviour is exercised without Iroh, TLS
//! or a physical phone.

use std::sync::{Arc, Mutex};

use tokio::sync::{mpsc, RwLock};
use tokio_util::sync::CancellationToken;

use super::*;
use crate::crypto::relay_identity::RelayIdentity;
use crate::relay::{
    AuthenticatedRelaySession, ChannelBinding, DeviceBinding, LegacyLanInboundSession,
    LocalSendPeer, MemoryTrustDirectory, PathDescriptor, RelayId, SessionRole,
};

// ---------------------------------------------------------------- fixtures

fn relay_id() -> RelayId {
    RelayId::from_local_identity(&RelayIdentity::generate()).unwrap()
}

fn direct_path() -> PathDescriptor {
    PathDescriptor::InternetDirect {
        host: String::new(),
        port: None,
    }
}

fn binding() -> ChannelBinding {
    ChannelBinding::from_uppercase_hex(&"AB".repeat(32)).unwrap()
}

/// Builds a proven session directly. Production code can only obtain one from
/// `RelayAuthCoordinator`; this shortcut exists so tests do not need a TLS
/// handshake to exercise policy.
fn proven_session(local: &RelayId, remote: &RelayId) -> AuthenticatedRelaySession {
    AuthenticatedRelaySession::from_coordinator(
        remote.clone(),
        local.clone(),
        SessionRole::Initiator,
        true,
        binding(),
        direct_path(),
    )
}

fn trusting(remote: &RelayId) -> Arc<MemoryTrustDirectory> {
    let mut directory = MemoryTrustDirectory::new();
    directory.insert(DeviceBinding::new(
        "binding-1",
        remote.clone(),
        "Pixel",
        true,
        false,
    ));
    Arc::new(directory)
}

fn blocking(remote: &RelayId) -> Arc<MemoryTrustDirectory> {
    let mut directory = MemoryTrustDirectory::new();
    directory.insert(DeviceBinding::new(
        "binding-1",
        remote.clone(),
        "Pixel",
        false,
        true,
    ));
    Arc::new(directory)
}

fn all_enabled(remote_hex: &str) -> ContinuityPermissions {
    let mut permissions = ContinuityPermissions::new();
    for capability in ContinuityCapability::GRANTABLE {
        permissions.set_grant(remote_hex, capability, CapabilityGrant::Granted);
    }
    permissions.set_clipboard_mode(remote_hex, ClipboardMode::Automatic);
    permissions
}

fn manifest(label: &str, platform: DevicePlatform) -> CapabilityManifest {
    CapabilityManifest {
        device_label: label.to_owned(),
        platform,
        entries: ContinuityCapability::GRANTABLE
            .into_iter()
            .map(|capability| capability_entry(capability, CapabilityState::Available))
            .collect(),
    }
}

fn envelope(sender: &str, payload: ContinuityPayload) -> ContinuityEnvelopeV1 {
    ContinuityEnvelopeV1 {
        protocol_version: CONTINUITY_PROTOCOL_VERSION,
        message_id: uuid::Uuid::new_v4().to_string(),
        correlation_id: None,
        sender_relay_id: sender.to_owned(),
        capability: payload.capability(),
        timestamp_ms: now_ms(),
        payload,
    }
}

// ---------------------------------------------------------------- protocol

#[test]
fn envelope_round_trips_through_the_codec() {
    let original = envelope(
        &"A".repeat(64),
        ContinuityPayload::Battery(BatteryState {
            percentage: Some(82),
            charging: ChargingState::Charging,
        }),
    );
    let frame = encode_frame(&original).unwrap();
    let decoded = decode_body(&frame[codec::LENGTH_PREFIX_BYTES..]).unwrap();
    assert_eq!(decoded, original);
}

#[test]
fn unknown_capability_strings_decode_to_unknown_and_are_never_authorized() {
    let capability: ContinuityCapability = serde_json::from_str("\"teleport\"").unwrap();
    assert_eq!(capability, ContinuityCapability::Unknown);
    assert!(!capability.is_grantable());

    let local = relay_id();
    let remote = relay_id();
    let session = proven_session(&local, &remote);
    let permissions = all_enabled(&remote.as_hex());
    assert_eq!(
        authorize_capability(
            &session,
            &trusting(&remote),
            &permissions,
            ContinuityCapability::Unknown
        ),
        ContinuityAuthorization::DeniedUnknownCapability
    );
}

#[test]
fn a_payload_cannot_be_smuggled_under_another_capability_label() {
    let mut smuggled = envelope(
        &"A".repeat(64),
        ContinuityPayload::SmsMessage(SmsMessage {
            conversation_id: "c1".to_owned(),
            message_id: "m1".to_owned(),
            direction: SmsDirection::Incoming,
            address: Some("+10000000000".to_owned()),
            body: "secret".to_owned(),
            sent_at_ms: 0,
            read: false,
        }),
    );
    smuggled.capability = ContinuityCapability::Battery;
    assert_eq!(
        smuggled.validate(),
        Err(ContinuityProtocolError::CapabilityMismatch)
    );
    assert!(encode_frame(&smuggled).is_err());
}

#[test]
fn oversized_fields_are_rejected() {
    let too_long = "x".repeat(MAX_CLIPBOARD_TEXT_BYTES + 1);
    let clipboard = envelope(
        &"A".repeat(64),
        ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
            text: too_long,
            content_fingerprint: clipboard_fingerprint("x"),
            origin_relay_id: "A".repeat(64),
            explicit: false,
        }),
    );
    assert!(matches!(
        clipboard.validate(),
        Err(ContinuityProtocolError::FieldTooLong { .. })
    ));

    let body = "y".repeat(MAX_SMS_BODY_BYTES + 1);
    let sms = envelope(
        &"A".repeat(64),
        ContinuityPayload::SmsSendRequest(SmsSendRequest {
            request_id: "r1".to_owned(),
            conversation_id: None,
            recipients: vec!["+10000000000".to_owned()],
            body,
            issued_at_ms: 0,
        }),
    );
    assert!(matches!(
        sms.validate(),
        Err(ContinuityProtocolError::FieldTooLong { .. })
    ));
}

#[test]
fn page_limits_are_bounded_in_both_directions() {
    let request = envelope(
        &"A".repeat(64),
        ContinuityPayload::SmsConversationsRequest(SmsConversationsRequest {
            limit: MAX_PAGE_SIZE + 1,
            before_ms: None,
        }),
    );
    assert!(matches!(
        request.validate(),
        Err(ContinuityProtocolError::OutOfRange { .. })
    ));

    let zero = envelope(
        &"A".repeat(64),
        ContinuityPayload::SmsConversationsRequest(SmsConversationsRequest {
            limit: 0,
            before_ms: None,
        }),
    );
    assert!(matches!(
        zero.validate(),
        Err(ContinuityProtocolError::OutOfRange { .. })
    ));
}

#[test]
fn non_dial_call_actions_may_not_carry_a_target_address() {
    let answer_with_address = envelope(
        &"A".repeat(64),
        ContinuityPayload::CallActionRequest(CallActionRequest {
            request_id: "r1".to_owned(),
            action: CallAction::Answer,
            address: Some("+10000000000".to_owned()),
            issued_at_ms: 0,
        }),
    );
    assert!(matches!(
        answer_with_address.validate(),
        Err(ContinuityProtocolError::OutOfRange { .. })
    ));

    let dial_without_address = envelope(
        &"A".repeat(64),
        ContinuityPayload::CallActionRequest(CallActionRequest {
            request_id: "r1".to_owned(),
            action: CallAction::Dial,
            address: None,
            issued_at_ms: 0,
        }),
    );
    assert!(matches!(
        dial_without_address.validate(),
        Err(ContinuityProtocolError::FieldEmpty { .. })
    ));
}

#[test]
fn a_wrong_protocol_version_is_rejected() {
    let mut wrong = envelope(&"A".repeat(64), ContinuityPayload::Heartbeat);
    wrong.protocol_version = CONTINUITY_PROTOCOL_VERSION + 1;
    assert_eq!(
        wrong.validate(),
        Err(ContinuityProtocolError::UnsupportedVersion)
    );
}

#[test]
fn malformed_input_is_an_error_rather_than_a_panic() {
    for body in [
        &b"{"[..],
        &b"null"[..],
        &b"[]"[..],
        &b"{\"protocol_version\":1}"[..],
        &b"\xff\xfe\xfd"[..],
        &b"{\"payload\":{\"type\":\"from_the_future\"}}"[..],
    ] {
        assert!(decode_body(body).is_err());
    }
}

#[tokio::test]
async fn an_oversized_length_prefix_is_refused_before_allocation() {
    let (mut client, mut server) = tokio::io::duplex(64);
    let announced = (MAX_ENVELOPE_BYTES + 1) as u32;
    tokio::io::AsyncWriteExt::write_all(&mut client, &announced.to_be_bytes())
        .await
        .unwrap();
    let error = read_envelope(&mut server).await.unwrap_err();
    assert!(matches!(
        error,
        ContinuityCodecError::FrameTooLarge { .. }
    ));
}

// ----------------------------------------------------------- authorization

#[test]
fn pairing_alone_does_not_authorize_any_capability() {
    let local = relay_id();
    let remote = relay_id();
    let session = proven_session(&local, &remote);
    // Trusted device, but the user has enabled nothing.
    let permissions = ContinuityPermissions::new();
    let trust = trusting(&remote);

    assert!(authorize_session(&session, &trust).is_allowed());
    for capability in ContinuityCapability::GRANTABLE {
        assert_eq!(
            authorize_capability(&session, &trust, &permissions, capability),
            ContinuityAuthorization::DeniedNotEnabled { capability },
            "{capability:?} must be denied until the user enables it"
        );
    }
}

#[test]
fn an_authenticated_but_untrusted_device_gets_no_continuity_session() {
    let local = relay_id();
    let remote = relay_id();
    let session = proven_session(&local, &remote);
    let empty = Arc::new(MemoryTrustDirectory::new());

    assert_eq!(
        authorize_session(&session, &empty),
        ContinuityAuthorization::DeniedNotTrusted
    );
    // Even a fully granted permission store cannot promote it.
    assert_eq!(
        authorize_capability(
            &session,
            &empty,
            &all_enabled(&remote.as_hex()),
            ContinuityCapability::Clipboard
        ),
        ContinuityAuthorization::DeniedNotTrusted
    );
}

#[test]
fn a_blocked_device_is_denied_even_with_grants() {
    let local = relay_id();
    let remote = relay_id();
    let session = proven_session(&local, &remote);
    assert_eq!(
        authorize_capability(
            &session,
            &blocking(&remote),
            &all_enabled(&remote.as_hex()),
            ContinuityCapability::Battery
        ),
        ContinuityAuthorization::DeniedBlocked
    );
}

#[test]
fn grants_do_not_leak_between_devices() {
    let local = relay_id();
    let granted_device = relay_id();
    let other_device = relay_id();
    let permissions = all_enabled(&granted_device.as_hex());

    let mut trust = MemoryTrustDirectory::new();
    trust.insert(DeviceBinding::new("a", granted_device.clone(), "A", true, false));
    trust.insert(DeviceBinding::new("b", other_device.clone(), "B", true, false));
    let trust = Arc::new(trust);

    assert!(authorize_capability(
        &proven_session(&local, &granted_device),
        &trust,
        &permissions,
        ContinuityCapability::Messages
    )
    .is_allowed());
    assert_eq!(
        authorize_capability(
            &proven_session(&local, &other_device),
            &trust,
            &permissions,
            ContinuityCapability::Messages
        ),
        ContinuityAuthorization::DeniedNotEnabled {
            capability: ContinuityCapability::Messages
        }
    );
}

#[test]
fn clipboard_mode_off_disables_the_capability_even_when_granted() {
    let local = relay_id();
    let remote = relay_id();
    let hex = remote.as_hex();
    let mut permissions = ContinuityPermissions::new();
    permissions.set_grant(&hex, ContinuityCapability::Clipboard, CapabilityGrant::Granted);
    permissions.set_clipboard_mode(&hex, ClipboardMode::Off);

    assert_eq!(
        authorize_capability(
            &proven_session(&local, &remote),
            &trusting(&remote),
            &permissions,
            ContinuityCapability::Clipboard
        ),
        ContinuityAuthorization::DeniedNotEnabled {
            capability: ContinuityCapability::Clipboard
        }
    );
}

#[test]
fn a_fresh_install_runs_no_continuity() {
    assert!(!ContinuityPermissions::new().any_capability_enabled());
    let mut permissions = ContinuityPermissions::new();
    permissions.set_grant(&"A".repeat(64), ContinuityCapability::Battery, CapabilityGrant::Granted);
    assert!(permissions.any_capability_enabled());
}

/// LocalSend peers and legacy LAN inbound sessions are structurally excluded:
/// neither type exposes a proven [`RelayId`], and continuity's only entry point
/// demands an [`AuthenticatedRelaySession`]. This test pins that shape so a
/// future refactor cannot quietly add a conversion.
#[test]
fn localsend_and_legacy_lan_sessions_cannot_reach_continuity() {
    let localsend = LocalSendPeer::from_claimed_device_fingerprint("DEADBEEF");
    assert!(!localsend.claimed_device_fingerprint().is_empty());

    let legacy = LegacyLanInboundSession::from_production_lan(
        "DEADBEEF",
        "Totally A Pixel",
        Some(&"AB".repeat(32)),
        direct_path(),
    );
    // The legacy type carries no proven identity at all.
    assert!(legacy.claimed_relay_id().is_none());

    // And a claimed id is a different type from a proven one: there is no
    // `RelayId::from(ClaimedRelayId)` for a caller to reach for.
    fn _only_accepts_proven(_session: &AuthenticatedRelaySession) {}
}

// ------------------------------------------------------------------ replay

#[test]
fn duplicate_envelope_ids_are_dropped() {
    let mut guard = ReplayGuard::new();
    assert!(guard.accept_envelope("m1"));
    assert!(!guard.accept_envelope("m1"));
    assert!(guard.accept_envelope("m2"));
}

#[test]
fn actions_outside_the_freshness_window_are_stale_in_both_directions() {
    let mut guard = ReplayGuard::new();
    let now = 1_000_000_u64;
    assert_eq!(guard.admit_action("r1", now, now), ActionAdmission::Fresh);
    assert_eq!(
        guard.admit_action("r2", now - MAX_ACTION_SKEW_MS - 1, now),
        ActionAdmission::Stale
    );
    assert_eq!(
        guard.admit_action("r3", now + MAX_ACTION_SKEW_MS + 1, now),
        ActionAdmission::Stale
    );
}

#[test]
fn a_replayed_action_is_reported_as_a_duplicate_not_executed_again() {
    let mut guard = ReplayGuard::new();
    let now = 1_000_000_u64;
    assert_eq!(guard.admit_action("send-1", now, now), ActionAdmission::Fresh);
    guard.record_action("send-1");
    assert_eq!(
        guard.admit_action("send-1", now, now),
        ActionAdmission::Duplicate
    );
}

#[test]
fn the_replay_guard_stays_bounded() {
    let mut guard = ReplayGuard::new();
    for index in 0..5_000 {
        guard.accept_envelope(&format!("m{index}"));
    }
    assert!(guard.tracked_envelopes() <= 512);
}

// ------------------------------------------------------- session harness

struct Peer {
    handle: ContinuitySessionHandle,
    events: Arc<Mutex<Vec<ContinuityEvent>>>,
    host: mpsc::Receiver<ContinuityHostRequest>,
    task: tokio::task::JoinHandle<ContinuitySessionEnd>,
}

fn spawn_peer<S>(
    stream: S,
    session: AuthenticatedRelaySession,
    label: &str,
    platform: DevicePlatform,
    trust: SharedTrust,
    permissions: ContinuityPermissions,
    cancel: CancellationToken,
) -> Peer
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let events: Arc<Mutex<Vec<ContinuityEvent>>> = Arc::new(Mutex::new(Vec::new()));
    let sink: ContinuityEventSink = {
        let events = events.clone();
        Arc::new(move |event| events.lock().unwrap().push(event))
    };
    let (host_tx, host_rx) = mpsc::channel(16);
    let (handle, outbound) = session_channel(&session.remote_relay_id().as_hex(), 32);
    let config = ContinuitySessionConfig {
        local_manifest: manifest(label, platform),
        trust,
        permissions: Arc::new(RwLock::new(permissions)),
        events: sink,
        host: host_tx,
    };
    let task = tokio::spawn(run_session(stream, session, config, outbound, cancel));
    Peer {
        handle,
        events,
        host: host_rx,
        task,
    }
}

/// Waits for an event matching `predicate`, or fails after a bounded number of
/// polls so a broken session cannot hang the suite.
async fn wait_for<T>(
    events: &Arc<Mutex<Vec<ContinuityEvent>>>,
    mut predicate: impl FnMut(&ContinuityEvent) -> Option<T>,
) -> T {
    for _ in 0..400 {
        if let Some(found) = events
            .lock()
            .unwrap()
            .iter()
            .find_map(&mut predicate)
        {
            return found;
        }
        tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    }
    panic!("expected continuity event never arrived");
}

/// Builds two peers that have mutually authenticated each other and trust each
/// other, connected by an in-process duplex pipe.
fn connected_pair(
    android_permissions: ContinuityPermissions,
    linux_permissions: ContinuityPermissions,
    android_id: &RelayId,
    linux_id: &RelayId,
    cancel: &CancellationToken,
) -> (Peer, Peer) {
    let (android_stream, linux_stream) = tokio::io::duplex(64 * 1024);
    let android = spawn_peer(
        android_stream,
        proven_session(android_id, linux_id),
        "Pixel",
        DevicePlatform::Android,
        trusting(linux_id),
        android_permissions,
        cancel.clone(),
    );
    let linux = spawn_peer(
        linux_stream,
        proven_session(linux_id, android_id),
        "Workstation",
        DevicePlatform::Linux,
        trusting(android_id),
        linux_permissions,
        cancel.clone(),
    );
    (android, linux)
}

// -------------------------------------------------------- session tests

#[tokio::test]
async fn peers_negotiate_capabilities_on_connect() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );

    let manifest = wait_for(&linux.events, |event| match event {
        ContinuityEvent::ManifestReceived { manifest, .. } => Some(manifest.clone()),
        _ => None,
    })
    .await;
    assert_eq!(manifest.device_label, "Pixel");
    assert_eq!(manifest.platform, DevicePlatform::Android);
    assert!(manifest
        .state_of(ContinuityCapability::Battery)
        .unwrap()
        .is_available());

    let subscribed = wait_for(&android.events, |event| match event {
        ContinuityEvent::PeerSubscribed { capabilities, .. } => Some(capabilities.clone()),
        _ => None,
    })
    .await;
    assert!(subscribed.contains(&ContinuityCapability::Battery));

    cancel.cancel();
    let _ = android.task.await;
    let _ = linux.task.await;
}

#[tokio::test]
async fn battery_state_flows_from_android_to_linux() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );
    // Wait until Linux has subscribed, otherwise the push is correctly dropped.
    wait_for(&android.events, |event| {
        matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
    })
    .await;

    android
        .handle
        .publish(ContinuityPayload::Battery(BatteryState {
            percentage: Some(82),
            charging: ChargingState::Charging,
        }))
        .await;

    let state = wait_for(&linux.events, |event| match event {
        ContinuityEvent::BatteryChanged { state, .. } => Some(*state),
        _ => None,
    })
    .await;
    assert_eq!(state.percentage, Some(82));
    assert_eq!(state.charging, ChargingState::Charging);

    cancel.cancel();
    let _ = android.task.await;
    let _ = linux.task.await;
}

#[tokio::test]
async fn a_disabled_capability_is_refused_in_both_directions() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    // Android grants nothing at all.
    let (android, linux) = connected_pair(
        ContinuityPermissions::new(),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );

    // Android tries to push battery anyway: the session drops it outbound.
    android
        .handle
        .publish(ContinuityPayload::Battery(BatteryState {
            percentage: Some(50),
            charging: ChargingState::Discharging,
        }))
        .await;
    // Linux asks Android for conversations: Android refuses inbound.
    linux
        .handle
        .publish(ContinuityPayload::SmsConversationsRequest(
            SmsConversationsRequest {
                limit: 20,
                before_ms: None,
            },
        ))
        .await;

    let error = wait_for(&linux.events, |event| match event {
        ContinuityEvent::PeerError { error, .. } => Some(error.clone()),
        _ => None,
    })
    .await;
    assert_eq!(error.code, ContinuityErrorCode::NotAuthorized);

    assert!(
        !linux
            .events
            .lock()
            .unwrap()
            .iter()
            .any(|event| matches!(event, ContinuityEvent::BatteryChanged { .. })),
        "a device that shares nothing must not leak battery state"
    );

    cancel.cancel();
    let _ = android.task.await;
    let _ = linux.task.await;
}

#[tokio::test]
async fn clipboard_content_is_applied_once_and_never_echoed_back() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (android, mut linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );
    wait_for(&android.events, |event| {
        matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
    })
    .await;

    let text = "one time password 123456";
    let update = ClipboardUpdate {
        text: text.to_owned(),
        content_fingerprint: clipboard_fingerprint(text),
        origin_relay_id: android_id.as_hex(),
        explicit: false,
    };
    android
        .handle
        .publish(ContinuityPayload::ClipboardUpdate(update.clone()))
        .await;

    let applied = linux.host.recv().await.expect("clipboard apply request");
    match applied {
        ContinuityHostRequest::ApplyClipboard {
            update: received,
            reply,
            ..
        } => {
            assert_eq!(received.text, text);
            let _ = reply.send(());
        }
        other => panic!("unexpected host request: {other:?}"),
    }

    // The Linux clipboard now holds the same text, and its watcher publishes it.
    // That must terminate rather than bouncing back to Android.
    linux
        .handle
        .publish(ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
            text: text.to_owned(),
            content_fingerprint: clipboard_fingerprint(text),
            origin_relay_id: linux_id.as_hex(),
            explicit: false,
        }))
        .await;

    tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    assert!(
        android.events.lock().unwrap().iter().all(|event| !matches!(
            event,
            ContinuityEvent::ClipboardOffered { .. }
        )),
        "clipboard content must not echo back to the device it came from"
    );

    cancel.cancel();
    let _ = android.task.await;
    let _ = linux.task.await;
}

#[tokio::test]
async fn ask_mode_offers_clipboard_content_instead_of_applying_it() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let mut linux_permissions = all_enabled(&android_id.as_hex());
    linux_permissions.set_clipboard_mode(&android_id.as_hex(), ClipboardMode::Ask);
    let (android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        linux_permissions,
        &android_id,
        &linux_id,
        &cancel,
    );
    wait_for(&android.events, |event| {
        matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
    })
    .await;

    let text = "https://example.invalid/report";
    android
        .handle
        .publish(ContinuityPayload::ClipboardUpdate(ClipboardUpdate {
            text: text.to_owned(),
            content_fingerprint: clipboard_fingerprint(text),
            origin_relay_id: android_id.as_hex(),
            explicit: false,
        }))
        .await;

    let offered = wait_for(&linux.events, |event| match event {
        ContinuityEvent::ClipboardOffered { update, .. } => Some(update.clone()),
        _ => None,
    })
    .await;
    assert_eq!(offered.text, text);

    cancel.cancel();
    let _ = android.task.await;
    let _ = linux.task.await;
}

#[tokio::test]
async fn notifications_mirror_and_dismiss() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (mut android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );
    wait_for(&android.events, |event| {
        matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
    })
    .await;

    android
        .handle
        .publish(ContinuityPayload::Notification(NotificationEvent {
            key: "0|com.example|7|null|10123".to_owned(),
            app_label: "Messages".to_owned(),
            title: Some("Mum".to_owned()),
            body: Some("On my way".to_owned()),
            posted_at_ms: now_ms(),
            clearable: true,
        }))
        .await;

    let posted = wait_for(&linux.events, |event| match event {
        ContinuityEvent::NotificationPosted { event, .. } => Some(event.clone()),
        _ => None,
    })
    .await;
    assert_eq!(posted.app_label, "Messages");

    linux
        .handle
        .publish(ContinuityPayload::NotificationDismiss(
            NotificationDismissRequest {
                key: posted.key.clone(),
                issued_at_ms: now_ms(),
            },
        ))
        .await;

    match android.host.recv().await.expect("dismiss request") {
        ContinuityHostRequest::DismissNotification { key, reply, .. } => {
            assert_eq!(key, posted.key);
            let _ = reply.send(());
        }
        other => panic!("unexpected host request: {other:?}"),
    }

    android
        .handle
        .publish(ContinuityPayload::NotificationRemoved(NotificationRemoval {
            key: posted.key.clone(),
        }))
        .await;
    let removed = wait_for(&linux.events, |event| match event {
        ContinuityEvent::NotificationRemoved { removal, .. } => Some(removal.key.clone()),
        _ => None,
    })
    .await;
    assert_eq!(removed, posted.key);

    cancel.cancel();
    let _ = android.task.await;
    let _ = linux.task.await;
}

#[tokio::test]
async fn messages_are_paged_and_sent_through_the_provider() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (mut android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );

    // Android answers provider requests with a small fake SMS store.
    let android_worker = tokio::spawn(async move {
        while let Some(request) = android.host.recv().await {
            match request {
                ContinuityHostRequest::ListConversations { request, reply, .. } => {
                    assert!(request.limit <= MAX_PAGE_SIZE);
                    let _ = reply.send(Ok(SmsConversationsPage {
                        conversations: vec![SmsConversation {
                            conversation_id: "42".to_owned(),
                            display_name: Some("Mum".to_owned()),
                            addresses: vec!["+10000000000".to_owned()],
                            snippet: Some("On my way".to_owned()),
                            last_message_at_ms: 1_700_000_000_000,
                            unread: true,
                        }],
                        has_more: false,
                    }));
                }
                ContinuityHostRequest::ListMessages { request, reply, .. } => {
                    let _ = reply.send(Ok(SmsMessagesPage {
                        conversation_id: request.conversation_id.clone(),
                        messages: vec![SmsMessage {
                            conversation_id: request.conversation_id,
                            message_id: "900".to_owned(),
                            direction: SmsDirection::Incoming,
                            address: Some("+10000000000".to_owned()),
                            body: "On my way".to_owned(),
                            sent_at_ms: 1_700_000_000_000,
                            read: false,
                        }],
                        has_more: true,
                    }));
                }
                ContinuityHostRequest::SendSms { request, reply, .. } => {
                    let _ = reply.send(SmsSendOutcome::Sent {
                        message_id: Some(format!("sent-{}", request.request_id)),
                    });
                }
                _ => {}
            }
        }
    });

    linux
        .handle
        .publish(ContinuityPayload::SmsConversationsRequest(
            SmsConversationsRequest {
                limit: 25,
                before_ms: None,
            },
        ))
        .await;
    let page = wait_for(&linux.events, |event| match event {
        ContinuityEvent::ConversationsPage { page, .. } => Some(page.clone()),
        _ => None,
    })
    .await;
    assert_eq!(page.conversations.len(), 1);
    assert_eq!(page.conversations[0].display_name.as_deref(), Some("Mum"));

    linux
        .handle
        .publish(ContinuityPayload::SmsMessagesRequest(SmsMessagesRequest {
            conversation_id: "42".to_owned(),
            limit: 50,
            before_ms: None,
        }))
        .await;
    let messages = wait_for(&linux.events, |event| match event {
        ContinuityEvent::MessagesPage { page, .. } => Some(page.clone()),
        _ => None,
    })
    .await;
    assert_eq!(messages.messages.len(), 1);
    assert!(messages.has_more, "older messages load on request");

    linux
        .handle
        .publish(ContinuityPayload::SmsSendRequest(SmsSendRequest {
            request_id: "send-1".to_owned(),
            conversation_id: Some("42".to_owned()),
            recipients: vec!["+10000000000".to_owned()],
            body: "Five minutes".to_owned(),
            issued_at_ms: now_ms(),
        }))
        .await;
    let outcome = wait_for(&linux.events, |event| match event {
        ContinuityEvent::SmsSendCompleted { outcome, .. } => Some(outcome.clone()),
        _ => None,
    })
    .await;
    assert!(matches!(outcome, SmsSendOutcome::Sent { .. }));

    cancel.cancel();
    let _ = linux.task.await;
    android_worker.abort();
}

#[tokio::test]
async fn a_resent_sms_request_is_answered_as_a_duplicate_not_sent_twice() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (mut android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );

    let sends = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let worker_sends = sends.clone();
    let android_worker = tokio::spawn(async move {
        while let Some(request) = android.host.recv().await {
            if let ContinuityHostRequest::SendSms { reply, .. } = request {
                worker_sends.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                let _ = reply.send(SmsSendOutcome::Sent { message_id: None });
            }
        }
    });

    let request = SmsSendRequest {
        request_id: "send-once".to_owned(),
        conversation_id: None,
        recipients: vec!["+10000000000".to_owned()],
        body: "Only once".to_owned(),
        issued_at_ms: now_ms(),
    };
    // The same logical request twice, with distinct envelope ids: exactly what a
    // client retry after a reconnect looks like.
    linux
        .handle
        .publish(ContinuityPayload::SmsSendRequest(request.clone()))
        .await;
    wait_for(&linux.events, |event| match event {
        ContinuityEvent::SmsSendCompleted { outcome, .. } => {
            matches!(outcome, SmsSendOutcome::Sent { .. }).then_some(())
        }
        _ => None,
    })
    .await;
    linux
        .handle
        .publish(ContinuityPayload::SmsSendRequest(request))
        .await;
    wait_for(&linux.events, |event| match event {
        ContinuityEvent::SmsSendCompleted { outcome, .. } => {
            matches!(outcome, SmsSendOutcome::Duplicate).then_some(())
        }
        _ => None,
    })
    .await;

    assert_eq!(sends.load(std::sync::atomic::Ordering::SeqCst), 1);

    cancel.cancel();
    let _ = linux.task.await;
    android_worker.abort();
}

#[tokio::test]
async fn call_state_streams_and_unsupported_actions_are_reported_honestly() {
    let cancel = CancellationToken::new();
    let android_id = relay_id();
    let linux_id = relay_id();
    let (mut android, linux) = connected_pair(
        all_enabled(&linux_id.as_hex()),
        all_enabled(&android_id.as_hex()),
        &android_id,
        &linux_id,
        &cancel,
    );
    wait_for(&android.events, |event| {
        matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
    })
    .await;

    let android_handle = android.handle.clone();
    let android_worker = tokio::spawn(async move {
        while let Some(request) = android.host.recv().await {
            if let ContinuityHostRequest::CallAction { request, reply, .. } = request {
                let outcome = match request.action {
                    CallAction::Answer => CallActionOutcome::Unsupported {
                        reason: "ANSWER_PHONE_CALLS has not been granted".to_owned(),
                    },
                    _ => CallActionOutcome::Accepted,
                };
                let _ = reply.send(outcome);
            }
        }
    });

    android_handle
        .publish(ContinuityPayload::CallState(CallState {
            phase: CallPhase::Ringing,
            address: Some("+10000000000".to_owned()),
            display_name: Some("Mum".to_owned()),
            active_duration_ms: None,
            changed_at_ms: now_ms(),
        }))
        .await;
    let state = wait_for(&linux.events, |event| match event {
        ContinuityEvent::CallStateChanged { state, .. } => Some(state.clone()),
        _ => None,
    })
    .await;
    assert_eq!(state.phase, CallPhase::Ringing);
    assert_eq!(state.display_name.as_deref(), Some("Mum"));

    linux
        .handle
        .publish(ContinuityPayload::CallActionRequest(CallActionRequest {
            request_id: "answer-1".to_owned(),
            action: CallAction::Answer,
            address: None,
            issued_at_ms: now_ms(),
        }))
        .await;
    let outcome = wait_for(&linux.events, |event| match event {
        ContinuityEvent::CallActionCompleted { outcome, .. } => Some(outcome.clone()),
        _ => None,
    })
    .await;
    assert!(matches!(outcome, CallActionOutcome::Unsupported { .. }));

    cancel.cancel();
    let _ = linux.task.await;
    android_worker.abort();
}

#[tokio::test]
async fn a_forged_sender_id_terminates_the_session() {
    let cancel = CancellationToken::new();
    let local = relay_id();
    let remote = relay_id();
    let (mut attacker, victim_stream) = tokio::io::duplex(64 * 1024);
    let victim = spawn_peer(
        victim_stream,
        proven_session(&local, &remote),
        "Workstation",
        DevicePlatform::Linux,
        trusting(&remote),
        all_enabled(&remote.as_hex()),
        cancel.clone(),
    );

    let forged = envelope(
        &"F".repeat(64),
        ContinuityPayload::Battery(BatteryState {
            percentage: Some(1),
            charging: ChargingState::Unknown,
        }),
    );
    let frame = encode_frame(&forged).unwrap();
    tokio::io::AsyncWriteExt::write_all(&mut attacker, &frame)
        .await
        .unwrap();

    let end = victim.task.await.unwrap();
    assert!(matches!(
        end,
        ContinuitySessionEnd::ProtocolViolation { .. }
    ));
    cancel.cancel();
}

#[tokio::test]
async fn a_malformed_frame_is_answered_rather_than_dropping_the_session() {
    let cancel = CancellationToken::new();
    let local = relay_id();
    let remote = relay_id();
    let (mut peer, victim_stream) = tokio::io::duplex(64 * 1024);
    let victim = spawn_peer(
        victim_stream,
        proven_session(&local, &remote),
        "Workstation",
        DevicePlatform::Linux,
        trusting(&remote),
        all_enabled(&remote.as_hex()),
        cancel.clone(),
    );

    let body = b"{\"nonsense\":true}";
    let mut frame = (body.len() as u32).to_be_bytes().to_vec();
    frame.extend_from_slice(body);
    tokio::io::AsyncWriteExt::write_all(&mut peer, &frame)
        .await
        .unwrap();

    // The peer stays up and answers with a structured error.
    let mut reply = None;
    for _ in 0..200 {
        if let Ok(envelope) = tokio::time::timeout(
            std::time::Duration::from_millis(20),
            read_envelope(&mut peer),
        )
        .await
        .unwrap_or(Err(ContinuityCodecError::Closed))
        {
            if let ContinuityPayload::Error(error) = envelope.payload {
                reply = Some(error);
                break;
            }
        }
    }
    assert_eq!(
        reply.expect("malformed input is answered").code,
        ContinuityErrorCode::Malformed
    );
    assert!(!victim.task.is_finished(), "the session survives bad input");

    cancel.cancel();
    let _ = victim.task.await;
}

#[tokio::test]
async fn an_untrusted_peer_cannot_open_a_continuity_session() {
    let cancel = CancellationToken::new();
    let local = relay_id();
    let remote = relay_id();
    let (_peer, victim_stream) = tokio::io::duplex(64 * 1024);
    let victim = spawn_peer(
        victim_stream,
        proven_session(&local, &remote),
        "Workstation",
        DevicePlatform::Linux,
        Arc::new(MemoryTrustDirectory::new()),
        all_enabled(&remote.as_hex()),
        cancel.clone(),
    );
    assert_eq!(victim.task.await.unwrap(), ContinuitySessionEnd::NotTrusted);
    cancel.cancel();
}

#[tokio::test]
async fn a_reconnect_re_establishes_and_resubscribes() {
    let android_id = relay_id();
    let linux_id = relay_id();

    for round in 0..2 {
        let cancel = CancellationToken::new();
        let (android, linux) = connected_pair(
            all_enabled(&linux_id.as_hex()),
            all_enabled(&android_id.as_hex()),
            &android_id,
            &linux_id,
            &cancel,
        );
        wait_for(&linux.events, |event| {
            matches!(event, ContinuityEvent::SessionEstablished { .. }).then_some(())
        })
        .await;
        wait_for(&android.events, |event| {
            matches!(event, ContinuityEvent::PeerSubscribed { .. }).then_some(())
        })
        .await;

        android
            .handle
            .publish(ContinuityPayload::Battery(BatteryState {
                percentage: Some(70 + round),
                charging: ChargingState::Discharging,
            }))
            .await;
        let state = wait_for(&linux.events, |event| match event {
            ContinuityEvent::BatteryChanged { state, .. } => Some(*state),
            _ => None,
        })
        .await;
        assert_eq!(state.percentage, Some(70 + round));

        cancel.cancel();
        // Either side may observe its own cancellation or the peer's stream
        // closing first; both are an orderly shutdown.
        for end in [android.task.await.unwrap(), linux.task.await.unwrap()] {
            assert!(
                matches!(
                    end,
                    ContinuitySessionEnd::Cancelled | ContinuitySessionEnd::Closed
                ),
                "unexpected shutdown reason: {end:?}"
            );
        }
    }
}
