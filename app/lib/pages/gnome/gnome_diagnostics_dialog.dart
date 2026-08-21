import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:yaru/yaru.dart';

/// GNOME Advanced Diagnostics modal dialog.
///
/// Houses technical telemetry and diagnostics (RelayId, Fingerprint, IP, Port)
/// without cluttering the main user-facing product UI.
class GnomeDiagnosticsDialog extends StatelessWidget {
  final RelayDeviceVm device;

  const GnomeDiagnosticsDialog({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kYaruContainerRadius)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
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
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  YaruIconButton(
                    icon: const Icon(YaruIcons.window_close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              AdwPreferencesGroup(
                title: 'Identity & Transport',
                uppercaseTitle: false,
                children: [
                  AdwActionRow(
                    title: 'Alias',
                    trailing: Text(device.alias, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7))),
                  ),
                  AdwActionRow(
                    title: 'Target Kind',
                    trailing: Text(
                      device.targetKind.name,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ),
                  if (device.relayId != null)
                    AdwActionRow(
                      title: 'Relay ID',
                      subtitle: device.relayId,
                      trailing: YaruIconButton(
                        icon: const Icon(YaruIcons.copy, size: 16),
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
                      trailing: YaruIconButton(
                        icon: const Icon(YaruIcons.copy, size: 16),
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
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
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
