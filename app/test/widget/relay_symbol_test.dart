import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/widget/relay_symbol.dart';

void main() {
  testWidgets('RelaySymbol pumps cleanly without lifecycle or MediaQuery exceptions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RelaySymbol(size: 64, animated: true),
        ),
      ),
    );

    expect(find.byType(RelaySymbol), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RelaySymbol respects system reduced motion and renders statically', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: RelaySymbol(size: 64, animated: true),
          ),
        ),
      ),
    );

    expect(find.byType(RelaySymbol), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RelaySymbol), matching: find.byType(AnimatedBuilder)),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RelaySymbol animates in normal mode with active AnimatedBuilder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: false),
          child: Scaffold(
            body: RelaySymbol(size: 64, animated: true),
          ),
        ),
      ),
    );

    expect(find.byType(RelaySymbol), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RelaySymbol), matching: find.byType(AnimatedBuilder)),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RelaySymbol dynamically toggles animation when MediaQuery disableAnimations changes', (tester) async {
    bool disable = false;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disable),
              child: Scaffold(
                body: const RelaySymbol(size: 64, animated: true),
                floatingActionButton: FloatingActionButton(
                  onPressed: () => setState(() => disable = !disable),
                ),
              ),
            ),
          );
        },
      ),
    );

    expect(
      find.descendant(of: find.byType(RelaySymbol), matching: find.byType(AnimatedBuilder)),
      findsOneWidget,
    );

    // Toggle reduced motion on
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(RelaySymbol), matching: find.byType(AnimatedBuilder)),
      findsNothing,
    );

    // Toggle reduced motion off
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(
      find.descendant(of: find.byType(RelaySymbol), matching: find.byType(AnimatedBuilder)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('RelaySymbol disposes cleanly without ticker leaks', (tester) async {
    bool mounted = true;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: mounted ? const RelaySymbol(size: 64, animated: true) : const SizedBox.shrink(),
              floatingActionButton: FloatingActionButton(
                onPressed: () => setState(() => mounted = false),
              ),
            ),
          );
        },
      ),
    );

    expect(find.byType(RelaySymbol), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.byType(RelaySymbol), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
