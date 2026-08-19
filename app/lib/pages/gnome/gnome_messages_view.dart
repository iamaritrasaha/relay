import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';
import 'package:localsend_app/widget/gnome/adw_status_page.dart';

/// GNOME Messages continuity surface.
///
/// Truthfully presents the message continuity capability without fake demo chats.
class GnomeMessagesView extends StatelessWidget {
  final RelayDeviceVm device;
  final VoidCallback onBack;

  const GnomeMessagesView({
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
                    'Messages',
                    style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              AdwStatusPage(
                icon: Icons.sms_outlined,
                title: 'Message Continuity',
                description:
                    'SMS and message synchronization with ${device.alias} will be available in a future update. No messages are currently synced or stored.',
                action: AdwButton(
                  label: 'Back to Overview',
                  isPill: true,
                  onPressed: onBack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
