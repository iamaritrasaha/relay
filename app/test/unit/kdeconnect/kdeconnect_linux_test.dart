import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
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
  int? batteryPercentage,
  bool? batteryIsCharging,
  String? networkType,
  int? signalLevel,
  bool connectivityStale = false,
  String transportState = 'local',
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
  batteryPercentage: batteryPercentage,
  batteryIsCharging: batteryIsCharging,
  networkType: networkType,
  signalLevel: signalLevel,
  connectivityStale: connectivityStale,
  incomingCapabilities: const [
    'kdeconnect.clipboard.connect',
    'kdeconnect.ping',
    'kdeconnect.findmyphone.request',
    'kdeconnect.notification.request',
  ],
  outgoingCapabilities: const [
    'kdeconnect.battery',
    'kdeconnect.clipboard.connect',
    'kdeconnect.notification',
  ],
  transportState: connected ? transportState : 'offline',
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
    expect(vm.devices.single.statusSummary, 'Offline');
  });

  test('live transport state drives Local Remote and Offline without duplicating the device', () {
    RelayDeviceVm mapped(String transportState, {bool connected = true}) => RelayHomeVm.kdeDeviceVm(
      kdeDevice(
        id: _phoneId,
        name: 'Pixel',
        paired: true,
        connected: connected,
        transportState: transportState,
      ),
    );

    final local = mapped('local');
    final remoteDirect = mapped('remoteDirect');
    final remoteRelay = mapped('remoteRelay');
    final offline = mapped('offline', connected: false);

    expect(local.statusSummary, 'Local');
    expect(local.connectionType, RelayConnectionType.local);
    expect(remoteDirect.statusSummary, 'Remote');
    expect(remoteDirect.connectionType, RelayConnectionType.direct);
    expect(remoteRelay.statusSummary, 'Remote');
    expect(remoteRelay.connectionType, RelayConnectionType.relayed);
    expect(offline.statusSummary, 'Offline');
    expect({local.key, remoteDirect.key, remoteRelay.key, offline.key}, {'kdeconnect:$_phoneId'});
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

  test('KDE phone with no battery packet shows unavailable/waiting state', () {
    final vm = homeVm(
      kdeConnectDevices: [kdeDevice(id: _phoneId, name: 'Pixel', paired: true, connected: true)],
    );
    final kde = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(kde.battery.hasInfo, isFalse);
    expect(kde.battery.percentage, isNull);
    expect(kde.battery.isCharging, isFalse);
    expect(kde.battery.isStale, isFalse);
  });

  test('KDE phone battery percentage and unplugged state renders', () {
    final vm = homeVm(
      kdeConnectDevices: [
        kdeDevice(
          id: _phoneId,
          name: 'Pixel',
          paired: true,
          connected: true,
          batteryPercentage: 76,
          batteryIsCharging: false,
        ),
      ],
    );
    final kde = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(kde.battery.hasInfo, isTrue);
    expect(kde.battery.percentage, 76);
    expect(kde.battery.isCharging, isFalse);
    expect(kde.battery.isStale, isFalse);
    expect(kde.battery.displayString, '76%');
  });

  test('KDE phone charging state renders', () {
    final vm = homeVm(
      kdeConnectDevices: [
        kdeDevice(
          id: _phoneId,
          name: 'Pixel',
          paired: true,
          connected: true,
          batteryPercentage: 76,
          batteryIsCharging: true,
        ),
      ],
    );
    final kde = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(kde.battery.hasInfo, isTrue);
    expect(kde.battery.percentage, 76);
    expect(kde.battery.isCharging, isTrue);
    expect(kde.battery.isStale, isFalse);
    expect(kde.battery.displayString, '76% · Charging');
  });

  test('KDE phone disconnect marks battery stale', () {
    final vm = homeVm(
      kdeConnectDevices: [
        kdeDevice(
          id: _phoneId,
          name: 'Pixel',
          paired: true,
          connected: false,
          batteryPercentage: 76,
          batteryIsCharging: false,
        ),
      ],
    );
    final kde = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(kde.battery.hasInfo, isTrue);
    expect(kde.battery.percentage, 76);
    expect(kde.battery.isStale, isTrue);
    expect(kde.battery.displayString, '76% · last known');
  });

  test('connectivity report propagates LTE level 3 into the KDE phone VM', () {
    final vm = homeVm(
      kdeConnectDevices: [
        kdeDevice(id: _phoneId, name: 'Pixel', paired: true, connected: true, networkType: 'LTE', signalLevel: 3),
      ],
    );
    final kde = vm.devices.singleWhere((d) => d.isKdeConnect);
    expect(kde.networkType, 'LTE');
    expect(kde.signalLevel, 3);
    expect(kde.connectivityStale, isFalse);
  });

  test('PingReceived event updates state', () {
    final it = service();
    it.dispatch(
      KdeConnectApplyEventAction(
        const RsKdeConnectEvent.pingReceived(deviceId: _phoneId, message: 'Ping test'),
      ),
    );
    expect(it.state.lastPingMessage, 'Ping test');
    expect(it.state.lastPingTimestamp, greaterThan(0));
  });

  test('NotificationsChanged event updates state', () {
    final it = service();
    it.dispatch(
      KdeConnectApplyEventAction(
        const RsKdeConnectEvent.notificationsChanged(
          deviceId: _phoneId,
          notifications: [
            RsKdeNotification(
              id: 'n1',
              appName: 'Signal',
              title: 'Bob',
              text: 'Hey',
              time: null,
              isClearable: true,
              silent: false,
            ),
          ],
        ),
      ),
    );
    expect(it.state.notifications[_phoneId]?.single.title, 'Bob');
  });

  test('SmsChanged stores conversations and messages under the raw Rust device ID', () {
    final it = service();
    final message = RsKdeSmsMessage(
      id: 9_223_372_036,
      threadId: 4_294_967_297,
      addresses: const ['+15550100'],
      body: 'private body not logged',
      date: 1_700_000_000_000,
      messageType: 1,
      read: false,
      attachments: const [],
    );

    it.dispatch(
      KdeConnectApplyEventAction(
        RsKdeConnectEvent.smsChanged(
          deviceId: _phoneId,
          conversations: [
            RsKdeSmsConversation(threadId: message.threadId, participants: message.addresses, latestMessage: message, unreadCount: 1),
          ],
          messages: [message],
        ),
      ),
    );

    expect(it.state.smsConversations[_phoneId]?.single.threadId, 4_294_967_297);
    expect(it.state.smsMessages[_phoneId]?[4_294_967_297]?.single.id, 9_223_372_036);
  });

  test('GNOME-prefixed device key normalizes to the Rust event map key', () {
    expect(kdeConnectDeviceIdFromKey('kdeconnect:$_phoneId'), _phoneId);
    expect(kdeConnectDeviceIdFromKey(_phoneId), _phoneId);
  });

  test('Actions when runtime is disconnected throw no uncaught exception', () async {
    final it = service();
    await expectLater(it.dispatchAsync(KdeConnectPingAction(_phoneId)), completes);
    await expectLater(it.dispatchAsync(KdeConnectFindPhoneAction(_phoneId)), completes);
    await expectLater(it.dispatchAsync(KdeConnectSendClipboardAction('test')), completes);
    await expectLater(it.dispatchAsync(KdeConnectRequestPairAction(_phoneId)), completes);
  });
}
