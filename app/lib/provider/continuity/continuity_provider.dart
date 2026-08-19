import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:localsend_app/model/continuity/continuity_runtime.dart';
import 'package:localsend_app/model/persistence/relay_continuity_settings.dart';
import 'package:localsend_app/model/persistence/relay_paired_address.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/relay_anywhere_listener_provider.dart';
import 'package:localsend_app/provider/relay_identity_provider.dart';
import 'package:localsend_app/provider/relay_paired_routes_provider.dart';
import 'package:localsend_app/util/native/continuity_channel.dart';
import 'package:localsend_app/util/security/relay_anywhere_listener_service.dart';
import 'package:localsend_app/util/security/relay_identity_coordinator.dart';
import 'package:localsend_isolates/rust/api/continuity.dart' as rust;
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('RelayContinuity');

/// Orchestrates Relay continuity.
///
/// Three concerns are kept apart on purpose:
///
///  * **Routing** — a stored Relay address, owned by the pairing flow.
///  * **Trust** — a user decision recorded per proven RelayId.
///  * **Capability consent** — a user decision per capability per device.
///
/// This notifier owns the last two and pushes them into Rust, which enforces
/// them. It never grants anything as a side effect of pairing or connecting.
final continuityProvider = ReduxProvider<ContinuityService, RelayContinuityState>((ref) {
  return ContinuityService(
    persistence: ref.read(persistenceProvider),
    channel: const ContinuityChannel(),
    identityCoordinator: ref.read(relayIdentityCoordinatorProvider),
    listenerService: ref.read(relayAnywhereListenerServiceProvider),
    pairedRoutes: () => ref.read(relayPairedRoutesProvider),
  );
});

class ContinuityService extends ReduxNotifier<RelayContinuityState> {
  final PersistenceService _persistence;
  final ContinuityChannel _channel;
  final RelayIdentityCoordinator _identityCoordinator;
  final RelayAnywhereListenerService _listenerService;
  final List<RelayPairedAddress> Function() _pairedRoutes;
  final Uuid _uuid = const Uuid();

  StreamSubscription<rust.RsContinuityEvent>? _events;
  StreamSubscription<rust.RsContinuityHostRequest>? _hostRequests;
  StreamSubscription<PlatformContinuityEvent>? _platformEvents;

  ContinuityService({
    required PersistenceService persistence,
    required ContinuityChannel channel,
    required RelayIdentityCoordinator identityCoordinator,
    required RelayAnywhereListenerService listenerService,
    required List<RelayPairedAddress> Function() pairedRoutes,
  })  : _persistence = persistence,
        _channel = channel,
        _identityCoordinator = identityCoordinator,
        _listenerService = listenerService,
        _pairedRoutes = pairedRoutes;

  @override
  RelayContinuityState init() {
    final settings = <String, RelayContinuitySettings>{
      for (final entry in _persistence.getRelayContinuitySettings()) entry.relayId: entry,
    };
    return RelayContinuityState(settings: settings);
  }

  /// This device's own platform label, used in the capability manifest.
  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  String _newRequestId() => _uuid.v4();
}

// --------------------------------------------------------------- lifecycle

