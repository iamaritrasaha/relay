import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/widget/gnome/relay_connection_status.dart';

void main() {
  final darkTheme = getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null);
  final lightTheme = getTheme(ColorMode.relay, Colors.blue, Brightness.light, null);

  Widget host({
    required ThemeData theme,
    required bool connected,
    required bool animationsEnabled,
    bool ambient = false,
    bool reducedMotion = false,
  }) {
    return MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Material(
          child: Center(
            child: RelayConnectionStatus(
              connected: connected,
              label: connected ? 'Connected' : 'Disconnected',
              animationsEnabled: animationsEnabled,
              ambient: ambient,
            ),
          ),
        ),
      ),
    );
  }

  Opacity dotOpacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('relay-connection-dot')), matching: find.byType(Opacity)).first);

  testWidgets('connected uses neutral text and a small Relay indicator in dark and light themes', (tester) async {
    for (final theme in [darkTheme, lightTheme]) {
      await tester.pumpWidget(host(theme: theme, connected: true, animationsEnabled: false));
      final context = tester.element(find.text('Connected'));
      final text = tester.widget<Text>(find.text('Connected'));
      final dot = tester.widget<Container>(find.byKey(const ValueKey('relay-connection-dot')));

      expect(text.style?.color, Theme.of(context).colorScheme.onSurface);
      expect((dot.decoration! as BoxDecoration).shape, BoxShape.circle);
      expect(tester.getSize(find.byKey(const ValueKey('relay-connection-dot'))), const Size.square(7));
    }
  });

  testWidgets('disconnected remains neutral and static', (tester) async {
    await tester.pumpWidget(host(theme: darkTheme, connected: false, animationsEnabled: true, ambient: true));
    final context = tester.element(find.text('Disconnected'));
    final text = tester.widget<Text>(find.text('Disconnected'));
    final before = dotOpacity(tester).opacity;
    await tester.pump(const Duration(seconds: 2));

    expect(text.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
    expect(dotOpacity(tester).opacity, before);
  });

  testWidgets('offline to connected event ring is finite', (tester) async {
    late StateSetter setHostState;
    var connected = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return Material(
              child: Center(
                child: RelayConnectionStatus(
                  connected: connected,
                  label: connected ? 'Connected' : 'Disconnected',
                  animationsEnabled: true,
                ),
              ),
            );
          },
        ),
      ),
    );

    setHostState(() => connected = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<Opacity>(find.byKey(const ValueKey('relay-connection-event-ring'))).opacity, greaterThan(0));

    await tester.pump(RelayConnectionStatus.eventDuration);
    expect(tester.widget<Opacity>(find.byKey(const ValueKey('relay-connection-event-ring'))).opacity, 0);
  });

  testWidgets('ambient rhythm stops for preference and reduced motion', (tester) async {
    await tester.pumpWidget(host(theme: darkTheme, connected: true, animationsEnabled: true, ambient: true));
    final animatedStart = dotOpacity(tester).opacity;
    await tester.pump(const Duration(milliseconds: 1250));
    expect(dotOpacity(tester).opacity, isNot(animatedStart));

    await tester.pumpWidget(host(theme: darkTheme, connected: true, animationsEnabled: false, ambient: true));
    final preferenceOff = dotOpacity(tester).opacity;
    await tester.pump(const Duration(milliseconds: 1250));
    expect(dotOpacity(tester).opacity, preferenceOff);

    await tester.pumpWidget(host(theme: darkTheme, connected: true, animationsEnabled: true, ambient: true, reducedMotion: true));
    final reduced = dotOpacity(tester).opacity;
    await tester.pump(const Duration(milliseconds: 1250));
    expect(dotOpacity(tester).opacity, reduced);
  });
}
