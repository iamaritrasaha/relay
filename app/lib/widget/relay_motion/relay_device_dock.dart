import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_app/widget/relay_motion/relay_ambient_clock.dart';

/// The rail of devices that are not currently in the hero.
///
/// Each tile visually reflects its device's unique multicolor identity.
/// Selecting a tile hands focus to it with a smooth palette transition bloom.
class RelayDeviceDock extends StatelessWidget {
  final List<RelayDeviceVm> devices;
  final String? selectedKey;
  final ValueChanged<RelayDeviceVm> onSelect;
  final bool animationsEnabled;

  const RelayDeviceDock({
    super.key,
    required this.devices,
    required this.selectedKey,
    required this.onSelect,
    this.animationsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (devices.length < 2) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: devices.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final device = devices[index];
          return RelayDockTile(
            key: ValueKey('relay-dock-${device.key}'),
            device: device,
            selected: device.key == selectedKey,
            animationsEnabled: animationsEnabled,
            onTap: () => onSelect(device),
          );
        },
      ),
    );
  }
}

/// One device in the dock with device-specific color identity and tactile hover feedback.
class RelayDockTile extends StatefulWidget {
  final RelayDeviceVm device;
  final bool selected;
  final bool animationsEnabled;
  final VoidCallback onTap;

  const RelayDockTile({
    super.key,
    required this.device,
    required this.selected,
    required this.onTap,
    this.animationsEnabled = true,
  });

  @override
  State<RelayDockTile> createState() => _RelayDockTileState();
}

class _RelayDockTileState extends State<RelayDockTile> with TickerProviderStateMixin {
  late final AnimationController _arrival;
  AnimationController? _ambientDotLocal;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _arrival = AnimationController(vsync: this, duration: RelayMotion.arrival);
    unawaited(_arrival.forward());
  }

  bool get _motionOn => widget.animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clock = RelayAmbientClock.maybeOf(context);
    _syncMotion(clock);
  }

  @override
  void didUpdateWidget(covariant RelayDockTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clock = RelayAmbientClock.maybeOf(context);
    _syncMotion(clock);
  }

  void _syncMotion(RelayAmbientClockNotifier? sharedClock) {
    if (sharedClock == null) {
      if (_online && _motionOn) {
        _ambientDotLocal ??= AnimationController(vsync: this, duration: RelayMotion.ambientGlowCycle);
        if (!_ambientDotLocal!.isAnimating) {
          unawaited(_ambientDotLocal!.repeat());
        }
      } else if (_ambientDotLocal != null) {
        _ambientDotLocal!.stop();
        _ambientDotLocal!.value = 0;
      }
    } else if (_ambientDotLocal != null) {
      _ambientDotLocal!.stop();
      _ambientDotLocal!.dispose();
      _ambientDotLocal = null;
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    _ambientDotLocal?.dispose();
    super.dispose();
  }

  bool get _online => widget.device.isPresent;

  @override
  Widget build(BuildContext context) {
    final sharedClock = RelayAmbientClock.maybeOf(context);
    final theme = Theme.of(context);
    final palette = theme.relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context) || !widget.animationsEnabled;
    final selected = widget.selected;
    final devicePalette = RelayDevicePalette.fromDevice(widget.device, brightness: theme.brightness);
    final Listenable? dotRepaint = sharedClock?.statusClock ?? _ambientDotLocal;

    final tile = AnimatedContainer(
      duration: reducedMotion ? Duration.zero : RelayMotion.focus,
      curve: RelayMotion.focusCurve,
      width: 190,
      padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
      decoration: BoxDecoration(
        color: selected
            ? palette.softSurface
            : (_hovered
                  ? palette.hoverSurface
                  : (_online ? devicePalette.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.03 : 0.02) : Colors.transparent)),
        borderRadius: BorderRadius.circular(RelayRadius.action),
        border: Border.all(
          color: selected
              ? devicePalette.primary.withValues(alpha: 0.3)
              : (_hovered ? devicePalette.primary.withValues(alpha: 0.18) : palette.hairline),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          // Device identity indicator bar
          AnimatedContainer(
            duration: reducedMotion ? Duration.zero : RelayMotion.state,
            width: 3.5,
            height: selected ? 26 : (_online ? 12 : 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [devicePalette.primary, devicePalette.secondary],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: selected ? 10 : 12),
          RelayDeviceSilhouette(
            deviceType: widget.device.deviceType,
            color: _online ? (selected ? devicePalette.primary : palette.textSecondary) : palette.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.device.alias,
                  style: RelayTypography.body(
                    _online ? palette.textPrimary : palette.textSecondary,
                    isGnome: true,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    if (_online && !reducedMotion && dotRepaint != null) ...[
                      AnimatedBuilder(
                        animation: dotRepaint,
                        builder: (context, _) {
                          final rawPhase = sharedClock != null ? sharedClock.phaseFast : (_ambientDotLocal?.value ?? 0.0);
                          final phase = (rawPhase + devicePalette.phaseOffset) % 1.0;
                          final opacity = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
                          return Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: devicePalette.primary.withValues(alpha: opacity),
                            ),
                          );
                        },
                      ),
                    ],
                    Expanded(
                      child: Text(
                        _online ? widget.device.statusSummary : 'Offline',
                        style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: '${widget.device.alias}. ${_online ? widget.device.statusSummary : 'Offline'}',
          child: AnimatedOpacity(
            opacity: _online ? 1.0 : 0.7,
            duration: reducedMotion ? Duration.zero : RelayMotion.departure,
            child: tile,
          ),
        ),
      ),
    );

    if (!reducedMotion) {
      result = AnimatedBuilder(
        animation: _arrival,
        child: result,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_arrival.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - t)),
              child: child,
            ),
          );
        },
      );
    }

    return RepaintBoundary(child: result);
  }
}
