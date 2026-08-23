import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/native/directories.dart';
import 'package:relay_app/provider/relay_clipboard_service.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

final _logger = Logger('KdeConnect');
final _smsLogger = Logger('RelaySmsBridge');

String kdeConnectDeviceIdFromKey(String key) => key.startsWith('kdeconnect:') ? key.substring('kdeconnect:'.length) : key;

class KdeConnectIncomingRequest {
  final String deviceId;
  final String name;

  const KdeConnectIncomingRequest({required this.deviceId, required this.name});
}

class KdeTelephonyState {
  final String event; // 'ringing', 'talking', 'missedCall'
  final bool isCancel;
  final String? phoneNumber;
  final String? contactName;
  final int timestamp;

  const KdeTelephonyState({
    required this.event,
    this.isCancel = false,
    this.phoneNumber,
    this.contactName,
    required this.timestamp,
  });
}

/// One notification, together with the logical device that produced it.
///
/// A remote notification id is assigned by the phone and is unique only *within*
/// that phone -- two devices can legitimately both send id `42`. So the stable
/// identity of a notification in Relay is the `(deviceId, notificationId)` pair,
/// exposed here as [key]. Nothing in Relay may key notifications on the
/// notification id alone, nor on a LAN address, WAN EndpointId, transport or
/// current route: those are routes to a logical device, not the device itself.
class RelayNotificationRecord {
  /// The logical KDE/Relay device id that produced this notification.
  final String deviceId;

  /// Display name of the originating device, for a merged/global view.
  final String deviceName;

  /// The id the originating device assigned. Unique only within [deviceId].
  final String notificationId;

  final RsKdeNotification notification;

  const RelayNotificationRecord({
    required this.deviceId,
    required this.deviceName,
    required this.notificationId,
    required this.notification,
  });

  /// The globally stable key: device identity first, then the remote id.
  String get key => '$deviceId:$notificationId';

  String? get appName => notification.appName;
  String? get title => notification.title;
  String? get text => notification.text;

  @override
  bool operator ==(Object other) =>
      other is RelayNotificationRecord &&
      other.deviceId == deviceId &&
      other.notificationId == notificationId &&
      other.deviceName == deviceName &&
      other.notification == notification;

  @override
  int get hashCode => Object.hash(deviceId, notificationId, deviceName, notification);
}

class KdeConnectState {
  /// The discovery/pairing view: every peer Relay can currently see, trusted or
  /// not. Kept because the fabric deliberately contains only trusted devices,
  /// and a pairing candidate has to come from somewhere.
  final List<RsKdeConnectDevice> devices;

  /// The Device Fabric: the authoritative product device model.
  ///
  /// One record per trusted logical device, with LAN and Relay WAN recorded as
  /// routes against it. Connection state, trust, capabilities and feature
  /// availability all come from here — never from a display string, a selected
  /// transport, or whichever network last worked.
  final RsRelayDeviceFabric? fabric;
  final KdeConnectIncomingRequest? incoming;
  final Map<String, List<RsKdeNotification>> notifications;

  /// The desktop's RunCommand allow-list. Owned by this machine, not by any
  /// device: which phone asked is carried in the request, never in the storage.
  final List<RsRunCommand> runCommands;

  /// File transfers, keyed by "deviceId:transferId" — never by filename, so two
  /// devices sending the same name stay independent.
  final Map<String, RsTransfer> transfers;

  /// Whether clipboard sync is on for this desktop.
  final bool clipboardEnabled;

  /// Whether this session permits unattended clipboard observation. False on
  /// Wayland, where only the focused client is offered the clipboard.
  final bool clipboardAutoSync;

  /// Whether the desktop user has switched remote input on.
  final bool remoteInputEnabled;

  /// Whether an OS-level input session is currently authorised. Being enabled
  /// is not enough: the compositor must also have granted a session.
  final bool remoteInputReady;
  final Map<String, List<RsKdeSmsConversation>> smsConversations;
  final Map<String, Map<int, List<RsKdeSmsMessage>>> smsMessages;
  final Map<String, KdeTelephonyState?> activeCalls;
  final Map<String, List<KdeTelephonyState>> recentTelephonyEvents;
  final String? lastPingDeviceName;
  final String? lastPingMessage;
  final int lastPingTimestamp;

