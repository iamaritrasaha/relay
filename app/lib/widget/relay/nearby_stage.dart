import 'package:flutter/material.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/relay/nearby_field.dart';

class NearbyStage extends StatelessWidget {
  final List<RelayDeviceVm> devices;
  final bool animationsEnabled;
  final bool payloadSelected;
  final ValueChanged<RelayDeviceVm>? onDeviceTap;

  const NearbyStage({
    required this.devices,
    required this.animationsEnabled,
    required this.payloadSelected,
    this.onDeviceTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final empty = devices.isEmpty;
    return SizedBox(
      height: empty ? 238 : 286,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          const Positioned.fill(child: _NearbyAtmosphere()),
          Column(
            children: [
              Text('Nearby devices', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: empty ? 26 : 30),
              if (empty)
                Column(
                  children: [
                    Icon(Icons.radar_rounded, size: 36, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)),
                    const SizedBox(height: 13),
                    Text('Looking nearby…', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Keep Relay open on your other device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                )
              else
                NearbyField(
                  devices: devices,
                  animationsEnabled: animationsEnabled,
                  payloadSelected: payloadSelected,
                  onDeviceTap: onDeviceTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NearbyAtmosphere extends StatelessWidget {
  const _NearbyAtmosphere();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, 0.2),
            radius: 0.72,
            colors: [color.withValues(alpha: 0.075), color.withValues(alpha: 0.022), Colors.transparent],
            stops: const [0, 0.56, 1],
          ),
        ),
        child: CustomPaint(painter: _NearbyRingsPainter(color.withValues(alpha: 0.08))),
      ),
    );
  }
}

class _NearbyRingsPainter extends CustomPainter {
  final Color color;

  const _NearbyRingsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.57);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final radius in [72.0, 128.0, 196.0]) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NearbyRingsPainter oldDelegate) => oldDelegate.color != color;
}
