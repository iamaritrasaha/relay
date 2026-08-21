import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// Ultra-soft, highly efficient ambient background atmosphere.
///
/// Slowly drifts 2 soft color fields derived from the active device's palette
/// behind the shell content. RepaintBoundary isolated with zero BackdropFilter or layout overhead.
class RelayAmbientBackground extends StatefulWidget {
  final Widget child;
  final RelayDevicePalette? palette;
  final bool animationsEnabled;

  const RelayAmbientBackground({
    super.key,
    required this.child,
    this.palette,
    this.animationsEnabled = true,
  });

  @override
  State<RelayAmbientBackground> createState() => _RelayAmbientBackgroundState();
}

class _RelayAmbientBackgroundState extends State<RelayAmbientBackground> with SingleTickerProviderStateMixin {
  AnimationController? _localController;

  bool get _motionOn => widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync(RelayAmbientClockNotifier? sharedClock) {
    if (sharedClock == null) {
      if (_motionOn) {
        _localController ??= AnimationController(
          vsync: this,
          duration: RelayMotion.ambientBackground,
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
  void didUpdateWidget(covariant RelayAmbientBackground oldWidget) {
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

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _RelayAmbientBackgroundPainter(
                repaint: (sharedClock?.backgroundClock ?? _localController)!,
                progressGetter: () => sharedClock != null ? sharedClock.phaseBackground : (_localController?.value ?? 0.0),
                palette: palette,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _RelayAmbientBackgroundPainter extends CustomPainter {
  final double Function() progressGetter;
  final RelayDevicePalette palette;

  final Paint _paint1 = Paint();
  final Paint _paint2 = Paint();
  Rect? _cachedRect;
  Size? _cachedSize;

  _RelayAmbientBackgroundPainter({
    required Listenable repaint,
    required this.progressGetter,
    required this.palette,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (_cachedRect == null || _cachedSize != size) {
      _cachedSize = size;
      _cachedRect = Offset.zero & size;
    }

    final rect = _cachedRect!;
    final t = (progressGetter() + palette.phaseOffset) % 1.0;
    final angle = t * 2 * math.pi;
    final isDark = palette.isDark;

    // Field 1: Drifting in upper-right
    final c1X = size.width * (0.80 + 0.12 * math.cos(angle));
    final c1Y = size.height * (0.25 + 0.15 * math.sin(angle));
    final alpha1 = isDark ? 0.035 : 0.022;

    _paint1.shader = RadialGradient(
      center: Alignment((c1X / size.width) * 2 - 1, (c1Y / size.height) * 2 - 1),
      radius: 0.9,
      colors: [
        palette.primary.withValues(alpha: alpha1),
        palette.primary.withValues(alpha: 0.0),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, _paint1);

    // Field 2: Drifting in lower-left
    final c2X = size.width * (0.20 - 0.14 * math.cos(angle * 0.8));
    final c2Y = size.height * (0.80 - 0.12 * math.sin(angle * 0.8));
    final alpha2 = isDark ? 0.028 : 0.018;

    _paint2.shader = RadialGradient(
      center: Alignment((c2X / size.width) * 2 - 1, (c2Y / size.height) * 2 - 1),
      radius: 0.85,
      colors: [
        palette.secondary.withValues(alpha: alpha2),
        palette.secondary.withValues(alpha: 0.0),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, _paint2);
  }

  @override
  bool shouldRepaint(covariant _RelayAmbientBackgroundPainter oldDelegate) => oldDelegate.palette != palette;
}
