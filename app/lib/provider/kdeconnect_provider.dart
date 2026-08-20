import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

final _logger = Logger('KdeConnect');

class KdeConnectIncomingRequest {
  final String deviceId;
  final String name;

  const KdeConnectIncomingRequest({required this.deviceId, required this.name});
}

class KdeConnectState {
  final List<RsKdeConnectDevice> devices;
  final KdeConnectIncomingRequest? incoming;
  final Map<String, List<RsKdeNotification>> notifications;
  final String? lastPingDeviceName;
  final String? lastPingMessage;
  final int lastPingTimestamp;

  const KdeConnectState({
    this.devices = const [],
    this.incoming,
    this.notifications = const {},
    this.lastPingDeviceName,
    this.lastPingMessage,
    this.lastPingTimestamp = 0,
  });

  KdeConnectState copyWith({
    List<RsKdeConnectDevice>? devices,
    KdeConnectIncomingRequest? incoming,
    bool clearIncoming = false,
    Map<String, List<RsKdeNotification>>? notifications,
    String? lastPingDeviceName,
    String? lastPingMessage,
    int? lastPingTimestamp,
  }) => KdeConnectState(
    devices: devices ?? this.devices,
    incoming: clearIncoming ? null : incoming ?? this.incoming,
    notifications: notifications ?? this.notifications,
    lastPingDeviceName: lastPingDeviceName ?? this.lastPingDeviceName,
    lastPingMessage: lastPingMessage ?? this.lastPingMessage,
    lastPingTimestamp: lastPingTimestamp ?? this.lastPingTimestamp,
  );
}

typedef KdeConnectIdentityFactory = Future<RsKdeConnectIdentity> Function({required String deviceName});
typedef KdeConnectStarter = Future<RsKdeConnect> Function(RsKdeConnectIdentity identity, List<RsKdeConnectTrustedDevice> trusted);

final kdeConnectProvider = ReduxProvider<KdeConnectService, KdeConnectState>((ref) {
  return KdeConnectService(
    persistence: ref.read(persistenceProvider),
    generateIdentity: kdeconnectGenerateIdentity,
    startRuntime: (identity, trusted) => startKdeconnect(identity: identity, trusted: trusted),
  );
});

class KdeConnectService extends ReduxNotifier<KdeConnectState> {
  final PersistenceService persistence;
  final KdeConnectIdentityFactory generateIdentity;
  final KdeConnectStarter startRuntime;

  RsKdeConnect? _runtime;
  StreamSubscription<RsKdeConnectEvent>? _events;
  String? _lastReceivedClipboard;

  KdeConnectService({
    required this.persistence,
    required this.generateIdentity,
    required this.startRuntime,
  });

  @override
  KdeConnectState init() => const KdeConnectState();

  @override
  void dispose() {
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
      identity = RsKdeConnectIdentity(
        deviceId: persisted['deviceId'] as String,
        deviceName: persisted['deviceName'] as String? ?? deviceName,
        certificatePem: persisted['certificatePem'] as String,
        privateKeyPem: persisted['privateKeyPem'] as String,
      );
    } else {
      identity = await notifier.generateIdentity(deviceName: deviceName);
      await notifier.persistence.setKdeConnectIdentity({
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'certificatePem': identity.certificatePem,
        'privateKeyPem': identity.privateKeyPem,
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
        ),
    ];
    final runtime = await notifier.startRuntime(identity, trusted);
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
    return state;
  }
}

class KdeConnectRequestPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRequestPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    try {
      await notifier._runtime?.requestPair(deviceId: deviceId);
    } on AnyhowException catch (error, stack) {
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
    } on AnyhowException catch (error, stack) {
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
    } on AnyhowException catch (error, stack) {
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
    } on AnyhowException catch (error, stack) {
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
      await notifier._runtime?.sendPing(deviceId: deviceId, message: message);
    } on AnyhowException catch (error, stack) {
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
    } on AnyhowException catch (error, stack) {
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
    if (content.isNotEmpty && content != notifier._lastReceivedClipboard) {
      try {
        await notifier._runtime?.sendClipboardToAllPaired(
          content: content,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
      } on AnyhowException catch (error, stack) {
        _logger.warning('Send clipboard failed', error, stack);
      }
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
      case RsKdeConnectEvent_DevicesChanged(:final devices):
        return state.copyWith(devices: devices);
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
      case RsKdeConnectEvent_ClipboardReceived(:final deviceId, :final content, :final timestampMs):
        if (content.isNotEmpty && content != notifier._lastReceivedClipboard) {
          notifier._lastReceivedClipboard = content;
          unawaited(Clipboard.setData(ClipboardData(text: content)));
        }
        return state;
      case RsKdeConnectEvent_NotificationsChanged(:final deviceId, :final notifications):
        return state.copyWith(
          notifications: {...state.notifications, deviceId: notifications},
        );
    }
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