  const KdeConnectState({
    this.devices = const [],
    this.fabric,
    this.incoming,
    this.notifications = const {},
    this.runCommands = const [],
    this.transfers = const {},
    this.clipboardEnabled = true,
    this.clipboardAutoSync = false,
    this.remoteInputEnabled = false,
    this.remoteInputReady = false,
    this.smsConversations = const {},
    this.smsMessages = const {},
    this.activeCalls = const {},
    this.recentTelephonyEvents = const {},
    this.lastPingDeviceName,
    this.lastPingMessage,
    this.lastPingTimestamp = 0,
  });

  /// Every trusted logical device, in the core's deterministic order.
  List<RsRelayDevice> get fabricDevices => fabric?.devices ?? const [];

  /// The fabric record for one logical device, or null when Relay does not know
  /// it. Never falls back to another device's record.
  RsRelayDevice? fabricFor(String deviceId) {
    final id = kdeConnectDeviceIdFromKey(deviceId);
    return fabricDevices.firstWhereOrNull((device) => device.deviceId == id);
  }

  /// Notifications belonging to exactly one logical device.
  ///
  /// Never falls back to "any device's notifications": an unknown device id
  /// yields an empty list rather than someone else's notifications.
  List<RsKdeNotification> notificationsForDevice(String deviceId) => notifications[kdeConnectDeviceIdFromKey(deviceId)] ?? const [];

  /// Every device's notifications merged into one list, each entry still
  /// carrying the device that produced it.
  ///
  /// This is what a global Notifications surface renders; the per-device
  /// collections stay authoritative and are never flattened into a shared
  /// id-keyed store, so two phones sending the same notification id produce two
  /// distinct records here.
  List<RelayNotificationRecord> get allNotifications => [
    for (final entry in notifications.entries)
      for (final notification in entry.value)
        RelayNotificationRecord(
          deviceId: entry.key,
          deviceName: deviceNameFor(entry.key),
          notificationId: notification.id,
          notification: notification,
        ),
  ];

  /// Transfers belonging to one logical device, newest activity included.
  List<RsTransfer> transfersForDevice(String deviceId) {
    final id = kdeConnectDeviceIdFromKey(deviceId);
    return transfers.values.where((transfer) => transfer.deviceId == id).toList();
  }

  /// Display name for a device id, falling back to the raw id so a merged view
  /// can always attribute a notification to *something*.
  String deviceNameFor(String deviceId) {
    final id = kdeConnectDeviceIdFromKey(deviceId);
    return fabricFor(id)?.displayName ?? devices.firstWhereOrNull((device) => device.deviceId == id)?.name ?? id;
  }

  KdeConnectState copyWith({
    List<RsKdeConnectDevice>? devices,
    RsRelayDeviceFabric? fabric,
    KdeConnectIncomingRequest? incoming,
    bool clearIncoming = false,
    Map<String, List<RsKdeNotification>>? notifications,
    List<RsRunCommand>? runCommands,
    Map<String, RsTransfer>? transfers,
    bool? clipboardEnabled,
    bool? clipboardAutoSync,
    bool? remoteInputEnabled,
    bool? remoteInputReady,
    Map<String, List<RsKdeSmsConversation>>? smsConversations,
    Map<String, Map<int, List<RsKdeSmsMessage>>>? smsMessages,
    Map<String, KdeTelephonyState?>? activeCalls,
    Map<String, List<KdeTelephonyState>>? recentTelephonyEvents,
    String? lastPingDeviceName,
    String? lastPingMessage,
    int? lastPingTimestamp,
  }) => KdeConnectState(
    devices: devices ?? this.devices,
    fabric: fabric ?? this.fabric,
    incoming: clearIncoming ? null : incoming ?? this.incoming,
    notifications: notifications ?? this.notifications,
    runCommands: runCommands ?? this.runCommands,
    transfers: transfers ?? this.transfers,
    clipboardEnabled: clipboardEnabled ?? this.clipboardEnabled,
    clipboardAutoSync: clipboardAutoSync ?? this.clipboardAutoSync,
    remoteInputEnabled: remoteInputEnabled ?? this.remoteInputEnabled,
    remoteInputReady: remoteInputReady ?? this.remoteInputReady,
    smsConversations: smsConversations ?? this.smsConversations,
    smsMessages: smsMessages ?? this.smsMessages,
    activeCalls: activeCalls ?? this.activeCalls,
    recentTelephonyEvents: recentTelephonyEvents ?? this.recentTelephonyEvents,
    lastPingDeviceName: lastPingDeviceName ?? this.lastPingDeviceName,
    lastPingMessage: lastPingMessage ?? this.lastPingMessage,
    lastPingTimestamp: lastPingTimestamp ?? this.lastPingTimestamp,
  );
}