/// Brings continuity up: reads real platform capability states, publishes them,
/// pushes trust and consent into Rust, and starts observation only for what the
/// user actually enabled.
///
/// Doing nothing is a valid outcome. On a fresh install this ends after
/// publishing the manifest: no observation, no background service, no dial.
class ContinuityInitAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String deviceLabel;

  ContinuityInitAction({required this.deviceLabel});

  @override
  Future<RelayContinuityState> reduce() async {
    final localCapabilities = await notifier._channel.capabilities();
    final next = state.copyWith(localCapabilities: localCapabilities);

    _publishManifest(deviceLabel, localCapabilities);
    await _pushConsent(next);
    _subscribe();

    unawaited(dispatchAsync(ContinuityApplyEnablementAction()));
    return next;
  }

  void _publishManifest(String label, Map<String, PlatformCapabilityState> capabilities) {
    rust.continuitySetLocalCapabilities(
      deviceLabel: label,
      platform: notifier._platformName(),
      entries: _manifestEntries(capabilities),
    );
  }

  List<rust.RsCapabilityEntry> _manifestEntries(Map<String, PlatformCapabilityState> capabilities) {
    final entries = <rust.RsCapabilityEntry>[];
    for (final capability in ContinuityCapabilityKind.values) {
      final platform = capabilities[capability.name];
      entries.add(
        rust.RsCapabilityEntry(
          capability: _toRustCapability(capability),
          state: platform == null
              ? _desktopStateFor(capability)
              : _fromPlatformState(platform),
        ),
      );
    }
    return entries;
  }

  /// Desktop honestly advertises only what a desktop can do. Messages and phone
  /// are consumed here, never provided, so they are reported unavailable rather
  /// than silently "available".
  rust.RsCapabilityState _desktopStateFor(ContinuityCapabilityKind capability) {
    return switch (capability) {
      ContinuityCapabilityKind.battery ||
      ContinuityCapabilityKind.clipboard =>
        const rust.RsCapabilityState.available(),
      ContinuityCapabilityKind.notifications => const rust.RsCapabilityState.unavailable(
          reason: 'This computer does not mirror its own notifications.',
        ),
      ContinuityCapabilityKind.messages => const rust.RsCapabilityState.unavailable(
          reason: 'This computer has no messaging service of its own.',
        ),
      ContinuityCapabilityKind.phone => const rust.RsCapabilityState.unavailable(
          reason: 'This computer has no telephony of its own.',
        ),
    };
  }

  rust.RsCapabilityState _fromPlatformState(PlatformCapabilityState platform) {
    final reason = platform.reason ?? '';
    return switch (platform.state) {
      'available' => const rust.RsCapabilityState.available(),
      'limited' => rust.RsCapabilityState.limited(reason: reason),
      'permissionRequired' => rust.RsCapabilityState.permissionRequired(reason: reason),
      _ => rust.RsCapabilityState.unavailable(reason: reason),
    };
  }

  Future<void> _pushConsent(RelayContinuityState next) async {
    // Trust and consent are pushed separately, exactly as they are stored.
    rust.continuitySetDeviceTrust(
      trusted: next.settings.values.where((entry) => entry.trusted).map((entry) => entry.relayId).toList(),
      blocked: const [],
    );
    for (final entry in next.settings.values) {
      for (final capability in ContinuityCapabilityKind.values) {
        final rustCapability = _toRustCapability(capability);
        if (entry.granted.contains(capability)) {
          await rust.continuityEnableCapability(relayId: entry.relayId, capability: rustCapability);
        } else {
          await rust.continuityDisableCapability(relayId: entry.relayId, capability: rustCapability);
        }
      }
      await rust.continuitySetClipboardMode(
        relayId: entry.relayId,
        mode: switch (entry.clipboardMode) {
          ClipboardSharingMode.off => rust.RsClipboardMode.off,
          ClipboardSharingMode.ask => rust.RsClipboardMode.ask,
          ClipboardSharingMode.automatic => rust.RsClipboardMode.automatic,
        },
      );
    }
  }

  void _subscribe() {
    notifier._events ??= rust.continuityEvents().listen(
      (event) => dispatch(ContinuityRemoteEventAction(event)),
      onError: (Object error) => _logger.warning('continuity event stream failed: $error'),
    );
    notifier._hostRequests ??= rust.continuityHostRequests().listen(
      (request) => dispatchAsync(ContinuityHostRequestAction(request)),
      onError: (Object error) => _logger.warning('continuity host stream failed: $error'),
    );
    notifier._platformEvents ??= notifier._channel.events().listen(
      (event) => dispatchAsync(ContinuityPlatformEventAction(event)),
      onError: (Object error) => _logger.warning('continuity platform stream failed: $error'),
    );
  }
}

/// Starts or stops everything that must only exist while continuity is enabled:
/// platform observation, the Android background service, and outbound links.
class ContinuityApplyEnablementAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  @override
  Future<RelayContinuityState> reduce() async {
    final enabledCapabilities = <String>{};
    for (final entry in state.settings.values) {
      for (final capability in ContinuityCapabilityKind.values) {
        if (entry.isEnabled(capability)) {
          enabledCapabilities.add(capability.name);
        }
      }
    }

    if (enabledCapabilities.isEmpty) {
      // Nothing is shared: tear down everything rather than idling.
      await notifier._channel.stopObserving();
      await notifier._channel.stopBackgroundService();
      rust.continuityDisconnectAll();
      return state.copyWith(backgroundServiceRunning: false);
    }

    await notifier._channel.startObserving(enabledCapabilities.toList());
    await notifier._channel.startBackgroundService();
    unawaited(dispatchAsync(ContinuityConnectEnabledDevicesAction()));
    return state.copyWith(backgroundServiceRunning: notifier._channel.isSupported);
  }
}

