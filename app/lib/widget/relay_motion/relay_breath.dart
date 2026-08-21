import 'dart:async';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';

/// Ambient luminosity breathing for the one or two focal surfaces on a page.
///
/// The overlay is painted *in front* of the child on purpose. Relay's surfaces
/// are matte and fully opaque, so a wash or an edge drawn behind them is
/// covered and never reaches the screen. Only the outer halo sits behind, where
/// the part that spills past the card is what shows.
///
/// Nothing scales: the card holds its exact shape and only its light moves, so
/// it reads as alive rather than as a pulsing button.
class RelayBreath extends StatefulWidget {
  final Widget child;
  final bool active;
  final bool animationsEnabled;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// One half-cycle. The controller reverses, so a full inhale/exhale is twice
  /// this — a little over five seconds, which is the slowest the motion can be
  /// while still being noticed inside the first few seconds of looking at it.
  static const Duration period = Duration(milliseconds: 2600);

  const RelayBreath({
    super.key,
    required this.child,
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
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: RelayBreath.period);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine);
  }

  /// Whether the caller wants motion, before the platform gets a say.
  bool get _wanted => widget.active && widget.animationsEnabled;

  bool get _motionOn => _wanted && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    if (_motionOn) {
      if (!_controller.isAnimating) {
        unawaited(_controller.repeat(reverse: true));
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  // Started here rather than in initState because whether the platform asks for
  // reduced motion is only knowable once dependencies are in place.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RelayBreath oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: widget.padding ?? EdgeInsets.zero, child: widget.child);

    if (!_motionOn) {
      return Container(margin: widget.margin, child: content);
    }

    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: widget.margin,
      child: RepaintBoundary(
        // The painters repaint off the animation directly, so a breath cycle
        // never rebuilds or re-lays-out the card underneath it.
        child: CustomPaint(
          painter: RelayBreathHaloPainter(animation: _animation, accent: palette.accent, radius: widget.radius, isDark: isDark),
          foregroundPainter: RelayBreathPainter(animation: _animation, accent: palette.accent, radius: widget.radius, isDark: isDark),
          child: content,
        ),
      ),
    );
  }
}

/// The part of the breath that lands on top of the surface: a warm wash that is
/// strongest along the top edge, and the accent edge itself.
class RelayBreathPainter extends CustomPainter {
  final Animation<double> animation;
  final Color accent;
  final double radius;
  final bool isDark;

  RelayBreathPainter({
    required this.animation,
    required this.accent,
    required this.radius,
    required this.isDark,
  }) : super(repaint: animation);

  /// Current point in the breath, for tests and diagnostics.
  double get progress => animation.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = animation.value;
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Luminance. Roughly a four percent swing, weighted to the top so the card
    // reads as catching light rather than being tinted.
    final wash = (isDark ? 0.014 : 0.012) + t * (isDark ? 0.042 : 0.034);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: wash),
            accent.withValues(alpha: wash * 0.25),
          ],
        ).createShader(rect),
    );

    // The edge is the part a person actually notices moving.
    final edgeAlpha = 0.10 + t * 0.12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.75), Radius.circular(radius - 0.75)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: edgeAlpha),
    );

    // A soft bloom hugging the inside of that edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(3.5), Radius.circular(radius - 3.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = accent.withValues(alpha: 0.016 + t * 0.038),
    );
  }

  @override
  bool shouldRepaint(covariant RelayBreathPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.radius != radius || oldDelegate.isDark != isDark;
}

/// The outer glow. Drawn behind the child, so only the spill past the card edge
/// is ever seen.
class RelayBreathHaloPainter extends CustomPainter {
  final Animation<double> animation;
  final Color accent;
  final double radius;
  final bool isDark;

  RelayBreathHaloPainter({
    required this.animation,
    required this.accent,
    required this.radius,
    required this.isDark,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = animation.value;
    final rect = Offset.zero & size;
    if (rect.width <= 12 || rect.height <= 12) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(6), Radius.circular(radius)),
      Paint()
        ..color = accent.withValues(alpha: (isDark ? 0.05 : 0.035) + t * (isDark ? 0.07 : 0.05))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 + t * 10),
    );
  }

  @override
  bool shouldRepaint(covariant RelayBreathHaloPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.radius != radius || oldDelegate.isDark != isDark;
}
