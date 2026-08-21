import 'dart:async';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// Ambient luminosity breathing for the one or two focal surfaces on a page.
///
/// Interpolates subtly between combinations of the device palette on the breath cycle
/// (~5.2 seconds full cycle), moving only light and color with zero layout scaling.
class RelayBreath extends StatefulWidget {
  final Widget child;
  final RelayDevicePalette? palette;
  final bool active;
  final bool animationsEnabled;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// One half-cycle. The controller reverses, so a full inhale/exhale is twice this.
  static const Duration period = Duration(milliseconds: 2600);

  const RelayBreath({
    super.key,
    required this.child,
    this.palette,
    this.active = true,
    this.animationsEnabled = true,
    this.radius = RelayRadius.panel,
    this.margin,
    this.padding,
  });

  @override
  State<RelayBreath> createState() => _RelayBreathState();
}

class _RelayBreathState extends State<RelayBreath> with SingleTickerProviderStateMixin {
  AnimationController? _localController;
  Animation<double>? _localAnimation;

  /// Whether the caller wants motion, before the platform gets a say.
  bool get _wanted => widget.active && widget.animationsEnabled;

  bool get _motionOn => _wanted && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync(RelayAmbientClockNotifier? sharedClock) {
    if (sharedClock == null) {
      if (_motionOn) {
        if (_localController == null) {
          _localController = AnimationController(vsync: this, duration: RelayBreath.period);
          _localAnimation = CurvedAnimation(parent: _localController!, curve: Curves.easeInOutSine);
        }
        if (!_localController!.isAnimating) {
          unawaited(_localController!.repeat(reverse: true));
        }
      } else if (_localController != null && _localController!.isAnimating) {
        _localController!.stop();
        _localController!.value = 0;
      }
    } else if (_localController != null) {
      _localController!.stop();
      _localController!.dispose();
      _localController = null;
      _localAnimation = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = RelayAmbientClock.maybeOf(context);
    _sync(clock);
  }

  @override
  void didUpdateWidget(covariant RelayBreath oldWidget) {
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
    final content = Padding(padding: widget.padding ?? EdgeInsets.zero, child: widget.child);

    if (!_motionOn) {
      return Container(margin: widget.margin, child: content);
    }

    final sharedClock = RelayAmbientClock.maybeOf(context);
    final theme = Theme.of(context);
    final fallbackPalette = theme.relayPalette;
    final isDark = theme.brightness == Brightness.dark;
    final devicePalette = widget.palette ?? RelayDevicePalette.fallback(brightness: theme.brightness);
    final Listenable repaint = (sharedClock?.cadenceClock ?? _localAnimation ?? _localController)!;
    double progressGetter() => sharedClock != null ? sharedClock.breathValue : (_localAnimation?.value ?? 0.0);

    return Container(
      margin: widget.margin,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: RelayBreathHaloPainter(
            repaint: repaint,
            progressGetter: progressGetter,
            palette: devicePalette,
            accent: fallbackPalette.accent,
            radius: widget.radius,
            isDark: isDark,
          ),
          foregroundPainter: RelayBreathPainter(
            repaint: repaint,
            progressGetter: progressGetter,
            palette: devicePalette,
            accent: fallbackPalette.accent,
            radius: widget.radius,
            isDark: isDark,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// The part of the breath that lands on top of the surface: an atmospheric wash
/// that smoothly shifts between primary and secondary device tones.
class RelayBreathPainter extends CustomPainter {
  final double Function() progressGetter;
  final RelayDevicePalette? palette;
  final Color accent;
  final double radius;
  final bool isDark;

  // Cached geometry and paints
  Size? _cachedSize;
  double? _cachedRadius;
  RRect? _cachedShape;
  RRect? _cachedEdgeShape;
  RRect? _cachedBloomShape;
  Rect? _cachedRect;

  final Paint _washPaint = Paint();
  final Paint _edgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  final Paint _bloomPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5;

  RelayBreathPainter({
    required Listenable repaint,
    required this.progressGetter,
    this.palette,
    required this.accent,
    required this.radius,
    required this.isDark,
  }) : super(repaint: repaint);

  /// Current point in the breath, for tests and diagnostics.
  double get progress => progressGetter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progressGetter();

    if (_cachedShape == null || _cachedSize != size || _cachedRadius != radius) {
      _cachedSize = size;
      _cachedRadius = radius;
      _cachedRect = Offset.zero & size;
      _cachedShape = RRect.fromRectAndRadius(_cachedRect!, Radius.circular(radius));
      _cachedEdgeShape = RRect.fromRectAndRadius(_cachedRect!.deflate(0.75), Radius.circular(radius - 0.75));
      _cachedBloomShape = RRect.fromRectAndRadius(_cachedRect!.deflate(2.5), Radius.circular(radius - 2.5));
    }

    final rect = _cachedRect!;
    final shape = _cachedShape!;
    final edgeShape = _cachedEdgeShape!;
    final bloomShape = _cachedBloomShape!;

    final effectiveColor1 = palette?.primary ?? accent;
    final effectiveColor2 = palette?.secondary ?? accent;
    final activeAccent = Color.lerp(effectiveColor1, effectiveColor2, t * 0.75)!;

    // Luminance wash
    final wash = (isDark ? 0.016 : 0.014) + t * (isDark ? 0.048 : 0.038);
    _washPaint.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        activeAccent.withValues(alpha: wash),
        (palette?.tertiary ?? activeAccent).withValues(alpha: wash * 0.2),
      ],
    ).createShader(rect);
    canvas.drawRRect(shape, _washPaint);

    // Dynamic edge accent
    final edgeAlpha = 0.12 + t * 0.16;
    _edgePaint.color = activeAccent.withValues(alpha: edgeAlpha);
    canvas.drawRRect(edgeShape, _edgePaint);

    // Inner subtle bloom without expensive software CPU blur
    _bloomPaint.color = (palette?.secondary ?? activeAccent).withValues(alpha: 0.03 + t * 0.05);
    canvas.drawRRect(bloomShape, _bloomPaint);
  }

  @override
  bool shouldRepaint(covariant RelayBreathPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.palette != palette || oldDelegate.radius != radius || oldDelegate.isDark != isDark;
}

/// The outer glow. Drawn behind the child, so only the spill past the card edge is seen.
class RelayBreathHaloPainter extends CustomPainter {
  final double Function() progressGetter;
  final RelayDevicePalette? palette;
  final Color accent;
  final double radius;
  final bool isDark;

  // Cached geometry and paints
  Size? _cachedSize;
  double? _cachedRadius;
  RRect? _cachedHaloShape1;
  RRect? _cachedHaloShape2;

  final Paint _haloPaint1 = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.0;

  final Paint _haloPaint2 = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14.0;

  RelayBreathHaloPainter({
    required Listenable repaint,
    required this.progressGetter,
    this.palette,
    required this.accent,
    required this.radius,
    required this.isDark,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progressGetter();
    final rect = Offset.zero & size;
    if (rect.width <= 12 || rect.height <= 12) return;

    if (_cachedHaloShape1 == null || _cachedSize != size || _cachedRadius != radius) {
      _cachedSize = size;
      _cachedRadius = radius;
      _cachedHaloShape1 = RRect.fromRectAndRadius(rect.inflate(2.0), Radius.circular(radius + 2.0));
      _cachedHaloShape2 = RRect.fromRectAndRadius(rect.inflate(5.0), Radius.circular(radius + 5.0));
    }

    final haloColor = palette?.primary ?? accent;
    final alpha = (isDark ? 0.045 : 0.03) + t * (isDark ? 0.065 : 0.045);

    _haloPaint1.color = haloColor.withValues(alpha: alpha * 0.7);
    canvas.drawRRect(_cachedHaloShape1!, _haloPaint1);

    _haloPaint2.color = haloColor.withValues(alpha: alpha * 0.35);
    canvas.drawRRect(_cachedHaloShape2!, _haloPaint2);
  }

  @override
  bool shouldRepaint(covariant RelayBreathHaloPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.palette != palette || oldDelegate.radius != radius || oldDelegate.isDark != isDark;
}
