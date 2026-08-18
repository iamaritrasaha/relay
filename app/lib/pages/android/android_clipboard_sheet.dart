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
                'Clipboard Sync',
                style: RelayTypography.title(palette.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: palette.softSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: palette.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: palette.accent),
                      const SizedBox(width: 8),
                      Text(
                        'Feature in development',
                        style: RelayTypography.body(palette.textPrimary, bold: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cross-device clipboard synchronization with ${device.alias} will be available in an upcoming update. No clipboard data is currently monitored or shared.',
                    style: RelayTypography.caption(palette.textSecondary),
                  ),
                ],
              ),
            ),
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
