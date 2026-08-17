import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/relay/nearby_field.dart';
import 'package:localsend_app/widget/relay/relay_desktop_metrics.dart';
import 'package:localsend_app/widget/relay/relay_waiting_beacon.dart';
import 'package:localsend_isolates/model/device.dart';

/// The nearby field: the region Home is actually about.
///
/// It is bounded rather than open — a hairline above and a faint wash from the
/// top — so the space around the devices reads as composed instead of leftover.
class NearbyStage extends StatelessWidget {
  final List<RelayDeviceVm> devices;
  final DeviceType selfDeviceType;
  final bool animationsEnabled;
  final bool payloadSelected;
  final bool compact;
  final ValueChanged<RelayDeviceVm>? onDeviceTap;
  final RelayResponsiveMetrics? metrics;

  const NearbyStage({
    required this.devices,
    required this.selfDeviceType,
    required this.animationsEnabled,
    required this.payloadSelected,
    this.compact = false,
    this.onDeviceTap,
    this.metrics,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final content = devices.isEmpty
        ? _WaitingState(selfDeviceType: selfDeviceType, compact: compact, scale: metrics?.emptyStateScale ?? 1)
        : NearbyField(
            devices: devices,
            animationsEnabled: animationsEnabled,
            payloadSelected: payloadSelected,
            onDeviceTap: onDeviceTap,
            metrics: metrics,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.hairline)),
        gradient: RadialGradient(
          center: const Alignment(0, -0.52),
          radius: 0.95,
          colors: [palette.accent.withValues(alpha: 0.055), palette.accent.withValues(alpha: 0)],
          stops: const [0, 0.72],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padded = Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 18 : metrics?.nearbyStageVerticalPadding ?? 36),
            child: content,
          );
          if (!constraints.hasBoundedHeight) {
            // The caller (the phone column) already scrolls.
            return Center(child: padded);
          }
          // The field owns the slack, but never at the cost of clipping: if the
          // window is too short the field scrolls instead of overflowing.
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: padded),
            ),
          );
        },
      ),
    );
  }
}

class _WaitingState extends StatelessWidget {
  final DeviceType selfDeviceType;
  final bool compact;
  final double scale;

  const _WaitingState({required this.selfDeviceType, required this.compact, required this.scale});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: scale,
          child: RelayWaitingBeacon(selfDeviceType: selfDeviceType, compact: compact),
        ),
        SizedBox(height: compact ? 24 : 40 * scale),
        Text(
          'Relay is listening',
          key: const ValueKey('relay-empty-title'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: compact ? 17 : 19, height: 1.25, fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
        const SizedBox(height: 9),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Nearby devices appear here automatically. You can pick something to share in the meantime.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}
