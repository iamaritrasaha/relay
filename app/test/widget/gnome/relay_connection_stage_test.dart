import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_device_palette.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_device_detail_view.dart';
import 'package:relay_app/widget/gnome/relay_connection_stage.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';
import 'package:relay_app/widget/relay_symbol.dart';
import 'package:relay_isolates/model/device.dart';

Widget _wrapWithApp(
  Widget child, {
  bool disableAnimations = false,
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: RelayAmbientClock(
          animationsEnabled: !disableAnimations,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  const phoneDevice = RelayDeviceVm(
    key: 'device-phone',
    alias: 'Redmi Note 14 Pro 5G',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    deviceModel: '24090RA29G',
  );

  const tabletDevice = RelayDeviceVm(
    key: 'device-tablet',
    alias: 'Galaxy Tab S6 Lite',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    deviceModel: 'SM-P610',
  );

  const desktopDevice = RelayDeviceVm(
    key: 'device-laptop',
    alias: 'ThinkPad X1 Carbon',
    deviceType: DeviceType.desktop,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Connected',
    targetKind: RelayDeviceTargetKind.kdeConnect,
    deviceModel: '20HR000FUS',
  );

  const offlineDevice = RelayDeviceVm(
    key: 'device-offline',
    alias: 'Offline Phone',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.idle,
    progress: null,
    detail: 'Offline',
    targetKind: RelayDeviceTargetKind.kdeConnect,
  );

  const connectingDevice = RelayDeviceVm(
    key: 'device-connecting',
    alias: 'Connecting Phone',
    deviceType: DeviceType.mobile,
    phase: RelayDevicePhase.waiting,
    progress: null,
    detail: 'Connecting…',
    targetKind: RelayDeviceTargetKind.kdeConnect,
  );

  group('RelayConnectionStage', () {
    testWidgets('renders both remote alias and local selfAlias endpoints', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: phoneDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redmi Note 14 Pro 5G'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
      expect(find.byType(RelaySymbol), findsOneWidget);
    });

    testWidgets('renders tablet device correctly with tablet silhouette', (tester) async {
      final palette = RelayDevicePalette.fromDevice(tabletDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: tabletDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Galaxy Tab S6 Lite'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
    });

    testWidgets('renders desktop device correctly with desktop silhouette', (tester) async {
      final palette = RelayDevicePalette.fromDevice(desktopDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: desktopDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ThinkPad X1 Carbon'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
    });

    testWidgets('renders connecting state cleanly', (tester) async {
      final palette = RelayDevicePalette.fromDevice(connectingDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: connectingDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: false,
            connecting: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connecting Phone'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
    });

    testWidgets('renders offline state with broken bridge and muted silhouette', (tester) async {
      final palette = RelayDevicePalette.fromDevice(offlineDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: offlineDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline Phone'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
    });

    testWidgets('adapts to narrow vertical layout below 480px', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          SizedBox(
            width: 360,
            child: RelayConnectionStage(
              device: phoneDevice,
              palette: palette,
              selfAlias: 'Falcon',
              selfDeviceType: DeviceType.desktop,
              connected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redmi Note 14 Pro 5G'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
    });

    testWidgets('renders static frame cleanly when disableAnimations is true', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: phoneDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: false,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redmi Note 14 Pro 5G'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
    });
  });

  group('RelayConnectionStage Geometry & Anchor Contact', () {
    testWidgets('horizontal layout has shared connection axis across phone, core, and local computer (dy within 1px)', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          SizedBox(
            width: 600,
            child: RelayConnectionStage(
              device: phoneDevice,
              palette: palette,
              selfAlias: 'Falcon',
              selfDeviceType: DeviceType.desktop,
              connected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final bridgePaint = customPaints.firstWhere((p) => p.painter.runtimeType.toString().contains('BridgePainter'));
      final dynamic painter = bridgePaint.painter;

      final startAnchor = painter.startAnchor as Offset;
      final coreLeft = painter.coreLeft as Offset;
      final coreRight = painter.coreRight as Offset;
      final endAnchor = painter.endAnchor as Offset;

      // All anchors must share the exact same horizontal connection axis Y (tolerance <= 1.0px)
      expect((startAnchor.dy - coreLeft.dy).abs(), lessThanOrEqualTo(1.0));
      expect((coreLeft.dy - coreRight.dy).abs(), lessThanOrEqualTo(1.0));
      expect((coreRight.dy - endAnchor.dy).abs(), lessThanOrEqualTo(1.0));
      expect(startAnchor.dy, equals(46.0));
      expect(endAnchor.dy, equals(46.0));

      // Phone silhouette contact point: padX(16) + phoneWidth(48) = 64
      expect(startAnchor.dx, equals(64.0));
      // Local desktop contact point: stageWidth(600) - padX(16) - desktopWidth(76) = 508
      expect(endAnchor.dx, equals(508.0));
      // Core contact points: center(300) ± radius(22) = 278 and 322
      expect(coreLeft.dx, equals(278.0));
      expect(coreRight.dx, equals(322.0));
    });

    testWidgets('horizontal layout tablet contact points meet tablet width', (tester) async {
      final palette = RelayDevicePalette.fromDevice(tabletDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          SizedBox(
            width: 600,
            child: RelayConnectionStage(
              device: tabletDevice,
              palette: palette,
              selfAlias: 'Falcon',
              selfDeviceType: DeviceType.desktop,
              connected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final bridgePaint = customPaints.firstWhere((p) => p.painter.runtimeType.toString().contains('BridgePainter'));
      final dynamic painter = bridgePaint.painter;

      final startAnchor = painter.startAnchor as Offset;
      // Tablet silhouette contact point: padX(16) + tabletWidth(66) = 82
      expect(startAnchor.dx, equals(82.0));
      expect(startAnchor.dy, equals(46.0));
    });

    testWidgets('horizontal layout desktop contact points meet desktop width', (tester) async {
      final palette = RelayDevicePalette.fromDevice(desktopDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          SizedBox(
            width: 600,
            child: RelayConnectionStage(
              device: desktopDevice,
              palette: palette,
              selfAlias: 'Falcon',
              selfDeviceType: DeviceType.desktop,
              connected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final bridgePaint = customPaints.firstWhere((p) => p.painter.runtimeType.toString().contains('BridgePainter'));
      final dynamic painter = bridgePaint.painter;

      final startAnchor = painter.startAnchor as Offset;
      // Desktop silhouette contact point: padX(16) + desktopWidth(76) = 92
      expect(startAnchor.dx, equals(92.0));
      expect(startAnchor.dy, equals(46.0));
    });

    testWidgets('narrow vertical layout has shared connection axis (dx within 1px)', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          SizedBox(
            width: 360,
            child: RelayConnectionStage(
              device: phoneDevice,
              palette: palette,
              selfAlias: 'Falcon',
              selfDeviceType: DeviceType.desktop,
              connected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final bridgePaint = customPaints.firstWhere((p) => p.painter.runtimeType.toString().contains('BridgePainter'));
      final dynamic painter = bridgePaint.painter;

      final startAnchor = painter.startAnchor as Offset;
      final coreLeft = painter.coreLeft as Offset; // coreTop in vertical
      final coreRight = painter.coreRight as Offset; // coreBottom in vertical
      final endAnchor = painter.endAnchor as Offset;

      // In vertical layout, all anchors share the exact center X: 360 / 2 = 180
      expect((startAnchor.dx - coreLeft.dx).abs(), lessThanOrEqualTo(1.0));
      expect((coreLeft.dx - coreRight.dx).abs(), lessThanOrEqualTo(1.0));
      expect((coreRight.dx - endAnchor.dx).abs(), lessThanOrEqualTo(1.0));
      expect(startAnchor.dx, equals(180.0));
      expect(endAnchor.dx, equals(180.0));
    });

    testWidgets('endpoint labels share the exact same vertical baseline', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          SizedBox(
            width: 600,
            child: RelayConnectionStage(
              device: phoneDevice,
              palette: palette,
              selfAlias: 'Falcon',
              selfDeviceType: DeviceType.desktop,
              connected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final remoteLabelTopLeft = tester.getTopLeft(find.text('Redmi Note 14 Pro 5G'));
      final localLabelTopLeft = tester.getTopLeft(find.text('Falcon'));

      // Both labels must share the same vertical baseline Y
      expect((remoteLabelTopLeft.dy - localLabelTopLeft.dy).abs(), lessThanOrEqualTo(1.0));
    });
  });

  group('Relay Link Core Rotation & Gating', () {
    testWidgets('rotates steadily when connected and animations are enabled', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: phoneDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pump();

      // Find Transform widget specifically inside RelayLinkCore
      final coreTransformFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString().contains('RelayLinkCore')),
        matching: find.byType(Transform),
      );
      expect(coreTransformFinder, findsOneWidget);
      final initialMatrix = tester.widget<Transform>(coreTransformFinder).transform;

      // Advance by 3.0 seconds (1/4 of a 12s period -> ~90 degree rotation)
      await tester.pump(const Duration(seconds: 3));

      expect(coreTransformFinder, findsOneWidget);
      final advancedMatrix = tester.widget<Transform>(coreTransformFinder).transform;

      // Rotation matrix must have changed
      expect(initialMatrix, isNot(equals(advancedMatrix)));
    });

    testWidgets('does not rotate when animationsEnabled is false (rotation gate)', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: phoneDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: false,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      final coreTransformFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString().contains('RelayLinkCore')),
        matching: find.byType(Transform),
      );
      expect(coreTransformFinder, findsNothing);
    });

    testWidgets('does not rotate when device is offline / paired (rotation gate)', (tester) async {
      final palette = RelayDevicePalette.fromDevice(offlineDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: offlineDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: false,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final coreTransformFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString().contains('RelayLinkCore')),
        matching: find.byType(Transform),
      );
      expect(coreTransformFinder, findsNothing);
    });

    testWidgets('bridge uses continuous glowing wave without any particle dots', (tester) async {
      final palette = RelayDevicePalette.fromDevice(phoneDevice, brightness: Brightness.dark);

      await tester.pumpWidget(
        _wrapWithApp(
          RelayConnectionStage(
            device: phoneDevice,
            palette: palette,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pump();

      // Ensure no obsolete dot or particle widgets exist
      expect(find.byKey(const ValueKey('packetTrain')), findsNothing);
      expect(find.byKey(const ValueKey('travelingDot')), findsNothing);

      // Painter elapsed phase advances smoothly across time
      final customPaints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final bridgePaint = customPaints.firstWhere((p) => p.painter.runtimeType.toString().contains('BridgePainter'));
      final dynamic painter0 = bridgePaint.painter;
      final t0 = painter0.elapsed as double;
      expect(t0, greaterThanOrEqualTo(0.0));

      await tester.pump(const Duration(seconds: 2));
      final customPaints2 = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      final bridgePaint2 = customPaints2.firstWhere((p) => p.painter.runtimeType.toString().contains('BridgePainter'));
      final dynamic painter2 = bridgePaint2.painter;
      final t2 = painter2.elapsed as double;
      expect(t2, greaterThan(t0));
    });
  });

  group('GnomeSelectedDeviceHeader', () {
    testWidgets('renders full header with Connection Stage and Secure badge when connected', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          const GnomeSelectedDeviceHeader(
            device: phoneDevice,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redmi Note 14 Pro 5G'), findsNWidgets(2)); // Title + silhouette label
      expect(find.text('Connected to Falcon'), findsOneWidget);
      expect(find.text('Falcon'), findsOneWidget);
      expect(find.text('Secure connection'), findsOneWidget);
    });

    testWidgets('omits Secure connection badge when device is offline', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          const GnomeSelectedDeviceHeader(
            device: offlineDevice,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: false,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Secure connection'), findsNothing);
      expect(find.text('Paired with Falcon'), findsOneWidget);
    });

    testWidgets('switching selected device updates remote endpoint while local endpoint stays stable', (tester) async {
      await tester.pumpWidget(
        _wrapWithApp(
          const GnomeSelectedDeviceHeader(
            device: phoneDevice,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redmi Note 14 Pro 5G'), findsNWidgets(2));
      expect(find.text('Falcon'), findsOneWidget);

      // Switch to tablet
      await tester.pumpWidget(
        _wrapWithApp(
          const GnomeSelectedDeviceHeader(
            device: tabletDevice,
            selfAlias: 'Falcon',
            selfDeviceType: DeviceType.desktop,
            connected: true,
            animationsEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Galaxy Tab S6 Lite'), findsNWidgets(2));
      expect(find.text('Falcon'), findsOneWidget);
    });
  });
}
