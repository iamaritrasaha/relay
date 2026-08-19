import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';

/// Android Material 3 Clipboard Continuity Bottom Sheet / Page.
class AndroidClipboardSheet extends StatelessWidget {
  final RelayDeviceVm device;

  const AndroidClipboardSheet({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.content_paste_outlined, color: palette.accent, size: 24),
              const SizedBox(width: 12),
              Text(
                'Clipboard',
                style: RelayTypography.title(palette.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Clipboard sharing is not available yet.',
            style: RelayTypography.heading(palette.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'When it is available, you will be able to share clipboard content with ${device.alias}. Relay does not currently read, store, or share clipboard content.',
            style: RelayTypography.body(palette.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}
