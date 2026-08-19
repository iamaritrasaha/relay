import 'dart:async';

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

  const KdeConnectState({this.devices = const [], this.incoming});

  KdeConnectState copyWith({
    List<RsKdeConnectDevice>? devices,
    KdeConnectIncomingRequest? incoming,
    bool clearIncoming = false,
  }) => KdeConnectState(
    devices: devices ?? this.devices,
    incoming: clearIncoming ? null : incoming ?? this.incoming,
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
    final snapshot = await runtime.snapshot();
    return state.copyWith(devices: snapshot);
  }
}

class KdeConnectRequestPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRequestPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier._runtime?.requestPair(deviceId: deviceId);
    return state;
  }
}

class KdeConnectAcceptPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectAcceptPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier._runtime?.acceptPair(deviceId: deviceId);
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectRejectPairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectRejectPairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier._runtime?.rejectPair(deviceId: deviceId);
    return state.copyWith(clearIncoming: true);
  }
}

class KdeConnectUnpairAction extends AsyncReduxAction<KdeConnectService, KdeConnectState> {
  final String deviceId;

  KdeConnectUnpairAction(this.deviceId);

  @override
  Future<KdeConnectState> reduce() async {
    await notifier._runtime?.unpair(deviceId: deviceId);
    return state.copyWith(clearIncoming: true);
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
