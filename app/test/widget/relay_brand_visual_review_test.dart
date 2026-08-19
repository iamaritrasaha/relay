import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/widget/relay_components.dart';
import 'package:relay_app/widget/relay_logo.dart';

void main() {
  Future<void> render(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.relay, Colors.blue, Brightness.light, null),
        darkTheme: getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null),
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: const _RelayBrandSample(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('dark Relay brand component sample', (tester) async {
    await render(tester, Brightness.dark);
    await expectLater(find.byType(_RelayBrandSample), matchesGoldenFile('goldens/relay_brand/dark_component_sample.png'));
  });

  testWidgets('light Relay brand component sample', (tester) async {
    await render(tester, Brightness.light);
    await expectLater(find.byType(_RelayBrandSample), matchesGoldenFile('goldens/relay_brand/light_component_sample.png'));
  });
}

class _RelayBrandSample extends StatelessWidget {
  const _RelayBrandSample();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: RelayLogo(withText: true, symbolSize: 72)),
              const SizedBox(height: 28),
              const RelaySectionHeading('Nearby sharing'),
              const SizedBox(height: 8),
              RelayGroupedSurface(
                child: Column(
                  children: [
                    const RelaySettingsRow(label: 'Device visibility', value: 'Visible'),
                    const Divider(height: 24),
                    RelaySettingsRow(
                      label: 'Receive requests',
                      trailing: Switch(value: true, onChanged: (_) {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(onPressed: () {}, style: RelayButtonStyles.primary(context), child: const Text('Choose files')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(onPressed: () {}, style: RelayButtonStyles.secondary(context), child: const Text('Learn more')),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: () {}, style: RelayButtonStyles.icon(context), icon: const Icon(Icons.more_horiz)),
                ],
              ),
              const SizedBox(height: 16),
              Text(RelayProduct.localSendAttribution, style: RelayTypography.legal(palette.textTertiary), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
