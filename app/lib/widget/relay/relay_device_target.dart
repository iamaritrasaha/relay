import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_motion.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/util/device_type_ext.dart';
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
    final status = active && widget.device.progress != null ? 'Sending · ${(widget.device.progress! * 100).round()}%' : widget.device.detail;
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withValues(
                          alpha: active
                              ? 0.12
                              : widget.payloadSelected
                              ? 0.08
                              : 0.035,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(
                              alpha: active
                                  ? 0.24
                                  : widget.payloadSelected
                                  ? 0.13
                                  : 0.07,
                            ),
                            blurRadius: active ? 28 : 20,
                            spreadRadius: active ? 4 : 0,
                          ),
                        ],
                      ),
                      child: RelayProgressRing(
                        size: 112,
                        phase: widget.device.phase,
                        progress: widget.device.progress,
                        animationsEnabled: widget.animationsEnabled,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer.withValues(alpha: 0.58),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedSwitcher(
                            duration: RelayMotion.gated(RelayMotion.deviceTransition, widget.animationsEnabled),
                            child: Icon(
                              successful ? Icons.check_rounded : widget.device.deviceType.icon,
                              key: ValueKey(successful),
                              size: successful ? 54 : 52,
                              color: successful ? colors.primary : colors.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      widget.device.alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: active ? colors.primary : colors.onSurfaceVariant),
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
