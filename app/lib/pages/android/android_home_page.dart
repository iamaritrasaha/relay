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

/// Full-Page Android Living Spatial Universe (Devices tab).
class AndroidHomePage extends StatefulWidget {
  final RelayHomeVm vm;
  final bool animationsEnabled;
  final VoidCallback onAddDevice;
  final VoidCallback? onOpenActivity;

  const AndroidHomePage({
    super.key,
    required this.vm,
    this.animationsEnabled = true,
    required this.onAddDevice,
    this.onOpenActivity,
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

    final hasActiveTransfer = widget.vm.activeTransfer != null;
    final hasFocusedDevice = _selectedDeviceKey != null;
    final latestHistory = history.firstOrNull;

    return Stack(
      children: [
        // Layer 0: Full-Page Spatial Motion Universe
        Positioned.fill(
          child: RelaySpatialScene(
            selfAlias: widget.vm.selfAlias,
            selfDeviceType: widget.vm.selfDeviceType,
            presence: widget.vm.presence,
            devices: widget.vm.devices,
            activeTransfer: widget.vm.activeTransfer,
            selectedDeviceKey: _selectedDeviceKey,
            animationsEnabled: widget.animationsEnabled,
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
        ),

        // Layer 1: Lightweight Floating Header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Relay',
                    style: RelayTypography.wordmark(palette.textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_link_rounded),
                    tooltip: 'Pair Device',
                    style: IconButton.styleFrom(
                      backgroundColor: palette.softSurface.withValues(alpha: 0.8),
                      foregroundColor: palette.textPrimary,
                    ),
                    onPressed: widget.onAddDevice,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Layer 2: Empty Discovery State Hint
        if (widget.vm.devices.isEmpty)
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: palette.softSurface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.hairline),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
            ),
          ),

        // Layer 3: Compact Floating Recent Activity Peek (only when idle, devices present, and un-focused)
        if (!hasActiveTransfer && !hasFocusedDevice && widget.vm.devices.isNotEmpty && latestHistory != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: widget.onOpenActivity,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: palette.softSurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        latestHistory.isMessage ? Icons.chat_bubble_outline : Icons.insert_drive_file_outlined,
                        size: 16,
                        color: palette.accentSoft,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${latestHistory.fileName} · ${latestHistory.fileSize.asReadableFileSize}',
                          style: RelayTypography.caption(palette.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: palette.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
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
                  ? 'Device identity verification failed. Re-pair device in Settings.'
                  : 'Transfer failed: $error';
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cannot send to ${device.alias}: device is not reachable')),
    );
  }
}
