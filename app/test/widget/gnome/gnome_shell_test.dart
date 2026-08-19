import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/ui/relay_capability_vm.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/pages/gnome/gnome_shell.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

void main() {
  final darkTheme = getTheme(ColorMode.localsend, Colors.teal, Brightness.dark, null);

  late MockPersistenceService mockPersistence;

  setUp(() {
    mockPersistence = MockPersistenceService();
    when(mockPersistence.getReceiveHistory()).thenReturn([]);
  });

  const testDevice = RelayDeviceVm(
    key: 'pixel-key',
    alias: 'Pixel 8 Pro',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Ready',
    targetKind: RelayDeviceTargetKind.verifiedRelay,
    relayId: 'relay-pixel-8',
    lanFingerprint: 'FP-PIXEL-8',
    connectionType: RelayConnectionType.local,
    securityState: RelaySecurityState.verifiedRelay,
    battery: RelayBatteryVm(percentage: 85, isCharging: true),
  );

  const testVm = RelayHomeVm(
    selfAlias: 'Fedora Workstation',
    selfDeviceType: DeviceType.desktop,
    presence: RelayPresence.ready,
    selection: RelayPayloadVm(fileCount: 0, totalBytes: 0),
    devices: [testDevice],
    incoming: RelayIncomingVm(hasActiveRequest: false),
    intents: RelayHomeIntents(canSelectPayload: true, canChooseTarget: true),
    activeTransfer: null,
  );

  testWidgets('GnomeShell renders sidebar, header, and device details', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(mockPersistence),
        ],
        child: MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: GnomeShell(
              vm: testVm,
              animationsEnabled: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify presence of sidebar and device
    expect(find.text('NEARBY DEVICES'), findsOneWidget);
    expect(find.text('Pixel 8 Pro'), findsWidgets);
    expect(find.text('Send Files'), findsOneWidget);
    expect(find.text('Send Folder'), findsOneWidget);
    expect(find.text('Clipboard'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
  });
}
