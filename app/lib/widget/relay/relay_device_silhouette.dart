import 'package:flutter/material.dart';
import 'package:localsend_isolates/model/device.dart';

/// Minimal, monochrome forms for Relay medallions. This maps only existing
/// protocol categories and deliberately never infers a device from its name.
class RelayDeviceSilhouette extends StatelessWidget {
  final DeviceType deviceType;
  final Color color;
  final double size;

  const RelayDeviceSilhouette({super.key, required this.deviceType, required this.color, this.size = 52});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _RelayDeviceSilhouettePainter(_kindFor(deviceType), color));

  static _RelayDeviceKind _kindFor(DeviceType type) => switch (type) {
    DeviceType.mobile => _RelayDeviceKind.phone,
    DeviceType.desktop => _RelayDeviceKind.desktop,
    DeviceType.web => _RelayDeviceKind.laptop,
    DeviceType.headless || DeviceType.server => _RelayDeviceKind.fallback,
  };
}

enum _RelayDeviceKind { phone, tablet, laptop, desktop, fallback }

class _RelayDeviceSilhouettePainter extends CustomPainter {
  final _RelayDeviceKind kind;
  final Color color;

  const _RelayDeviceSilhouettePainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 56;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.75 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case _RelayDeviceKind.phone:
        _device(canvas, Rect.fromLTWH(18 * scale, 8 * scale, 20 * scale, 40 * scale), 5 * scale, paint, indicator: true);
        break;
      case _RelayDeviceKind.tablet:
        _device(canvas, Rect.fromLTWH(10 * scale, 13 * scale, 36 * scale, 30 * scale), 5 * scale, paint);
        break;
      case _RelayDeviceKind.laptop:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(10 * scale, 11 * scale, 36 * scale, 26 * scale), Radius.circular(4 * scale)), paint);
        canvas.drawLine(Offset(7 * scale, 43 * scale), Offset(49 * scale, 43 * scale), paint);
        break;
      case _RelayDeviceKind.desktop:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(8 * scale, 9 * scale, 40 * scale, 27 * scale), Radius.circular(4 * scale)), paint);
        canvas.drawLine(Offset(28 * scale, 37 * scale), Offset(28 * scale, 44 * scale), paint);
        canvas.drawLine(Offset(19 * scale, 45 * scale), Offset(37 * scale, 45 * scale), paint);
        break;
      case _RelayDeviceKind.fallback:
        _device(canvas, Rect.fromLTWH(13 * scale, 11 * scale, 30 * scale, 34 * scale), 5 * scale, paint);
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(Offset(21 * scale, 28 * scale), 1 * scale, paint);
        canvas.drawCircle(Offset(28 * scale, 28 * scale), 1 * scale, paint);
        canvas.drawCircle(Offset(35 * scale, 28 * scale), 1 * scale, paint);
        break;
    }
  }

  void _device(Canvas canvas, Rect rect, double radius, Paint paint, {bool indicator = false}) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    if (indicator) {
      canvas.drawLine(Offset(rect.center.dx - 2, rect.bottom - 5), Offset(rect.center.dx + 2, rect.bottom - 5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RelayDeviceSilhouettePainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.color != color;
}