typedef KdeConnectIdentityFactory = Future<RsKdeConnectIdentity> Function({required String deviceName});
typedef KdeConnectStarter =
    Future<RsKdeConnect> Function(RsKdeConnectIdentity identity, List<RsKdeConnectTrustedDevice> trusted, List<RsRunCommand> runCommands);

final kdeConnectProvider = ReduxProvider<KdeConnectService, KdeConnectState>((ref) {
  return KdeConnectService(
    persistence: ref.read(persistenceProvider),
    generateIdentity: kdeconnectGenerateIdentity,
    startRuntime: (identity, trusted, runCommands) => startKdeconnect(identity: identity, trusted: trusted, runCommands: runCommands),
  );
});

class KdeConnectService extends ReduxNotifier<KdeConnectState> {
  final PersistenceService persistence;
  final KdeConnectIdentityFactory generateIdentity;
  final KdeConnectStarter startRuntime;

  RsKdeConnect? _runtime;

  /// Watches the local clipboard and applies remote values to it.
  late final RelayClipboardService clipboard = RelayClipboardService(
    onLocalChange: (text) async => dispatchAsync(KdeConnectSendClipboardAction(text)),
  );
  StreamSubscription<RsKdeConnectEvent>? _events;

  KdeConnectService({
    required this.persistence,
    required this.generateIdentity,
    required this.startRuntime,
  });

  @override
  KdeConnectState init() => const KdeConnectState();

  @override
  void dispose() {
    unawaited(clipboard.stop());
    unawaited(_events?.cancel());
    final runtime = _runtime;
    if (runtime != null) {
      unawaited(runtime.stop());
    }
    super.dispose();
  }
}

class KdeConnectStartAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceName;

  KdeConnectStartAction({required this.deviceName});

  @override
  Future<KdeConnectState> reduce() async {
    final persisted = notifier.persistence.getKdeConnectIdentity();
    final RsKdeConnectIdentity identity;
    if (persisted != null) {
      final persistedWanSecret = persisted['wanSecretKey'];
      final wanSecret = persistedWanSecret is List
          ? Uint8List.fromList(persistedWanSecret.cast<num>().map((value) => value.toInt()).toList())
          : await kdeconnectGenerateWanSecret();
      identity = RsKdeConnectIdentity(
        deviceId: persisted['deviceId'] as String,
        deviceName: persisted['deviceName'] as String? ?? deviceName,
        certificatePem: persisted['certificatePem'] as String,
        privateKeyPem: persisted['privateKeyPem'] as String,
        wanSecretKey: wanSecret,
      );
      if (persistedWanSecret == null) {
        await notifier.persistence.setKdeConnectIdentity({...persisted, 'wanSecretKey': wanSecret.toList()});
      }
    } else {
      identity = await notifier.generateIdentity(deviceName: deviceName);
      await notifier.persistence.setKdeConnectIdentity({
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'certificatePem': identity.certificatePem,
        'privateKeyPem': identity.privateKeyPem,
        'wanSecretKey': identity.wanSecretKey.toList(),
      });
    }
    final trusted = [
      for (final item in notifier.persistence.getKdeConnectTrustedDevices())
        RsKdeConnectTrustedDevice(
          deviceId: item['deviceId'] as String,
          certificatePem: item['certificatePem'] as String,
          name: item['name'] as String? ?? 'Phone',
          deviceType: item['deviceType'] as String? ?? 'phone',
          protocolVersion: (item['protocolVersion'] as num?)?.toInt() ?? 8,
          pairedAtUnix: (item['pairedAtUnix'] as num?)?.toInt() ?? 0,
          wanEndpointId: item['wanEndpointId'] as String?,
        ),
    ];
    // Restored *before* the runtime starts: a phone asks for the command list
    // once when its plugin starts and caches the answer, and it can connect
    // before a post-start call lands. Ids come from persistence unchanged, so a
    // phone's cached command ids still resolve after a desktop restart.
    final restoredCommands = kdeRunCommandsFromJson(notifier.persistence.getKdeConnectRunCommands());
    final runtime = await notifier.startRuntime(identity, trusted, restoredCommands);

    await notifier._events?.cancel();
    notifier._runtime = runtime;
    notifier._events = runtime.listen().listen(
      (event) {
        dispatch(KdeConnectApplyEventAction(event));
      },
      onError: (Object error, StackTrace stack) {
        _logger.warning('KDE Connect event stream failed', error, stack);
      },
    );
    // Remote input is restored as a stored preference only. The OS-level
    // session is deliberately never re-established automatically: input control
    // must be granted by a present user, not inherited from a previous run.
    final remoteInputEnabled = notifier.persistence.getKdeConnectRemoteInputEnabled();
    await runtime.setRemoteInputEnabled(enabled: remoteInputEnabled);

    // Received files need a destination before any transfer can be accepted.
    final downloadDir = notifier.persistence.getDestination() ?? await getDefaultDestinationDirectory();
    await runtime.setDownloadDir(directory: downloadDir);

    final clipboardEnabled = notifier.persistence.getKdeConnectClipboardEnabled();
    await runtime.setClipboardEnabled(enabled: clipboardEnabled);
    if (clipboardEnabled) {
      await notifier.clipboard.start();
    }

    // Read once at start-up so restored trust is on screen immediately, as
    // Offline. Waiting for the first DevicesChanged would leave a user who has
    // paired three phones looking at an empty app until one of them connects.
    // Trust is restored here; a connection is not, and the fabric says so.
    final initialFabric = await runtime.deviceFabric();

    return state.copyWith(
      fabric: initialFabric,
      runCommands: restoredCommands,
      remoteInputEnabled: remoteInputEnabled,
      remoteInputReady: false,
      clipboardEnabled: clipboardEnabled,
      clipboardAutoSync: notifier.clipboard.autoSyncAvailable,
    );
  }
}

class KdeConnectRequestPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRequestPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.requestPair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Pair request failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectAcceptPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectAcceptPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.acceptPair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Accept pair failed for device $deviceId', error, stack);
    }
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectRejectPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRejectPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.rejectPair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Reject pair failed for device $deviceId', error, stack);
    }
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectUnpairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectUnpairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.unpair(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Unpair failed for device $deviceId', error, stack);
    }
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectPingAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final String? message;

  KdeConnectPingAction(this.deviceId, {this.message});

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.sendRelayPing(deviceId: deviceId);
      await notifier._runtime?.requestRelayDeviceState(deviceId: deviceId);
      await notifier._runtime?.sendPing(deviceId: deviceId, message: message);
    } catch (error, stack) {
      _logger.warning('Send ping failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectFindPhoneAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectFindPhoneAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.findPhone(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Find phone failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectSendClipboardAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String content;

  KdeConnectSendClipboardAction(this.content);

  @override
  Future<KdeConnectState> reduce() async {
    if (content.isEmpty) return state;
    try {
      // Loop suppression, the enable switch and the size bound all live in the
      // core, which is the only layer that sees both directions.
      await notifier._runtime?.sendClipboardToAllPaired(
        content: content,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error, stack) {
      // Never log the content itself.
      _logger.warning('Send clipboard failed', error, stack);
    }
    return state;
  }
}

/// Dismisses one notification on the device that produced it.
///
/// Both the device id and the remote notification id are required, because the
/// remote id alone cannot identify a notification across simultaneously
/// connected phones. The core routes the packet to that logical device and the
/// TransportRouter picks LAN or Relay WAN on its own, so dismissal behaves
/// identically whether the device is Local or Remote.
class KdeConnectDismissNotificationAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final String notificationId;

  KdeConnectDismissNotificationAction({required this.deviceId, required this.notificationId});

  @override
  Future<KdeConnectState> reduce() async {
    final id = kdeConnectDeviceIdFromKey(deviceId);
    try {
      await notifier._runtime?.dismissNotification(deviceId: id, remoteNotificationId: notificationId);
    } catch (error, stack) {
      // Deliberately no notification body in the log.
      _logger.warning('Dismiss notification failed for device=$id', error, stack);
    }
    return state;
  }
}

/// Decodes persisted RunCommand entries, skipping anything malformed rather
/// than throwing away the whole list because one entry is bad.
List<RsRunCommand> kdeRunCommandsFromJson(List<Map<String, dynamic>> raw) => [
  for (final item in raw)
    if (item['id'] is String && (item['id'] as String).isNotEmpty)
      RsRunCommand(
        id: item['id'] as String,
        name: item['name'] as String? ?? '',
        command: item['command'] as String? ?? '',
        enabled: item['enabled'] as bool? ?? false,
      ),
];

List<Map<String, dynamic>> kdeRunCommandsToJson(List<RsRunCommand> commands) => [
  for (final command in commands) {'id': command.id, 'name': command.name, 'command': command.command, 'enabled': command.enabled},
];

/// Replaces the desktop's RunCommand allow-list, persisting it and pushing it
/// into the running KDE core.
///
/// Persist-then-push keeps the two in step: a phone can only ever run what is
/// in this list, so the list that survives a restart must be the list the core
/// is enforcing right now.
class KdeConnectSetRunCommandsAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final List<RsRunCommand> commands;

  KdeConnectSetRunCommandsAction(this.commands);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier.persistence.setKdeConnectRunCommands(kdeRunCommandsToJson(commands));
    try {
      await notifier._runtime?.setRunCommands(commands: commands);
    } catch (error, stack) {
      // Never log a command line: they routinely carry paths and secrets.
      _logger.warning('Applying the RunCommand list failed', error, stack);
    }
    final fabric = await notifier._runtime?.deviceFabric();
    return state.copyWith(runCommands: commands, fabric: fabric);
  }
}

