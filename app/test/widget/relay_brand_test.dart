import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/widget/relay_components.dart';
import 'package:relay_app/widget/relay_logo.dart';
import 'package:relay_app/widget/relay_symbol.dart';

void main() {
  test('Relay product identity retains the required attribution', () {
    expect(RelayProduct.name, 'Relay');
    expect(RelayProduct.copyright, '© 2026 Aritra Saha');
    expect(RelayProduct.localSendAttribution, 'Portions based on LocalSend, licensed under the Apache License 2.0.');
  });

  test('Relay semantic colors use the GNOME/Yaru palette', () {
    expect(RelayPalette.dark.canvas, const Color(0xff242424));
    expect(RelayPalette.dark.elevated, const Color(0xff303030));
    expect(RelayPalette.dark.accent, const Color(0xffe95420));
    expect(RelayPalette.dark.accentSoft, const Color(0xffff7846));
    expect(RelayPalette.dark.accentSecondary, const Color(0xffc89a55));
    expect(RelayPalette.dark.accent, isNot(const Color(0xff008080)));
    for (final accent in [RelayPalette.dark.accent, RelayPalette.light.accent, RelayPalette.dark.accentSecondary]) {
      expect(accent.b, lessThan(accent.g));
      expect(accent.g, lessThan(accent.r));
    }
    expect(RelayPalette.dark.canvas.b, lessThanOrEqualTo(RelayPalette.dark.canvas.r));
    expect(RelayPalette.dark.elevated.b, lessThanOrEqualTo(RelayPalette.dark.elevated.r));
    expect(relayColorScheme(Brightness.dark).primary, RelayPalette.dark.accent);
    expect(relayColorScheme(Brightness.light).primary, RelayPalette.light.accent);
  });

  testWidgets('the shared logo renders the Relay symbol and wordmark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null),
        home: const Scaffold(body: Center(child: RelayLogo(withText: true))),
      ),
    );

    expect(find.byType(RelaySymbol), findsOneWidget);
    expect(find.text(RelayProduct.name), findsOneWidget);
    expect(find.bySemanticsLabel(RelayProduct.name), findsAtLeastNWidgets(1));
  });

  testWidgets('Relay component primitives preserve the compact visual contract', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null),
        home: Scaffold(
          body: Builder(
            builder: (context) => RelayGroupedSurface(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RelaySectionHeading('Sharing'),
                  const SizedBox(height: 8),
                  const RelaySettingsRow(label: 'Visibility', value: 'On'),
                  FilledButton(onPressed: () {}, style: RelayButtonStyles.primary(context), child: const Text('Send')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('SHARING'), findsOneWidget);
    expect(find.text('Visibility'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });
}
