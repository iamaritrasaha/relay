import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/model/ui/relay_connection_state.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/model/ui/relay_feature.dart';
import 'package:relay_app/model/ui/relay_last_seen.dart';
import 'package:relay_app/pages/gnome/gnome_diagnostics_dialog.dart';
import 'package:relay_isolates/model/device.dart';

RelayDeviceVm _phoneDevice() => const RelayDeviceVm(
  key: 'kdeconnect:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  alias: 'Redmi Note 14 Pro 5G',
  deviceType: DeviceType.mobile,
  phase: RelayDevicePhase.idle,
  progress: null,
  detail: 'Connected',
  targetKind: RelayDeviceTargetKind.kdeConnect,
  explicitConnectionState: RelayConnectionState.local,
  lanFingerprint: '3F1A9C7E2B0D5468A1C3E7F92B4D6081AABBCCDDEEFF00112233445566778899',
  deviceModel: '24090RA29G',
  deviceClass: RelayDeviceClass.phone,
  hasFabricRecord: true,
  lanAvailable: true,
  wanAvailable: false,
  wanBound: true,
  wanPath: 'direct',
  lanLastSeenUnix: null,
  wanLastSeenUnix: null,
  platform: 'android',
  platformVersion: '14',
  relayVersion: '8',
  featureAvailability: {
    RelayFeature.battery: RelayFeatureAvailability.available,
    RelayFeature.clipboard: RelayFeatureAvailability.available,
    RelayFeature.commands: RelayFeatureAvailability.notConfigured,
    RelayFeature.files: RelayFeatureAvailability.available,
    RelayFeature.media: RelayFeatureAvailability.available,
    RelayFeature.messages: RelayFeatureAvailability.available,
    RelayFeature.notifications: RelayFeatureAvailability.available,
    RelayFeature.ping: RelayFeatureAvailability.available,
    RelayFeature.remoteInput: RelayFeatureAvailability.disabled,
  },
);

Future<void> _pumpAtSize(WidgetTester tester, Size size, RelayDeviceVm device) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => GnomeDiagnosticsDialog(device: device),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('GnomeDiagnosticsDialog', () {
    testWidgets('preserves every diagnostic field the legacy dialog showed', (tester) async {
      final device = _phoneDevice();
      await _pumpAtSize(tester, const Size(1440, 900), device);

      expect(tester.takeException(), isNull);

      // Identity
      expect(find.text('Redmi Note 14 Pro 5G'), findsWidgets);
      expect(find.text('KDE Connect'), findsOneWidget);

      // Connection
      expect(find.text('KDE LAN'), findsOneWidget); // route diagnosticLabel
      expect(find.text('Available'), findsWidgets); // local network + capabilities
      expect(find.textContaining('Bound'), findsOneWidget);
      expect(find.text('Never'), findsNWidgets(2)); // last local + last remote activity

      // Device
      expect(find.text('Phone'), findsOneWidget); // device class
      expect(find.textContaining('Android'), findsOneWidget); // real reported platform, title-cased for display
      expect(find.text('8'), findsOneWidget);

      // Capabilities: every visible feature title present
      for (final feature in device.featureAvailability.keys) {
        expect(find.text(feature.title), findsOneWidget, reason: '${feature.title} must remain visible');
      }
      expect(find.text('Not set up yet'), findsOneWidget); // Commands reason
      expect(find.text('Turned off'), findsOneWidget); // Remote input reason

      // GNOME-style header: top-right close, no bottom Close text button.
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Close'), findsNothing);
      expect(find.text('Device diagnostics'), findsOneWidget);
    });

    testWidgets('top-right close affordance dismisses the dialog', (tester) async {
      await _pumpAtSize(tester, const Size(1440, 900), _phoneDevice());
      expect(find.byType(GnomeDiagnosticsDialog), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(GnomeDiagnosticsDialog), findsNothing);
    });

    testWidgets('fingerprint is truncated but copies the full value', (tester) async {
      final device = _phoneDevice();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await _pumpAtSize(tester, const Size(1440, 900), device);

      // The full 64-char fingerprint must not be shown in full.
      expect(find.text(device.lanFingerprint!), findsNothing);

      await tester.tap(find.byTooltip('Copy fingerprint'));
      await tester.pumpAndSettle();

      final copyCall = calls.where((call) => call.method == 'Clipboard.setData').toList();
      expect(copyCall, isNotEmpty);
      expect((copyCall.first.arguments as Map)['text'], device.lanFingerprint);
      expect(find.text('Fingerprint copied to clipboard'), findsOneWidget);
    });

    for (final resolution in [const Size(1280, 720), const Size(1440, 900), const Size(1920, 1080)]) {
      testWidgets('fits without overflow at ${resolution.width.toInt()}x${resolution.height.toInt()}', (tester) async {
        await _pumpAtSize(tester, resolution, _phoneDevice());
        expect(tester.takeException(), isNull);
        expect(find.byType(GnomeDiagnosticsDialog), findsOneWidget);
      });
    }

    testWidgets('offline device with no fabric record still opens cleanly', (tester) async {
      const device = RelayDeviceVm(
        key: 'kdeconnect:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        alias: 'Unpaired Phone',
        deviceType: DeviceType.mobile,
        phase: RelayDevicePhase.idle,
        progress: null,
        detail: 'Offline',
        targetKind: RelayDeviceTargetKind.kdeConnect,
        explicitConnectionState: RelayConnectionState.offline,
      );
      await _pumpAtSize(tester, const Size(1280, 720), device);
      expect(tester.takeException(), isNull);
      expect(find.text('Unpaired Phone'), findsWidgets);
      expect(find.text('Offline'), findsOneWidget);
    });
  });
}
