import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_capability_vm.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/widget/gnome/adw_action_row.dart';
import 'package:localsend_app/widget/gnome/adw_boxed_list.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// GNOME Device Detail and Overview View.
class GnomeDeviceDetailView extends StatelessWidget {
  final RelayDeviceVm device;
  final RelayTransferVm? activeTransfer;
  final VoidCallback onSendFiles;
  final VoidCallback onSendFolder;
  final VoidCallback onOpenClipboard;
  final VoidCallback onOpenMessages;
  final VoidCallback onOpenPhone;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback? onCancelTransfer;

  const GnomeDeviceDetailView({
    super.key,
    required this.device,
    this.activeTransfer,
    required this.onSendFiles,
    required this.onSendFolder,
    required this.onOpenClipboard,
    required this.onOpenMessages,
    required this.onOpenPhone,
    required this.onOpenDiagnostics,
    this.onCancelTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = context.watch(receiveHistoryProvider);

    final isSending =
        device.phase == RelayDevicePhase.sending || device.phase == RelayDevicePhase.waiting || device.phase == RelayDevicePhase.verifying;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Device Header Banner
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x1fffffff) : const Color(0x0f000000),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      device.deviceType.icon,
                      size: 28,
                      color: device.isVerifiedRelay ? palette.accent : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.alias,
                          style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          device.battery.hasInfo ? '${device.statusSummary} · ${device.battery.displayString}' : device.statusSummary,
                          style: RelayTypography.body(palette.textSecondary, isGnome: true),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Active Transfer Progress Banner
              if (isSending && activeTransfer != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Transferring to ${device.alias}…',
                                style: RelayTypography.heading(palette.textPrimary, isGnome: true),
                              ),
                            ],
                          ),
                          if (onCancelTransfer != null)
                            AdwButton(
                              label: 'Cancel',
                              style: AdwButtonStyle.flat,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              onPressed: onCancelTransfer,
                            ),
                        ],
                      ),
                      if (activeTransfer!.progress != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: activeTransfer!.progress,
                            minHeight: 6,
                            backgroundColor: palette.accent.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation(palette.accent),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${((activeTransfer!.progress ?? 0) * 100).toStringAsFixed(0)}% complete',
                          style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Primary Action Buttons
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AdwButton.suggested(
                    key: const ValueKey('gnome-send-files-button'),
                    icon: Icons.file_upload_outlined,
                    label: 'Send Files',
                    isPill: true,
                    onPressed: onSendFiles,
                  ),
                  AdwButton(
                    key: const ValueKey('gnome-send-folder-button'),
                    icon: Icons.folder_open_outlined,
                    label: 'Send Folder',
                    isPill: true,
                    onPressed: onSendFolder,
                  ),
                  AdwButton.flat(
                    key: const ValueKey('gnome-clipboard-button'),
                    icon: Icons.content_paste_outlined,
                    label: 'Clipboard',
                    onPressed: onOpenClipboard,
                  ),
                  AdwButton.flat(
                    key: const ValueKey('gnome-messages-button'),
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Messages',
                    onPressed: onOpenMessages,
                  ),
                  // Phone only makes sense for a device that could have one.
                  if (!device.isLocalSend)
                    AdwButton.flat(
                      key: const ValueKey('gnome-phone-button'),
                      icon: Icons.call_outlined,
                      label: 'Phone',
                      onPressed: onOpenPhone,
                    ),
                ],
              ),

              const SizedBox(height: 32),

              // Device Information Boxed Group
              AdwPreferencesGroup(
                title: 'Device',
                children: [
                  AdwActionRow(
                    leading: const Icon(Icons.wifi_rounded),
                    title: 'Connection',
                    subtitle: device.isLocalSend
                        ? 'Nearby on your local network'
                        : device.connectionType == RelayConnectionType.direct
                        ? 'Direct connection'
                        : device.connectionType == RelayConnectionType.relayed
                        ? 'Connected remotely'
                        : 'Nearby on your local network',
                  ),
                  AdwActionRow(
                    leading: Icon(
                      device.isVerifiedRelay ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                    ),
                    title: 'Device verification',
                    subtitle: device.isVerifiedRelay ? 'Authenticated Relay device identity' : 'LocalSend-compatible device (unauthenticated)',
                  ),
                  AdwActionRow(
                    leading: const Icon(Icons.battery_std_rounded),
                    title: 'Battery',
                    subtitle: switch (device.battery) {
                      // A stale reading is labelled as such rather than shown as live.
                      final battery when !battery.hasInfo =>
                        device.isLocalSend ? 'LocalSend devices do not share battery status' : 'Not shared by this device',
                      final battery when battery.isStale => 'Last known before disconnecting',
                      final battery when battery.isFull => 'Charged',
                      final battery when battery.isCharging => 'Charging',
                      _ => 'On battery',
                    },
                    trailing: Text(
                      device.battery.displayString,
                      style: RelayTypography.body(palette.textSecondary, isGnome: true),
                    ),
                  ),
                  AdwNavigationRow(
                    leading: const Icon(Icons.tune_rounded),
                    title: 'Security & diagnostics',
                    subtitle: 'Verify this device and view technical details',
                    onTap: onOpenDiagnostics,
                  ),
                ],
              ),

              // Recent Activity Boxed Group
              AdwPreferencesGroup(
                title: 'Recent Activity',
                children: history.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          child: Center(
                            child: Text(
                              'No recent file activity',
                              style: RelayTypography.body(palette.textTertiary, isGnome: true),
                            ),
                          ),
                        ),
                      ]
                    : [
                        for (final entry in history.take(5))
                          AdwActionRow(
                            leading: Icon(
                              entry.isMessage ? Icons.chat_bubble_outline : Icons.insert_drive_file_outlined,
                            ),
                            title: entry.fileName,
                            subtitle: '${entry.senderAlias} · ${entry.fileSize.asReadableFileSize} · ${_formatDate(entry.timestamp)}',
                            trailing: entry.path != null
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                                        tooltip: 'Open Folder',
                                        onPressed: () => openFolder(folderPath: entry.path!),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                        tooltip: 'Open File',
                                        onPressed: () => openFile(context, entry.fileType, entry.path!),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.month}/${dt.day}';
  }
}
