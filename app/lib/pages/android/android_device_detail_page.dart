import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/pages/android/android_clipboard_sheet.dart';
import 'package:localsend_app/pages/android/android_messages_page.dart';
import 'package:localsend_app/pages/gnome/gnome_diagnostics_dialog.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/relay_send_service.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/relay_paired_routes_provider.dart';
import 'package:localsend_app/provider/relay_verified_lan_devices_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Android Material 3 Device Detail Page.
class AndroidDeviceDetailPage extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayTransferVm? activeTransfer;

  const AndroidDeviceDetailPage({
    super.key,
    required this.device,
    this.activeTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final palette = Theme.of(context).relayPalette;
    final history = ref.watch(receiveHistoryProvider);
    final isDeviceHistory = history.where((e) => e.senderAlias == device.alias).take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.alias,
              style: RelayTypography.title(palette.textPrimary),
            ),
            Text(
              device.isVerifiedRelay ? 'Verified Relay Device' : 'LocalSend Device',
              style: RelayTypography.caption(palette.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Diagnostics',
            onPressed: () {
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => GnomeDiagnosticsDialog(device: device),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Device Status Summary Card
          Card(
            elevation: 0,
            color: palette.softSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: palette.elevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      device.deviceType.icon,
                      size: 26,
                      color: device.isVerifiedRelay ? palette.accent : palette.textTertiary,
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
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: device.isVerifiedRelay ? palette.success : palette.textTertiary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              device.statusSummary,
                              style: RelayTypography.caption(palette.textSecondary),
                            ),
                            if (device.battery.hasInfo) ...[
                              const SizedBox(width: 8),
                              Icon(
                                device.battery.isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                                size: 14,
                                color: palette.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                device.battery.displayString,
                                style: RelayTypography.caption(palette.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (device.isVerifiedRelay)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // In-Flight Transfer Progress
          if (activeTransfer != null) ...[
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: palette.accentSoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: palette.accent.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sync_rounded, size: 20, color: palette.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Transferring to ${device.alias}…',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (activeTransfer!.progress != null)
                          Text(
                            '${(activeTransfer!.progress! * 100).toStringAsFixed(0)}%',
                            style: RelayTypography.monospace(palette.accent),
                          ),
                      ],
                    ),
                    if (activeTransfer!.progress != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: activeTransfer!.progress!,
                          backgroundColor: palette.elevated,
                          valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                          minHeight: 6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final sessionId = activeTransfer!.sessionId;
                            if (await context.pushBottomSheet(() => const CancelSessionDialog()) == true) {
                              ref.read(relaySendServiceProvider).cancel(sessionId);
                            }
                          },
                          child: Text('Cancel', style: TextStyle(color: palette.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Primary Transfer Actions
          Text(
            'ACTIONS',
            style: RelayTypography.sectionHeader(palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _pickAndSendFiles(context, ref),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Send Files'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _pickAndSendFolder(context, ref),
                  icon: const Icon(Icons.drive_folder_upload_rounded),
                  label: const Text('Send Folder'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Secondary Continuity Surfaces
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    unawaited(context.push(() => AndroidMessagesPage(device: device)));
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Messages'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    unawaited(
                      showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => AndroidClipboardSheet(device: device),
                      ),
                    );
                  },
                  icon: const Icon(Icons.content_paste_outlined),
                  label: const Text('Clipboard'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Device Information Card
          Text(
            'DEVICE INFORMATION',
            style: RelayTypography.sectionHeader(palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: palette.softSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.hairline),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.devices_rounded),
                  title: const Text('Device Model / Type'),
                  trailing: Text(
                    '${device.deviceModel ?? 'Unknown'} (${device.deviceType.name})',
                    style: RelayTypography.body(palette.textSecondary),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Connection Route'),
                  trailing: Text(
                    device.connectionType.label,
                    style: RelayTypography.body(palette.textSecondary),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.security_rounded),
                  title: const Text('Trust & Security'),
                  trailing: Text(
                    device.securityState.label,
                    style: RelayTypography.body(palette.textSecondary),
                  ),
                ),
                if (device.battery.hasInfo) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      device.battery.isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                    ),
                    title: const Text('Battery'),
                    trailing: Text(
                      device.battery.displayString,
                      style: RelayTypography.body(palette.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Recent Activity with this Device
          Text(
            'RECENT ACTIVITY',
            style: RelayTypography.sectionHeader(palette.textSecondary),
          ),
          const SizedBox(height: 8),
          if (isDeviceHistory.isEmpty)
            Card(
              elevation: 0,
              color: palette.softSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: palette.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No recent transfers with this device',
                    style: RelayTypography.body(palette.textSecondary),
                  ),
                ),
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
                  for (int i = 0; i < isDeviceHistory.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        isDeviceHistory[i].isMessage ? Icons.chat_bubble_outline : Icons.insert_drive_file_outlined,
                      ),
                      title: Text(isDeviceHistory[i].fileName),
                      subtitle: Text(isDeviceHistory[i].fileSize.asReadableFileSize),
                      trailing: isDeviceHistory[i].path != null
                          ? IconButton(
                              icon: const Icon(Icons.open_in_new_rounded),
                              tooltip: 'Open File',
                              onPressed: () => openFile(context, isDeviceHistory[i].fileType, isDeviceHistory[i].path!),
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendFiles(BuildContext context, Ref ref) async {
    await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: context));
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isNotEmpty && context.mounted) {
      await _sendToDevice(context, ref, files);
    }
  }

  Future<void> _pickAndSendFolder(BuildContext context, Ref ref) async {
    await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.folder, context: context));
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isNotEmpty && context.mounted) {
      await _sendToDevice(context, ref, files);
    }
  }

  Future<void> _sendToDevice(BuildContext context, Ref ref, List<CrossFile> files) async {
    final nearbyDevice = ref.read(nearbyDevicesProvider).allDevices[device.key];
    if (nearbyDevice != null) {
      unawaited(ref.read(relaySendServiceProvider).send(target: nearbyDevice, files: files, background: true));
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
              files: files,
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
