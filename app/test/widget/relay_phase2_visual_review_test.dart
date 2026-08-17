import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/widget/relay/relay_desktop_metrics.dart';
import 'package:localsend_app/widget/relay/relay_device_silhouette.dart';
import 'package:localsend_app/widget/relay/relay_settings_primitives.dart';
import 'package:localsend_app/widget/relay/relay_shell.dart';
import 'package:localsend_app/widget/relay/relay_top_bar.dart';
import 'package:localsend_app/widget/relay_components.dart';
import 'package:localsend_app/widget/relay_logo.dart';
import 'package:localsend_isolates/model/device.dart';

void main() {
  const desktop = Size(1280, 800);
  const mobile = Size(412, 915);

  const nearbyDevices = [
    RelayDeviceVm(
      key: 'pixel',
      alias: 'Pixel 9',
      deviceType: DeviceType.mobile,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Nearby',
    ),
    RelayDeviceVm(
      key: 'studio',
      alias: 'Studio',
      deviceType: DeviceType.desktop,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Nearby',
    ),
    RelayDeviceVm(
      key: 'tablet',
      alias: 'Tab S9',
      deviceType: DeviceType.mobile,
      phase: RelayDevicePhase.idle,
      progress: null,
      detail: 'Nearby',
    ),
  ];

  RelayHomeVm homeVm({bool selected = false, bool sending = false}) {
    final devices = sending
        ? [
            nearbyDevices[0],
            const RelayDeviceVm(
              key: 'studio',
              alias: 'Studio',
              deviceType: DeviceType.desktop,
              phase: RelayDevicePhase.sending,
              progress: 0.64,
              detail: 'Sending',
            ),
            nearbyDevices[2],
          ]
        : nearbyDevices;
    return RelayHomeVm(
      selfAlias: 'Aritra’s Linux',
      selfDeviceType: DeviceType.desktop,
      presence: RelayPresence.ready,
      selection: RelayPayloadVm(fileCount: selected || sending ? 3 : 0, totalBytes: selected || sending ? 24000000 : 0),
      devices: devices,
      incoming: const RelayIncomingVm(hasActiveRequest: false),
      intents: RelayHomeIntents(canSelectPayload: true, canChooseTarget: selected || sending),
    );
  }

  Future<void> render(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.localsend, Colors.blue, Brightness.dark, null),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Widget home({required bool selected, required bool sending}) => RelayShell(
    vm: homeVm(selected: selected, sending: sending),
    animationsEnabled: false,
    onSelectPayload: () {},
    onDeviceTap: (_) {},
  );

  for (final (name, size) in [('desktop', desktop), ('android', mobile)]) {
    testWidgets('$name home nearby visual review', (tester) async {
      await render(tester, size, home(selected: false, sending: false));
      await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_phase2/${name}_home_nearby.png'));
    });

    testWidgets('$name home payload visual review', (tester) async {
      await render(tester, size, home(selected: true, sending: false));
      await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_phase2/${name}_home_payload.png'));
    });

    testWidgets('$name home sending visual review', (tester) async {
      await render(tester, size, home(selected: true, sending: true));
      await expectLater(find.byType(RelayShell), matchesGoldenFile('goldens/relay_phase2/${name}_home_sending.png'));
    });

    testWidgets('$name settings visual review', (tester) async {
      await render(tester, size, const _SettingsReview());
      await expectLater(find.byType(_SettingsReview), matchesGoldenFile('goldens/relay_phase2/${name}_settings.png'));
    });

    testWidgets('$name about visual review', (tester) async {
      await render(tester, size, const _AboutReview());
      await expectLater(find.byType(_AboutReview), matchesGoldenFile('goldens/relay_phase2/${name}_about.png'));
    });
  }

  testWidgets('main Relay home has no Send or Receive navigation', (tester) async {
    await render(tester, desktop, home(selected: false, sending: false));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
  });

  testWidgets('Relay device silhouettes render every existing device category', (tester) async {
    await render(
      tester,
      desktop,
      Scaffold(
        body: Row(
          children: [
            for (final type in DeviceType.values) RelayDeviceSilhouette(deviceType: type, color: Colors.white),
          ],
        ),
      ),
    );

    expect(find.byType(RelayDeviceSilhouette), findsNWidgets(DeviceType.values.length));
  });

  testWidgets('about branding retains Relay ownership and the upstream attribution', (tester) async {
    await render(tester, desktop, const _AboutReview());

    expect(find.text('Relay'), findsOneWidget);
    expect(find.text(RelayProduct.copyright), findsOneWidget);
    expect(find.text(RelayProduct.localSendAttribution), findsOneWidget);
    expect(find.text('Open Source Licenses'), findsOneWidget);
  });
}

class _SettingsReview extends StatelessWidget {
  const _SettingsReview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            RelayTopBar.titled(title: 'Settings', onBack: () {}),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: RelayDesktopMetrics.settingsFrameWidth),
                    child: RelaySettingsColumns(
                      groups: [
                        RelaySettingsGroup(
                          title: 'General',
                          children: [
                            RelayNavigationEntry(label: 'Language', value: 'English', onTap: () {}),
                            RelayBooleanEntry(label: 'Animations', value: true, onChanged: (_) {}),
                          ],
                        ),
                        RelaySettingsGroup(
                          title: 'Receiving',
                          children: [
                            RelayNavigationEntry(label: 'Save to', value: 'Downloads', onTap: () {}),
                            RelayBooleanEntry(label: 'Require a PIN', value: false, onChanged: (_) {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutReview extends StatelessWidget {
  const _AboutReview();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: RelayGroupedSurface(
                padding: const EdgeInsets.fromLTRB(28, 38, 28, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RelayLogo(withText: true, symbolSize: 100),
                    const SizedBox(height: 18),
                    Text('Version 0.1.0', style: RelayTypography.value(palette.textSecondary)),
                    const SizedBox(height: 3),
                    Text('Build 62', style: RelayTypography.legal(palette.textSecondary)),
                    const SizedBox(height: 12),
                    Text(RelayProduct.copyright, style: RelayTypography.legal(palette.textSecondary)),
                    const SizedBox(height: 18),
                    Text(RelayProduct.localSendAttribution, style: RelayTypography.legal(palette.textTertiary), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    const Divider(),
                    TextButton.icon(onPressed: () {}, icon: const Icon(Icons.article_outlined), label: const Text('Open Source Licenses')),
                    TextButton.icon(onPressed: () {}, icon: const Icon(Icons.open_in_new_rounded), label: const Text('Apache License 2.0')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
