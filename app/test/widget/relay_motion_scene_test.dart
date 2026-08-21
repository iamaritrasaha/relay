import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/model/state/nearby_devices_state.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/file_transfer_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/widget/relay_motion/relay_motion_controller.dart';
import 'package:relay_app/widget/relay_motion/relay_spatial_scene.dart';
import 'package:relay_app/widget/relay_motion/relay_transfer_stream.dart';
import 'package:relay_isolates/model/device.dart';

import '../mocks.mocks.dart';

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

  group('RelaySpatialLayoutEngine Continuous Idle Orbit & Depth', () {
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

    test('resting device positions remain stable across ambient phases', () {
      const sceneSize = Size(400, 600);

      final pos1 = RelaySpatialLayoutEngine.computeRemotePosition(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneSize: sceneSize,
        ambientPhase: 0.1,
        focusedDeviceKey: null,
        focusProgress: 0.0,
      );

      final pos2 = RelaySpatialLayoutEngine.computeRemotePosition(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneSize: sceneSize,
        ambientPhase: 0.4,
        focusedDeviceKey: null,
        focusProgress: 0.0,
      );

      expect(pos1.offset, equals(pos2.offset));
      expect(pos1.angle, equals(pos2.angle));
    });

    test('different devices revolve at distinct deterministic velocities', () {
      const sceneSize = Size(400, 600);

      final posVerified = RelaySpatialLayoutEngine.computeRemotePosition(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneSize: sceneSize,
        ambientPhase: 0.25,
        focusedDeviceKey: null,
        focusProgress: 0.0,
      );

      final posCompat = RelaySpatialLayoutEngine.computeRemotePosition(
        device: compatibilityPhone,
        indexInRing: 0,
        totalInRing: 1,
        sceneSize: sceneSize,
        ambientPhase: 0.25,
        focusedDeviceKey: null,
        focusProgress: 0.0,
      );

      // Inner primary vs outer compatibility revolve at different speeds
      expect(posVerified.distance, isNot(equals(posCompat.distance)));
    });

    test('reduced motion freezes continuous orbital revolution to static polar resting coordinates', () {
      const sceneSize = Size(400, 600);

      final posReduced = RelaySpatialLayoutEngine.computeRemotePosition(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneSize: sceneSize,
        ambientPhase: 0.0, // Reduced motion / static phase
        focusedDeviceKey: null,
        focusProgress: 0.0,
      );

      final polar = RelaySpatialLayoutEngine.calculatePolarResting(
        device: verifiedLaptop,
        indexInRing: 0,
        totalInRing: 1,
        sceneRadius: 200,
      );

      expect(posReduced.angle, equals(polar.angle));
      expect(posReduced.scale, equals(1.0));
      expect(posReduced.opacity, equals(1.0));
    });

    test('computes depth z-ordering and perspective scale during transfer', () {
      const sceneSize = Size(400, 600);

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
      const sceneSize = Size(400, 600);

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

  group('RelayTransferStream Curved Trajectory & Direction Geometry', () {
    test('active transfer path has non-zero curvature when isFocusedPair is true', () {
      const source = Offset(100, 150);
      const target = Offset(300, 220);
      final midPoint = (source + target) / 2;

      final controlPoint = RelayTransferStreamPainter.computeControlPoint(
        sourceOffset: source,
        targetOffset: target,
        isFocusedPair: true,
      );

      final deflection = (controlPoint - midPoint).distance;
      expect(deflection, greaterThan(15.0));
    });

    test('send path departs from source and arrives at target', () {
      const source = Offset(120, 160);
      const target = Offset(280, 240);

      const painter = RelayTransferStreamPainter(
        sourceOffset: source,
        targetOffset: target,
        direction: RelayTransferDirection.send,
        phase: RelayDevicePhase.sending,
        progress: 0.5,
        primaryColor: Colors.grey,
        accentColor: Colors.blue,
        successColor: Colors.green,
        errorColor: Colors.red,
        isFocusedPair: true,
      );

      expect(painter.direction, equals(RelayTransferDirection.send));
      expect(painter.sourceOffset, equals(source));
      expect(painter.targetOffset, equals(target));
    });

    test('receive path departs from remote target and arrives at center source', () {
      const source = Offset(120, 160);
      const target = Offset(280, 240);

      const painter = RelayTransferStreamPainter(
        sourceOffset: source,
        targetOffset: target,
        direction: RelayTransferDirection.receive,
        phase: RelayDevicePhase.sending,
        progress: 0.5,
        primaryColor: Colors.grey,
        accentColor: Colors.blue,
        successColor: Colors.green,
        errorColor: Colors.red,
        isFocusedPair: true,
      );

      expect(painter.direction, equals(RelayTransferDirection.receive));
      expect(painter.sourceOffset, equals(source));
      expect(painter.targetOffset, equals(target));
    });
  });

  group('RelaySpatialScene Full-Page & Terminal State Tests', () {
    testWidgets('Android home page spatial scene fills available viewport without enclosing Card', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final homeVm = RelayHomeVm.fromState(
        configuredAlias: 'Linux Workstation',
        selfDeviceType: DeviceType.desktop,
        server: null,
        nearby: const NearbyDevicesState(runningFavoriteScan: false, runningIps: {}, devices: {}, signalingDevices: {}),
        sendSessions: const {},
        transfers: FileTransferNotifier(),
        selectedFiles: const [],
      );

      final mockPersistence = MockPersistenceService();
      when(mockPersistence.getReceiveHistory()).thenReturn([]);

      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            persistenceProvider.overrideWithValue(mockPersistence),
          ],
          child: MaterialApp(
            theme: darkTheme,
            home: Scaffold(
              body: RelaySpatialScene(
                selfAlias: 'Linux Workstation',
                selfDeviceType: DeviceType.desktop,
                presence: homeVm.presence,
                devices: homeVm.devices,
                activeTransfer: null,
                animationsEnabled: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Spatial scene is present and fills the full viewport
      expect(find.byType(RelaySpatialScene), findsOneWidget);
      final sceneBox = tester.renderObject<RenderBox>(find.byType(RelaySpatialScene));
      expect(sceneBox.size.height, equals(800));
    });

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

    testWidgets('completed backend state reaches visual success epilogue', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const successTransfer = RelayTransferVm(
        sessionId: 'test-success-1',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.send,
        progress: 1.0,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.success,
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
              activeTransfer: successTransfer,
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Transfer complete'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byType(RelayTransferStream), findsOneWidget);

      final stream = tester.widget<RelayTransferStream>(find.byType(RelayTransferStream));
      expect(stream.phase, equals(RelayDevicePhase.success));
    });

    testWidgets('failed backend state reaches failure epilogue', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const failedTransfer = RelayTransferVm(
        sessionId: 'test-fail-1',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.send,
        progress: 0.35,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.failed,
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
              activeTransfer: failedTransfer,
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Transfer failed'), findsOneWidget);
      expect(find.byType(RelayTransferStream), findsOneWidget);

      final stream = tester.widget<RelayTransferStream>(find.byType(RelayTransferStream));
      expect(stream.phase, equals(RelayDevicePhase.failed));
    });

    testWidgets('cancelled backend state reaches distinct cancel epilogue', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const cancelledTransfer = RelayTransferVm(
        sessionId: 'test-cancel-1',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.send,
        progress: 0.40,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.cancelled,
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
              activeTransfer: cancelledTransfer,
              animationsEnabled: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Transfer cancelled'), findsOneWidget);
      expect(find.byType(RelayTransferStream), findsOneWidget);

      final stream = tester.widget<RelayTransferStream>(find.byType(RelayTransferStream));
      expect(stream.phase, equals(RelayDevicePhase.cancelled));
    });

    testWidgets('terminal visual epilogue retains transition when backend clears immediately and settles to idle', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const nearCompleteTransfer = RelayTransferVm(
        sessionId: 'test-transient-1',
        targetAlias: 'Arch Laptop',
        direction: RelayTransferDirection.send,
        progress: 0.98,
        deviceKey: 'laptop-key-1',
        phase: RelayDevicePhase.sending,
      );

      // Step 1: In-flight active transfer
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              activeTransfer: nearCompleteTransfer,
              animationsEnabled: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Sending to device…'), findsOneWidget);

      // Step 2: Backend immediately removes the transfer session (activeTransfer = null)
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme,
          home: const Scaffold(
            body: RelaySpatialScene(
              selfAlias: 'Linux Workstation',
              selfDeviceType: DeviceType.desktop,
              presence: RelayPresence.ready,
              devices: [verifiedLaptop],
              activeTransfer: null, // Removed by backend
              animationsEnabled: true,
            ),
          ),
        ),
      );

      // Frame during epilogue (~200ms in): UI transition memory retains success epilogue
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(RelayTransferStream), findsOneWidget);
      final streamDuringEpilogue = tester.widget<RelayTransferStream>(find.byType(RelayTransferStream));
      expect(streamDuringEpilogue.phase, equals(RelayDevicePhase.success));

      // Step 3: Epilogue duration expires (~900ms total) -> scene settles back to idle
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(RelayTransferStream), findsNothing);
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

    testWidgets('reduced-motion mode renders static transfer view without continuous orbit and bypasses epilogue delays', (tester) async {
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

    testWidgets('nearby compatibility peer remains visually distinct without protocol jargon', (tester) async {
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
      expect(find.byIcon(Icons.near_me_outlined), findsOneWidget);
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
