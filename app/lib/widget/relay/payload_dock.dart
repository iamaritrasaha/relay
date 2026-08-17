import 'package:flutter/material.dart';
import 'package:localsend_app/pages/relay_home_vm.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';

class PayloadDock extends StatelessWidget {
  final RelayPayloadVm selection;
  final VoidCallback onSelect;
  final VoidCallback? onClear;

  const PayloadDock({required this.selection, required this.onSelect, this.onClear, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (selection.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Drop files to share', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: onSelect, icon: const Icon(Icons.add), label: const Text('Select files')),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: colors.secondaryContainer.withValues(alpha: 0.42),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${selection.fileCount} ${selection.fileCount == 1 ? 'file' : 'files'} · ${selection.totalBytes.asReadableFileSize}',
                key: const ValueKey('relay-payload-summary'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 6),
                TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('Choose a nearby device', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
      ],
    );
  }
}
