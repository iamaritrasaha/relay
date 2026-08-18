import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// Native QR rendering for a public Relay pairing address.
///
/// It receives only the encoded address; routing keys and Relay private keys
/// never enter this widget or the normal UI.
class RelayPairingQr extends StatelessWidget {
  final String address;
  final double size;

  const RelayPairingQr({super.key, required this.address, this.size = 224});

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode.fromData(data: address, errorCorrectLevel: QrErrorCorrectLevel.M));
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _RelayPairingQrPainter(image)),
    );
  }
}

class _RelayPairingQrPainter extends CustomPainter {
  final QrImage _image;

  const _RelayPairingQrPainter(this._image);

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Colors.white;
    final foreground = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, background);
    const quietZone = 4;
    final module = size.shortestSide / (_image.moduleCount + quietZone * 2);
    for (var row = 0; row < _image.moduleCount; row++) {
      for (var column = 0; column < _image.moduleCount; column++) {
        if (_image.isDark(row, column)) {
          canvas.drawRect(Rect.fromLTWH((column + quietZone) * module, (row + quietZone) * module, module, module), foreground);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RelayPairingQrPainter oldDelegate) => oldDelegate._image != _image;
}
