import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
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

              if (history.isEmpty)
                const AdwStatusPage(
                  icon: Icons.history_rounded,
                  title: 'No Recent Activity',
                  description: 'Files and transfers received from other devices will be listed here.',
                )
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
                              onPressed: () => ref
                                  .redux(receiveHistoryProvider)
                                  .dispatchAsync(RemoveHistoryEntryAction(entry.id)),
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
