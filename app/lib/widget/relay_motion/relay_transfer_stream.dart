import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';

/// Painter for the connection beam, curved orbital bridge, and travelling payload stream.
class RelayTransferStreamPainter extends CustomPainter {
  final Offset sourceOffset;
  final Offset targetOffset;
  final RelayTransferDirection direction;
  final RelayDevicePhase phase;
  final double? progress;
  final double pulsePhase;
  final Color primaryColor;
  final Color accentColor;
  final Color successColor;
  final Color errorColor;
  final bool isFocusedPair;
  final int fileCount;
  final String? origin;

  const RelayTransferStreamPainter({
    required this.sourceOffset,
    required this.targetOffset,
    this.direction = RelayTransferDirection.send,
    this.phase = RelayDevicePhase.idle,
    this.progress,
    this.pulsePhase = 0.0,
    required this.primaryColor,
    required this.accentColor,
    required this.successColor,
    required this.errorColor,
    this.isFocusedPair = false,
    this.fileCount = 1,
    this.origin,
  });

  /// Computes the deterministic quadratic bezier control point guaranteeing
  /// a restrained, non-zero curvature that participates in orbital depth.
  static Offset computeControlPoint({
    required Offset sourceOffset,
    required Offset targetOffset,
    bool isFocusedPair = false,
  }) {
    final midPoint = (sourceOffset + targetOffset) / 2;
    final delta = targetOffset - sourceOffset;
    final distance = delta.distance;
    if (distance < 1.0) return midPoint;
    final normal = Offset(-delta.dy, delta.dx) / distance;
    // Signature spatial curvature: participate in the orbital universe without collapsing to straight line
    final double curvatureMagnitude = (distance * 0.13).clamp(16.0, 30.0);
    // Maintain a cohesive, premium arc orientation
    final double arcSign = (delta.dx * delta.dy < 0) ? -1.0 : 1.0;
    return midPoint + (normal * (curvatureMagnitude * arcSign));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final distance = (targetOffset - sourceOffset).distance;
    if (distance < 1.0) return;

    // Physical travel direction:
    // Send: departure from source (center) -> arrives at target (remote)
    // Receive: departure from target (remote) -> arrives at source (center)
    final departureOffset = direction == RelayTransferDirection.send ? sourceOffset : targetOffset;
    final arrivalOffset = direction == RelayTransferDirection.send ? targetOffset : sourceOffset;

    // Compute curved trajectory control point (subtle curve based on orbital orientation)
    final controlPoint = computeControlPoint(
      sourceOffset: sourceOffset,
      targetOffset: targetOffset,
      isFocusedPair: isFocusedPair,
    );

    final path = Path()
      ..moveTo(departureOffset.dx, departureOffset.dy)
      ..quadraticBezierTo(controlPoint.dx, controlPoint.dy, arrivalOffset.dx, arrivalOffset.dy);

    // 1. Render Underlying Connection Bridge Track
    if (phase != RelayDevicePhase.cancelled) {
      _paintConnectionBridge(canvas, path, departureOffset, arrivalOffset);
    }

    // 2. Render State-Driven Payload Stream / Epilogue
    if (phase == RelayDevicePhase.sending) {
      _paintPayloadStream(canvas, departureOffset, controlPoint, arrivalOffset);
    } else if (phase == RelayDevicePhase.waiting || phase == RelayDevicePhase.verifying) {
      _paintVerifyingPulse(canvas, departureOffset, controlPoint, arrivalOffset);
    } else if (phase == RelayDevicePhase.success) {
      _paintSuccessPulse(canvas, arrivalOffset);
    } else if (phase == RelayDevicePhase.failed) {
      _paintFailureBridge(canvas, path);
    } else if (phase == RelayDevicePhase.cancelled) {
      _paintCancelledBridge(canvas, departureOffset, controlPoint, arrivalOffset);
    }
  }