/// Turns remote input on or off on this desktop.
///
/// Switching it on does not by itself let a phone move the cursor — an OS-level
/// session still has to be authorised, which is a separate, explicit step.
class KdeConnectSetRemoteInputEnabledAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final bool enabled;

  KdeConnectSetRemoteInputEnabledAction(this.enabled);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier.persistence.setKdeConnectRemoteInputEnabled(enabled);
    await notifier._runtime?.setRemoteInputEnabled(enabled: enabled);
    final fabric = await notifier._runtime?.deviceFabric();
    return state.copyWith(remoteInputEnabled: enabled, fabric: fabric);
  }
}

/// Asks the desktop session for permission to inject input.
///
/// Triggers the compositor's own approval dialog, so it is only ever dispatched
/// from a deliberate action in Settings.
class KdeConnectAuthorizeRemoteInputAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.authorizeRemoteInput();
    } catch (error, stack) {
      _logger.warning('Remote input authorization failed or was declined', error, stack);
    }
    final ready = await notifier._runtime?.remoteInputReady() ?? false;
    final fabric = await notifier._runtime?.deviceFabric();
    return state.copyWith(remoteInputReady: ready, fabric: fabric);
  }
}

class KdeConnectRevokeRemoteInputAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  @override
  Future<KdeConnectState> reduce() async {
    await notifier._runtime?.revokeRemoteInput();
    final fabric = await notifier._runtime?.deviceFabric();
    return state.copyWith(remoteInputReady: false, fabric: fabric);
  }
}

/// Turns clipboard sync on or off.
///
/// Switching it off stops the local watcher *and* tells the core to refuse
/// incoming clipboard packets, so neither direction can move data.
class KdeConnectSetClipboardEnabledAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final bool enabled;

  KdeConnectSetClipboardEnabledAction(this.enabled);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier.persistence.setKdeConnectClipboardEnabled(enabled);
    await notifier._runtime?.setClipboardEnabled(enabled: enabled);
    if (enabled) {
      await notifier.clipboard.start();
    } else {
      await notifier.clipboard.stop();
    }
    final fabric = await notifier._runtime?.deviceFabric();
    return state.copyWith(clipboardEnabled: enabled, fabric: fabric);
  }
}

/// Sends one file to a device.
///
/// The core decides the route and applies the remote size policy; an oversized
/// file resolves to `requiresLocalConnection` rather than failing, so the UI can
/// explain what to do instead of showing an error.
class KdeConnectSendFileAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final String path;

  KdeConnectSendFileAction({required this.deviceId, required this.path});

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.sendFile(deviceId: kdeConnectDeviceIdFromKey(deviceId), path: path);
    } catch (error, stack) {
      // Log the failure, not the file's contents or full path.
      _logger.warning('Send file failed for device=$deviceId', error, stack);
    }
    return state;
  }
}

