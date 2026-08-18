import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/pages/android/android_device_detail_page.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/relay_send_service.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/relay_paired_routes_provider.dart';
import 'package:localsend_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Android Material 3 Devices Page (Home tab).
class AndroidHomePage extends StatelessWidget {
  final RelayHomeVm vm;
  final VoidCallback onAddDevice;

  const AndroidHomePage({
    super.key,
    required this.vm,
    required this.onAddDevice,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final history = context.watch(receiveHistoryProvider);
    final ref = context.ref;

    final relayDevices = vm.devices.where((d) => !d.isLocalSend).toList();
    final localSendDevices = vm.devices.where((d) => d.isLocalSend).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Self Presence Header Card
        Card(
          elevation: 0,
          color: palette.softSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: palette.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: vm.presence == RelayPresence.offline
                        ? palette.textTertiary
                        : vm.presence == RelayPresence.discovering
                            ? palette.warning
                            : palette.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vm.selfAlias,
                        style: RelayTypography.heading(palette.textPrimary),
                      ),
                      Text(
                        vm.presence == RelayPresence.offline
                            ? 'Offline · Not listening'
                            : 'Listening for nearby devices',
                        style: RelayTypography.caption(palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_link_rounded),
                  tooltip: 'Pair Device',
                  onPressed: onAddDevice,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Your Devices Section
        Text(
          'YOUR DEVICES',
          style: RelayTypography.sectionHeader(palette.textSecondary),
        ),
        const SizedBox(height: 8),

        if (vm.devices.isEmpty)
          Card(
            elevation: 0,
            color: palette.softSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.devices_outlined, size: 40, color: palette.textTertiary),
                  const SizedBox(height: 12),
                  Text(
                    'No Devices Found',
                    style: RelayTypography.heading(palette.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ensure other devices are on the same Wi-Fi network or tap Pair Device above.',
                    style: RelayTypography.caption(palette.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else ...[
          for (final device in relayDevices)
            _AndroidDeviceCard(
              device: device,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AndroidDeviceDetailPage(
                      device: device,
                      activeTransfer: vm.activeTransfer,
                    ),
                  ),
                );
              },
              onSendFiles: () => _pickAndSendFiles(context, ref, device),
            ),
          if (localSendDevices.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'LOCALSEND COMPATIBILITY',
              style: RelayTypography.sectionHeader(palette.textTertiary),
            ),
            const SizedBox(height: 8),
            for (final device in localSendDevices)
              _AndroidDeviceCard(
                device: device,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AndroidDeviceDetailPage(
                        device: device,
                        activeTransfer: vm.activeTransfer,
                      ),
                    ),
                  );
                },
                onSendFiles: () => _pickAndSendFiles(context, ref, device),
              ),
          ],
        ],

        const SizedBox(height: 24),

        // Recent Activity Section
        Text(
          'RECENT ACTIVITY',
          style: RelayTypography.sectionHeader(palette.textSecondary),
        ),
        const SizedBox(height: 8),

        if (history.isEmpty)
          Card(
            elevation: 0,
            color: palette.softSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.hairline),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No recent transfers')),
            ),
          )
        else
          Card(
            elevation: 0,
            color: palette.softSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.hairline),
            ),
            child: Column(
              children: [
                for (final (index, entry) in history.take(3).indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      entry.isMessage ? Icons.chat_bubble_outline : Icons.insert_drive_file_outlined,
                    ),
                    title: Text(entry.fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${entry.fileSize.asReadableFileSize} · ${entry.senderAlias}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _pickAndSendFiles(BuildContext context, Ref ref, RelayDeviceVm device) async {
    await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: context));
    final crossFiles = ref.read(selectedSendingFilesProvider);
    if (crossFiles.isEmpty) {
      return;
    }

    final nearbyDevice = ref.read(nearbyDevicesProvider).allDevices[device.key];
    if (nearbyDevice != null) {
      unawaited(ref.read(relaySendServiceProvider).send(target: nearbyDevice, files: crossFiles, background: true));
      return;
    }

    final relayId = device.relayId ?? (device.key.startsWith('relay:') ? device.key.substring('relay:'.length) : null);
    final route = relayId == null
        ? null
        : ref.read(relayPairedRoutesProvider).where((entry) => entry.relayId == relayId).firstOrNull;
    final verifiedLan = relayId == null ? null : ref.read(relayVerifiedLanDevicesProvider)[relayId];

    if (relayId != null && (route != null || verifiedLan != null)) {
      unawaited(
        ref
            .read(relaySendServiceProvider)
            .sendRelayDevice(
              relayId: relayId,
              verifiedLanTarget: verifiedLan == null
                  ? null
                  : ref.read(nearbyDevicesProvider).allDevices[verifiedLan.device.fingerprint],
              pairedRoute: route,
              files: crossFiles,
              background: true,
            )
            .onError((error, _) {
              if (!context.mounted) return;
              final message = error is RelaySendFailure && error.category == 'identity'
                  ? 'Device identity could not be verified.'
                  : 'Transfer failed.';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }),
      );
    }
  }
}

class _AndroidDeviceCard extends StatelessWidget {
  final RelayDeviceVm device;
  final VoidCallback onTap;
  final VoidCallback onSendFiles;

  const _AndroidDeviceCard({
    required this.device,
    required this.onTap,
    required this.onSendFiles,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        color: palette.softSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: palette.canvas,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        device.deviceType.icon,
                        size: 22,
                        color: device.isVerifiedRelay ? palette.accent : palette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.alias,
                            style: RelayTypography.heading(palette.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            device.statusSummary,
                            style: RelayTypography.caption(palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (device.battery.hasInfo)
                      Text(
                        device.battery.displayString,
                        style: RelayTypography.caption(palette.textTertiary),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: onSendFiles,
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Send Files'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
