import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/widget/responsive_list_view.dart';

/// Regression coverage for the desktop Settings overflow.
///
/// Settings was built with [ResponsiveListView.single], which does not scroll —
/// that constructor exists for children that scroll themselves (a
/// `CustomScrollView`). Feeding it a plain column meant the page overflowed as
/// soon as the window was shorter than the content, which is what produced the
/// "BOTTOM OVERFLOWED BY 114 PIXELS" banner on the real desktop app.
void main() {
  /// Content taller than any of the viewports exercised below.
  Widget tallColumn() => const Column(
    children: [SizedBox(height: 2000, width: 400)],
  );

  Future<void> pump(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  // The real desktop and phone viewports Settings has to survive.
  const viewports = <String, Size>{
    'desktop 1280x800': Size(1280, 800),
    'desktop 1280x650': Size(1280, 650),
    'desktop 1000x700': Size(1000, 700),
    'android 412x915': Size(412, 915),
    'android 360x800': Size(360, 800),
  };

  for (final entry in viewports.entries) {
    testWidgets('list constructor scrolls instead of overflowing at ${entry.key}', (tester) async {
      await pump(
        tester,
        ResponsiveListView(
          maxWidth: 1080,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [tallColumn()],
        ),
        entry.value,
      );

      // An overflow renders as a FlutterError exception during paint.
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
    });
  }

  testWidgets('single constructor deliberately does not add a scroll view', (tester) async {
    // Guards the contract the other two callers (apk picker, selected files)
    // rely on: they pass their own CustomScrollView, so wrapping this
    // constructor in a SingleChildScrollView would give them unbounded height.
    await pump(
      tester,
      ResponsiveListView.single(
        padding: EdgeInsets.zero,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: tallColumn()),
          ],
        ),
      ),
      const Size(1280, 650),
    );

    expect(tester.takeException(), isNull);
    // Exactly the caller's own scroll view — no extra one wrapped around it.
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
