import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';

class RelayProgressRing extends StatelessWidget {
  final double size;
  final RelayDevicePhase phase;
  final double? progress;

  /// Optional content centred inside the ring. Relay's medallions draw the ring
  /// as an overlay *around* the device instead, so it is usually null.
  final Widget? child;
  final bool animationsEnabled;

  const RelayProgressRing({
    required this.size,
    required this.phase,
    required this.progress,
    required this.animationsEnabled,
    this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final targetProgress = switch (phase) {
      RelayDevicePhase.sending => progress ?? 0,
      RelayDevicePhase.success => 1.0,
      _ => null,
    };
    Widget buildRing(double? displayedProgress) => SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RelayProgressRingPainter(
          phase: phase,
          progress: displayedProgress,
          trackColor: colors.outlineVariant.withValues(alpha: 0.45),
          accentColor: phase == RelayDevicePhase.success ? colors.tertiary : colors.primary,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
    if (targetProgress == null) {
      return buildRing(null);
    }
    return TweenAnimationBuilder<double?>(
      tween: Tween(end: targetProgress),
      duration: RelayMotion.gated(RelayMotion.progressTransition, animationsEnabled),
      curve: RelayMotion.curve,
      builder: (context, animatedProgress, _) => buildRing(animatedProgress),
    );
  }
}

class _RelayProgressRingPainter extends CustomPainter {
  final RelayDevicePhase phase;
  final double? progress;
  final Color trackColor;
  final Color accentColor;

  const _RelayProgressRingPainter({
    required this.phase,
    required this.progress,
    required this.trackColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.0;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    if (phase == RelayDevicePhase.sending || phase == RelayDevicePhase.success) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = trackColor);
    }

    final sweep = switch (phase) {
      RelayDevicePhase.sending => math.pi * 2 * (progress ?? 0),
      RelayDevicePhase.success => math.pi * 2,
      RelayDevicePhase.waiting || RelayDevicePhase.verifying => math.pi * 0.28,
      _ => 0.0,
    };
    if (sweep > 0) {
      canvas.drawArc(rect, -math.pi / 2, sweep, false, paint..color = accentColor);
    }
  }

  @override
  bool shouldRepaint(covariant _RelayProgressRingPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.accentColor != accentColor;
  }
}
