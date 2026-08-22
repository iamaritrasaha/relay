import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/provider/relay_desktop_notification_service.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// Builds a record the way `KdeConnectState.allNotifications` does.
RelayNotificationRecord record(
  String deviceId,
  String id, {
  String deviceName = 'Test Phone',
  String appName = 'app',
  String title = 'title',
  String text = 'text',
  String time = '1000',
}) => RelayNotificationRecord(
  deviceId: deviceId,
  deviceName: deviceName,
  notificationId: id,
  notification: RsKdeNotification(
    id: id,
    appName: appName,
    title: title,
    text: text,
    time: time,
    isClearable: true,
    silent: false,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('com.foresight.app.relay/desktop_notifications');
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      methodCalls.add(methodCall);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('RelayDesktopNotificationService handles sync, insert, update, delete correctly', () async {
    final streamController = StreamController<List<RelayNotificationRecord>>();
    final service = RelayDesktopNotificationService(platform: TargetPlatform.linux);
    service.start(streamController.stream);

    // Initial sync
    streamController.add([record('device1', 'n1', appName: 'app1', title: 'title1', text: 'text1')]);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(methodCalls, isEmpty, reason: 'Initial sync should not trigger any native calls');

    // New notification
    streamController.add([
      record('device1', 'n1', appName: 'app1', title: 'title1', text: 'text1'),
      record('device1', 'n2', appName: 'app2', title: 'title2', text: 'text2', time: '2000'),
    ]);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'showNotification');
    expect(methodCalls.first.arguments['id'], 'device1:n2');
    expect(methodCalls.first.arguments['appName'], 'app2');
    expect(methodCalls.first.arguments['title'], 'title2');
    expect(methodCalls.first.arguments['body'], 'text2');
    methodCalls.clear();

    // Update notification
    streamController.add([
      record('device1', 'n1', appName: 'app1', title: 'title1', text: 'text1'),
      record('device1', 'n2', appName: 'app2', title: 'title2 updated', text: 'text2', time: '2000'),
    ]);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'showNotification');
    expect(methodCalls.first.arguments['id'], 'device1:n2');
    expect(methodCalls.first.arguments['title'], 'title2 updated');
    methodCalls.clear();

    // Identical update (no native call)
    streamController.add([
      record('device1', 'n1', appName: 'app1', title: 'title1', text: 'text1'),
      record('device1', 'n2', appName: 'app2', title: 'title2 updated', text: 'text2', time: '2000'),
    ]);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(methodCalls, isEmpty);

    // Delete notification
    streamController.add([record('device1', 'n1', appName: 'app1', title: 'title1', text: 'text1')]);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'withdrawNotification');
    expect(methodCalls.first.arguments['id'], 'device1:n2');
    methodCalls.clear();

    // Remove device entirely
    streamController.add([]);

    await Future.delayed(const Duration(milliseconds: 10));
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'withdrawNotification');
    expect(methodCalls.first.arguments['id'], 'device1:n1');

    await service.dispose();
    await streamController.close();
  });
}
