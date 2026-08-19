import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Android Material 3 Activity Page.
class AndroidActivityPage extends StatelessWidget {
  const AndroidActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final history = context.watch(receiveHistoryProvider);
    final ref = context.ref;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Activity',
          style: RelayTypography.title(palette.textPrimary),
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear History',
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
      body: history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, size: 48, color: palette.textTertiary),
                    const SizedBox(height: 16),
                    Text(
                      'No Recent Activity',
                      style: RelayTypography.title(palette.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Received files and messages will appear here.',
                      style: RelayTypography.body(palette.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = history[index];
                return Card(
                  elevation: 0,
                  color: palette.softSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: palette.hairline),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: palette.canvas,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        entry.isMessage ? Icons.chat_bubble_outline : Icons.insert_drive_file_outlined,
                        size: 20,
                        color: palette.accent,
                      ),
                    ),
                    title: Text(entry.fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.senderAlias} · ${entry.fileSize.asReadableFileSize} · ${_formatDate(entry.timestamp)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (entry.path != null)
                          IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, size: 20),
                            tooltip: 'Open',
                            onPressed: () => openFile(context, entry.fileType, entry.path!),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                          tooltip: 'Remove',
                          onPressed: () => ref.redux(receiveHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(entry.id)),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
