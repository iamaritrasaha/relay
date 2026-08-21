import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// A warm accent segment travelling the rounded perimeter of a focal surface.
///
/// Two modes share one painter:
///
///  * [ambient] runs continuously while the surface is the live subject of the
///    page. One slow circuit is the low-level sign that the link is up.
///  * [trigger] fires a single brighter, faster circuit when something actually
///    happened — a device connecting, a transfer starting, a message arriving.
///
/// The segment is feathered by splitting it into slices and fading each one on
/// a sine envelope, which follows the corner curves correctly. A gradient
/// across the bounding box, which is what a naive version uses, fades against
/// the box instead of along the path and reads as a flat smear.
class RelayEdgeSweep extends StatefulWidget {
  final Widget child;
  final double radius;

  /// Fires one brighter circuit on the rising edge.
  final bool trigger;

  /// Fires one circuit whenever this value changes. Use it for events that are
  /// identified rather than flagged — a new message id, a transfer id — where a
  /// boolean cannot distinguish "still true" from "happened again".
  final Object? burstKey;

  /// Keeps a quieter segment travelling for as long as it stays true.
  final bool ambient;

  final bool animationsEnabled;
  final EdgeInsetsGeometry? padding;

  /// One full ambient circuit. Slow enough to be calm, quick enough that a
  /// person watching the card sees the colour move.
  static const Duration ambientPeriod = Duration(milliseconds: 8500);

  /// One event circuit.
  static const Duration burstPeriod = Duration(milliseconds: 1100);

  const RelayEdgeSweep({
    super.key,
    required this.child,
    this.radius = RelayRadius.card,
    this.trigger = false,
    this.burstKey,
    this.ambient = false,
    this.animationsEnabled = true,
    this.padding,
  });

  @override
  State<RelayEdgeSweep> createState() => _RelayEdgeSweepState();
}

class _RelayEdgeSweepState extends State<RelayEdgeSweep> with TickerProviderStateMixin {
  late final AnimationController _ambient;
  late final AnimationController _burst;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(vsync: this, duration: RelayEdgeSweep.ambientPeriod);
    _burst = AnimationController(vsync: this, duration: RelayEdgeSweep.burstPeriod);
  }

  bool get _motionOn => widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    if (widget.ambient && _motionOn) {
      if (!_ambient.isAnimating) {
        unawaited(_ambient.repeat());
      }
    } else if (_ambient.isAnimating) {
      _ambient.stop();
      _ambient.value = 0;
    }
    if (!_motionOn && _burst.isAnimating) {
      _burst.stop();
      _burst.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RelayEdgeSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final triggered = widget.trigger && !oldWidget.trigger;
    final keyed = widget.burstKey != null && widget.burstKey != oldWidget.burstKey;
    if ((triggered || keyed) && _motionOn) {
      unawaited(_burst.forward(from: 0));
    }
    _sync();
  }

  @override
  void dispose() {
    _ambient.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: widget.padding ?? EdgeInsets.zero, child: widget.child);

    if (!_motionOn) {
      return RepaintBoundary(child: content);
    }

    final palette = Theme.of(context).relayPalette;

    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: RelayEdgeSweepPainter(
          ambient: _ambient,
          burst: _burst,
          ambientEnabled: widget.ambient,
          radius: widget.radius,
          coral: palette.accent,
          copper: palette.accentSecondary,
          amber: Color.lerp(palette.accentSecondary, palette.accentSoft, 0.35)!,
        ),
        child: content,
      ),
    );
  }
}

/// Paints the travelling segment. Public so a test can read [progress] straight
/// off the live painter instead of inferring motion from a screenshot.
class RelayEdgeSweepPainter extends CustomPainter {
  final Animation<double> ambient;
  final Animation<double> burst;
  final bool ambientEnabled;
  final double radius;
  final Color coral;
  final Color copper;
  final Color amber;

  /// Fraction of the perimeter the ambient segment covers.
  static const double ambientFraction = 0.16;
  static const double burstFraction = 0.22;

  static const double _strokeWidth = 2.0;
  static const int _slices = 18;

  RelayEdgeSweepPainter({
    required this.ambient,
    required this.burst,
    required this.ambientEnabled,
    required this.radius,
    required this.coral,
    required this.copper,
    required this.amber,
  }) : super(repaint: Listenable.merge([ambient, burst]));

  /// Where the ambient segment currently sits on the perimeter, 0..1.
  double get progress => ambient.value;

  /// Whether anything is currently being drawn.
  bool get isPainting => ambientEnabled || (burst.value > 0 && burst.value < 1);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const inset = _strokeWidth / 2 + 0.5;
    final rect = (Offset.zero & size).deflate(inset);
    if (rect.width <= 0 || rect.height <= 0) return;

    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - inset))));
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    if (metric.length <= 0) return;

    if (ambientEnabled) {
      _paintSegment(canvas, metric, center: ambient.value, fraction: ambientFraction, peak: 0.62);
    }

    final b = burst.value;
    if (b > 0 && b < 1) {
      // Fades in and out over its own circuit so an event never leaves a hard
      // edge appearing or disappearing on the card.
      _paintSegment(canvas, metric, center: b, fraction: burstFraction, peak: 0.9 * math.sin(math.pi * b));
    }
  }

  void _paintSegment(Canvas canvas, PathMetric metric, {required double center, required double fraction, required double peak}) {
    if (peak <= 0.01) return;
    final total = metric.length;
    final segment = total * fraction;
    final head = center * total - segment / 2;

    for (var i = 0; i < _slices; i++) {
      final mid = (i + 0.5) / _slices;
      final envelope = math.pow(math.sin(math.pi * mid), 1.6).toDouble();
      if (envelope <= 0.02) continue;

      // A hair of overlap keeps the slices reading as one continuous segment.
      final start = head + segment * (i / _slices);
      final end = start + segment / _slices + 0.6;
      final color = _ramp(mid);

      _stroke(canvas, metric, start, end, total, color.withValues(alpha: peak * envelope * 0.2), _strokeWidth * 3.4);
      _stroke(canvas, metric, start, end, total, color.withValues(alpha: peak * envelope), _strokeWidth);
    }
  }

  void _stroke(Canvas canvas, PathMetric metric, double start, double end, double total, Color color, double width) {
    var s = start % total;
    if (s < 0) s += total;
    var e = s + (end - start);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color;

    if (e > total) {
      canvas.drawPath(metric.extractPath(s, total), paint);
      canvas.drawPath(metric.extractPath(0, e - total), paint);
    } else {
      canvas.drawPath(metric.extractPath(s, e), paint);
    }
  }

  Color _ramp(double t) => t < 0.5 ? Color.lerp(coral, copper, t * 2)! : Color.lerp(copper, amber, (t - 0.5) * 2)!;

  @override
  bool shouldRepaint(covariant RelayEdgeSweepPainter oldDelegate) =>
      oldDelegate.ambientEnabled != ambientEnabled ||
      oldDelegate.radius != radius ||
      oldDelegate.coral != coral ||
      oldDelegate.copper != copper ||
      oldDelegate.amber != amber;
}