/// Opens continuity links to every device that is trusted and has at least one
/// capability enabled. A stored route on its own connects nothing.
class ContinuityConnectEnabledDevicesAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  @override
  Future<RelayContinuityState> reduce() async {
    final routes = {
      for (final route in notifier._pairedRoutes()) route.relayId: route,
    };
    final targets = state.settings.values.where((entry) => entry.hasAnyCapability).toList();
    if (targets.isEmpty) {
      return state;
    }

    // The listener owns the endpoint continuity rides on; without it there is
    // nothing to dial from, and that is reported rather than retried blindly.
    if (notifier._listenerService.address == null) {
      _logger.info('continuity is enabled but the Relay listener is not running yet');
      return state;
    }

    await notifier._identityCoordinator.withPrivateKey((privateKey, identity) async {
      for (final target in targets) {
        final route = routes[target.relayId];
        if (route == null) {
          continue;
        }
        try {
          await rust.continuityConnectDevice(
            privateKeyPem: privateKey,
            relayId: identity.relayId,
            remoteAddress: route.relayAddress,
          );
        } catch (error) {
          _logger.warning('continuity connect failed for ${target.relayId}: $error');
        }
      }
      return null;
    });
    return state;
  }
}

// ----------------------------------------------------------------- consent

/// Records that the user trusts a proven device for continuity.
///
/// This is the only path that can set trust, and it is always a deliberate
/// action in the UI. Pairing does not call it.
class ContinuitySetTrustedAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final bool trusted;

  ContinuitySetTrustedAction({required this.relayId, required this.trusted});

  @override
  Future<RelayContinuityState> reduce() async {
    final updated = state.settingsFor(relayId).copyWith(
          trusted: trusted,
          // Withdrawing trust withdraws every capability with it, so trust can
          // never be re-granted later and silently restore old consent.
          granted: trusted ? null : const {},
          clipboardMode: trusted ? null : ClipboardSharingMode.off,
        );
    final next = await _persist(updated);
    rust.continuitySetDeviceTrust(
      trusted: next.settings.values.where((entry) => entry.trusted).map((entry) => entry.relayId).toList(),
      blocked: const [],
    );
    if (!trusted) {
      rust.continuityDisconnectDevice(relayId: relayId);
    }
    unawaited(dispatchAsync(ContinuityApplyEnablementAction()));
    return next;
  }

  Future<RelayContinuityState> _persist(RelayContinuitySettings updated) async {
    final settings = Map<String, RelayContinuitySettings>.from(state.settings)..[relayId] = updated;
    await notifier._persistence.setRelayContinuitySettings(settings.values.toList());
    return state.copyWith(settings: settings);
  }
}

/// Enables or disables one capability for one device.
class ContinuitySetCapabilityAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final ContinuityCapabilityKind capability;
  final bool enabled;

  ContinuitySetCapabilityAction({
    required this.relayId,
    required this.capability,
    required this.enabled,
  });

  @override
  Future<RelayContinuityState> reduce() async {
    final current = state.settingsFor(relayId);
    if (enabled && !current.trusted) {
      // A capability cannot be enabled for a device the user has not trusted.
      // Rust would refuse it anyway; refusing here keeps the UI honest.
      return state;
    }

    if (enabled) {
      // Ask the platform for whatever this capability actually needs, and do
      // not record consent for something the platform then refused.
      final granted = await notifier._channel.requestPermissions(capability.name);
      if (!granted && notifier._channel.isSupported && capability != ContinuityCapabilityKind.battery) {
        final refreshed = await notifier._channel.capabilities();
        final platform = refreshed[capability.name];
        if (platform != null && !platform.isAvailable) {
          return state.copyWith(localCapabilities: refreshed);
        }
      }
    }

    var updated = current.withCapability(capability, enabled);
    if (capability == ContinuityCapabilityKind.clipboard) {
      updated = updated.copyWith(
        clipboardMode: enabled
            ? (current.clipboardMode.isEnabled ? current.clipboardMode : ClipboardSharingMode.ask)
            : ClipboardSharingMode.off,
      );
    }

    final settings = Map<String, RelayContinuitySettings>.from(state.settings)..[relayId] = updated;
    await notifier._persistence.setRelayContinuitySettings(settings.values.toList());

    final rustCapability = _toRustCapability(capability);
    if (enabled) {
      await rust.continuityEnableCapability(relayId: relayId, capability: rustCapability);
    } else {
      await rust.continuityDisableCapability(relayId: relayId, capability: rustCapability);
    }
    await rust.continuitySetClipboardMode(
      relayId: relayId,
      mode: _toRustClipboardMode(updated.clipboardMode),
    );

    final next = state.copyWith(settings: settings);
    unawaited(dispatchAsync(ContinuityApplyEnablementAction()));
    return next;
  }
}

