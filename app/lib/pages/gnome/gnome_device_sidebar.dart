import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/util/device_type_ext.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';

/// Libadwaita device list sidebar for GNOME desktop.
class GnomeDeviceSidebar extends StatelessWidget {
  final RelayHomeVm vm;
  final String? selectedDeviceKey;
  final ValueChanged<String> onSelectDevice;
  final VoidCallback onAddDevice;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenActivity;

  const GnomeDeviceSidebar({
    super.key,
    required this.vm,
    required this.selectedDeviceKey,
    required this.onSelectDevice,
    required this.onAddDevice,
    required this.onOpenSettings,
    required this.onOpenActivity,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final relayDevices = vm.devices.where((d) => !d.isRelay).toList();
    final localSendDevices = vm.devices.where((d) => d.isRelay).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Presence header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: vm.presence == RelayPresence.offline
                      ? palette.textTertiary
                      : vm.presence == RelayPresence.discovering
                      ? palette.warning
                      : palette.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  vm.selfAlias,
                  style: RelayTypography.heading(palette.textPrimary, isGnome: true),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12),

        // Nearby device list. Technical route details stay in Diagnostics.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'NEARBY DEVICES',
            style: RelayTypography.sectionHeader(palette.textSecondary, isGnome: true),
          ),
        ),

        // Device list
        Expanded(
          child: vm.devices.isEmpty
              ? _EmptySidebarState(presence: vm.presence)
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  children: [
                    if (relayDevices.isNotEmpty) ...[
                      for (final device in relayDevices)
                        _DeviceSidebarItem(
                          device: device,
                          isSelected: device.key == selectedDeviceKey,
                          onTap: () => onSelectDevice(device.key),
                        ),
                    ],
                    if (localSendDevices.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                        child: Text(
                          'OTHER DEVICES',
                          style: RelayTypography.sectionHeader(palette.textTertiary, isGnome: true),
                        ),
                      ),
                      for (final device in localSendDevices)
                        _DeviceSidebarItem(
                          device: device,
                          isSelected: device.key == selectedDeviceKey,
                          onTap: () => onSelectDevice(device.key),
                        ),
                    ],
                  ],
                ),
        ),

        // Bottom Actions
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0x14ffffff) : const Color(0x0f000000),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: AdwButton(
                  icon: Icons.add_rounded,
                  label: 'Add device',
                  isPill: true,
                  onPressed: onAddDevice,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceSidebarItem extends StatelessWidget {
  final RelayDeviceVm device;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeviceSidebarItem({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color statusDotColor;
    if (device.phase == RelayDevicePhase.sending) {
      statusDotColor = palette.accent;
    } else if (device.phase == RelayDevicePhase.failed) {
      statusDotColor = palette.error;
    } else if (device.phase == RelayDevicePhase.waiting || device.phase == RelayDevicePhase.verifying) {
      statusDotColor = palette.warning;
    } else if (device.isPaired) {
      statusDotColor = palette.accentSecondary;
    } else {
      statusDotColor = palette.success;
    }

    final selectedBg = isDark ? palette.accent.withValues(alpha: 0.22) : palette.accent.withValues(alpha: 0.12);
    final selectedFg = palette.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? selectedBg : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSelected ? BorderSide(color: palette.accent.withValues(alpha: 0.4), width: 1) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: isDark ? const Color(0x10ffffff) : const Color(0x08000000),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusDotColor,
                  ),
                ),
                const SizedBox(width: 8),
                // Device Icon
                Icon(
                  device.deviceType.icon,
                  size: 18,
                  color: isSelected ? palette.accent : palette.textSecondary,
                ),
                const SizedBox(width: 10),
                // Alias and Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        device.alias,
                        style: RelayTypography.body(selectedFg, isGnome: true, bold: isSelected),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        device.statusSummary,
                        style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (device.battery.hasInfo) ...[
                  const SizedBox(width: 6),
                  Text(
                    device.battery.displayString,
                    style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySidebarState extends StatelessWidget {
  final RelayPresence presence;

  const _EmptySidebarState({required this.presence});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_outlined,
              size: 32,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              presence == RelayPresence.offline ? 'Relay is offline' : 'No nearby devices',
              style: RelayTypography.body(palette.textSecondary, isGnome: true, bold: true),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              presence == RelayPresence.offline
                  ? 'Turn on receiving to find devices on your network.'
                  : 'Devices on your network and paired devices will appear here.',
              style: RelayTypography.caption(palette.textTertiary, isGnome: true),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
