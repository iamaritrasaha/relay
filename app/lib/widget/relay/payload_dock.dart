import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_app/widget/relay_components.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';

class PayloadDock extends StatelessWidget {
  final RelayPayloadVm selection;
  final VoidCallback onSelect;
  final VoidCallback? onClear;

  const PayloadDock({required this.selection, required this.onSelect, this.onClear, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = Theme.of(context).relayPalette;
    if (selection.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Theme.of(context).platform != TargetPlatform.android) ...[
            Text(
              'Drop files here or choose something to share',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            key: const ValueKey('relay-share-something'),
            onPressed: onSelect,
            style: RelayButtonStyles.primary(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Share something'),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 13, right: 4, top: 4, bottom: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: colors.surfaceContainerHighest.withValues(alpha: 0.64),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file_rounded, size: 17, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '${selection.fileCount} ${selection.fileCount == 1 ? 'file' : 'files'} · ${selection.totalBytes.asReadableFileSize}',
                key: const ValueKey('relay-payload-summary'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 6),
                IconButton(tooltip: 'Clear selection', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Choose a nearby device', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textSecondary)),
      ],
    );
  }
}