/// Changes how clipboard content moves with one device.
class ContinuitySetClipboardModeAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final ClipboardSharingMode mode;

  ContinuitySetClipboardModeAction({required this.relayId, required this.mode});

  @override
  Future<RelayContinuityState> reduce() async {
    final updated = state.settingsFor(relayId).copyWith(clipboardMode: mode);
    final settings = Map<String, RelayContinuitySettings>.from(state.settings)..[relayId] = updated;
    await notifier._persistence.setRelayContinuitySettings(settings.values.toList());
    await rust.continuitySetClipboardMode(relayId: relayId, mode: _toRustClipboardMode(mode));
    unawaited(dispatchAsync(ContinuityApplyEnablementAction()));
    return state.copyWith(settings: settings);
  }
}

// ------------------------------------------------------------ remote events

/// Folds one event from a peer into UI state.
class ContinuityRemoteEventAction extends ReduxAction<ContinuityService, RelayContinuityState> {
  final rust.RsContinuityEvent event;

  ContinuityRemoteEventAction(this.event);

  @override
  RelayContinuityState reduce() {
    return switch (event) {
      rust.RsContinuityEvent_SessionEstablished(:final remoteRelayId, :final directPath) =>
        _update(remoteRelayId, (device) => device.copyWith(connected: true, directPath: directPath, clearError: true)),
      rust.RsContinuityEvent_SessionEnded(:final remoteRelayId, :final reason) =>
        _update(remoteRelayId, (device) => device.copyWith(connected: false, lastError: _endReason(reason))),
      rust.RsContinuityEvent_ManifestReceived(:final remoteRelayId, :final manifest) =>
        _update(remoteRelayId, (device) => device.copyWith(
              remoteLabel: manifest.deviceLabel,
              remoteCapabilities: _capabilitiesFrom(manifest),
            )),
      rust.RsContinuityEvent_BatteryChanged(:final remoteRelayId, :final percentage, :final charging) =>
        _update(remoteRelayId, (device) => device.copyWith(
              battery: RemoteBattery(
                percentage: percentage?.toInt(),
                charging: _chargingName(charging),
                observedAt: DateTime.now(),
              ),
            )),
      rust.RsContinuityEvent_ClipboardOffered(:final remoteRelayId, :final text, :final explicit) =>
        _update(remoteRelayId, (device) => device.copyWith(
              clipboardOffer: ClipboardOffer(text: text, explicit: explicit, receivedAt: DateTime.now()),
            )),
      rust.RsContinuityEvent_NotificationPosted(
        :final remoteRelayId,
        :final key,
        :final appLabel,
        :final title,
        :final body,
        :final postedAtMs,
        :final clearable,
      ) =>
        _update(remoteRelayId, (device) {
          final mirrored = MirroredNotification(
            key: key,
            appLabel: appLabel,
            title: title,
            body: body,
            postedAt: DateTime.fromMillisecondsSinceEpoch(postedAtMs.toInt()),
            clearable: clearable,
          );
          // Replace an existing entry with the same key rather than stacking
          // duplicates when an app updates its notification in place.
          final notifications = [
            mirrored,
            ...device.notifications.where((entry) => entry.key != key),
          ];
          return device.copyWith(notifications: notifications.take(50).toList());
        }),
      rust.RsContinuityEvent_NotificationRemoved(:final remoteRelayId, :final key) =>
        _update(remoteRelayId, (device) => device.copyWith(
              notifications: device.notifications.where((entry) => entry.key != key).toList(),
            )),
      rust.RsContinuityEvent_ConversationsPage(:final remoteRelayId, :final conversations, :final hasMore) =>
        _update(remoteRelayId, (device) => device.copyWith(
              conversations: conversations.map(_conversation).toList(),
              conversationsHasMore: hasMore,
            )),
      rust.RsContinuityEvent_MessagesPage(:final remoteRelayId, :final conversationId, :final messages, :final hasMore) =>
        _update(remoteRelayId, (device) {
          final thread = Map<String, List<RemoteMessage>>.from(device.messages);
          thread[conversationId] = messages.map(_message).toList();
          final more = Map<String, bool>.from(device.messagesHasMore)..[conversationId] = hasMore;
          return device.copyWith(messages: thread, messagesHasMore: more);
        }),
      rust.RsContinuityEvent_MessageReceived(:final remoteRelayId, :final message) =>
        _update(remoteRelayId, (device) {
          final thread = Map<String, List<RemoteMessage>>.from(device.messages);
          final existing = thread[message.conversationId] ?? const <RemoteMessage>[];
          thread[message.conversationId] = [_message(message), ...existing];
          return device.copyWith(messages: thread);
        }),
      rust.RsContinuityEvent_SmsSendCompleted(:final remoteRelayId, :final sent, :final detail) =>
        _update(remoteRelayId, (device) => sent
            ? device.copyWith(clearError: true)
            : device.copyWith(lastError: detail ?? 'The message could not be sent.')),
      rust.RsContinuityEvent_CallStateChanged(:final remoteRelayId, :final state) =>
        _update(remoteRelayId, (device) => device.copyWith(
              call: RemoteCall(
                phase: RemoteCall.parsePhase(_phaseName(state.phase)),
                address: state.address,
                displayName: state.displayName,
                activeDuration: state.activeDurationMs == null
                    ? null
                    : Duration(milliseconds: state.activeDurationMs!.toInt()),
              ),
            )),
      rust.RsContinuityEvent_CallActionCompleted(:final remoteRelayId, :final accepted, :final detail) =>
        _update(remoteRelayId, (device) => accepted
            ? device.copyWith(clearError: true)
            : device.copyWith(lastError: detail ?? 'That is not available on this phone.')),
      rust.RsContinuityEvent_PeerError(:final remoteRelayId, :final detail) =>
        _update(remoteRelayId, (device) => device.copyWith(lastError: detail)),
    };
  }

