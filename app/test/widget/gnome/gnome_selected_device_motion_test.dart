import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_device_detail_view.dart';
import 'package:relay_app/widget/relay_motion/relay_atmospheric_drift.dart';
import 'package:relay_app/widget/relay_motion/relay_breath.dart';
import 'package:relay_app/widget/relay_motion/relay_edge_sweep.dart';
import 'package:relay_isolates/model/device.dart';

const _connectedDevice = RelayDeviceVm(
  key: 'motion-device',
  alias: 'Connected phone',
  deviceType: DeviceType.mobile,
  phase: RelayDevicePhase.idle,
  progress: null,
  detail: 'Connected',
  targetKind: RelayDeviceTargetKind.kdeConnect,
);

Widget _subject({
  bool selected = true,
  bool connected = true,
  bool animationsEnabled = true,
  bool reducedMotion = false,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Material(
        child: Center(
          child: SizedBox(
            width: 640,
            child: GnomeSelectedDeviceHeader(
              device: _connectedDevice,
              selfAlias: 'Relay workstation',
              selfDeviceType: DeviceType.desktop,
              selected: selected,
              connected: connected,
              animationsEnabled: animationsEnabled,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Uint8List> _captureHeader(WidgetTester tester) async {
  final motion = find.byKey(const ValueKey('selected-device-edge-sweep'));
  final boundaryFinder = find.descendant(of: motion, matching: find.byType(RepaintBoundary)).first;
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

({int maxChannelDelta, double changedPercent}) _difference(Uint8List before, Uint8List after) {
  expect(after.length, before.length);
  var maxChannelDelta = 0;
  var changedPixels = 0;
  final pixels = before.length ~/ 4;

  for (var pixel = 0; pixel < pixels; pixel++) {
    var changed = false;
    for (var channel = 0; channel < 4; channel++) {
      final index = pixel * 4 + channel;
      final delta = (before[index] - after[index]).abs();
      if (delta > maxChannelDelta) maxChannelDelta = delta;
      if (channel < 3 && delta >= 3) changed = true;
    }
    if (changed) changedPixels++;
  }

  return (maxChannelDelta: maxChannelDelta, changedPercent: changedPixels * 100 / pixels);
}

void main() {
  testWidgets('selected connected device produces visible finite frame differences without moving content', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_subject());
    await tester.pump();
    final textRect = tester.getRect(find.text('Connected phone').first);
    final frame0 = await _captureHeader(tester);

    await tester.pump(const Duration(milliseconds: 1500));
    final frame1500 = await _captureHeader(tester);
    expect(tester.getRect(find.text('Connected phone').first), textRect);

    await tester.pump(const Duration(milliseconds: 1500));
    final frame3000 = await _captureHeader(tester);
    expect(tester.getRect(find.text('Connected phone').first), textRect);

    final first = _difference(frame0, frame1500);
    final second = _difference(frame1500, frame3000);
    debugPrint(
      'selected-device motion pixels: '
      '0→1500ms max=${first.maxChannelDelta} changed=${first.changedPercent.toStringAsFixed(2)}%; '
      '1500→3000ms max=${second.maxChannelDelta} changed=${second.changedPercent.toStringAsFixed(2)}%',
    );

    expect(first.maxChannelDelta, greaterThanOrEqualTo(8));
    expect(first.changedPercent, greaterThan(1));
    expect(second.maxChannelDelta, greaterThanOrEqualTo(8));
    expect(second.changedPercent, greaterThan(1));
  });

  testWidgets('ambient motion gates require selected, connected, spatial and system animation permission', (tester) async {
    Future<void> expectGate({
      required bool selected,
      required bool connected,
      required bool animationsEnabled,
      required bool reducedMotion,
      required bool expectedActive,
    }) async {
      await tester.pumpWidget(
        _subject(
          selected: selected,
          connected: connected,
          animationsEnabled: animationsEnabled,
          reducedMotion: reducedMotion,
        ),
      );
      await tester.pump();

      final edge = tester.widget<RelayEdgeSweep>(find.byKey(const ValueKey('selected-device-edge-sweep')));
      final drift = tester.widget<RelayAtmosphericDrift>(find.byKey(const ValueKey('selected-device-drift')));
      final breath = tester.widget<RelayBreath>(find.byKey(const ValueKey('selected-device-breath')));
      expect(edge.ambient && edge.animationsEnabled && !reducedMotion, expectedActive);
      expect(drift.active && drift.animationsEnabled && !reducedMotion, expectedActive);
      expect(breath.active && breath.animationsEnabled && !reducedMotion, expectedActive);
    }

    await expectGate(selected: true, connected: true, animationsEnabled: true, reducedMotion: false, expectedActive: true);
    await expectGate(selected: false, connected: true, animationsEnabled: true, reducedMotion: false, expectedActive: false);
    await expectGate(selected: true, connected: false, animationsEnabled: true, reducedMotion: false, expectedActive: false);
    await expectGate(selected: true, connected: true, animationsEnabled: false, reducedMotion: false, expectedActive: false);
    await expectGate(selected: true, connected: true, animationsEnabled: true, reducedMotion: true, expectedActive: false);
  });

  testWidgets('reduced motion renders identical selected-device frames', (tester) async {
    await tester.pumpWidget(_subject(reducedMotion: true));
    await tester.pump();
    final before = await _captureHeader(tester);
    await tester.pump(const Duration(seconds: 3));
    final after = await _captureHeader(tester);
    final difference = _difference(before, after);
    expect(difference.maxChannelDelta, 0);
    expect(difference.changedPercent, 0);
  });

  test('selected-device perimeter uses the 14px major-surface geometry and 20-30% coverage', () {
    expect(RelayRadius.hero, 14);
    expect(RelayEdgeSweepPainter.ambientFraction, inInclusiveRange(0.20, 0.30));
    expect(RelayEdgeSweep.ambientPeriod.inMilliseconds, inInclusiveRange(6500, 9000));
  });
}
