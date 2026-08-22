import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_shell.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/device_info_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/ui/dynamic_colors.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/device_info_result.dart';

import 'mocks_helper.dart';

/// Review renders of the Relay GNOME/Yaru desktop shell.
///
/// These exist to be looked at: they are the only way to inspect the desktop
/// composition at each supported viewport without a running session. The device
/// lists here are presentation fixtures for the render only — the app itself
/// never fabricates devices, and nothing in this file is reachable at runtime.
void main() {
  const reviewFontFamily = 'RelayReview';

  const textFonts = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ];
  const iconFonts = ['fonts/MaterialIcons-Regular.otf', 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf'];

  Future<void> loadFamily(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var loaded = 0;
    for (final path in paths) {
      final file = File(path);
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
        loaded++;
      }
    }
    if (loaded > 0) {
      await loader.load();
    }
  }

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (arguments, sink) {},
        onCancel: (arguments) {},
      ),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, String>{
        'appName': 'Relay',
        'packageName': 'com.foresight.app.relay',
        'version': '0.2.0',
        'buildNumber': '63',
      },
    );
    messenger.setMockStreamHandler(
      const EventChannel('yaru_window/events'),
      MockStreamHandler.inline(
        onListen: (arguments, sink) {},
        onCancel: (arguments) {},
      ),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window'),
      (call) async => <String, dynamic>{
        'isMaximized': false,
        'isActive': true,
        'isFullscreen': false,
        'isMinimized': false,
      },
    );

    await loadFamily(reviewFontFamily, textFonts);
    await loadFamily('Roboto', textFonts);
    await loadFamily('Geist', textFonts);
    await loadFamily('MaterialIcons', iconFonts);
  });

  late ReviewPersistenceService persistence;

  setUp(() {
    persistence = ReviewPersistenceService();
    stubReviewPersistence(persistence);
  });

  const phone = RelayDeviceVm(
    key: 'kdeconnect:redmi',
    alias: 'Redmi Note 14 Pro 5G',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    battery: RelayBatteryVm(percentage: 77),
    networkType: 'LTE',
    signalLevel: 2,
    deviceModel: 'Android 14',
    canPing: true,
    canFindDevice: true,
    capabilities: {
      RelayCapability.clipboard: CapabilityStatus.available,
      RelayCapability.battery: CapabilityStatus.available,
      RelayCapability.notifications: CapabilityStatus.available,
      RelayCapability.phone: CapabilityStatus.available,
    },
  );

  const tablet = RelayDeviceVm(
    key: 'relay:tablet',
    alias: 'Pixel Tablet',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Ready',
    targetKind: RelayDeviceTargetKind.pairedRelay,
    relayId: 'relay-tablet',
    battery: RelayBatteryVm(percentage: 41, isCharging: true),
  );

  const laptop = RelayDeviceVm(
    key: 'relay:thinkpad',
    alias: 'ThinkPad X1',
    deviceType: DeviceType.desktop,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Ready',
    targetKind: RelayDeviceTargetKind.verifiedRelay,
    relayId: 'relay-thinkpad',
  );

  /// A device that was known and is no longer reachable.
  const offlinePhone = RelayDeviceVm(
    key: 'relay:pixel7',
    alias: 'Pixel 7 Pro',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Paired',
    targetKind: RelayDeviceTargetKind.pairedRelay,
    relayId: 'relay-pixel-7',
    connectionType: RelayConnectionType.relayed,
  );

  RelayHomeVm vmWith(List<RelayDeviceVm> devices) => RelayHomeVm(
    selfAlias: 'Falcon',
    selfDeviceType: DeviceType.desktop,
    presence: RelayPresence.ready,
    selection: const RelayPayloadVm(fileCount: 0, totalBytes: 0),
    devices: devices,
    incoming: const RelayIncomingVm(hasActiveRequest: false),
    intents: const RelayHomeIntents(canSelectPayload: true, canChooseTarget: true),
  );

  Future<void> render(WidgetTester tester, RelayHomeVm vm, Size viewport, {Brightness brightness = Brightness.dark}) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = getTheme(ColorMode.relay, Colors.blue, brightness, null);

    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
          dynamicColorsProvider.overrideWithValue(null),
          deviceRawInfoProvider.overrideWithValue(
            DeviceInfoResult(deviceType: DeviceType.desktop, deviceModel: 'Linux', androidSdkInt: null),
          ),
          parentIsolateProvider.overrideWithNotifier((ref) => ReviewIsolateController()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: reviewFontFamily),
              primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: reviewFontFamily),
            ),
            home: Scaffold(body: GnomeShell(vm: vm, animationsEnabled: false)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final viewport in const [Size(1280, 720), Size(1440, 900), Size(1920, 1080)]) {
    testWidgets('yaru one device ${viewport.width.toInt()}x${viewport.height.toInt()}', (tester) async {
      await render(tester, vmWith(const [phone]), viewport);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/relay_yaru/one_device_${viewport.width.toInt()}x${viewport.height.toInt()}.png'),
      );
    });
  }

  testWidgets('yaru connected tablet wide 1920x1080', (tester) async {
    await render(tester, vmWith(const [tablet]), const Size(1920, 1080));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/connected_tablet_1920x1080.png'));
  });

  testWidgets('yaru narrow vertical stage 460x800', (tester) async {
    await render(tester, vmWith(const [phone]), const Size(460, 800));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/narrow_stage_460x800.png'));
  });

  testWidgets('yaru light mode 1440x900', (tester) async {
    await render(tester, vmWith(const [phone]), const Size(1440, 900), brightness: Brightness.light);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/light_mode_1440x900.png'));
  });

  testWidgets('yaru multi device dock 1920x1080', (tester) async {
    await render(tester, vmWith(const [phone, tablet, laptop, offlinePhone]), const Size(1920, 1080));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/multi_device_1920x1080.png'));
  });

  testWidgets('yaru focus moves to another device', (tester) async {
    await render(tester, vmWith(const [phone, tablet, laptop, offlinePhone]), const Size(1920, 1080));
    await tester.tap(find.text('ThinkPad X1').first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/focus_thinkpad_1920x1080.png'));
  });

  testWidgets('yaru offline device focused', (tester) async {
    await render(tester, vmWith(const [offlinePhone, phone]), const Size(1440, 900));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/offline_1440x900.png'));
  });

  testWidgets('yaru empty state 1280x720', (tester) async {
    await render(tester, vmWith(const []), const Size(1280, 720));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/relay_yaru/empty_1280x720.png'));
  });
}