  RelayContinuityState _update(String relayId, DeviceContinuity Function(DeviceContinuity) update) {
    final devices = Map<String, DeviceContinuity>.from(state.devices);
    devices[relayId] = update(state.deviceFor(relayId));
    return state.copyWith(devices: devices);
  }

  String _endReason(String reason) => switch (reason) {
        'not_trusted' => 'This device is not trusted for continuity.',
        'blocked' => 'This device is blocked.',
        'protocol_violation' => 'The connection was closed after unexpected data.',
        'transport_failed' => 'The connection dropped. Relay will retry.',
        _ => 'Disconnected.',
      };
}

/// Fulfils work an authorized peer asked this device to do.
///
/// Authorization already happened in Rust before this action ever runs; the
/// only decisions here are platform ones.
class ContinuityHostRequestAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final rust.RsContinuityHostRequest request;

  ContinuityHostRequestAction(this.request);

  @override
  Future<RelayContinuityState> reduce() async {
    final channel = notifier._channel;
    switch (request) {
      case rust.RsContinuityHostRequest_ApplyClipboard(:final requestId, :final remoteRelayId, :final text):
        final written = await _applyClipboard(text);
        rust.continuityAnswerAck(requestId: requestId);
        if (written) {
          final devices = Map<String, DeviceContinuity>.from(state.devices);
          devices[remoteRelayId] = state.deviceFor(remoteRelayId).copyWith(
                lastClipboardText: text,
                clearClipboardOffer: true,
              );
          return state.copyWith(devices: devices);
        }
        return state;

      case rust.RsContinuityHostRequest_DismissNotification(:final requestId, :final key):
        await channel.dismissNotification(key);
        rust.continuityAnswerAck(requestId: requestId);
        return state;

      case rust.RsContinuityHostRequest_ListConversations(:final requestId, :final limit, :final beforeMs):
        if (!channel.isSupported) {
          rust.continuityAnswerUnavailable(
            requestId: requestId,
            permissionRequired: false,
            detail: 'This device has no messages to share.',
          );
          return state;
        }
        final capabilities = await channel.capabilities();
        final messages = capabilities['messages'];
        if (messages != null && !messages.isAvailable) {
          rust.continuityAnswerUnavailable(
            requestId: requestId,
            permissionRequired: messages.needsPermission,
            detail: messages.reason ?? 'Messages are not available on this phone.',
          );
          return state;
        }
        final page = await channel.conversations(limit: limit, beforeMs: beforeMs?.toInt());
        rust.continuityAnswerConversations(
          requestId: requestId,
          conversations: page.conversations
              .map((conversation) => rust.RsSmsConversation(
                    conversationId: conversation.conversationId,
                    displayName: conversation.displayName,
                    addresses: conversation.addresses,
                    snippet: conversation.snippet,
                    lastMessageAtMs: BigInt.from(conversation.lastMessageAtMs),
                    unread: conversation.unread,
                  ))
              .toList(),
          hasMore: page.hasMore,
        );
        return state;

      case rust.RsContinuityHostRequest_ListMessages(
          :final requestId,
          :final conversationId,
          :final limit,
          :final beforeMs
        ):
        if (!channel.isSupported) {
          rust.continuityAnswerUnavailable(
            requestId: requestId,
            permissionRequired: false,
            detail: 'This device has no messages to share.',
          );
          return state;
        }
        final page = await channel.messages(
          conversationId: conversationId,
          limit: limit,
          beforeMs: beforeMs?.toInt(),
        );
        rust.continuityAnswerMessages(
          requestId: requestId,
          conversationId: conversationId,
          messages: page.messages.map(_toRustMessage).toList(),
          hasMore: page.hasMore,
        );
        return state;

      case rust.RsContinuityHostRequest_SendSms(:final requestId, :final recipients, :final body):
        final outcome = await channel.sendSms(recipients: recipients, body: body);
        if (outcome.succeeded) {
          rust.continuityAnswerSmsSent(requestId: requestId, messageId: null);
        } else if (outcome.state == 'rejected') {
          rust.continuityAnswerUnavailable(
            requestId: requestId,
            permissionRequired: true,
            detail: outcome.reason ?? 'Relay is not allowed to send messages on this phone.',
          );
        } else {
          rust.continuityAnswerSmsFailed(
            requestId: requestId,
            reason: outcome.reason ?? 'The message could not be sent.',
          );
        }
        return state;

      case rust.RsContinuityHostRequest_CallAction(:final requestId, :final action, :final address):
        final outcome = await channel.callAction(action: _actionName(action), address: address);
        rust.continuityAnswerCallAction(
          requestId: requestId,
          accepted: outcome.succeeded,
          reason: outcome.reason ?? 'That is not available on this phone.',
        );
        return state;
    }
  }

  Future<bool> _applyClipboard(String text) async {
    if (notifier._channel.isSupported) {
      return notifier._channel.clipboardWrite(text);
    }
    // Desktop uses Flutter's own clipboard service rather than shelling out.
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (error) {
      _logger.warning('could not write the clipboard: $error');
      return false;
    }
  }
}

