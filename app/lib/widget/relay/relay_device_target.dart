import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_motion.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/relay/relay_device_silhouette.dart';
import 'package:localsend_app/widget/relay/relay_progress_ring.dart';

class RelayDeviceTarget extends StatefulWidget {
  final RelayDeviceVm device;
  final bool animationsEnabled;
  final bool payloadSelected;
  final bool dimmed;
  final VoidCallback? onTap;

  const RelayDeviceTarget({
    required this.device,
    required this.animationsEnabled,
    required this.payloadSelected,
    required this.dimmed,
    this.onTap,
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
    final colors = Theme.of(context).colorScheme;
    final active = widget.device.phase == RelayDevicePhase.sending;
    final successful = widget.device.phase == RelayDevicePhase.success;
    final waiting = widget.device.phase == RelayDevicePhase.waiting || widget.device.phase == RelayDevicePhase.verifying;
    final status = active && widget.device.progress != null ? 'Sending · ${(widget.device.progress! * 100).round()}%' : widget.device.detail;
    final statusColor = switch (widget.device.phase) {
      RelayDevicePhase.sending || RelayDevicePhase.waiting || RelayDevicePhase.verifying => colors.primary,
      RelayDevicePhase.success => colors.tertiary,
      RelayDevicePhase.failed => colors.error,
      RelayDevicePhase.idle => colors.onSurfaceVariant,
    };
    return Semantics(
      button: widget.onTap != null,
      label: '${widget.device.alias}, $status',
      child: AnimatedOpacity(
        opacity: _visible ? (widget.dimmed ? 0.58 : 1) : 0,
        duration: RelayMotion.gated(RelayMotion.deviceTransition, widget.animationsEnabled),
        curve: RelayMotion.curve,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedScale(
            scale: !_visible
                ? 0.96
                : _hovered && widget.onTap != null
                ? 1.04
                : 1,
            duration: RelayMotion.gated(RelayMotion.deviceTransition, widget.animationsEnabled),
            curve: RelayMotion.curve,
            child: InkWell(
              key: ValueKey('relay-device-${widget.device.key}'),
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(80),
              child: SizedBox(
                width: 160,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: RelayMotion.gated(RelayMotion.deviceTransition, widget.animationsEnabled),
                      curve: RelayMotion.curve,
                      width: 128,
                      height: 128,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.surfaceContainerHighest.withValues(alpha: 0.94),
                            colors.surface.withValues(alpha: 0.72),
                          ],
                        ),
                        border: Border.all(color: colors.outlineVariant.withValues(alpha: active || waiting ? 0.9 : 0.58)),
                        boxShadow: [
                          BoxShadow(color: colors.shadow.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: RelayProgressRing(
                        size: 114,
                        phase: widget.device.phase,
                        progress: widget.device.progress,
                        animationsEnabled: widget.animationsEnabled,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [colors.surfaceContainerHighest.withValues(alpha: 0.84), colors.surface.withValues(alpha: 0.8)],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedSwitcher(
                            duration: RelayMotion.gated(RelayMotion.deviceTransition, widget.animationsEnabled),
                            child: successful
                                ? Icon(Icons.check_rounded, key: const ValueKey(true), size: 54, color: colors.tertiary)
                                : RelayDeviceSilhouette(
                                    key: const ValueKey(false),
                                    deviceType: widget.device.deviceType,
                                    color: colors.onSurface,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.device.alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
