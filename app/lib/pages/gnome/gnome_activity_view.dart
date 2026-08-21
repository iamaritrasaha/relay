import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/continuity/continuity_runtime.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/provider/receive_history_provider.dart';
import 'package:relay_app/util/native/open_file.dart';
import 'package:relay_app/util/native/open_folder.dart';
import 'package:relay_app/widget/dialogs/history_clear_dialog.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_status_page.dart';
import 'package:relay_app/widget/relay_motion/relay_section_reveal.dart';
import 'package:relay_isolates/util/file_size_helper.dart';
import 'package:yaru/yaru.dart';

/// GNOME dedicated Activity view.
class GnomeActivityView extends StatelessWidget {
  final VoidCallback? onBack;

  const GnomeActivityView({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = context.watch(receiveHistoryProvider);
    final continuityActivity = context.watch(continuityProvider).activity;
    final ref = context.ref;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                    YaruBackButton(onPressed: onBack),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      'Activity',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (history.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(YaruIcons.trash, size: 16),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
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
              const SizedBox(height: 20),

              if (continuityActivity.isNotEmpty)
                RelaySectionReveal(
                  index: 0,
                  child: AdwPreferencesGroup(
                    title: 'Continuity',
                    description: 'What happened, not what was in it. Cleared when Relay closes.',
                    uppercaseTitle: false,
                    children: [
                      for (final entry in continuityActivity)
                        AdwActionRow(
                          leading: Icon(_continuityIcon(entry.kind)),
                          title: entry.summary,
                          subtitle: _formatDate(entry.at),
                        ),
                    ],
                  ),
                ),

              if (history.isEmpty && continuityActivity.isEmpty)
                const AdwStatusPage(
                  icon: YaruIcons.clock,
                  title: 'No recent activity',
                  description: 'Files and transfers received from other devices will be listed here.',
                )
              else if (history.isEmpty)
                const SizedBox.shrink()
              else
                RelaySectionReveal(
                  index: 1,
                  child: AdwPreferencesGroup(
                    title: 'Transfer History',
                    uppercaseTitle: false,
                    children: [
                      for (final entry in history)
                        AdwActionRow(
                          leading: Icon(
                            entry.isMessage ? YaruIcons.chat_bubble : YaruIcons.document,
                          ),
                          title: entry.fileName,
                          subtitle: '${entry.senderAlias} · ${entry.fileSize.asReadableFileSize} · ${_formatDate(entry.timestamp)}',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (entry.path != null) ...[
                                YaruIconButton(
                                  icon: const Icon(YaruIcons.folder_open, size: 16),
                                  tooltip: 'Open Folder',
                                  onPressed: () => openFolder(folderPath: entry.path!),
                                ),
                                YaruIconButton(
                                  icon: const Icon(YaruIcons.external_link, size: 16),
                                  tooltip: 'Open File',
                                  onPressed: () => openFile(context, entry.fileType, entry.path!),
                                ),
                              ],
                              YaruIconButton(
                                icon: const Icon(YaruIcons.trash, size: 16),
                                tooltip: 'Delete',
                                onPressed: () => ref.redux(receiveHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(entry.id)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _continuityIcon(ContinuityActivityKind kind) => switch (kind) {
    ContinuityActivityKind.connected => YaruIcons.insert_link,
    ContinuityActivityKind.disconnected => YaruIcons.window_close,
    ContinuityActivityKind.clipboardShared => YaruIcons.copy,
    ContinuityActivityKind.clipboardReceived => YaruIcons.paste,
    ContinuityActivityKind.messageSent => YaruIcons.send,
    ContinuityActivityKind.callPlaced => YaruIcons.call_outgoing,
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
