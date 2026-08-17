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
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Nearby',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        SizedBox(height: empty ? 34 : 30),
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                Icon(Icons.near_me_outlined, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 13),
                Text('Looking nearby…', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Keep Relay open on your other device.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          NearbyField(
            devices: devices,
            animationsEnabled: animationsEnabled,
            payloadSelected: payloadSelected,
            onDeviceTap: onDeviceTap,
          ),
      ],
    );
  }
}
