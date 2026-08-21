import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/theme.dart';
import 'package:relay_app/model/persistence/color_mode.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_motion/relay_breath.dart';
import 'package:relay_app/widget/relay_motion/relay_edge_sweep.dart';

/// These tests exist because a previous pass shipped both of these widgets in
/// the tree and neither of them was visible on screen. Asserting that the class
/// is present proves nothing, so every test here either reads the live painter
/// or compares real painted pixels.
void main() {
  final theme = getTheme(ColorMode.relay, Colors.blue, Brightness.dark, null);

  Widget host({
    required Widget child,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 240,
              child: RepaintBoundary(key: const ValueKey('capture'), child: child),
            ),
          ),
        ),
      ),
    );
  }

  Widget hero({bool animationsEnabled = true, bool connected = true}) {
    return RelayEdgeSweep(
      ambient: connected,
      animationsEnabled: animationsEnabled,
      radius: RelayRadius.hero,
      child: RelayBreath(
        active: connected,
        animationsEnabled: animationsEnabled,
        radius: RelayRadius.hero,
        child: const RelaySurface(
          radius: RelayRadius.hero,
          padding: EdgeInsets.all(24),
          child: SizedBox.expand(),
        ),
      ),
    );
  }

  RelayBreathPainter breathPainter(WidgetTester tester) {
    final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere((p) => p.foregroundPainter is RelayBreathPainter);
    return paint.foregroundPainter! as RelayBreathPainter;
  }

  RelayEdgeSweepPainter sweepPainter(WidgetTester tester) {
    final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere((p) => p.foregroundPainter is RelayEdgeSweepPainter);
    return paint.foregroundPainter! as RelayEdgeSweepPainter;
  }

  Future<Uint8List> capture(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));
    late Uint8List bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
      image.dispose();
    });
    return bytes;
  }

  /// How far apart two frames are, averaged per channel. Zero means the two
  /// frames are literally the same image.
  double frameDelta(Uint8List a, Uint8List b) {
    expect(a.length, b.length);
    var total = 0;
    for (var i = 0; i < a.length; i++) {
      total += (a[i] - b[i]).abs();
    }
    return total / a.length;
  }

  testWidgets('breath runs by default when animations are enabled', (tester) async {
    await tester.pumpWidget(host(child: hero()));
    await tester.pump();

    final painter = breathPainter(tester);
    final first = painter.progress;
    await tester.pump(const Duration(milliseconds: 900));
    expect(painter.progress, isNot(equals(first)), reason: 'the breath controller must actually be ticking');
  });

  testWidgets('breath does not run under reduced motion', (tester) async {
    await tester.pumpWidget(host(child: hero(), disableAnimations: true));
    await tester.pump();

    expect(
      tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((p) => p.foregroundPainter is RelayBreathPainter),
      isEmpty,
      reason: 'reduced motion must remove the breath overlay entirely, not just slow it',
    );
  });

  testWidgets('breath does not run when the device is disconnected', (tester) async {
    await tester.pumpWidget(host(child: hero(connected: false)));
    await tester.pump();

    expect(
      tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((p) => p.foregroundPainter is RelayBreathPainter),
      isEmpty,
    );
  });

  testWidgets('edge sweep progress advances over time', (tester) async {
    await tester.pumpWidget(host(child: hero()));
    await tester.pump();

    final painter = sweepPainter(tester);
    expect(painter.isPainting, isTrue);

    final first = painter.progress;
    await tester.pump(const Duration(milliseconds: 2000));
    final second = painter.progress;

    expect(second, isNot(equals(first)));
    // A 8.5s circuit means two seconds is a little under a quarter of the way
    // round. Anything far off that means the period regressed.
    expect((second - first).abs(), greaterThan(0.15));
    expect((second - first).abs(), lessThan(0.30));
  });

  testWidgets('edge sweep paints nothing under reduced motion', (tester) async {
    await tester.pumpWidget(host(child: hero(), disableAnimations: true));
    await tester.pump();

    expect(
      tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((p) => p.foregroundPainter is RelayEdgeSweepPainter),
      isEmpty,
    );
  });

  testWidgets('the hero visibly changes between frames two seconds apart', (tester) async {
    await tester.pumpWidget(host(child: hero()));
    await tester.pump();

    final a = await capture(tester);
    await tester.pump(const Duration(milliseconds: 2000));
    final b = await capture(tester);

    // This is the assertion the previous pass could not have passed: real
    // painted pixels have to differ, not just controller values.
    expect(frameDelta(a, b), greaterThan(0.5), reason: 'the hero must look different two seconds apart');
  });

  testWidgets('a reduced-motion hero is pixel-identical two seconds apart', (tester) async {
    await tester.pumpWidget(host(child: hero(), disableAnimations: true));
    await tester.pump();

    final a = await capture(tester);
    await tester.pump(const Duration(milliseconds: 2000));
    final b = await capture(tester);

    expect(frameDelta(a, b), equals(0));
  });
}
