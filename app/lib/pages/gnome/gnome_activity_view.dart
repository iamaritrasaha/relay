import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/continuity/continuity_runtime.dart';
import 'package:localsend_app/provider/continuity/continuity_provider.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/gnome/adw_action_row.dart';
import 'package:localsend_app/widget/gnome/adw_boxed_list.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';
import 'package:localsend_app/widget/gnome/adw_status_page.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// GNOME dedicated Activity view.
class GnomeActivityView extends StatelessWidget {
  final VoidCallback? onBack;

  const GnomeActivityView({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final history = context.watch(receiveHistoryProvider);
    final continuityActivity = context.watch(continuityProvider).activity;
    final ref = context.ref;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  if (onBack != null) ...[
                    AdwButton.flat(
                      icon: Icons.arrow_back_rounded,
                      label: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      'Activity',
                      style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true),
                    ),
                  ),
                  if (history.isNotEmpty)
                    AdwButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Clear',
                      style: AdwButtonStyle.destructive,
                      isPill: true,
                      onPressed: () async {
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (_) => const HistoryClearDialog(),
                        );
                        if (result == true) {
                          await ref.redux(receiveHistoryProvider).dispatchAsync(RemoveAllHistoryEntriesAction());
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Continuity activity is metadata only and lives for this session:
              // no clipboard text, message body, number or contact name is ever
              // written down.
              if (continuityActivity.isNotEmpty)
                AdwPreferencesGroup(
                  title: 'Continuity',
                  description: 'What happened, not what was in it. Cleared when Relay closes.',
                  children: [
                    for (final entry in continuityActivity)
                      AdwActionRow(
                        leading: Icon(_continuityIcon(entry.kind)),
                        title: entry.summary,
                        subtitle: _formatDate(entry.at),
                      ),
                  ],
                ),

              if (history.isEmpty && continuityActivity.isEmpty)
                const AdwStatusPage(
                  icon: Icons.history_rounded,
                  title: 'No Recent Activity',
                  description: 'Files and transfers received from other devices will be listed here.',
                )
              else if (history.isEmpty)
                const SizedBox.shrink()
              else
                AdwPreferencesGroup(
                  title: 'Transfer History',
                  children: [
                    for (final entry in history)
                      AdwActionRow(
                        leading: Icon(
                          entry.isMessage ? Icons.chat_bubble_outline : Icons.insert_drive_file_outlined,
                        ),
                        title: entry.fileName,
                        subtitle: '${entry.senderAlias} · ${entry.fileSize.asReadableFileSize} · ${_formatDate(entry.timestamp)}',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (entry.path != null) ...[
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
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              tooltip: 'Delete',
                              onPressed: () => ref.redux(receiveHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(entry.id)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _continuityIcon(ContinuityActivityKind kind) => switch (kind) {
    ContinuityActivityKind.connected => Icons.link_rounded,
    ContinuityActivityKind.disconnected => Icons.link_off_rounded,
    ContinuityActivityKind.clipboardShared => Icons.content_paste_go_rounded,
    ContinuityActivityKind.clipboardReceived => Icons.content_paste_rounded,
    ContinuityActivityKind.messageSent => Icons.send_rounded,
    ContinuityActivityKind.callPlaced => Icons.call_made_rounded,
  };

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
