import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';

/// Painter for the connection beam and transfer stream between two spatial device nodes.
class RelayTransferStreamPainter extends CustomPainter {
  final Offset sourceOffset;
  final Offset targetOffset;
  final RelayDevicePhase phase;
  final double? progress;
  final double pulsePhase;
  final Color primaryColor;
  final Color accentColor;
  final bool isFocusedPair;

  const RelayTransferStreamPainter({
    required this.sourceOffset,
    required this.targetOffset,
    this.phase = RelayDevicePhase.idle,
    this.progress,
    this.pulsePhase = 0.0,
    required this.primaryColor,
    required this.accentColor,
    this.isFocusedPair = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final distance = (targetOffset - sourceOffset).distance;
    if (distance < 1.0) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isFocusedPair) {
      // Subtle glowing energy bridge between focused devices
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.18 + 0.08 * math.sin(pulsePhase * 2 * math.pi))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawLine(sourceOffset, targetOffset, glowPaint);

      linePaint
        ..color = accentColor.withValues(alpha: 0.55)
        ..strokeWidth = 1.8;

      canvas.drawLine(sourceOffset, targetOffset, linePaint);

      // Traveling ambient energy pulse along the bridge
      final travelingFraction = (pulsePhase % 1.0);
      final pulsePoint = Offset.lerp(sourceOffset, targetOffset, travelingFraction)!;
      final pulseDotPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pulsePoint, 2.5, pulseDotPaint);
    } else {
      // Very faint ambient tether line
      linePaint
        ..color = primaryColor.withValues(alpha: 0.10)
        ..strokeWidth = 1.0;
      canvas.drawLine(sourceOffset, targetOffset, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant RelayTransferStreamPainter oldDelegate) {
    return oldDelegate.sourceOffset != sourceOffset ||
        oldDelegate.targetOffset != targetOffset ||
        oldDelegate.phase != phase ||
        oldDelegate.progress != progress ||
        oldDelegate.pulsePhase != pulsePhase ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isFocusedPair != isFocusedPair;
  }
}

/// Reusable transfer stream widget bridging two nodes in the spatial scene.
class RelayTransferStream extends StatelessWidget {
  final Offset sourceOffset;
  final Offset targetOffset;
  final RelayDevicePhase phase;
  final double? progress;
  final double pulsePhase;
  final bool isFocusedPair;

  const RelayTransferStream({
    super.key,
    required this.sourceOffset,
    required this.targetOffset,
    this.phase = RelayDevicePhase.idle,
    this.progress,
    this.pulsePhase = 0.0,
    this.isFocusedPair = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return CustomPaint(
      painter: RelayTransferStreamPainter(
        sourceOffset: sourceOffset,
        targetOffset: targetOffset,
        phase: phase,
        progress: progress,
        pulsePhase: pulsePhase,
        primaryColor: palette.hairline,
        accentColor: palette.accent,
        isFocusedPair: isFocusedPair,
      ),
    );
  }
}
