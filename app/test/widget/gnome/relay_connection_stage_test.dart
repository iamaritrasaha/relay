import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
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