/// Folds a local platform change into the protocol.
class ContinuityPlatformEventAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final PlatformContinuityEvent event;

  ContinuityPlatformEventAction(this.event);

  @override
  Future<RelayContinuityState> reduce() async {
    switch (event.kind) {
      case 'battery':
        await rust.continuityPublishBattery(
          percentage: (event.data['percentage'] as num?)?.toInt(),
          charging: _toRustCharging(event.data['charging'] as String? ?? 'unknown'),
        );
      case 'clipboard':
        final text = event.data['text'] as String?;
        if (text != null && text.isNotEmpty) {
          await rust.continuityShareClipboard(
            text: text,
            explicit: false,
            originRelayId: _localRelayId(),
          );
        }
      case 'notificationPosted':
        await rust.continuityPublishNotification(
          key: event.data['key'] as String? ?? '',
          appLabel: event.data['appLabel'] as String? ?? '',
          title: event.data['title'] as String?,
          body: event.data['body'] as String?,
          postedAtMs: BigInt.from((event.data['postedAtMs'] as num?)?.toInt() ?? 0),
          clearable: event.data['clearable'] == true,
        );
      case 'notificationRemoved':
        await rust.continuityPublishNotificationRemoved(key: event.data['key'] as String? ?? '');
      case 'callState':
        await rust.continuityPublishCallState(
          phase: _toRustPhase(event.data['phase'] as String? ?? 'unknown'),
          address: event.data['address'] as String?,
          displayName: event.data['displayName'] as String?,
          activeDurationMs: (event.data['activeDurationMs'] as num?) == null
              ? null
              : BigInt.from((event.data['activeDurationMs'] as num).toInt()),
        );
      case 'smsReceived':
        await rust.continuityPublishIncomingMessage(
          conversationId: event.data['conversationId'] as String? ?? '',
          messageId: event.data['messageId'] as String? ?? '',
          address: event.data['address'] as String?,
          body: event.data['body'] as String? ?? '',
          sentAtMs: BigInt.from((event.data['sentAtMs'] as num?)?.toInt() ?? 0),
        );
    }
    return state;
  }

  /// The local RelayId, read from persisted public identity metadata.
  ///
  /// It travels with clipboard content purely so a three-device topology stops
  /// bouncing; it is advisory metadata, not identity.
  String _localRelayId() => notifier._persistence.getRelayPublicIdentity()?.relayId ?? '';
}

// ------------------------------------------------------------- user actions

