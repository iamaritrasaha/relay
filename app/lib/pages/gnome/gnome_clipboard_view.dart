import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';

/// GNOME Clipboard continuity surface.
///
/// Truthfully presents the clipboard synchronization capability.
/// Controls are explicitly disabled with an explanation of upcoming features.
class GnomeClipboardView extends StatelessWidget {
  final RelayDeviceVm device;
  final VoidCallback onBack;

  const GnomeClipboardView({
    super.key,
    required this.device,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
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
                  AdwButton.flat(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Clipboard',
                    style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                'Clipboard sharing is not available yet.',
                style: RelayTypography.title(palette.textPrimary, isGnome: true),
              ),
              const SizedBox(height: 8),
              Text(
                'When it is available, you will be able to share clipboard content with ${device.alias}. Relay does not currently read, store, or share clipboard content.',
                style: RelayTypography.body(palette.textSecondary, isGnome: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
