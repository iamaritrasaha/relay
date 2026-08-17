import 'package:flutter/material.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/relay/relay_device_target.dart';

class NearbyField extends StatelessWidget {
  final List<RelayDeviceVm> devices;
  final bool animationsEnabled;
  final bool payloadSelected;
  final ValueChanged<RelayDeviceVm>? onDeviceTap;

  const NearbyField({
    required this.devices,
    required this.animationsEnabled,
    required this.payloadSelected,
    this.onDeviceTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveTransfer = devices.any((device) => device.phase == RelayDevicePhase.sending);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 48,
      runSpacing: 36,
      children: [
        for (final device in devices)
          RelayDeviceTarget(
            device: device,
            animationsEnabled: animationsEnabled,
            payloadSelected: payloadSelected,
            dimmed: hasActiveTransfer && device.phase != RelayDevicePhase.sending,
            onTap: onDeviceTap == null ? null : () => onDeviceTap!(device),
          ),
      ],
    );
  }
}