/// Shares this device's clipboard on purpose. Works even in Ask mode, because
/// the user just asked.
class ContinuityShareClipboardAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;

  ContinuityShareClipboardAction({required this.relayId});

  @override
  Future<RelayContinuityState> reduce() async {
    String? text;
    if (notifier._channel.isSupported) {
      final read = await notifier._channel.clipboardRead();
      if (read.unavailableReason != null) {
        final devices = Map<String, DeviceContinuity>.from(state.devices);
        devices[relayId] = state.deviceFor(relayId).copyWith(lastError: read.unavailableReason);
        return state.copyWith(devices: devices);
      }
      text = read.text;
    } else {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    }
    if (text == null || text.isEmpty) {
      return state;
    }
    await rust.continuityShareClipboard(
      text: text,
      explicit: true,
      originRelayId: notifier._persistence.getRelayPublicIdentity()?.relayId ?? '',
    );
    final devices = Map<String, DeviceContinuity>.from(state.devices);
    devices[relayId] = state.deviceFor(relayId).copyWith(lastClipboardText: text, clearError: true);
    return state.copyWith(devices: devices);
  }
}

/// Applies clipboard content a peer offered, after the user chose to.
class ContinuityAcceptClipboardOfferAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;

  ContinuityAcceptClipboardOfferAction({required this.relayId});

  @override
  Future<RelayContinuityState> reduce() async {
    final offer = state.deviceFor(relayId).clipboardOffer;
    if (offer == null) {
      return state;
    }
    if (notifier._channel.isSupported) {
      await notifier._channel.clipboardWrite(offer.text);
    } else {
      await Clipboard.setData(ClipboardData(text: offer.text));
    }
    final devices = Map<String, DeviceContinuity>.from(state.devices);
    devices[relayId] = state.deviceFor(relayId).copyWith(
          lastClipboardText: offer.text,
          clearClipboardOffer: true,
        );
    return state.copyWith(devices: devices);
  }
}

class ContinuityLoadConversationsAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final int limit;
  final int? beforeMs;

  ContinuityLoadConversationsAction({required this.relayId, this.limit = 25, this.beforeMs});

  @override
  Future<RelayContinuityState> reduce() async {
    await rust.continuityRequestConversations(
      relayId: relayId,
      limit: limit,
      beforeMs: beforeMs == null ? null : BigInt.from(beforeMs!),
    );
    return state;
  }
}

class ContinuityLoadMessagesAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final String conversationId;
  final int limit;
  final int? beforeMs;

  ContinuityLoadMessagesAction({
    required this.relayId,
    required this.conversationId,
    this.limit = 50,
    this.beforeMs,
  });

  @override
  Future<RelayContinuityState> reduce() async {
    await rust.continuityRequestMessages(
      relayId: relayId,
      conversationId: conversationId,
      limit: limit,
      beforeMs: beforeMs == null ? null : BigInt.from(beforeMs!),
    );
    return state;
  }
}

class ContinuitySendMessageAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final String? conversationId;
  final List<String> recipients;
  final String body;

  ContinuitySendMessageAction({
    required this.relayId,
    required this.conversationId,
    required this.recipients,
    required this.body,
  });

  @override
  Future<RelayContinuityState> reduce() async {
    await rust.continuitySendSms(
      relayId: relayId,
      // A stable id per composed message: a retry after a reconnect is answered
      // as a duplicate rather than sending twice.
      requestId: notifier._newRequestId(),
      conversationId: conversationId,
      recipients: recipients,
      body: body,
    );
    return state;
  }
}

class ContinuityCallAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final rust.RsCallAction action;
  final String? address;

  ContinuityCallAction({required this.relayId, required this.action, this.address});

  @override
  Future<RelayContinuityState> reduce() async {
    await rust.continuityCallAction(
      relayId: relayId,
      requestId: notifier._newRequestId(),
      action: action,
      address: address,
    );
    return state;
  }
}

class ContinuityDismissRemoteNotificationAction extends AsyncReduxAction<ContinuityService, RelayContinuityState> {
  final String relayId;
  final String key;

  ContinuityDismissRemoteNotificationAction({required this.relayId, required this.key});

  @override
  Future<RelayContinuityState> reduce() async {
    await rust.continuityDismissRemoteNotification(relayId: relayId, key: key);
    final devices = Map<String, DeviceContinuity>.from(state.devices);
    devices[relayId] = state.deviceFor(relayId).copyWith(
          notifications: state.deviceFor(relayId).notifications.where((entry) => entry.key != key).toList(),
        );
    return state.copyWith(devices: devices);
  }
}

// ---------------------------------------------------------------- mapping

rust.RsContinuityCapability _toRustCapability(ContinuityCapabilityKind capability) =>
    switch (capability) {
      ContinuityCapabilityKind.battery => rust.RsContinuityCapability.battery,
      ContinuityCapabilityKind.clipboard => rust.RsContinuityCapability.clipboard,
      ContinuityCapabilityKind.notifications => rust.RsContinuityCapability.notifications,
      ContinuityCapabilityKind.messages => rust.RsContinuityCapability.messages,
      ContinuityCapabilityKind.phone => rust.RsContinuityCapability.phone,
    };

