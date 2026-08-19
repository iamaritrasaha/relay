import 'package:flutter/material.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';
import 'package:relay_app/widget/relay/relay_device_target.dart';

/// The devices themselves. On desktop they are placed with an alternating
/// stagger so the field reads as a space rather than a table; the offset comes
/// from the device's position in the (stably sorted) list, so it does not move
/// when a transfer starts.
class NearbyField extends StatelessWidget {
  final List<RelayDeviceVm> devices;
  final bool animationsEnabled;
  final bool payloadSelected;
  final ValueChanged<RelayDeviceVm>? onDeviceTap;
  final RelayResponsiveMetrics? metrics;

  const NearbyField({
    required this.devices,
    required this.animationsEnabled,
    required this.payloadSelected,
    this.onDeviceTap,
    this.metrics,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveTransfer = devices.any((device) => device.phase == RelayDevicePhase.sending);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = RelayDesktopMetrics.isDesktopWidth(constraints.maxWidth);
        final targets = [
          for (final device in devices)
            RelayDeviceTarget(
              device: device,
              animationsEnabled: animationsEnabled,
              payloadSelected: payloadSelected,
              dimmed: hasActiveTransfer && device.phase != RelayDevicePhase.sending,
              compact: !desktop,
              metrics: desktop ? metrics : null,
              onTap: onDeviceTap == null ? null : () => onDeviceTap!(device),
            ),
        ];

        if (!desktop) {
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 26,
            children: targets,
          );
        }

        // The gap shrinks before the stagger does — the placement is the point.
        final resolved = metrics ?? RelayDesktopMetrics.resolve(Size(constraints.maxWidth, 800));
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: resolved.deviceGap,
          runSpacing: resolved.deviceGap * 0.55,
          children: [
            for (final (index, target) in targets.indexed)
              Transform.translate(
                offset: Offset(0, index.isEven ? -resolved.deviceStagger : resolved.deviceStagger),
                child: target,
              ),
          ],
        );
      },
    );
  }
}
