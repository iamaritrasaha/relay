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

  const tabletPeer = RelayDeviceVm(
    key: 'tablet-key-3',
    alias: 'Office Tablet',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Nearby',
    targetKind: RelayDeviceTargetKind.verifiedRelay,
    connectionType: RelayConnectionType.local,
    securityState: RelaySecurityState.verifiedRelay,
  );

  group('RelaySpatialLayoutEngine deterministic positions & depth', () {
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

    test('computes depth z-ordering and perspective scale during transfer', () {
      const sceneSize = Size(400, 360);

      // Early orbit (front/side)
      final posFront = RelaySpatialLayoutEngine.computeRemotePosition(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneSize: sceneSize,
        ambientPhase: 0.0,
        focusedDeviceKey: null,
        focusProgress: 0.0,
        transferDeviceKey: verifiedLaptop.key,
        transferProgress: 0.5,
      );

      expect(posFront.isTransferring, isTrue);
      expect(posFront.scale, isNotNull);
    });

    test('other devices recede during active transfer', () {
      const sceneSize = Size(400, 360);

      final bystanderPos = RelaySpatialLayoutEngine.computeRemotePosition(
        device: tabletPeer,
        indexInRing: 1,
        totalInRing: 2,
        sceneSize: sceneSize,
        ambientPhase: 0.0,
        focusedDeviceKey: null,
        focusProgress: 0.0,
        transferDeviceKey: verifiedLaptop.key,
        transferProgress: 0.5,
      );

      expect(bystanderPos.isTransferring, isFalse);
      expect(bystanderPos.opacity, lessThan(0.5));
      expect(bystanderPos.scale, lessThan(1.0));
    });
  });

  group('RelaySpatialScene Phase 2 Transfer Tests', () {
    testWidgets('renders active SEND transfer from center to remote device', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sendTransfer = RelayTransferVm(
        sessionId: 'test-send-1',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.send,
        progress: 0.45,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.sending,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop, compatibilityPhone],
              activeTransfer: sendTransfer,
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Linux Workstation'), findsOneWidget);
      expect(find.text('Arch Laptop'), findsWidgets);
      expect(find.text('Sending to device…'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('renders active RECEIVE transfer from remote device to center', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const receiveTransfer = RelayTransferVm(
        sessionId: 'test-receive-1',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.receive,
        progress: 0.72,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.sending,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop, compatibilityPhone],
              activeTransfer: receiveTransfer,
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Receiving from device…'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('handles progress states: 0%, 50%, 100%, and unknown/null progress', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. 0% progress
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              activeTransfer: RelayTransferVm(
                sessionId: 's-0',
                targetAlias: 'Arch Laptop',
                progress: 0.0,
                deviceKey: 'laptop-key-1',
                phase: RelayDevicePhase.sending,
              ),
              animationsEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0%'), findsOneWidget);

      // 2. 100% progress
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              activeTransfer: RelayTransferVm(
                sessionId: 's-100',
                targetAlias: 'Arch Laptop',
                progress: 1.0,
                deviceKey: 'laptop-key-1',
                phase: RelayDevicePhase.sending,
              ),
              animationsEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('100%'), findsOneWidget);

      // 3. Null / unknown progress (preparing state)
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              activeTransfer: RelayTransferVm(
                sessionId: 's-null',
                targetAlias: 'Arch Laptop',
                progress: null,
                deviceKey: 'laptop-key-1',
                phase: RelayDevicePhase.verifying,
              ),
              animationsEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Arch Laptop'), findsWidgets);
    });

    testWidgets('reduced-motion mode renders static transfer view without continuous orbit', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const transfer = RelayTransferVm(
        sessionId: 'test-rm',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.send,
        progress: 0.60,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.sending,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              activeTransfer: transfer,
              animationsEnabled: false, // Reduced motion
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Linux Workstation'), findsOneWidget);
      expect(find.text('Arch Laptop'), findsWidgets);
      expect(find.text('60%'), findsOneWidget);
    });

    testWidgets('compatibility peer remains visually classified with LS badge', (tester) async {
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
              devices: [compatibilityPhone],
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Guest Phone'), findsOneWidget);
      expect(find.text('LS'), findsOneWidget);
    });

    testWidgets('no duplicate source/destination nodes in scene', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop, tabletPeer],
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Each alias should appear exactly once in the spatial universe
      expect(find.text('Workstation'), findsOneWidget);
      expect(find.text('Arch Laptop'), findsOneWidget);
      expect(find.text('Office Tablet'), findsOneWidget);
    });
  });
}
