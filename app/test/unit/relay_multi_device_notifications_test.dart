import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/relay_desktop_notification_service.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// Multi-device notification ownership.
///
/// Notifications are owned by a *logical device*, keyed by
/// `(deviceId, notificationId)`. Transport (LAN vs Relay WAN), LAN address and
/// WAN EndpointId are routes to that device and never part of the key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phoneA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const phoneB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const tablet = 'cccccccccccccccccccccccccccccccc';

  RsKdeNotification notification(String id, {String title = 'title', String app = 'app'}) => RsKdeNotification(
    id: id,
    appName: app,
    title: title,
    text: 'text',
    time: '1000',
    isClearable: true,
    silent: false,
  );

  RsKdeConnectDevice device(String id, String name) => RsKdeConnectDevice(
    deviceId: id,
    name: name,
    deviceType: 'phone',
    paired: true,
    connected: true,
    incomingPair: false,
    identityMismatch: false,
    connectivityStale: false,
    incomingCapabilities: const [],
    outgoingCapabilities: const [],
    transportState: 'Local',
  );

  KdeConnectState stateWith(Map<String, List<RsKdeNotification>> notifications) => KdeConnectState(
    devices: [
      device(phoneA, 'Galaxy M05'),
      device(phoneB, 'Pixel 8'),
      device(tablet, 'Tab S9'),
    ],
    notifications: notifications,
  );

  group('per-device ownership', () {
    test('1+2+3: notifications from three devices are all stored and all visible globally', () {
      final state = stateWith({
        phoneA: [notification('n1', title: 'From A')],
        phoneB: [notification('n2', title: 'From B')],
        tablet: [notification('n3', title: 'From Tablet')],
      });

      final all = state.allNotifications;

      expect(all, hasLength(3));
      expect(all.map((r) => r.title), containsAll(['From A', 'From B', 'From Tablet']));
      // Source device identity survives the merge.
      expect(all.firstWhere((r) => r.title == 'From A').deviceName, 'Galaxy M05');
      expect(all.firstWhere((r) => r.title == 'From B').deviceName, 'Pixel 8');
      expect(all.firstWhere((r) => r.title == 'From Tablet').deviceName, 'Tab S9');
    });

    test('4+5: each device view contains only that device', () {
      final state = stateWith({
        phoneA: [notification('n1', title: 'From A')],
        phoneB: [notification('n2', title: 'From B')],
      });

      expect(state.notificationsForDevice(phoneA).map((n) => n.title), ['From A']);
      expect(state.notificationsForDevice(phoneB).map((n) => n.title), ['From B']);
      // Accepts the prefixed UI key form too, and never falls back to another device.
      expect(state.notificationsForDevice('kdeconnect:$phoneA').map((n) => n.title), ['From A']);
      expect(state.notificationsForDevice('unknown-device'), isEmpty);
    });

    test('6: the same remote notification id on two devices does not collide', () {
      final state = stateWith({
        phoneA: [notification('42', title: 'Alice')],
        phoneB: [notification('42', title: 'Bob')],
      });

      final all = state.allNotifications;
      expect(all, hasLength(2), reason: 'id 42 on two phones is two distinct notifications');
      expect(all.map((r) => r.key).toSet(), {'$phoneA:42', '$phoneB:42'});
      expect(state.notificationsForDevice(phoneA).single.title, 'Alice');
      expect(state.notificationsForDevice(phoneB).single.title, 'Bob');
    });

    test('7: updating device A leaves device B untouched', () {
      var state = stateWith({
        phoneA: [notification('42', title: 'Alice')],
        phoneB: [notification('42', title: 'Bob')],
      });

      state = state.copyWith(
        notifications: {...state.notifications, phoneA: [notification('42', title: 'Alice edited')]},
      );

      expect(state.notificationsForDevice(phoneA).single.title, 'Alice edited');
      expect(state.notificationsForDevice(phoneB).single.title, 'Bob');
    });

    test('8: dismissing on A does not dismiss the same id on B', () {
      var state = stateWith({
        phoneA: [notification('42', title: 'Alice')],
        phoneB: [notification('42', title: 'Bob')],
      });

      state = state.copyWith(notifications: {...state.notifications, phoneA: const []});

      expect(state.notificationsForDevice(phoneA), isEmpty);
      expect(state.notificationsForDevice(phoneB), hasLength(1));
      expect(state.allNotifications.single.deviceId, phoneB);
    });

    test('9: a device disconnecting never clears another device', () {
      var state = stateWith({
        phoneA: [notification('n1')],
        phoneB: [notification('n2')],
      });

      // Disconnect drops A's live records only; B's map entry is untouched.
      final remaining = Map<String, List<RsKdeNotification>>.from(state.notifications)..remove(phoneA);
      state = state.copyWith(notifications: remaining);

      expect(state.notificationsForDevice(phoneA), isEmpty);
      expect(state.notificationsForDevice(phoneB), hasLength(1));
      expect(state.allNotifications.single.deviceId, phoneB);
    });

    test('10+11: Local <-> Remote transitions neither clear nor duplicate records', () {
      // The transport never appears in the key, so the identical state that
      // described a Local device describes it Remote as well.
      final local = stateWith({phoneA: [notification('n1', title: 'Alice')]});
      final remote = stateWith({phoneA: [notification('n1', title: 'Alice')]});

      expect(remote.allNotifications, local.allNotifications);
      expect(remote.allNotifications, hasLength(1));
      expect(remote.allNotifications.single.key, '$phoneA:n1');
      // And back again.
      expect(stateWith({phoneA: [notification('n1', title: 'Alice')]}).allNotifications, local.allNotifications);
    });
  });

  group('banner routing', () {
    const channel = MethodChannel('com.foresight.app.relay/desktop_notifications');
    final methodCalls = <MethodCall>[];

    setUp(() {
      methodCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        methodCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    RelayNotificationRecord record(String deviceId, String deviceName, String id, {String title = 'title'}) => RelayNotificationRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      notificationId: id,
      notification: notification(id, title: title),
    );

    test('a second device connecting later does not replay its backlog as banners', () async {
      final controller = StreamController<List<RelayNotificationRecord>>();
      final service = RelayDesktopNotificationService(platform: TargetPlatform.linux);
      service.start(controller.stream);

      // Phone A connects first and syncs silently.
      controller.add([record(phoneA, 'Galaxy M05', 'a1')]);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(methodCalls, isEmpty);

      // Phone B connects later with an existing backlog. It must sync silently
      // too -- initial-sync suppression is per device, not one global flag.
      controller.add([record(phoneA, 'Galaxy M05', 'a1'), record(phoneB, 'Pixel 8', 'b1')]);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(methodCalls, isEmpty, reason: "B's backlog is not new activity");

      // A genuinely new notification on B does raise a banner.
      controller.add([
        record(phoneA, 'Galaxy M05', 'a1'),
        record(phoneB, 'Pixel 8', 'b1'),
        record(phoneB, 'Pixel 8', 'b2', title: 'live'),
      ]);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(methodCalls, hasLength(1));
      expect(methodCalls.single.arguments['id'], '$phoneB:b2');

      await service.dispose();
      await controller.close();
    });

    test('every banner carries the originating device name', () async {
      final controller = StreamController<List<RelayNotificationRecord>>();
      final service = RelayDesktopNotificationService(platform: TargetPlatform.linux);
      service.start(controller.stream);

      controller.add([record(phoneA, 'Galaxy M05', 'a1')]);
      await Future.delayed(const Duration(milliseconds: 10));
      controller.add([record(phoneA, 'Galaxy M05', 'a1'), record(phoneA, 'Galaxy M05', 'a2', title: 'new')]);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(methodCalls.single.arguments['deviceName'], 'Galaxy M05');

      await service.dispose();
      await controller.close();
    });

    test('the same id on two devices produces two independent banners', () async {
      final controller = StreamController<List<RelayNotificationRecord>>();
      final service = RelayDesktopNotificationService(platform: TargetPlatform.linux);
      service.start(controller.stream);

      // Both devices sync silently first.
      controller.add([record(phoneA, 'Galaxy M05', 'seed'), record(phoneB, 'Pixel 8', 'seed')]);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(methodCalls, isEmpty);

      controller.add([
        record(phoneA, 'Galaxy M05', 'seed'),
        record(phoneB, 'Pixel 8', 'seed'),
        record(phoneA, 'Galaxy M05', '42', title: 'Alice'),
        record(phoneB, 'Pixel 8', '42', title: 'Bob'),
      ]);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(methodCalls, hasLength(2));
      expect(methodCalls.map((c) => c.arguments['id']).toSet(), {'$phoneA:42', '$phoneB:42'});
      expect(methodCalls.map((c) => c.arguments['deviceName']).toSet(), {'Galaxy M05', 'Pixel 8'});

      await service.dispose();
      await controller.close();
    });

    test('withdrawing on one device leaves the other device banner alone', () async {
      final controller = StreamController<List<RelayNotificationRecord>>();
      final service = RelayDesktopNotificationService(platform: TargetPlatform.linux);
      service.start(controller.stream);

      controller.add([record(phoneA, 'Galaxy M05', '42'), record(phoneB, 'Pixel 8', '42')]);
      await Future.delayed(const Duration(milliseconds: 10));
      methodCalls.clear();

      // A dismisses id 42; B still has its own 42.
      controller.add([record(phoneB, 'Pixel 8', '42')]);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(methodCalls, hasLength(1));
      expect(methodCalls.single.method, 'withdrawNotification');
      expect(methodCalls.single.arguments['id'], '$phoneA:42');

      await service.dispose();
      await controller.close();
    });

    test('12: a banner key resolves back to the logical device that produced it', () {
      final origin = splitNotificationKey('$phoneA:0|com.whatsapp|42');

      expect(origin, isNotNull);
      expect(origin!.deviceId, phoneA);
      // Split on the first separator only -- remote ids may contain colons.
      expect(origin.notificationId, '0|com.whatsapp|42');

      // A key with no device half has nowhere correct to route and is refused.
      expect(splitNotificationKey(':42'), isNull);
      expect(splitNotificationKey('no-separator'), isNull);
      expect(splitNotificationKey('$phoneA:'), isNull);
      expect(splitNotificationKey(null), isNull);
    });
  });
}
