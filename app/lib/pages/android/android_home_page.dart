import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/pages/android/android_device_detail_page.dart';
import 'package:relay_app/pages/relay_home_vm.dart';
import 'package:relay_app/provider/network/nearby_devices_provider.dart';
import 'package:relay_app/provider/network/relay_send_service.dart';
import 'package:relay_app/provider/network/server/server_provider.dart';
import 'package:relay_app/provider/receive_history_provider.dart';
import 'package:relay_app/provider/relay_paired_routes_provider.dart';
import 'package:relay_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:relay_app/provider/selection/selected_sending_files_provider.dart';
import 'package:relay_app/util/native/file_picker.dart';
import 'package:relay_app/widget/relay_motion/relay_spatial_scene.dart';
import 'package:relay_isolates/util/file_size_helper.dart';

/// Android Spatial Devices Page (Home tab).
class AndroidHomePage extends StatefulWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final VoidCallback onAddDevice;

  const AndroidHomePage({
    super.key,
    required this.vm,
    this.animationsEnabled = true,
    required this.onAddDevice,
  });

  @override
  State<AndroidHomePage> createState() => _AndroidHomePageState();
}

class _AndroidHomePageState extends State<AndroidHomePage> {
  String? _selectedDeviceKey;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final history = context.watch(receiveHistoryProvider);
    final ref = context.ref;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Top Spatial Motion Canvas & Relationship Hub
        Card(
          elevation: 0,
          color: palette.canvasTonalHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: palette.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              RelaySpatialScene(
                selfAlias: widget.vm.selfAlias,
                selfDeviceType: widget.vm.selfDeviceType,
                presence: widget.vm.presence,
                devices: widget.vm.devices,
                activeTransfer: widget.vm.activeTransfer,
                selectedDeviceKey: _selectedDeviceKey,
                animationsEnabled: widget.animationsEnabled,
                height: widget.vm.devices.isEmpty ? 260 : 340,
                onDeviceSelected: (device) {
                  setState(() => _selectedDeviceKey = device?.key);
                },
                onSendFiles: (device) => _pickAndSendFiles(context, ref, device),
                onCancelTransfer: () {
                  final transfer = widget.vm.activeTransfer;
                  if (transfer != null) {
                    if (transfer.isReceive) {
                      ref.notifier(serverProvider).cancelSession();
                    } else {
                      ref.read(relaySendServiceProvider).cancel(transfer.sessionId);
                    }
                  }
                },
                onOpenDetails: (device) {
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AndroidDeviceDetailPage(
                          device: device,
                          activeTransfer: widget.vm.activeTransfer,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (widget.vm.devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    children: [
                      Text(
                        'Searching for Relay Devices',
                        style: RelayTypography.heading(palette.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ensure other devices are on the same Wi-Fi network or tap below to pair.',
                        style: RelayTypography.caption(palette.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: widget.onAddDevice,
                        icon: const Icon(Icons.add_link_rounded, size: 16),
                        label: const Text('Pair Device'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.accent,
                          side: BorderSide(color: palette.accent.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

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
                      color: palette.accentSoft,
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
    final route = relayId == null ? null : ref.read(relayPairedRoutesProvider).where((entry) => entry.relayId == relayId).firstOrNull;
    final verifiedLan = relayId == null ? null : ref.read(relayVerifiedLanDevicesProvider)[relayId];

    if (relayId != null && (route != null || verifiedLan != null)) {
      unawaited(
        ref
            .read(relaySendServiceProvider)
            .sendRelayDevice(
              relayId: relayId,
              verifiedLanTarget: verifiedLan == null ? null : ref.read(nearbyDevicesProvider).allDevices[verifiedLan.device.fingerprint],
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
