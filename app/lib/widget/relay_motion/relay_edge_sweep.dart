import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// A vibrant multicolor accent segment travelling the rounded perimeter of a focal surface.
///
/// Supports device-specific multicolor palettes (`RelayDevicePalette`), seamlessly
/// rendering the device's unique color identity (e.g. coral -> amber -> magenta -> violet).
///
/// Two modes share one painter:
///  * [ambient] runs continuously while the surface is the live subject of the
///    page. One full circuit is the sign that the link is live.
///  * [trigger] fires a single brighter, faster circuit when something actually
///    happened — a device connecting, a transfer starting, a message arriving.
class RelayEdgeSweep extends StatefulWidget {
  final Widget child;
  final double radius;
  final RelayDevicePalette? palette;

  /// Fires one brighter circuit on the rising edge.
  final bool trigger;

  /// Fires one circuit whenever this value changes.
  final Object? burstKey;

  /// Keeps a segment travelling for as long as it stays true.
  final bool ambient;

  final bool animationsEnabled;
  final EdgeInsetsGeometry? padding;

  /// One full ambient circuit (~7.5 seconds).
  static const Duration ambientPeriod = RelayMotion.ambientHeroPerimeter;

  /// One event circuit (~1.1 seconds).
  static const Duration burstPeriod = RelayMotion.connectionEvent;

  const RelayEdgeSweep({
    super.key,
    required this.child,
    this.radius = RelayRadius.card,
    this.palette,
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
  AnimationController? _ambientLocal;
  late final AnimationController _burst;

  @override
  void initState() {
    super.initState();
    _burst = AnimationController(vsync: this, duration: RelayEdgeSweep.burstPeriod);
  }

  bool get _motionOn => widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync(RelayAmbientClockNotifier? sharedClock) {
    if (sharedClock == null) {
      if (widget.ambient && _motionOn) {
        _ambientLocal ??= AnimationController(vsync: this, duration: RelayEdgeSweep.ambientPeriod);
        if (!_ambientLocal!.isAnimating) {
          unawaited(_ambientLocal!.repeat());
        }
      } else if (_ambientLocal != null && _ambientLocal!.isAnimating) {
        _ambientLocal!.stop();
        _ambientLocal!.value = 0;
      }
    } else if (_ambientLocal != null) {
      _ambientLocal!.stop();
      _ambientLocal!.dispose();
      _ambientLocal = null;
    }

    if (!_motionOn && _burst.isAnimating) {
      _burst.stop();
      _burst.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = RelayAmbientClock.maybeOf(context);
    _sync(clock);
  }

  @override
  void didUpdateWidget(covariant RelayEdgeSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clock = RelayAmbientClock.maybeOf(context);
    final triggered = widget.trigger && !oldWidget.trigger;
    final keyed = widget.burstKey != null && widget.burstKey != oldWidget.burstKey;
    if ((triggered || keyed) && _motionOn) {
      unawaited(_burst.forward(from: 0));
    }
    _sync(clock);
  }

  @override
  void dispose() {
    _ambientLocal?.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: widget.padding ?? EdgeInsets.zero, child: widget.child);

    if (!_motionOn) {
      return RepaintBoundary(child: content);
    }

    final sharedClock = RelayAmbientClock.maybeOf(context);
    final theme = Theme.of(context);
    final fallbackPalette = theme.relayPalette;
    final devicePalette = widget.palette ?? RelayDevicePalette.fallback(brightness: theme.brightness);

    final Listenable repaint = sharedClock != null
        ? Listenable.merge([sharedClock.fastClock, _burst])
        : Listenable.merge([_ambientLocal ?? _burst, _burst]);

    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: RelayEdgeSweepPainter(
          repaint: repaint,
          ambientProgressGetter: () => sharedClock != null ? sharedClock.phaseMedium : (_ambientLocal?.value ?? 0.0),
          burst: _burst,
          ambientEnabled: widget.ambient,
          radius: widget.radius,
          palette: devicePalette,
          coral: fallbackPalette.accent,
          copper: fallbackPalette.accentSecondary,
          amber: Color.lerp(fallbackPalette.accentSecondary, fallbackPalette.accentSoft, 0.35)!,
        ),
        child: content,
      ),
    );
  }
}

/// Paints the travelling multicolor segment along the perimeter.
class RelayEdgeSweepPainter extends CustomPainter {
  final double Function() ambientProgressGetter;
  final Animation<double> burst;
  final bool ambientEnabled;
  final double radius;
  final RelayDevicePalette? palette;
  final Color coral;
  final Color copper;
  final Color amber;

