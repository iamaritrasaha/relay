import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// Layer B for the Hero surface: a soft, slowly drifting atmospheric gradient
/// matching the device's unique multicolor palette.
///
/// Drifts in an organic orbital path inside the card (12–16 seconds) while
/// maintaining strict text contrast and zero layout disruption.
class RelayAtmosphericDrift extends StatefulWidget {
  final Widget child;
  final RelayDevicePalette? palette;
  final bool active;
  final bool animationsEnabled;
  final double radius;

  const RelayAtmosphericDrift({
    super.key,
    required this.child,
    this.palette,
    this.active = true,
    this.animationsEnabled = true,
    this.radius = RelayRadius.hero,
  });

  @override
  State<RelayAtmosphericDrift> createState() => _RelayAtmosphericDriftState();
}

class _RelayAtmosphericDriftState extends State<RelayAtmosphericDrift> with SingleTickerProviderStateMixin {
  AnimationController? _localController;

  bool get _motionOn => widget.active && widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync(RelayAmbientClockNotifier? sharedClock) {
    if (sharedClock == null) {
      if (_motionOn) {
        _localController ??= AnimationController(
          vsync: this,
          duration: RelayMotion.ambientHeroDrift,
        );
        if (!_localController!.isAnimating) {
          unawaited(_localController!.repeat());
        }
      } else if (_localController != null && _localController!.isAnimating) {
        _localController!.stop();
        _localController!.value = 0;
      }
    } else if (_localController != null) {
      _localController!.stop();
      _localController!.dispose();
      _localController = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = RelayAmbientClock.maybeOf(context);
    _sync(clock);
  }

  @override
  void didUpdateWidget(covariant RelayAtmosphericDrift oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clock = RelayAmbientClock.maybeOf(context);
    _sync(clock);
  }

  @override
  void dispose() {
    _localController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_motionOn) {
      return widget.child;
    }

    final sharedClock = RelayAmbientClock.maybeOf(context);
    final brightness = Theme.of(context).brightness;
    final palette = widget.palette ?? RelayDevicePalette.fallback(brightness: brightness);

    return RepaintBoundary(
      child: CustomPaint(
        painter: RelayAtmosphericDriftPainter(
          repaint: (sharedClock?.cadenceClock ?? _localController)!,
          progressGetter: () => sharedClock != null ? sharedClock.phaseSlow : (_localController?.value ?? 0.0),
          palette: palette,
          radius: widget.radius,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Lightweight painter rendering moving radial color nodes with zero BackdropFilter overhead.
class RelayAtmosphericDriftPainter extends CustomPainter {
  final double Function() progressGetter;
  final RelayDevicePalette palette;
  final double radius;

  // Cached geometry and paints
  Size? _cachedSize;
  double? _cachedRadius;
  RRect? _cachedRRect;
  Rect? _cachedRect;

  final Paint _paint1 = Paint();
  final Paint _paint2 = Paint();

  RelayAtmosphericDriftPainter({
    required Listenable repaint,
    required this.progressGetter,
    required this.palette,
    required this.radius,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (_cachedRRect == null || _cachedSize != size || _cachedRadius != radius) {
      _cachedSize = size;
      _cachedRadius = radius;
      _cachedRect = Offset.zero & size;
      _cachedRRect = RRect.fromRectAndRadius(_cachedRect!, Radius.circular(radius));
    }

    final rect = _cachedRect!;
    final rrect = _cachedRRect!;

    canvas.save();
    canvas.clipRRect(rrect);

    final t = (progressGetter() + palette.phaseOffset) % 1.0;
    final angle = t * 2 * math.pi;
    final isDark = palette.isDark;

    // Node 1: Primary color drifting in top-left to bottom-right ellipse
    final node1X = size.width * (0.28 + 0.18 * math.cos(angle));
    final node1Y = size.height * (0.35 + 0.22 * math.sin(angle));
    final node1Alpha = isDark ? 0.08 : 0.05;

    _paint1.shader = RadialGradient(
      center: Alignment(
        (node1X / size.width) * 2 - 1,
        (node1Y / size.height) * 2 - 1,
      ),
      radius: 0.8,
      colors: [
        palette.primary.withValues(alpha: node1Alpha),
        palette.primary.withValues(alpha: 0.0),
      ],
    ).createShader(rect);

    canvas.drawRect(rect, _paint1);

    // Node 2: Secondary color drifting opposite quadrant
    final node2X = size.width * (0.72 - 0.16 * math.sin(angle));
    final node2Y = size.height * (0.65 - 0.20 * math.cos(angle));
    final node2Alpha = isDark ? 0.06 : 0.035;

    _paint2.shader = RadialGradient(
      center: Alignment(
        (node2X / size.width) * 2 - 1,
        (node2Y / size.height) * 2 - 1,
      ),
      radius: 0.75,
      colors: [
        palette.secondary.withValues(alpha: node2Alpha),
        palette.secondary.withValues(alpha: 0.0),
      ],
    ).createShader(rect);

    canvas.drawRect(rect, _paint2);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RelayAtmosphericDriftPainter oldDelegate) => oldDelegate.palette != palette || oldDelegate.radius != radius;
}
