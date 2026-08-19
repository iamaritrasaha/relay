import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';

/// Android Material 3 Messages Continuity Page.
class AndroidMessagesPage extends StatelessWidget {
  final RelayDeviceVm device;

  const AndroidMessagesPage({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Messages',
          style: RelayTypography.title(palette.textPrimary),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.sms_outlined, size: 36, color: palette.accent),
              ),
              const SizedBox(height: 20),
              Text(
                'SMS & Message Continuity',
                style: RelayTypography.title(palette.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Messaging continuity between your devices will be supported in a future update. No messages are currently mirrored from ${device.alias}.',
                style: RelayTypography.body(palette.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to Device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