/// Cancels an in-flight transfer.
///
/// The core marks it cancelled, drops any pending payload correlation and
/// removes the partial file, so a cancelled transfer can never later report as
/// completed.
class KdeConnectCancelTransferAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final String transferId;

  KdeConnectCancelTransferAction({required this.deviceId, required this.transferId});

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.cancelTransfer(
        deviceId: kdeConnectDeviceIdFromKey(deviceId),
        transferId: transferId,
      );
    } catch (error, stack) {
      _logger.warning('Cancel transfer failed', error, stack);
    }
    return state;
  }
}

class KdeConnectApplyEventAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final RsKdeConnectEvent event;

  KdeConnectApplyEventAction(this.event);

  @override
  KdeConnectState reduce() {
    switch (event) {
      case RsKdeConnectEvent_DevicesChanged(:final devices, :final fabric):
        // One event carries both views of the same observation, so the fabric
        // and the discovery list can never describe different moments. Device-
        // owned caches are pruned against that same snapshot: when Forget
        // removes a Fabric record, no stale message, notification, transfer or
        // phone state can keep living behind a vanished card.
        final retainedIds = fabric.devices.map((device) => device.deviceId).toSet();
        return state.copyWith(
          devices: devices,
          fabric: fabric,
          notifications: Map.fromEntries(state.notifications.entries.where((entry) => retainedIds.contains(entry.key))),
          transfers: Map.fromEntries(state.transfers.entries.where((entry) => retainedIds.contains(entry.value.deviceId))),
          smsConversations: Map.fromEntries(state.smsConversations.entries.where((entry) => retainedIds.contains(entry.key))),
          smsMessages: Map.fromEntries(state.smsMessages.entries.where((entry) => retainedIds.contains(entry.key))),
          activeCalls: Map.fromEntries(state.activeCalls.entries.where((entry) => retainedIds.contains(entry.key))),
          recentTelephonyEvents: Map.fromEntries(state.recentTelephonyEvents.entries.where((entry) => retainedIds.contains(entry.key))),
        );
      case RsKdeConnectEvent_IncomingPair(:final deviceId, :final name):
        return state.copyWith(
          incoming: KdeConnectIncomingRequest(deviceId: deviceId, name: name),
        );
      case RsKdeConnectEvent_PairingFailed():
        return state.copyWith(clearIncoming: true);
      case RsKdeConnectEvent_TrustChanged(:final devices):
        unawaited(
          notifier.persistence.setKdeConnectTrustedDevices([
            for (final device in devices)
              {
                'deviceId': device.deviceId,
                'certificatePem': device.certificatePem,
                'name': device.name,
                'deviceType': device.deviceType,
                'protocolVersion': device.protocolVersion,
                'pairedAtUnix': device.pairedAtUnix,
                'wanEndpointId': device.wanEndpointId,
              },
          ]),
        );
        return state;
      case RsKdeConnectEvent_PingReceived(:final deviceId, :final message):
        final dev = state.devices.firstWhereOrNull((d) => d.deviceId == deviceId);
        final devName = dev?.name ?? 'Phone';
        return state.copyWith(
          lastPingDeviceName: devName,
          lastPingMessage: message,
          lastPingTimestamp: DateTime.now().millisecondsSinceEpoch,
        );
      case RsKdeConnectEvent_ClipboardReceived(:final content):
        // The core has already decided this is worth applying: it checked trust,
        // the enable switch, the size bound and loop suppression, and recorded
        // the value so the resulting local change is not echoed back. Applying
        // it here through the GTK channel keeps Wayland working.
        unawaited(notifier.clipboard.applyRemote(content));
        return state;
      case RsKdeConnectEvent_NotificationsChanged(:final deviceId, :final notifications):
        return state.copyWith(
          notifications: {...state.notifications, deviceId: notifications},
        );
      case RsKdeConnectEvent_SmsChanged(:final deviceId, :final conversations, :final messages):
        final deviceMessages = Map<int, List<RsKdeSmsMessage>>.from(state.smsMessages[deviceId] ?? const {});
        for (final message in messages) {
          final threadList = (deviceMessages[message.threadId] ?? const <RsKdeSmsMessage>[])
              .where((item) => item.id > 0 || item.body != message.body)
              .toList();
          final current = Map<int, RsKdeSmsMessage>.fromEntries(
            threadList.map((item) => MapEntry(item.id, item)),
          );
          current[message.id] = message;
          final merged = current.values.toList()..sort((a, b) => a.date.compareTo(b.date));
          deviceMessages[message.threadId] = merged;
        }
        final nextState = state.copyWith(
          smsConversations: {...state.smsConversations, deviceId: conversations},
          smsMessages: {...state.smsMessages, deviceId: deviceMessages},
        );
        _smsLogger.info(
          'PROVIDER updated device=$deviceId conversations=${nextState.smsConversations[deviceId]?.length ?? 0} '
          'messages=${nextState.smsMessages[deviceId]?.values.fold<int>(0, (total, thread) => total + thread.length) ?? 0}',
        );
        return nextState;
      case RsKdeConnectEvent_TransferChanged(:final transfer):
        // Keyed by device *and* transfer id: a second device sending the same
        // filename must not overwrite the first one's progress.
        return state.copyWith(
          transfers: {...state.transfers, '${transfer.deviceId}:${transfer.transferId}': transfer},
        );
      case RsKdeConnectEvent_TelephonyReceived(:final deviceId, :final event):
        final currentEvent = KdeTelephonyState(
          event: event.event,
          isCancel: event.isCancel,
          phoneNumber: event.phoneNumber,
          contactName: event.contactName,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        final recentList = List<KdeTelephonyState>.from(state.recentTelephonyEvents[deviceId] ?? const []);
        recentList.insert(0, currentEvent);
        if (recentList.length > 50) {
          recentList.removeLast();
        }

        final active = nextActiveCall(state.activeCalls[deviceId], currentEvent);

        return state.copyWith(
          activeCalls: {...state.activeCalls, deviceId: active},
          recentTelephonyEvents: {...state.recentTelephonyEvents, deviceId: recentList},
        );
    }
  }
}

