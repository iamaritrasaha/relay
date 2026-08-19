import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/widget/gnome/adw_action_row.dart';
import 'package:localsend_app/widget/gnome/adw_boxed_list.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';

/// GNOME Advanced Diagnostics modal dialog.
///
/// Houses technical telemetry and diagnostics (RelayId, Fingerprint, IP, Port)
/// without cluttering the main user-facing product UI.
class GnomeDiagnosticsDialog extends StatelessWidget {
  final RelayDeviceVm device;

  const GnomeDiagnosticsDialog({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xff181a22) : const Color(0xfff6f7fa),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Device Diagnostics',
                    style: RelayTypography.title(palette.textPrimary, isGnome: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              AdwPreferencesGroup(
                title: 'Identity & Transport',
                children: [
                  AdwActionRow(
                    title: 'Alias',
                    trailing: Text(device.alias, style: RelayTypography.body(palette.textSecondary, isGnome: true)),
                  ),
                  AdwActionRow(
                    title: 'Target Kind',
                    trailing: Text(device.targetKind.name, style: RelayTypography.body(palette.textSecondary, isGnome: true)),
                  ),
                  if (device.relayId != null)
                    AdwActionRow(
                      title: 'Relay ID',
                      subtitle: device.relayId,
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: 'Copy Relay ID',
                        onPressed: () {
                          unawaited(Clipboard.setData(ClipboardData(text: device.relayId!)));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Relay ID copied to clipboard')),
                          );
                        },
                      ),
                    ),
                  if (device.lanFingerprint != null || !device.key.startsWith('relay:'))
                    AdwActionRow(
                      title: 'Fingerprint',
                      subtitle: device.lanFingerprint ?? device.key,
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: 'Copy Fingerprint',
                        onPressed: () {
                          unawaited(Clipboard.setData(ClipboardData(text: device.lanFingerprint ?? device.key)));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Fingerprint copied to clipboard')),
                          );
                        },
                      ),
                    ),
                  if (device.ip != null)
                    AdwActionRow(
                      title: 'Endpoint',
                      trailing: Text(
                        '${device.ip}:${device.port ?? 53317}',
                        style: RelayTypography.monospace(palette.textSecondary),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AdwButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
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
