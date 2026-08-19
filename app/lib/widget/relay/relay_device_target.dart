import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/relay/relay_desktop_metrics.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_app/widget/relay/relay_progress_ring.dart';

/// A nearby device, drawn as a restrained dimensional medallion.
///
/// The medallion keeps a fixed square slot whatever the transfer phase is, so
/// starting a send never moves the device: the progress arc is painted in space
/// that was already reserved around it.
class RelayDeviceTarget extends StatefulWidget {
  final RelayDeviceVm device;
  final bool animationsEnabled;
  final bool payloadSelected;
  final bool dimmed;
  final bool compact;
  final VoidCallback? onTap;
  final RelayResponsiveMetrics? metrics;

  const RelayDeviceTarget({
    required this.device,
    required this.animationsEnabled,
    required this.payloadSelected,
    required this.dimmed,
    this.compact = false,
    this.onTap,
    this.metrics,
    super.key,
  });

  @override
  State<RelayDeviceTarget> createState() => _RelayDeviceTargetState();
}

class _RelayDeviceTargetState extends State<RelayDeviceTarget> {
  bool _hovered = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _visible = !widget.animationsEnabled;
    if (widget.animationsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _visible = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final duration = RelayMotion.gated(RelayMotion.deviceTransition, widget.animationsEnabled);
    final layout = widget.metrics;
    final slot = widget.compact ? 126.0 : layout?.deviceSlotDiameter ?? RelayDesktopMetrics.medallionSlot;
    final medallion = widget.compact ? 104.0 : layout?.deviceMedallionDiameter ?? RelayDesktopMetrics.medallionSize;
    final ringDiameter = widget.compact ? 120.0 : layout?.progressRingDiameter ?? medallion + 20;
    final silhouetteSize = widget.compact ? 41.0 : layout?.deviceSilhouetteSize ?? medallion * 0.38;
    final textScale = widget.compact ? 0.9 : 1.0;

    final successful = widget.device.phase == RelayDevicePhase.success;
    final active = widget.device.phase == RelayDevicePhase.sending;
    final status = active && widget.device.progress != null ? 'Sending · ${(widget.device.progress! * 100).round()}%' : widget.device.detail;
    final statusColor = switch (widget.device.phase) {
      RelayDevicePhase.sending || RelayDevicePhase.waiting || RelayDevicePhase.verifying => palette.accentSoft,
      RelayDevicePhase.success => palette.success,
      RelayDevicePhase.failed => palette.error,
      RelayDevicePhase.cancelled || RelayDevicePhase.idle => palette.textTertiary,
    };

    return Semantics(
      button: widget.onTap != null,
      label: '${widget.device.alias}, $status',
      child: AnimatedOpacity(
        opacity: _visible ? (widget.dimmed ? 0.34 : 1) : 0,
        duration: duration,
        curve: RelayMotion.curve,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            key: ValueKey('relay-device-${widget.device.key}'),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: slot,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: slot,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Cast shadow: the medallion sits on the field rather
                        // than floating in front of it.
                        Positioned(
                          bottom: (slot - medallion) / 2 - 8,
                          child: _CastShadow(width: medallion * 0.85, height: 20),
                        ),
                        AnimatedScale(
                          scale: _hovered && widget.onTap != null ? 1.03 : 1,
                          duration: duration,
                          curve: RelayMotion.curve,
                          child: _Medallion(
                            diameter: medallion,
                            emphasised: active || _hovered && widget.onTap != null,
                            child: AnimatedSwitcher(
                              duration: duration,
                              child: successful
                                  ? Icon(Icons.check_rounded, key: const ValueKey(true), size: medallion * 0.36, color: palette.success)
                                  : RelayDeviceSilhouette(
                                      key: const ValueKey(false),
                                      deviceType: widget.device.deviceType,
                                      color: palette.accentSoft,
                                      size: silhouetteSize,
                                    ),
                            ),
                          ),
                        ),
                        SizedBox.square(
                          dimension: ringDiameter,
                          child: RelayProgressRing(
                            size: ringDiameter,
                            phase: widget.device.phase,
                            progress: widget.device.progress,
                            animationsEnabled: widget.animationsEnabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.device.alias,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5 * textScale, height: 1.2, fontWeight: FontWeight.w600, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: widget.device.phase == RelayDevicePhase.idle ? palette.success : statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5 * textScale, height: 1.2, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  final double diameter;
  final bool emphasised;
  final Widget child;

  const _Medallion({required this.diameter, required this.emphasised, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Top-lit: the light source is above the field, consistently.
        gradient: RadialGradient(
          center: const Alignment(0, -0.68),
          radius: 0.95,
          colors: [palette.canvasTonalHigh, palette.elevated, palette.canvasTonalLow],
          stops: const [0, 0.52, 1],
        ),
        border: Border.all(color: emphasised ? palette.accentSoft.withValues(alpha: 0.35) : palette.hairline),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.42), blurRadius: 26, offset: const Offset(0, 14), spreadRadius: -12),
        ],
      ),
      child: Center(child: child),
    );
  }
}

class _CastShadow extends StatelessWidget {
  final double width;
  final double height;

  const _CastShadow({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          // A radial gradient fills its paint rect, so a wide box gives the
          // ellipse the medallion is meant to be sitting on.
          borderRadius: BorderRadius.all(Radius.elliptical(width / 2, height / 2)),
          gradient: RadialGradient(
            colors: [Colors.black.withValues(alpha: 0.45), Colors.black.withValues(alpha: 0)],
            stops: const [0, 0.72],
          ),
        ),
      ),
    );
  }
}