rust.RsClipboardMode _toRustClipboardMode(ClipboardSharingMode mode) => switch (mode) {
      ClipboardSharingMode.off => rust.RsClipboardMode.off,
      ClipboardSharingMode.ask => rust.RsClipboardMode.ask,
      ClipboardSharingMode.automatic => rust.RsClipboardMode.automatic,
    };

rust.RsChargingState _toRustCharging(String raw) => switch (raw) {
      'charging' => rust.RsChargingState.charging,
      'full' => rust.RsChargingState.full,
      'discharging' => rust.RsChargingState.discharging,
      'not_charging' => rust.RsChargingState.notCharging,
      _ => rust.RsChargingState.unknown,
    };

rust.RsCallPhase _toRustPhase(String raw) => switch (raw) {
      'ringing' => rust.RsCallPhase.ringing,
      'dialing' => rust.RsCallPhase.dialing,
      'active' => rust.RsCallPhase.active,
      'ended' => rust.RsCallPhase.ended,
      'idle' => rust.RsCallPhase.idle,
      _ => rust.RsCallPhase.unknown,
    };

String _chargingName(rust.RsChargingState state) => switch (state) {
      rust.RsChargingState.charging => 'charging',
      rust.RsChargingState.full => 'full',
      rust.RsChargingState.discharging => 'discharging',
      rust.RsChargingState.notCharging => 'not_charging',
      rust.RsChargingState.unknown => 'unknown',
    };

String _phaseName(rust.RsCallPhase phase) => switch (phase) {
      rust.RsCallPhase.ringing => 'ringing',
      rust.RsCallPhase.dialing => 'dialing',
      rust.RsCallPhase.active => 'active',
      rust.RsCallPhase.ended => 'ended',
      rust.RsCallPhase.idle => 'idle',
      rust.RsCallPhase.unknown => 'unknown',
    };

String _actionName(rust.RsCallAction action) => switch (action) {
      rust.RsCallAction.dial => 'dial',
      rust.RsCallAction.answer => 'answer',
      rust.RsCallAction.reject => 'reject',
      rust.RsCallAction.hangUp => 'hangUp',
    };

Map<ContinuityCapabilityKind, RemoteCapabilityState> _capabilitiesFrom(rust.RsCapabilityManifest manifest) {
  final result = <ContinuityCapabilityKind, RemoteCapabilityState>{};
  for (final entry in manifest.entries) {
    final capability = switch (entry.capability) {
      rust.RsContinuityCapability.battery => ContinuityCapabilityKind.battery,
      rust.RsContinuityCapability.clipboard => ContinuityCapabilityKind.clipboard,
      rust.RsContinuityCapability.notifications => ContinuityCapabilityKind.notifications,
      rust.RsContinuityCapability.messages => ContinuityCapabilityKind.messages,
      rust.RsContinuityCapability.phone => ContinuityCapabilityKind.phone,
    };
    result[capability] = switch (entry.state) {
      rust.RsCapabilityState_Available() => const RemoteCapabilityState('available'),
      rust.RsCapabilityState_Limited(:final reason) => RemoteCapabilityState('limited', reason),
      rust.RsCapabilityState_PermissionRequired(:final reason) =>
        RemoteCapabilityState('permissionRequired', reason),
      rust.RsCapabilityState_Unavailable(:final reason) => RemoteCapabilityState('unavailable', reason),
    };
  }
  return result;
}

RemoteConversation _conversation(rust.RsSmsConversation raw) => RemoteConversation(
      conversationId: raw.conversationId,
      displayName: raw.displayName,
      addresses: raw.addresses,
      snippet: raw.snippet,
      lastMessageAt: DateTime.fromMillisecondsSinceEpoch(raw.lastMessageAtMs.toInt()),
      unread: raw.unread,
    );

RemoteMessage _message(rust.RsSmsMessage raw) => RemoteMessage(
      conversationId: raw.conversationId,
      messageId: raw.messageId,
      outgoing: raw.outgoing,
      address: raw.address,
      body: raw.body,
      sentAt: DateTime.fromMillisecondsSinceEpoch(raw.sentAtMs.toInt()),
    );

rust.RsSmsMessage _toRustMessage(PlatformMessage message) => rust.RsSmsMessage(
      conversationId: message.conversationId,
      messageId: message.messageId,
      outgoing: message.outgoing,
      address: message.address,
      body: message.body,
      sentAtMs: BigInt.from(message.sentAtMs),
      read: message.read,
    );
