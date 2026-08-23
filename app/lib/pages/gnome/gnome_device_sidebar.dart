import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/gnome/gnome_shell.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/widget/gnome/relay_connection_status.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_symbol.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:yaru/yaru.dart';

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

  /// Devices Relay is trusted with, whatever their current reachability.
  ///
  /// Trust is the criterion, not connectivity, so a phone the user paired stays
  /// in their own list while it is asleep.
  List<RelayDeviceVm> get myDevices => vm.devices.where((device) => device.isPaired || !device.isKdeConnect).toList();

  /// Peers Relay can see but has no relationship with.
  List<RelayDeviceVm> get pairingCandidates => vm.devices.where((device) => device.isKdeConnect && !device.isPaired).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final yaruColors = YaruColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              const RelaySymbol(size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  RelayProduct.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final destination in destinations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: YaruMasterTile(
                    leading: Icon(destination.icon, size: 20),
                    title: Text(destination.label),
                    trailing: destination.badge > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(RelayRadius.pill),
                            ),
                            child: Text(
                              '${destination.badge}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : null,
                    selected: destination.view != null && destination.view == subView,
                    onTap: () => onSelectDestination(destination),
                  ),
                ),
              const SizedBox(height: 20),
              _SidebarSectionHeader(
                key: const ValueKey('relay-sidebar-my-devices-header'),
                title: 'MY DEVICES',
                trailing: _AddDeviceButton(onPressed: onAddDevice),
              ),
              if (myDevices.isEmpty && pairingCandidates.isEmpty)
                _EmptySidebarState(presence: vm.presence)
              else if (myDevices.isEmpty)
                const _SidebarHint(
                  key: ValueKey('relay-sidebar-no-paired-devices'),
                  text: 'No paired devices yet.',
                )
              else
                for (final device in myDevices)
                  _DeviceSidebarCard(
                    key: ValueKey('relay-sidebar-${device.key}'),
                    device: device,
                    selected: device.key == selectedDeviceKey && subView == GnomeSubView.overview,
                    onTap: () => onSelectDevice(device.key),
                  ),
              // Kept strictly apart from the section above. A phone the user has
              // already paired must never reappear here just because it went
              // offline: "forgotten" and "asleep" are different situations, and
              // offering to pair a device again implies the first pairing is gone.
              if (pairingCandidates.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SidebarSectionHeader(
                  key: const ValueKey('relay-sidebar-available-header'),
                  title: 'AVAILABLE TO PAIR',
                ),
                for (final device in pairingCandidates)
                  _DeviceSidebarCard(
                    key: ValueKey('relay-sidebar-${device.key}'),
                    device: device,
                    selected: device.key == selectedDeviceKey && subView == GnomeSubView.overview,
                    onTap: () => onSelectDevice(device.key),
                  ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (vm.presence) {
                    RelayPresence.offline => colorScheme.onSurface.withValues(alpha: 0.4),
                    RelayPresence.discovering => yaruColors.warning,
                    RelayPresence.ready => theme.relayPalette.accent,
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (vm.presence) {
                    RelayPresence.offline => 'Offline',
                    RelayPresence.discovering => 'Looking for devices',
                    RelayPresence.ready => 'Ready',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
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

class _SidebarSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SidebarSectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SidebarHint extends StatelessWidget {
  final String text;

  const _SidebarHint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _AddDeviceButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddDeviceButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return YaruIconButton(
      icon: const Icon(YaruIcons.plus, size: 18),
      tooltip: 'Add device',
      onPressed: onPressed,
    );
  }
}

/// A known device in the sidebar.
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final device = widget.device;
    final selected = widget.selected;

    final tone = switch (device.phase) {
      RelayDevicePhase.failed => RelayPresenceTone.attention,
      RelayDevicePhase.sending || RelayDevicePhase.waiting || RelayDevicePhase.verifying => RelayPresenceTone.busy,
      _ => _online ? RelayPresenceTone.online : RelayPresenceTone.offline,
    };

    final IconData deviceIcon = switch (device.deviceType) {
      DeviceType.mobile => YaruIcons.smartphone,
      DeviceType.desktop => YaruIcons.desktop,
      _ => YaruIcons.computer,
    };

    final devicePalette = RelayDevicePalette.fromDevice(device, brightness: theme.brightness);

    Widget card = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: YaruMasterTile(
        leading: Icon(
          deviceIcon,
          size: 20,
          color: _online ? (selected ? devicePalette.primary : colorScheme.onSurface) : colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        title: Text(
          device.alias,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: device.phase == RelayDevicePhase.idle
                  ? RelayConnectionStatus(
                      connected: _online,
                      label: _online ? device.statusSummary : 'Offline',
                      palette: devicePalette,
                      animationsEnabled: !reducedMotion,
                      ambient: true,
                      compact: true,
                    )
                  : RelayStatusPill(
                      tone: tone,
                      label: device.statusSummary,
                      compact: true,
                    ),
            ),
            if (device.battery.hasInfo) ...[
              const SizedBox(width: 6),
              Text(
                '${device.battery.percentage}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ] else if (!_online && device.hasFabricRecord) ...[
              const SizedBox(width: 6),
              Text(
                // The fabric's own timestamp. Never a rebuild time, which would
                // make every offline device look freshly seen on every repaint.
                device.lastSeenLabel(now: DateTime.now()),
                key: const ValueKey('relay-sidebar-last-seen'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        selected: selected,
        onTap: widget.onTap,
      ),
    );

    if (reducedMotion) {
      return card;
    }

    return AnimatedBuilder(
      animation: _arrival,
      child: card,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_arrival.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(YaruIcons.computer, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            presence == RelayPresence.offline ? 'Relay is offline' : 'No devices yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            presence == RelayPresence.offline ? 'Turn on receiving to find devices.' : 'Devices on your network appear here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