  /// Fraction of the perimeter the ambient segment covers (24%).
  static const double ambientFraction = 0.24;
  static const double burstFraction = 0.28;

  static const double _strokeWidth = 2.2;
  static const int _slices = 8;

  // Cached geometry and paints
  Size? _cachedSize;
  double? _cachedRadius;
  PathMetric? _cachedMetric;

  final Paint _bloomPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = _strokeWidth * 3.2;

  final Paint _corePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = _strokeWidth;

  RelayEdgeSweepPainter({
    required Listenable repaint,
    required this.ambientProgressGetter,
    required this.burst,
    required this.ambientEnabled,
    required this.radius,
    this.palette,
    required this.coral,
    required this.copper,
    required this.amber,
  }) : super(repaint: repaint);

  /// Where the ambient segment currently sits on the perimeter, 0..1.
  double get progress => ambientProgressGetter();

  /// Whether anything is currently being drawn.
  bool get isPainting => ambientEnabled || (burst.value > 0 && burst.value < 1);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const inset = _strokeWidth / 2 + 0.5;
    final rect = (Offset.zero & size).deflate(inset);
    if (rect.width <= 0 || rect.height <= 0) return;

    if (_cachedMetric == null || _cachedSize != size || _cachedRadius != radius) {
      _cachedSize = size;
      _cachedRadius = radius;
      final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - inset))));
      final metrics = path.computeMetrics().toList();
      _cachedMetric = metrics.isNotEmpty ? metrics.first : null;
    }

    final metric = _cachedMetric;
    if (metric == null || metric.length <= 0) return;

    final phaseOffset = palette?.phaseOffset ?? 0.0;

    if (ambientEnabled) {
      final ambientProgress = (ambientProgressGetter() + phaseOffset) % 1.0;
      _paintSegment(canvas, metric, center: ambientProgress, fraction: ambientFraction, peak: 0.85);
    }

    final b = burst.value;
    if (b > 0 && b < 1) {
      _paintSegment(canvas, metric, center: b, fraction: burstFraction, peak: 0.95 * math.sin(math.pi * b));
    }
  }

  void _paintSegment(Canvas canvas, PathMetric metric, {required double center, required double fraction, required double peak}) {
    if (peak <= 0.01) return;
    final total = metric.length;
    final segment = total * fraction;
    final head = center * total - segment / 2;

    for (var i = 0; i < _slices; i++) {
      final mid = (i + 0.5) / _slices;
      final envelope = math.pow(math.sin(math.pi * mid), 1.5).toDouble();
      if (envelope <= 0.02) continue;

      final start = head + segment * (i / _slices);
      final end = start + segment / _slices + 0.8;
      final color = _ramp(mid);

      // Outer luminous bloom
      _bloomPaint.color = color.withValues(alpha: peak * envelope * 0.35);
      _stroke(canvas, metric, start, end, total, _bloomPaint);

      // Core crisp stroke
      _corePaint.color = color.withValues(alpha: peak * envelope);
      _stroke(canvas, metric, start, end, total, _corePaint);
    }
  }

  void _stroke(Canvas canvas, PathMetric metric, double start, double end, double total, Paint paint) {
    var s = start % total;
    if (s < 0) s += total;
    var e = s + (end - start);

    if (e > total) {
      canvas.drawPath(metric.extractPath(s, total), paint);
      canvas.drawPath(metric.extractPath(0, e - total), paint);
    } else {
      canvas.drawPath(metric.extractPath(s, e), paint);
    }
  }

  Color _ramp(double t) {
    if (palette != null) {
      final colors = palette!.perimeterColors;
      final scaled = t.clamp(0.0, 1.0) * (colors.length - 1);
      final index = scaled.floor().clamp(0, colors.length - 2);
      final localT = scaled - index;
      return Color.lerp(colors[index], colors[index + 1], localT)!;
    }
    return t < 0.5 ? Color.lerp(coral, copper, t * 2)! : Color.lerp(copper, amber, (t - 0.5) * 2)!;
  }

  @override
  bool shouldRepaint(covariant RelayEdgeSweepPainter oldDelegate) =>
      oldDelegate.ambientEnabled != ambientEnabled ||
      oldDelegate.radius != radius ||
      oldDelegate.palette != palette ||
      oldDelegate.coral != coral ||
      oldDelegate.copper != copper ||
      oldDelegate.amber != amber;
}
