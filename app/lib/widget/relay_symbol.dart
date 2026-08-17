import 'package:flutter/material.dart';

/// Relay's Direction-C handoff mark: two open endpoint tiles and the solid
/// packet between them on a shared 45-degree axis.
class RelaySymbol extends StatelessWidget {
  final double size;
  final Color? color;
  final String? semanticLabel;

  const RelaySymbol({super.key, this.size = 48, this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final symbol = CustomPaint(
      size: Size.square(size),
      painter: _RelaySymbolPainter(color),
    );
    return semanticLabel == null ? ExcludeSemantics(child: symbol) : Semantics(label: semanticLabel, image: true, child: symbol);
  }
}

class _RelaySymbolPainter extends CustomPainter {
  final Color? color;

  const _RelaySymbolPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 128;
    final shader = color == null
        ? const LinearGradient(
            colors: [Color(0xff5b8cff), Color(0xff6e79fb), Color(0xff8b5cf6)],
            stops: [0, 0.55, 1],
          ).createShader(Rect.fromLTWH(16 * scale, 16 * scale, 96 * scale, 96 * scale))
        : null;
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
  bool shouldRepaint(_RelaySymbolPainter oldDelegate) => color != oldDelegate.color;
}
