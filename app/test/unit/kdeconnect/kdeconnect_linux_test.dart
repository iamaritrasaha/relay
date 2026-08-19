import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';

RsKdeConnectDevice kdeDevice({
  required String id,
  required String name,
  bool paired = false,
  bool connected = false,
  bool incomingPair = false,
}) => RsKdeConnectDevice(
  deviceId: id,
  name: name,
  deviceType: 'phone',
  ip: '192.168.1.24',
  port: 1716,
  paired: paired,
  connected: connected,
  incomingPair: incomingPair,
  identityMismatch: false,
);

const _phoneId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _localSend = Device(
  signalingId: null,
  ip: '192.168.1.4',
  version: '2.1',
  port: 53317,
  https: true,
  fingerprint: 'pixel-fingerprint',
  alias: 'LocalSend Phone',
  deviceModel: null,
  deviceType: DeviceType.mobile,
  download: false,
  channels: [],
);

RelayHomeVm homeVm({
  NearbyDevicesState? nearby,
  List<RsKdeConnectDevice> kdeConnectDevices = const [],
}) => RelayHomeVm.fromState(
  configuredAlias: 'My Linux',
  selfDeviceType: DeviceType.desktop,
  server: null,
  nearby:
      nearby ??
      NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: const {},
        devices: const {},
        signalingDevices: const {},
      ),
  sendSessions: const {},
  transfers: FileTransferNotifier(),
  selectedFiles: const [],
  kdeConnectDevices: kdeConnectDevices,
);

void main() {
  ReduxNotifierTester<KdeConnectState> service() => ReduxNotifier.test(
    redux: KdeConnectService(
      persistence: MockPersistenceService(),
      generateIdentity: ({required String deviceName}) async => throw UnimplementedError(),
      startRuntime: (identity, trusted) async => throw UnimplementedError(),
    ),
  );

  test('discovered phone becomes Nearby', () {
    final vm = homeVm(
      kdeConnectDevices: [kdeDevice(id: _phoneId, name: 'Pixel')],
    );
    final device = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(device.detail, 'Nearby');
    expect(device.statusSummary, 'Nearby');
  });

  test('Nearby device is unpaired', () {
    final vm = homeVm(
      kdeConnectDevices: [kdeDevice(id: _phoneId, name: 'Pixel')],
    );
    expect(vm.devices.single.detail, isNot('Paired'));
    expect(vm.devices.single.key, 'kdeconnect:$_phoneId');
  });

  test('paired phone shows Paired', () {
    final vm = homeVm(
      kdeConnectDevices: [kdeDevice(id: _phoneId, name: 'Pixel', paired: true)],
    );
    expect(vm.devices.single.detail, 'Paired');
    expect(vm.devices.single.statusSummary, 'Paired');
  });

  test('incoming request shows accept/reject state', () {
    final it = service();
    it.dispatch(
      KdeConnectApplyEventAction(const RsKdeConnectEvent.incomingPair(deviceId: _phoneId, name: 'Pixel')),
    );
    expect(it.state.incoming?.deviceId, _phoneId);
    expect(it.state.incoming?.name, 'Pixel');
  });

  test('reject leaves device unpaired', () async {
    final it = service();
    it.dispatch(
      KdeConnectReplaceDevicesAction(
        devices: [kdeDevice(id: _phoneId, name: 'Pixel')],
        incoming: const KdeConnectIncomingRequest(deviceId: _phoneId, name: 'Pixel'),
      ),
    );
    await it.dispatchAsync(KdeConnectRejectPairAction(_phoneId));
    expect(it.state.incoming, isNull);
    expect(it.state.devices.single.paired, isFalse);
  });

  test('accept updates incoming request', () async {
    final it = service();
    it.dispatch(
      KdeConnectReplaceDevicesAction(
        devices: [kdeDevice(id: _phoneId, name: 'Pixel')],
        incoming: const KdeConnectIncomingRequest(deviceId: _phoneId, name: 'Pixel'),
      ),
    );
    await it.dispatchAsync(KdeConnectAcceptPairAction(_phoneId));
    expect(it.state.incoming, isNull);
    it.dispatch(
      KdeConnectReplaceDevicesAction(
        devices: [kdeDevice(id: _phoneId, name: 'Pixel', paired: true)],
      ),
    );
    expect(it.state.devices.single.paired, isTrue);
  });

  test('Remove Device clears pairing', () async {
    final it = service();
    it.dispatch(
      KdeConnectReplaceDevicesAction(
        devices: [kdeDevice(id: _phoneId, name: 'Pixel', paired: true)],
      ),
    );
    await it.dispatchAsync(KdeConnectUnpairAction(_phoneId));
    it.dispatch(
      KdeConnectReplaceDevicesAction(
        devices: [kdeDevice(id: _phoneId, name: 'Pixel')],
      ),
    );
    expect(it.state.devices.single.paired, isFalse);
  });

  test('restart-loaded pairing renders correctly', () {
    final vm = homeVm(
      kdeConnectDevices: [kdeDevice(id: _phoneId, name: 'Pixel', paired: true)],
    );
    expect(vm.devices.single.detail, 'Paired');
    expect(vm.devices.single.isKdeConnect, isTrue);
  });

  test('Relay-native device state is unaffected', () {
    final vm = homeVm(
      nearby: NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: const {},
        devices: {_localSend.fingerprint: _localSend},
        signalingDevices: const {},
      ),
      kdeConnectDevices: [kdeDevice(id: _phoneId, name: 'Pixel', paired: true)],
    );
    final localSend = vm.devices.singleWhere((d) => d.isCompatibilityPeer);
    final kde = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(localSend.alias, 'LocalSend Phone');
    expect(localSend.detail, 'Nearby');
    expect(kde.alias, 'Pixel');
    expect(kde.detail, 'Paired');
    expect(localSend.key, isNot(kde.key));
  });
}