/// The call state machine for one device.
///
/// Only the event that is actually live can end the call. Android sends the
/// ringing cancel around the same time as the talking event when a call is
/// answered, so a blanket "any cancel clears the call" rule tears down a call
/// that has just been picked up, and leaves ringing stuck when the order is
/// reversed. A repeat of the event already in progress keeps its original
/// timestamp, which is what makes an in-call duration measurable from the
/// moment talking actually began.
///
/// [previous] is the call currently held for the device, [incoming] the event
/// just received. Returns the call to hold next, or null for idle.
KdeTelephonyState? nextActiveCall(KdeTelephonyState? previous, KdeTelephonyState incoming) {
  // A missed call is a notification about a call that is already over.
  if (incoming.event == 'missedCall') return null;

  if (incoming.isCancel) {
    return (previous != null && previous.event == incoming.event) ? null : previous;
  }

  if (previous != null && previous.event == incoming.event) return previous;

  return incoming;
}

class KdeConnectUpdateMessagesAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final Map<int, List<RsKdeSmsMessage>> messages;

  KdeConnectUpdateMessagesAction({required this.deviceId, required this.messages});

  @override
  KdeConnectState reduce() => state.copyWith(
    smsMessages: {...state.smsMessages, deviceId: messages},
  );
}

/// How many unreconciled outgoing bubbles a single thread may hold.
const int _maxPendingPerThread = 20;

class KdeConnectSendSmsAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final int threadId;
  final List<String> addresses;
  final String messageBody;
  final int? subId;

  KdeConnectSendSmsAction({
    required this.deviceId,
    required this.threadId,
    required this.addresses,
    required this.messageBody,
    this.subId,
  });

  @override
  Future<KdeConnectState> reduce() async {
    final pendingId = -DateTime.now().millisecondsSinceEpoch;
    final pendingMessage = RsKdeSmsMessage(
      id: pendingId,
      threadId: threadId,
      addresses: addresses,
      body: messageBody,
      date: DateTime.now().millisecondsSinceEpoch,
      messageType: 2, // outgoing
      read: true,
      attachments: const [],
    );

    final deviceMessages = Map<int, List<RsKdeSmsMessage>>.from(state.smsMessages[deviceId] ?? const {});
    var currentList = List<RsKdeSmsMessage>.from(deviceMessages[threadId] ?? const []);

    // A pending bubble is cleared when Android echoes the canonical message
    // back. If that echo never comes the entry would otherwise sit in the
    // thread forever, so the oldest unreconciled ones are dropped.
    final pendingCount = currentList.where((message) => message.id < 0).length;
    if (pendingCount >= _maxPendingPerThread) {
      var toDrop = pendingCount - _maxPendingPerThread + 1;
      currentList = currentList.where((message) {
        if (message.id >= 0 || toDrop <= 0) return true;
        toDrop--;
        return false;
      }).toList();
    }

    currentList.add(pendingMessage);
    deviceMessages[threadId] = currentList;

    dispatch(KdeConnectUpdateMessagesAction(deviceId: deviceId, messages: deviceMessages));

    try {
      await notifier._runtime?.sendSms(
        deviceId: deviceId,
        addresses: addresses,
        body: messageBody,
        subId: subId,
      );
    } catch (error, stack) {
      _logger.warning('Send SMS failed for device $deviceId', error, stack);
      final updatedMessages = Map<int, List<RsKdeSmsMessage>>.from(state.smsMessages[deviceId] ?? const {});
      final list = List<RsKdeSmsMessage>.from(updatedMessages[threadId] ?? const []);
      list.removeWhere((m) => m.id == pendingId);
      updatedMessages[threadId] = list;
      return state.copyWith(smsMessages: {...state.smsMessages, deviceId: updatedMessages});
    }
    return state;
  }
}

class KdeConnectMuteCallAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  KdeConnectMuteCallAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.muteCall(deviceId: deviceId);
    } catch (error, stack) {
      _logger.warning('Mute call failed for device $deviceId', error, stack);
    }
    return state;
  }
}

class KdeConnectRequestSmsConversationsAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  KdeConnectRequestSmsConversationsAction(this.deviceId);
  @override
  Future<KdeConnectState> reduce() async {
    final runtime = notifier._runtime;
    if (runtime == null) {
      _smsLogger.warning('REQUEST skipped device=$deviceId packetType=kdeconnect.sms.request_conversations runtimeAvailable=false');
      return state;
    }
    _smsLogger.info('REQUEST action device=$deviceId packetType=kdeconnect.sms.request_conversations');
    try {
      await runtime.requestSmsConversations(deviceId: deviceId);
      _smsLogger.info('REQUEST bridged device=$deviceId packetType=kdeconnect.sms.request_conversations');
    } catch (error, stack) {
      _logger.warning('SMS conversation request failed for device $deviceId', error, stack);
      _smsLogger.warning('REQUEST failed device=$deviceId packetType=kdeconnect.sms.request_conversations reason=${error.runtimeType}');
    }
    return state;
  }
}

class KdeConnectRequestSmsConversationAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;
  final int threadId;
  final int? beforeTimestamp;
  KdeConnectRequestSmsConversationAction(this.deviceId, this.threadId, {this.beforeTimestamp});
  @override
  Future<KdeConnectState> reduce() async {
    final runtime = notifier._runtime;
    if (runtime == null) {
      _smsLogger.warning(
        'REQUEST skipped device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId runtimeAvailable=false',
      );
      return state;
    }
    _smsLogger.info('REQUEST action device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId');
    try {
      await runtime.requestSmsConversation(deviceId: deviceId, threadId: threadId, before: beforeTimestamp);
      _smsLogger.info('REQUEST bridged device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId');
    } catch (error, stack) {
      _logger.warning('SMS history request failed for device $deviceId', error, stack);
      _smsLogger.warning(
        'REQUEST failed device=$deviceId packetType=kdeconnect.sms.request_conversation threadId=$threadId reason=${error.runtimeType}',
      );
    }
    return state;
  }
}

class KdeConnectReplaceDevicesAction extends ReduxAction<KdeConnectService, KdeConnectState> {
  final List<RsKdeConnectDevice> devices;
  final KdeConnectIncomingRequest? incoming;
  final bool clearIncoming;

  KdeConnectReplaceDevicesAction({required this.devices, this.incoming, this.clearIncoming = false});

  @override
  KdeConnectState reduce() => state.copyWith(devices: devices, incoming: incoming, clearIncoming: clearIncoming);
}
