import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_shell.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/relay/relay_device_silhouette.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_symbol.dart';

/// One entry in the sidebar's main navigation.
class GnomeNavDestination {
  final IconData icon;
  final String label;
  final GnomeSubView? view;
  final VoidCallback? action;
  final int badge;

  const GnomeNavDestination({
    required this.icon,
    required this.label,
    this.view,
    this.action,
    this.badge = 0,
  });
}

/// Relay's desktop sidebar: what you can do, then which devices you have.
class GnomeDeviceSidebar extends StatelessWidget {
  final RelayHomeVm vm;
  final String? selectedDeviceKey;
  final GnomeSubView subView;
  final List<GnomeNavDestination> destinations;
  final ValueChanged<String> onSelectDevice;
  final ValueChanged<GnomeNavDestination> onSelectDestination;
  final VoidCallback onAddDevice;

  const GnomeDeviceSidebar({
    super.key,
    required this.vm,
    required this.selectedDeviceKey,
    required this.subView,
    required this.destinations,
    required this.onSelectDevice,
    required this.onSelectDestination,
    required this.onAddDevice,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          child: Row(
            children: [
              const RelaySymbol(size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  RelayProduct.name,
                  style: RelayTypography.wordmark(palette.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final destination in destinations)
                _NavItem(
                  destination: destination,
                  selected: destination.view != null && destination.view == subView,
                  onTap: () => onSelectDestination(destination),
                ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 6, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'DEVICES',
                        style: RelayTypography.sectionHeader(palette.textTertiary, isGnome: true),
                      ),
                    ),
                    _AddDeviceButton(onPressed: onAddDevice),
                  ],
                ),
              ),
              if (vm.devices.isEmpty)
                _EmptySidebarState(presence: vm.presence)
              else
                for (final device in vm.devices)
                  _DeviceSidebarCard(
                    key: ValueKey('relay-sidebar-${device.key}'),
                    device: device,
                    selected: device.key == selectedDeviceKey && subView == GnomeSubView.overview,
                    onTap: () => onSelectDevice(device.key),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (vm.presence) {
                    RelayPresence.offline => palette.textTertiary,
                    RelayPresence.discovering => palette.warning,
                    RelayPresence.ready => palette.success,
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  switch (vm.presence) {
                    RelayPresence.offline => 'Offline',
                    RelayPresence.discovering => 'Looking for devices',
                    RelayPresence.ready => 'Ready',
                  },
                  style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddDeviceButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddDeviceButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    return Tooltip(
      message: 'Add device',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.add_rounded, size: 18, color: palette.textSecondary),
        ),
      ),
    );
  }
}

/// A navigation row. Selection reads as an elevated surface plus a short warm
/// strip on the leading edge, never as a saturated fill.
class _NavItem extends StatefulWidget {
  final GnomeNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.destination, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final selected = widget.selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: reducedMotion ? Duration.zero : RelayMotion.hover,
              curve: RelayMotion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? palette.softSurface : (_hovered ? palette.hoverSurface : Colors.transparent),
                borderRadius: BorderRadius.circular(RelayRadius.nav),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: reducedMotion ? Duration.zero : RelayMotion.state,
                    width: 4,
                    height: selected ? 16 : 0,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: selected ? 10 : 14),
                  Icon(
                    widget.destination.icon,
                    size: 18,
                    color: selected ? palette.textPrimary : palette.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.destination.label,
                      style: RelayTypography.navLabel(selected ? palette.textPrimary : palette.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.destination.badge > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(RelayRadius.pill),
                      ),
                      child: Text(
                        '${widget.destination.badge}',
                        style: RelayTypography.caption(palette.accent, isGnome: true),
                      ),
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

/// A known device in the sidebar: what it is, whether it is here, and its
/// battery when the device actually reports one.
class _DeviceSidebarCard extends StatefulWidget {
  final RelayDeviceVm device;
  final bool selected;
  final VoidCallback onTap;

  const _DeviceSidebarCard({super.key, required this.device, required this.selected, required this.onTap});

  @override
  State<_DeviceSidebarCard> createState() => _DeviceSidebarCardState();
}

class _DeviceSidebarCardState extends State<_DeviceSidebarCard> with SingleTickerProviderStateMixin {
  late final AnimationController _arrival;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
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
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final device = widget.device;
    final selected = widget.selected;

    final tone = switch (device.phase) {
      RelayDevicePhase.failed => RelayPresenceTone.attention,
      RelayDevicePhase.sending || RelayDevicePhase.waiting || RelayDevicePhase.verifying => RelayPresenceTone.busy,
      _ => _online ? RelayPresenceTone.online : RelayPresenceTone.offline,
    };

    Widget card = AnimatedContainer(
      duration: reducedMotion ? Duration.zero : RelayMotion.focus,
      curve: RelayMotion.focusCurve,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: selected ? palette.softSurface : (_hovered ? palette.hoverSurface : Colors.transparent),
        borderRadius: BorderRadius.circular(RelayRadius.nav),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: reducedMotion ? Duration.zero : RelayMotion.state,
            width: 4,
            height: selected ? 26 : 0,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: selected ? 10 : 14),
          RelayDeviceSilhouette(
            deviceType: device.deviceType,
            color: _online ? palette.textSecondary : palette.textTertiary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  device.alias,
                  style: RelayTypography.body(palette.textPrimary, isGnome: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                RelayStatusPill(
                  tone: tone,
                  label: _online ? device.statusSummary : 'Offline',
                  compact: true,
                ),
              ],
            ),
          ),
          if (device.battery.hasInfo) ...[
            const SizedBox(width: 8),
            Text(
              '${device.battery.percentage}%',
              style: RelayTypography.caption(palette.textTertiary, isGnome: true),
            ),
          ],
        ],
      ),
    );

    card = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(onTap: widget.onTap, child: card),
      ),
    );

    if (reducedMotion) {
      return card;
    }

    // Relay Arrival, in the sidebar: a newly discovered device rises in once.
    return AnimatedBuilder(
      animation: _arrival,
      child: card,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_arrival.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        );
      },
    );
  }
}

class _EmptySidebarState extends StatelessWidget {
  final RelayPresence presence;

  const _EmptySidebarState({required this.presence});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.devices_other_outlined, size: 19, color: palette.textTertiary),
          const SizedBox(height: 10),
          Text(
            presence == RelayPresence.offline ? 'Relay is offline' : 'No devices yet',
            style: RelayTypography.body(palette.textSecondary, isGnome: true),
          ),
          const SizedBox(height: 3),
          Text(
            presence == RelayPresence.offline ? 'Turn on receiving to find devices.' : 'Devices on your network appear here.',
            style: RelayTypography.caption(palette.textTertiary, isGnome: true),
          ),
        ],
      ),
    );
  }
}
