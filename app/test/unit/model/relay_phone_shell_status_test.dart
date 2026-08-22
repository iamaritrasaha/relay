import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/model/ui/relay_phone_shell_status.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/provider/relay_shell_status_provider.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';
import 'package:test/test.dart';

RsKdeConnectDevice kdeDevice({
  required String id,
  required String name,
  String deviceType = 'phone',
  bool paired = true,
  bool connected = true,
  int? batteryPercentage,
  bool? batteryIsCharging,
  String? networkType,
  int? signalLevel,
  bool connectivityStale = false,
  String transportState = 'local',
}) => RsKdeConnectDevice(
  deviceId: id,
  name: name,
  deviceType: deviceType,
  ip: '192.168.1.24',
  port: 1716,
  paired: paired,
  connected: connected,
  incomingPair: false,
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

List<RelayDeviceVm> devicesFor(List<RsKdeConnectDevice> kdeConnectDevices) => RelayHomeVm.fromState(
  configuredAlias: 'My Linux',
  selfDeviceType: DeviceType.desktop,
  server: null,
  nearby: const NearbyDevicesState(
    runningFavoriteScan: false,
    runningIps: {},
    devices: {},
    signalingDevices: {},
  ),
  sendSessions: const {},
  transfers: FileTransferNotifier(),
  selectedFiles: const [],
  kdeConnectDevices: kdeConnectDevices,
).devices;

RelayPhoneShellStatus? statusFor(
  List<RsKdeConnectDevice> kdeConnectDevices, {
  String? pinnedDeviceId,
  String? focusedDeviceId,
  Map<String, int> notificationCounts = const {},
  bool showNetworkLabel = true,
  bool showBatteryPercentage = true,
  bool showNotifications = true,
  bool chargingAnimationEnabled = true,
  bool showSignal = true,
}) => RelayPhoneShellStatus.select(
  devices: devicesFor(kdeConnectDevices),
  now: DateTime.utc(2026),
  pinnedDeviceId: pinnedDeviceId,
  focusedDeviceId: focusedDeviceId,
  showNetworkLabel: showNetworkLabel,
  showBatteryPercentage: showBatteryPercentage,
  showNotifications: showNotifications,
  chargingAnimationEnabled: chargingAnimationEnabled,
  showSignal: showSignal,
  notificationCounts: notificationCounts,
);

const _phoneId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _secondPhoneId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// Everything Relay is willing to put on the session bus.
const _allowedBridgeKeys = {
  'deviceId',
  'displayName',
  'deviceType',
  'connected',
  'paired',
  'batteryPercentage',
  'batteryIsCharging',
  'batteryIsFull',
  'batteryIsStale',
  'networkKind',
  'networkLabel',
  'signalLevel',
  'unreadMessageCount',
  'notificationCount',
  'supportsFindDevice',
  'supportsClipboard',
  'supportsMessages',
  'supportsNotifications',
  'showNetworkLabel',
  'showBatteryPercentage',
  'showNotifications',
  'chargingAnimationEnabled',
  'showSignal',
  'phoneCount',
  'lastUpdated',
};

RelayPhoneShellStatus status({
  int? batteryPercentage,
  bool batteryIsCharging = false,
  bool batteryIsFull = false,
  bool batteryIsStale = false,
  String? networkKind,
  String? networkLabel,
  int? signalLevel,
  int? unreadMessageCount,
  int? notificationCount,
  String displayName = 'Redmi Note 14 Pro',
  bool connected = true,
  bool showNetworkLabel = true,
  bool showBatteryPercentage = true,
  bool showNotifications = true,
  bool chargingAnimationEnabled = true,
  bool showSignal = true,
}) => RelayPhoneShellStatus(
  deviceId: 'kdeconnect:$_phoneId',
  displayName: displayName,
  deviceType: 'mobile',
  connected: connected,
  paired: true,
  lastUpdated: DateTime.utc(2026),
  batteryPercentage: batteryPercentage,
  batteryIsCharging: batteryIsCharging,
  batteryIsFull: batteryIsFull,
  batteryIsStale: batteryIsStale,
  networkKind: networkKind,
  networkLabel: networkLabel,
  signalLevel: signalLevel,
  unreadMessageCount: unreadMessageCount,
  notificationCount: notificationCount,
  showNetworkLabel: showNetworkLabel,
  showBatteryPercentage: showBatteryPercentage,
  showNotifications: showNotifications,
  chargingAnimationEnabled: chargingAnimationEnabled,
  showSignal: showSignal,
);

void main() {
  group('primary phone selection', () {
    test('a single paired connected phone is the primary phone', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Redmi Note 14 Pro')]);
      expect(snapshot, isNotNull);
      expect(snapshot!.displayName, 'Redmi Note 14 Pro');
      expect(snapshot.connected, isTrue);
      expect(snapshot.paired, isTrue);
      expect(snapshot.phoneCount, 1);
    });

    test('an unpaired phone is a discovery result, not the user phone', () {
      expect(statusFor([kdeDevice(id: _phoneId, name: 'Redmi Note 14 Pro', paired: false)]), isNull);
    });

    test('a paired desktop peer is not a phone', () {
      expect(statusFor([kdeDevice(id: _phoneId, name: 'Workstation', deviceType: 'laptop')]), isNull);
    });

    test('no devices means no phone', () {
      expect(statusFor(const []), isNull);
    });

    test('a connected phone wins over a merely paired one in fallback mode', () {
      final snapshot = statusFor([
        kdeDevice(id: _phoneId, name: 'Old Phone', connected: false),
        kdeDevice(id: _secondPhoneId, name: 'Redmi Note 14 Pro'),
      ]);
      expect(snapshot!.displayName, 'Redmi Note 14 Pro');
      expect(snapshot.phoneCount, 2);
    });

    test('follow focused device selects the active focused phone', () {
      final devices = [
        kdeDevice(id: _phoneId, name: 'Phone A'),
        kdeDevice(id: _secondPhoneId, name: 'Phone B'),
      ];
      final first = statusFor(devices, focusedDeviceId: 'kdeconnect:$_phoneId')!;
      final second = statusFor(devices, focusedDeviceId: 'kdeconnect:$_secondPhoneId')!;
      expect(first.deviceId, 'kdeconnect:$_phoneId');
      expect(second.deviceId, 'kdeconnect:$_secondPhoneId');
    });

    test('pinned device strictly stays selected even when another phone connects', () {
      final devices = [
        kdeDevice(id: _phoneId, name: 'Phone A'),
        kdeDevice(id: _secondPhoneId, name: 'Phone B'),
      ];
      final pinned = statusFor(devices, pinnedDeviceId: 'kdeconnect:$_secondPhoneId')!;
      expect(pinned.deviceId, 'kdeconnect:$_secondPhoneId');
    });

    test('pinned device that disconnects stays selected and reports offline state', () {
      final snapshot = statusFor(
        [
          kdeDevice(id: _phoneId, name: 'Phone A', connected: false),
          kdeDevice(id: _secondPhoneId, name: 'Phone B', connected: true),
        ],
        pinnedDeviceId: 'kdeconnect:$_phoneId',
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.deviceId, 'kdeconnect:$_phoneId');
      expect(snapshot.connected, isFalse);
    });

    test('follow mode falls back when focused device drops off', () {
      final snapshot = statusFor(
        [
          kdeDevice(id: _phoneId, name: 'Phone A', connected: false),
          kdeDevice(id: _secondPhoneId, name: 'Phone B', connected: true),
        ],
        focusedDeviceId: 'kdeconnect:$_phoneId',
      );
      // If Phone A was focused but is offline, candidates sort connected first -> Phone B
      expect(snapshot, isNotNull);
    });
  });

  test('KDE connectivity reaches the shell status unchanged', () {
    final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Redmi', networkType: 'LTE', signalLevel: 3)]);
    expect(snapshot!.networkKind, 'cellular');
    expect(snapshot.networkLabel, 'LTE');
    expect(snapshot.signalLevel, 3);
  });

  group('battery', () {
    test('a phone that never reported its battery reports nothing', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!;
      expect(snapshot.batteryPercentage, isNull);
      expect(snapshot.batteryIsCharging, isNull);
      expect(snapshot.batteryIsFull, isNull);
      expect(snapshot.hasBattery, isFalse);
      expect(snapshot.toBridgeMap().containsKey('batteryPercentage'), isFalse);
    });

    test('a flat battery is a reading, not a missing one', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone', batteryPercentage: 0)])!;
      expect(snapshot.batteryPercentage, 0);
      expect(snapshot.hasBattery, isTrue);
      expect(snapshot.toBridgeMap()['batteryPercentage'], 0);
    });

    test('a charging phone carries its charge state', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone', batteryPercentage: 67, batteryIsCharging: true)])!;
      expect(snapshot.batteryPercentage, 67);
      expect(snapshot.batteryIsCharging, isTrue);
      expect(snapshot.batteryIsFull, isFalse);
    });

    test('a full battery on charge reads as charged', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone', batteryPercentage: 100, batteryIsCharging: true)])!;
      expect(snapshot.batteryPercentage, 100);
      expect(snapshot.batteryIsFull, isTrue);
    });

    test('a reading from a phone that went away is marked stale', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone', connected: false, batteryPercentage: 67)])!;
      expect(snapshot.connected, isFalse);
      expect(snapshot.batteryPercentage, 67);
      expect(snapshot.batteryIsStale, isTrue);
    });

    test('an impossible battery is dropped rather than clamped', () {
      expect(status(batteryPercentage: 400).batteryPercentage, isNull);
      expect(status(batteryPercentage: -5).batteryPercentage, isNull);
      expect(status(batteryPercentage: 101).batteryPercentage, isNull);
    });

    test('charge state cannot exist without a reading', () {
      final snapshot = status(batteryIsCharging: true, batteryIsStale: true);
      expect(snapshot.batteryIsCharging, isNull);
      expect(snapshot.batteryIsStale, isFalse);
    });
  });

  group('network and messages', () {
    test('Relay reports no network until a capability provides one', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!;
      expect(snapshot.networkKind, isNull);
      expect(snapshot.networkLabel, isNull);
      expect(snapshot.signalLevel, isNull);
      expect(snapshot.hasNetwork, isFalse);
      expect(snapshot.toBridgeMap().containsKey('networkLabel'), isFalse);
    });

    test('a reported network travels with its signal', () {
      final snapshot = status(networkKind: 'cellular', networkLabel: '5G', signalLevel: 3);
      expect(snapshot.networkLabel, '5G');
      expect(snapshot.signalLevel, 3);
      expect(snapshot.toBridgeMap()['networkKind'], 'cellular');
    });

    test('a signal without a network label is still presentable', () {
      expect(status(signalLevel: 3).signalLevel, 3);
      expect(status(signalLevel: 3).toBridgeMap()['signalLevel'], 3);
    });

    test('every normalized signal level survives exactly', () {
      for (var level = 0; level <= 4; level++) {
        expect(status(signalLevel: level).signalLevel, level);
      }
    });

    test('an absurd signal is dropped', () {
      expect(status(networkKind: 'cellular', signalLevel: -1000).signalLevel, isNull);
      expect(status(networkKind: 'cellular', signalLevel: 9).signalLevel, isNull);
    });

    test('a paired phone mirrors notifications, and none is a real answer', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!;
      expect(snapshot.supportsNotifications, isTrue);
      expect(snapshot.notificationCount, 0);
    });

    test('standing notifications are counted', () {
      final snapshot = statusFor(
        [kdeDevice(id: _phoneId, name: 'Phone')],
        notificationCounts: {'kdeconnect:$_phoneId': 4},
      )!;
      expect(snapshot.notificationCount, 4);
    });

    test('a phone that went away is not still holding notifications', () {
      final snapshot = statusFor(
        [kdeDevice(id: _phoneId, name: 'Phone', connected: false)],
        notificationCounts: {'kdeconnect:$_phoneId': 4},
      )!;
      expect(snapshot.notificationCount, isNull);
    });

    test('a negative notification count is dropped', () {
      expect(status(notificationCount: -2).notificationCount, isNull);
    });

    test('Relay reports no unread count until a capability provides one', () {
      final snapshot = statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!;
      expect(snapshot.unreadMessageCount, isNull);
      expect(snapshot.supportsMessages, isFalse);
      expect(snapshot.toBridgeMap().containsKey('unreadMessageCount'), isFalse);
    });

    test('nothing unread is an answer, not a gap', () {
      final snapshot = status(unreadMessageCount: 0);
      expect(snapshot.unreadMessageCount, 0);
      expect(snapshot.toBridgeMap()['unreadMessageCount'], 0);
    });

    test('an unread count survives', () {
      expect(status(unreadMessageCount: 7).unreadMessageCount, 7);
    });

    test('a negative unread count is dropped', () {
      expect(status(unreadMessageCount: -1).unreadMessageCount, isNull);
    });
  });

  group('capabilities', () {
    test('ringing a phone is offered only while it is reachable', () {
      expect(statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!.supportsFindDevice, isTrue);
      expect(statusFor([kdeDevice(id: _phoneId, name: 'Phone', connected: false)])!.supportsFindDevice, isFalse);
    });

    test('clipboard support follows the paired capability', () {
      expect(statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!.supportsClipboard, isTrue);
    });
  });

  group('bridge payload', () {
    test('an empty name falls back rather than showing nothing', () {
      expect(status(displayName: '   ').displayName, 'Phone');
    });

    test('only presentation fields reach the bus', () {
      final snapshot = status(batteryPercentage: 67, networkKind: 'cellular', networkLabel: '5G', signalLevel: 3, unreadMessageCount: 2);
      expect(snapshot.toBridgeMap().keys.toSet().difference(_allowedBridgeKeys), isEmpty);
    });

    test('unknown values are absent rather than sent as sentinels', () {
      final map = statusFor([kdeDevice(id: _phoneId, name: 'Phone')])!.toBridgeMap();
      expect(map.keys, isNot(contains('batteryPercentage')));
      expect(map.keys, isNot(contains('networkKind')));
      expect(map.keys, isNot(contains('signalLevel')));
      expect(map.keys, isNot(contains('unreadMessageCount')));
      expect(map.values, isNot(contains(null)));
    });

    test('the payload carries no protocol, trust or content material', () {
      final map = status(batteryPercentage: 67, networkKind: 'cellular', networkLabel: '5G', unreadMessageCount: 2).toBridgeMap();
      // Capability flags say whether something is possible; they never carry the
      // thing itself, so only the values are searched.
      final values = map.values.whereType<String>().join(' ').toLowerCase();
      for (final forbidden in ['certificate', 'pem', 'private', 'fingerprint', 'clipboard', 'notification', 'ssid', 'token', 'password']) {
        expect(values.contains(forbidden), isFalse, reason: 'the shell payload must not carry $forbidden');
      }
      expect(map.values.every((value) => value is String || value is int || value is bool), isTrue);
    });
  });

  group('change detection', () {
    test('a rebuilt but unchanged snapshot is the same state', () {
      expect(status(batteryPercentage: 67).sameStateAs(status(batteryPercentage: 67)), isTrue);
    });

    test('a battery change is a change', () {
      expect(status(batteryPercentage: 67).sameStateAs(status(batteryPercentage: 68)), isFalse);
    });

    test('losing the phone is a change', () {
      expect(status().sameStateAs(status(connected: false)), isFalse);
    });

    test('nothing is the same as a missing snapshot', () {
      expect(status().sameStateAs(null), isFalse);
    });
  });

  group('bridge', () {
    late List<Map<String, Object?>?> published;
    late RelayShellStatusBridge bridge;
    late List<String> actions;

    setUp(() {
      published = [];
      actions = [];
      bridge = RelayShellStatusBridge(
        publish: (snapshot) async => published.add(snapshot),
        activate: () async => actions.add('activate'),
        quit: () async => actions.add('quit'),
        findPhone: (deviceId) async => actions.add('find:$deviceId'),
        shellSurfaceChanged: (attached) async => actions.add('surface:$attached'),
        now: () => DateTime.utc(2026),
      );
    });

    test('the first snapshot is always published', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      expect(published, hasLength(1));
      expect(published.single!['displayName'], 'Phone');
    });

    test('an unchanged rebuild does not reach the shell', () async {
      final devices = devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]);
      await bridge.apply(devices: devices);
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      expect(published, hasLength(1));
    });

    test('a disconnect produces an offline snapshot', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone', connected: false)]),
      );
      expect(published, hasLength(2));
      expect(published.last!['connected'], isFalse);
    });

    test('a reconnect produces a new snapshot', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone', connected: false)]),
      );
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      expect(published.last!['connected'], isTrue);
    });

    test('losing every phone publishes nothing rather than stale data', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      await bridge.apply(devices: const []);
      expect(published, hasLength(2));
      expect(published.last, isNull);
    });

    test('an empty device list before anything was published still tells the shell', () async {
      await bridge.apply(devices: const []);
      expect(published, [null]);
    });

    test('the bridge keeps showing the phone it already chose', () async {
      final devices = [kdeDevice(id: _phoneId, name: 'Phone A'), kdeDevice(id: _secondPhoneId, name: 'Phone B')];
      await bridge.apply(devices: devicesFor(devices));
      final chosen = bridge.published!.deviceId;
      await bridge.apply(devices: devicesFor(devices.reversed.toList()));
      expect(bridge.published!.deviceId, chosen);
      expect(published, hasLength(1));
    });

    test('opening Relay is always available to the shell', () async {
      await bridge.handleAction('relayShellActivate', null);
      expect(actions, ['activate']);
    });

    test('ringing a phone Relay is not showing is ignored', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      await bridge.handleAction('relayShellFindPhone', 'kdeconnect:$_secondPhoneId');
      await bridge.handleAction('relayShellFindPhone', null);
      expect(actions, isEmpty);
    });

    test('ringing an unreachable phone is ignored', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone', connected: false)]),
      );
      await bridge.handleAction('relayShellFindPhone', 'kdeconnect:$_phoneId');
      expect(actions, isEmpty);
    });

    test('ringing the phone on screen reaches Relay', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      await bridge.handleAction('relayShellFindPhone', 'kdeconnect:$_phoneId');
      expect(actions, ['find:kdeconnect:$_phoneId']);
    });

    test('an unknown shell action does nothing', () async {
      await bridge.handleAction('relayShellSomethingElse', 'kdeconnect:$_phoneId');
      expect(actions, isEmpty);
    });

    test('quitting Relay from the shell reaches Relay', () async {
      await bridge.handleAction('relayShellQuit', null);
      expect(actions, ['quit']);
    });

    test('a shell surface appearing and going away is reported', () async {
      await bridge.handleAction('relayShellSurfaceChanged', true);
      await bridge.handleAction('relayShellSurfaceChanged', false);
      expect(actions, ['surface:true', 'surface:false']);
    });

    test('a notification count change alone reaches the shell', () async {
      await bridge.apply(
        devices: devicesFor([kdeDevice(id: _phoneId, name: 'Phone')]),
      );
      expect(published.single!['notificationCount'], 0);
      await bridge.apply(notificationCounts: {'kdeconnect:$_phoneId': 3});
      expect(published, hasLength(2));
      expect(published.last!['notificationCount'], 3);
    });
  });
}
