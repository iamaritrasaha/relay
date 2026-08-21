import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';

/// The rail of devices that are not currently in the hero.
///
/// Relay keeps one focused device at a time, so the dock is where the rest of
/// the room lives. Selecting a tile hands focus to it: the tile grows into the
/// hero's weight while the outgoing device settles back into the rail, which is
/// why focus is an animation on the tiles themselves rather than a page swap.
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

/// One device in the dock, including its arrival animation.
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

class _RelayDockTileState extends State<RelayDockTile> with SingleTickerProviderStateMixin {
  late final AnimationController _arrival;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // Relay Arrival: a device that has just been discovered rises into place
    // once. There is no idle pulse afterwards.
    _arrival = AnimationController(vsync: this, duration: RelayMotion.arrival);
    unawaited(_arrival.forward());
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  bool get _online => widget.device.isPresent;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context) || !widget.animationsEnabled;

    final selected = widget.selected;

    final tile = AnimatedContainer(
      duration: reducedMotion ? Duration.zero : RelayMotion.focus,
      curve: RelayMotion.focusCurve,
      width: 190,
      padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
      decoration: BoxDecoration(
        color: selected ? palette.softSurface : (_hovered ? palette.hoverSurface : Colors.transparent),
        borderRadius: BorderRadius.circular(RelayRadius.action),
      ),
      child: Row(
        children: [
          // The selected device carries a short warm marker, not an outline.
          AnimatedContainer(
            duration: reducedMotion ? Duration.zero : RelayMotion.state,
            width: 3,
            height: selected ? 26 : 0,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: selected ? 10 : 13),
          RelayDeviceSilhouette(
            deviceType: widget.device.deviceType,
            color: _online ? palette.textSecondary : palette.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.device.alias,
                  style: RelayTypography.body(_online ? palette.textPrimary : palette.textSecondary, isGnome: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  _online ? widget.device.statusSummary : 'Offline',
                  style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          child: AnimatedScale(
            scale: reducedMotion ? 1.0 : (selected ? 1.0 : 0.95),
            alignment: Alignment.centerLeft,
            duration: reducedMotion ? Duration.zero : RelayMotion.focus,
            curve: RelayMotion.focusCurve,
            child: AnimatedOpacity(
              opacity: _online ? 1.0 : 0.7,
              duration: reducedMotion ? Duration.zero : RelayMotion.departure,
              child: tile,
            ),
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
              child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
            ),
          );
        },
      );
    }

    return RepaintBoundary(child: result);
  }
}
