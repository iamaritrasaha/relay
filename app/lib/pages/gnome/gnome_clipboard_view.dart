import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/gnome/adw_action_row.dart';
import 'package:localsend_app/widget/gnome/adw_boxed_list.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    'Clipboard Sync',
                    style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Status notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x1fffffff) : const Color(0x0f000000),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0x18ffffff) : const Color(0x12000000)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: palette.accent, size: 22),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clipboard continuity is in development',
                            style: RelayTypography.body(palette.textPrimary, isGnome: true, bold: true),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Cross-device clipboard sharing with ${device.alias} will be supported in an upcoming release. No clipboard content is currently shared.',
                            style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Preferences preview (disabled truthfully)
              AdwPreferencesGroup(
                title: 'Clipboard Settings',
                children: [
                  AdwActionRow(
                    leading: const Icon(Icons.sync_rounded),
                    title: 'Auto-sync clipboard',
                    subtitle: 'Not available in this build',
                    trailing: Switch(
                      value: false,
                      onChanged: null,
                    ),
                  ),
                  AdwActionRow(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: 'End-to-end encryption',
                    subtitle: 'Clipboard items will be encrypted with device keys',
                    trailing: Text(
                      'Planned',
                      style: RelayTypography.caption(palette.textTertiary, isGnome: true),
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
}
