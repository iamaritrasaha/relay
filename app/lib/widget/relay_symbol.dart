import 'dart:async';
import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// Relay's Direction-C handoff mark: two open endpoint tiles and the solid
/// packet between them on a shared 45-degree axis.
///
/// Supports smooth animated gradient flow through Relay's signature palette.
class RelaySymbol extends StatefulWidget {
  final double size;
  final Color? color;
  final RelayDevicePalette? palette;
  final bool animated;
  final String? semanticLabel;

  const RelaySymbol({
    super.key,
    this.size = 48,
    this.color,
    this.palette,
    this.animated = false,
    this.semanticLabel,
  });

  @override
  State<RelaySymbol> createState() => _RelaySymbolState();
}

class _RelaySymbolState extends State<RelaySymbol> {
  Timer? _localTimer;
  final Stopwatch _localStopwatch = Stopwatch();
  final ValueNotifier<double> _localPhase = ValueNotifier<double>(0.0);

  bool get _motionOn => widget.animated && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) && TickerMode.valuesOf(context).enabled;

  void _sync() {
    final sharedClock = RelayAmbientClock.maybeOf(context);
    if (sharedClock != null) {
      _stopLocalTimer();
      return;
    }

    if (_motionOn) {
      if (_localTimer == null || !_localTimer!.isActive) {
        if (!_localStopwatch.isRunning) {
          _localStopwatch.start();
        }
        _localTimer = Timer.periodic(const Duration(milliseconds: 83), (_) {
          if (!_motionOn) {
            _stopLocalTimer();
            return;
          }
          final seconds = _localStopwatch.elapsedMicroseconds / 1000000.0;
          _localPhase.value = (seconds / 7.5) % 1.0;
        });
      }
    } else {
      _stopLocalTimer();
    }
  }

  void _stopLocalTimer() {
    _localTimer?.cancel();
    _localTimer = null;
    _localStopwatch.stop();
    _localPhase.value = 0.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RelaySymbol oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) {
      _sync();
    }
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _localTimer = null;
    _localStopwatch.stop();
    _localPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sharedClock = RelayAmbientClock.maybeOf(context);
    final motionAllowed = _motionOn;

    Widget symbol;
    if (motionAllowed) {
      if (sharedClock != null) {
        symbol = AnimatedBuilder(
          animation: sharedClock.mediumClock,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _RelaySymbolPainter(
              widget.color,
              palette: widget.palette,
              phase: sharedClock.phaseMedium,
            ),
          ),
        );
      } else {
        symbol = AnimatedBuilder(
          animation: _localPhase,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _RelaySymbolPainter(
              widget.color,
              palette: widget.palette,
              phase: _localPhase.value,
            ),
          ),
        );
      }
    } else {
      symbol = CustomPaint(
        size: Size.square(widget.size),
        painter: _RelaySymbolPainter(
          widget.color,
          palette: widget.palette,
          phase: 0.0,
        ),
      );
    }

    return widget.semanticLabel == null ? ExcludeSemantics(child: symbol) : Semantics(label: widget.semanticLabel, image: true, child: symbol);
  }
}

class _RelaySymbolPainter extends CustomPainter {
  final Color? color;
  final RelayDevicePalette? palette;
  final double phase;

  const _RelaySymbolPainter(this.color, {this.palette, this.phase = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 128;
    Shader? shader;

    if (color == null) {
      final colors = palette != null ? palette!.gradientColors : const [Color(0xfff07855), Color(0xffe08a52), Color(0xffc89a55), Color(0xfff07855)];

      shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(phase * 2 * 3.141592653589793),
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }

    final paint = Paint()..color = color ?? Colors.white;
    if (shader != null) {
      paint.shader = shader;
    }

    if (size.shortestSide < 20) {
      _drawCompact(canvas, paint, scale);
    } else {
      _drawRegular(canvas, paint, scale);
    }
  }

  void _drawRegular(Canvas canvas, Paint paint, double scale) {
    final stroke = paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * scale;
    canvas.drawRRect(_tile(16, 16, 30, 10, scale), stroke);
    canvas.drawRRect(_tile(82, 82, 30, 10, scale), stroke);

    final packet = paint..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(64 * scale, 64 * scale);
    canvas.rotate(45 * 3.141592653589793 / 180);
    canvas.translate(-64 * scale, -64 * scale);
    canvas.drawRRect(_tile(53, 53, 22, 6, scale), packet);
    canvas.restore();
  }

  void _drawCompact(Canvas canvas, Paint paint, double scale) {
    final fill = paint..style = PaintingStyle.fill;
    canvas.drawRRect(_tile(10, 10, 42, 14, scale), fill);
    canvas.drawRRect(_tile(76, 76, 42, 14, scale), fill);
    canvas.save();
    canvas.translate(64 * scale, 64 * scale);
    canvas.rotate(45 * 3.141592653589793 / 180);
    canvas.translate(-64 * scale, -64 * scale);
    canvas.drawRRect(_tile(52, 52, 24, 7, scale), fill);
    canvas.restore();
  }

  RRect _tile(double x, double y, double edge, double radius, double scale) => RRect.fromRectAndRadius(
    Rect.fromLTWH(x * scale, y * scale, edge * scale, edge * scale),
    Radius.circular(radius * scale),
  );

  @override
  bool shouldRepaint(_RelaySymbolPainter oldDelegate) => color != oldDelegate.color || palette != oldDelegate.palette || phase != oldDelegate.phase;
}
