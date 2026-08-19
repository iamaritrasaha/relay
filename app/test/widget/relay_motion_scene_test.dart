import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/relay_motion/relay_motion_controller.dart';
import 'package:relay_app/widget/relay_motion/relay_spatial_scene.dart';
import 'package:relay_isolates/model/device.dart';

void main() {
  final darkTheme = getTheme(ColorMode.relay, Colors.teal, Brightness.dark, null);

  const verifiedLaptop = RelayDeviceVm(
    key: 'laptop-key-1',
    alias: 'Arch Laptop',
    deviceType: DeviceType.desktop,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby · Local',
    targetKind: RelayDeviceTargetKind.verifiedRelay,
    relayId: 'relay-arch-laptop',
    connectionType: RelayConnectionType.local,
    securityState: RelaySecurityState.verifiedRelay,
    battery: RelayBatteryVm(percentage: 92, isCharging: false),
    capabilities: {
      RelayCapability.files: CapabilityStatus.available,
      RelayCapability.clipboard: CapabilityStatus.available,
      RelayCapability.messages: CapabilityStatus.available,
      RelayCapability.notifications: CapabilityStatus.available,
      RelayCapability.phone: CapabilityStatus.available,
    },
    continuityConnected: true,
  );

  const compatibilityPhone = RelayDeviceVm(
    key: 'compat-phone-key-2',
    alias: 'Guest Phone',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
    targetKind: RelayDeviceTargetKind.unresolvedLan,
    connectionType: RelayConnectionType.local,
    securityState: RelaySecurityState.localSendCompatible,
    capabilities: {
      RelayCapability.files: CapabilityStatus.available,
    },
  );

  group('RelaySpatialLayoutEngine deterministic positions', () {
    test('calculates deterministic resting polar coordinates for devices', () {
      final polar1 = RelaySpatialLayoutEngine.calculatePolarResting(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneRadius: 180,
      );

      final polar2 = RelaySpatialLayoutEngine.calculatePolarResting(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneRadius: 180,
      );

      // Deterministic: same inputs yield same output
      expect(polar1.radius, equals(polar2.radius));
      expect(polar1.angle, equals(polar2.angle));
    });

    test('places verified device in primary inner orbit and compatibility device in secondary outer orbit', () {
      final polarVerified = RelaySpatialLayoutEngine.calculatePolarResting(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneRadius: 180,
      );

      final polarCompat = RelaySpatialLayoutEngine.calculatePolarResting(
        device: compatibilityPhone,
        indexInRing: 0,
        totalInRing: 1,
        sceneRadius: 180,
      );

      expect(polarVerified.radius, lessThan(polarCompat.radius));
    });

    test('computes self position at center when unfocused and shifted when focused', () {
      const sceneSize = Size(400, 360);
      final unfocusedPos = RelaySpatialLayoutEngine.computeSelfPosition(
        sceneSize: sceneSize,
        focusProgress: 0.0,
        hasFocusedDevice: false,
        ambientPhase: 0.0,
      );

      expect(unfocusedPos.offset.dx, closeTo(200.0, 2.0));
      expect(unfocusedPos.offset.dy, closeTo(180.0, 2.0));

      final focusedPos = RelaySpatialLayoutEngine.computeSelfPosition(
        sceneSize: sceneSize,
        focusProgress: 1.0,
        hasFocusedDevice: true,
        ambientPhase: 0.0,
      );

      expect(focusedPos.offset.dx, lessThan(200.0)); // Shifted left to form paired line
    });
  });

  group('RelaySpatialScene Widget Tests', () {
    testWidgets('renders center self device node and remote device nodes', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop, compatibilityPhone],
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Check self device node
      expect(find.text('Linux Workstation'), findsOneWidget);
      expect(find.text('This Device'), findsOneWidget);

      // Check remote device nodes
      expect(find.text('Arch Laptop'), findsOneWidget);
      expect(find.text('Guest Phone'), findsOneWidget);

      // Check visual badges: Compatibility peer has 'LS' badge
      expect(find.text('LS'), findsOneWidget);
      // Battery on verified laptop
      expect(find.text('92%'), findsOneWidget);
    });

    testWidgets('tapping a remote device focuses it and expands relationship panel', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      RelayDeviceVm? selected;

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: const [verifiedLaptop, compatibilityPhone],
              animationsEnabled: true,
              onDeviceSelected: (d) => selected = d,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tap on Arch Laptop node
      await tester.tap(find.text('Arch Laptop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(selected?.key, equals(verifiedLaptop.key));

      // Relationship capabilities panel emerges
      expect(find.text('Send Files'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Clipboard'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
    });

    testWidgets('reduced-motion mode renders resting positions cleanly without continuous ticker', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              animationsEnabled: false, // Reduced motion
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Linux Workstation'), findsOneWidget);
      expect(find.text('Arch Laptop'), findsOneWidget);
    });
  });
}