  void _paintConnectionBridge(Canvas canvas, Path path, Offset departure, Offset arrival) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isFocusedPair) {
      // Glowing relationship bridge
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.18 + 0.08 * math.sin(pulsePhase * 2 * math.pi))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawPath(path, glowPaint);

      linePaint
        ..color = accentColor.withValues(alpha: 0.50)
        ..strokeWidth = 1.8;
      canvas.drawPath(path, linePaint);
    } else {
      // Subtle orbital connection ray
      linePaint
        ..color = primaryColor.withValues(alpha: 0.12)
        ..strokeWidth = 1.2;
      canvas.drawPath(path, linePaint);
    }

    // Origin-specific nuance (Relayed connection waypoint indicator)
    if (origin == 'Relayed' || origin == 'relay') {
      final mid = (departure + arrival) / 2;
      final relayPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.70)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(mid, 3.0, relayPaint);
      canvas.drawCircle(
        mid,
        5.0 + 2.0 * math.sin(pulsePhase * 2 * math.pi),
        Paint()
          ..color = accentColor.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  void _paintPayloadStream(Canvas canvas, Offset p0, Offset pC, Offset p1) {
    final effectiveProgress = (progress ?? (pulsePhase % 1.0)).clamp(0.0, 1.0);
    final isDeterminate = progress != null;

    // Bounded number of travelling visual payload objects (3 to 5 particles)
    final int particleCount = (fileCount > 1) ? 5 : 3;

    for (int i = 0; i < particleCount; i++) {
      // Distribute particles along the travel path behind the leading progress head
      final double particleOffset = (i * 0.14);
      double t = (effectiveProgress - particleOffset);

      if (!isDeterminate) {
        // Continuous looping flow when progress is indeterminate
        t = ((pulsePhase + (i * (1.0 / particleCount))) % 1.0);
      }

      if (t < 0.0 || t > 1.0) continue;

      // Quadratic bezier evaluation: B(t) = (1-t)^2 P0 + 2(1-t)t Pc + t^2 P1
      final double invT = 1.0 - t;
      final double x = (invT * invT * p0.dx) + (2 * invT * t * pC.dx) + (t * t * p1.dx);
      final double y = (invT * invT * p0.dy) + (2 * invT * t * pC.dy) + (t * t * p1.dy);
      final particlePos = Offset(x, y);

      // Tangent vector for payload tile rotation
      final double dx = 2 * invT * (pC.dx - p0.dx) + 2 * t * (p1.dx - pC.dx);
      final double dy = 2 * invT * (pC.dy - p0.dy) + 2 * t * (p1.dy - pC.dy);
      final angle = math.atan2(dy, dx);

      // Particle intensity and scale fades in at start and out near completion
      final double alpha = (math.sin(t * math.pi)).clamp(0.2, 1.0);
      final bool isLead = (i == 0);

      canvas.save();
      canvas.translate(particlePos.dx, particlePos.dy);
      canvas.rotate(angle);

      // Luminous payload glow
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: (isLead ? 0.40 : 0.22) * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: isLead ? 14 : 10, height: isLead ? 9 : 6),
          const Radius.circular(3),
        ),
        glowPaint,
      );

      // Core luminous payload capsule/tile
      final tilePaint = Paint()
        ..color = isLead ? Colors.white : accentColor.withValues(alpha: 0.90 * alpha)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: isLead ? 10 : 7, height: isLead ? 6 : 4),
          const Radius.circular(2),
        ),
        tilePaint,
      );

      canvas.restore();
    }
  }

  void _paintVerifyingPulse(Canvas canvas, Offset p0, Offset pC, Offset p1) {
    // Subtle verification energy wave along bridge without byte particles
    final double waveT = (pulsePhase % 1.0);
    final double invT = 1.0 - waveT;
    final double x = (invT * invT * p0.dx) + (2 * invT * waveT * pC.dx) + (waveT * waveT * p1.dx);
    final double y = (invT * invT * p0.dy) + (2 * invT * waveT * pC.dy) + (waveT * waveT * p1.dy);

    final wavePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35 * math.sin(waveT * math.pi))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 3.5, wavePaint);
  }

  void _paintSuccessPulse(Canvas canvas, Offset destination) {
    // Soft completion ripple expanding around the receiving destination node
    final double rippleRadius = 20.0 + (32.0 * pulsePhase);
    final double rippleAlpha = (1.0 - pulsePhase).clamp(0.0, 1.0);

    final pulsePaint = Paint()
      ..color = successColor.withValues(alpha: 0.55 * rippleAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(destination, rippleRadius, pulsePaint);

    final innerGlow = Paint()
      ..color = successColor.withValues(alpha: 0.22 * rippleAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(destination, rippleRadius * 0.75, innerGlow);
  }

  void _paintFailureBridge(Canvas canvas, Path path) {
    final double fadeAlpha = (1.0 - pulsePhase).clamp(0.2, 1.0) * 0.38;
    final errorPaint = Paint()
      ..color = errorColor.withValues(alpha: fadeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * (1.0 - pulsePhase).clamp(0.3, 1.0);
    canvas.drawPath(path, errorPaint);
  }

  void _paintCancelledBridge(Canvas canvas, Offset p0, Offset pC, Offset p1) {
    // Stream retracts / fades toward source (departure)
    final double retractT = (1.0 - pulsePhase).clamp(0.0, 1.0);
    if (retractT <= 0.01) return;

    final retractPath = Path()..moveTo(p0.dx, p0.dy);
    const int segments = 20;
    final int count = (segments * retractT).ceil();
    for (int i = 1; i <= count; i++) {
      final double t = (i / segments) * retractT;
      final double invT = 1.0 - t;
      final double x = (invT * invT * p0.dx) + (2 * invT * t * pC.dx) + (t * t * p1.dx);
      final double y = (invT * invT * p0.dy) + (2 * invT * t * pC.dy) + (t * t * p1.dy);
      retractPath.lineTo(x, y);
    }

    final double fadeAlpha = (1.0 - pulsePhase).clamp(0.0, 1.0) * 0.35;
    final cancelPaint = Paint()
      ..color = accentColor.withValues(alpha: fadeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5 * (1.0 - pulsePhase).clamp(0.2, 1.0);
    canvas.drawPath(retractPath, cancelPaint);
  }

  @override
  bool shouldRepaint(covariant RelayTransferStreamPainter oldDelegate) {
    return oldDelegate.sourceOffset != sourceOffset ||
        oldDelegate.targetOffset != targetOffset ||
        oldDelegate.direction != direction ||
        oldDelegate.phase != phase ||
        oldDelegate.progress != progress ||
        oldDelegate.pulsePhase != pulsePhase ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.successColor != successColor ||
        oldDelegate.errorColor != errorColor ||
        oldDelegate.isFocusedPair != isFocusedPair ||
        oldDelegate.fileCount != fileCount ||
        oldDelegate.origin != origin;
  }
}

/// Reusable state-driven transfer stream widget bridging source and destination in the spatial scene.
class RelayTransferStream extends StatelessWidget {
  final Offset sourceOffset;
  final Offset targetOffset;
  final RelayTransferDirection direction;
  final RelayDevicePhase phase;
  final double? progress;
  final double pulsePhase;
  final RelayDevicePalette? devicePalette;
  final bool isFocusedPair;
  final int fileCount;
  final String? origin;

  const RelayTransferStream({
    super.key,
    required this.sourceOffset,
    required this.targetOffset,
    this.direction = RelayTransferDirection.send,
    this.phase = RelayDevicePhase.idle,
    this.progress,
    this.pulsePhase = 0.0,
    this.devicePalette,
    this.isFocusedPair = false,
    this.fileCount = 1,
    this.origin,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return CustomPaint(
      painter: RelayTransferStreamPainter(
        sourceOffset: sourceOffset,
        targetOffset: targetOffset,
        direction: direction,
        phase: phase,
        progress: progress,
        pulsePhase: pulsePhase,
        primaryColor: palette.hairline,
        accentColor: devicePalette?.primary ?? palette.accent,
        successColor: palette.success,
        errorColor: palette.error,
        isFocusedPair: isFocusedPair,
        fileCount: fileCount,
        origin: origin,
      ),
    );
  }
}
