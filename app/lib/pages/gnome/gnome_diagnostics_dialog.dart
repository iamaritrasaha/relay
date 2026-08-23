import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/model/ui/relay_last_seen.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:yaru/yaru.dart';

/// GNOME Advanced Diagnostics modal dialog.
///
/// Houses technical telemetry and diagnostics (logical id, route health and
/// feature metadata)
/// without cluttering the main user-facing product UI.
class GnomeDiagnosticsDialog extends StatelessWidget {
  final RelayDeviceVm device;

  const GnomeDiagnosticsDialog({super.key, required this.device});

  static Widget _yesNo(ThemeData theme, ColorScheme colorScheme, bool value) => Text(
    value ? 'Available' : 'Unavailable',
    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
  );

  /// Every feature and the core's verdict on it, in one line.
  ///
  static String _featureSummary(RelayDeviceVm device) {
    final entries = device.featureAvailability.entries.toList()..sort((a, b) => a.key.name.compareTo(b.key.name));
    if (entries.isEmpty) {
      return 'None reported';
    }
    return entries.map((entry) => '${entry.key.title}: ${entry.value.reason ?? 'Available'}').join(', ');
  }

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
                ],
              ),

              if (device.hasFabricRecord) ...[
                const SizedBox(height: 12),
                AdwPreferencesGroup(
                  key: const ValueKey('diagnostics-fabric-group'),
                  title: 'Routes',
                  uppercaseTitle: false,
                  children: [
                    AdwActionRow(
                      title: 'Logical device ID',
                      subtitle: device.key.replaceFirst('kdeconnect:', ''),
                    ),
                    AdwActionRow(
                      title: 'Route',
                      // The precise route, which the product surfaces
                      // deliberately reduce to Local / Remote / Offline.
                      trailing: Text(
                        device.connectionState.diagnosticLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ),
                    AdwActionRow(
                      title: 'Local network route',
                      trailing: _yesNo(theme, colorScheme, device.lanAvailable),
                    ),
                    AdwActionRow(
                      title: 'Remote binding',
                      // Whether remote reachability is possible at all, which is
                      // a different fact from whether it is up right now.
                      subtitle: device.wanBound ? 'Bound' : 'Not bound',
                      trailing: Text(
                        device.wanAvailable ? (device.wanPath == 'relay' ? 'Up · relayed' : 'Up · direct') : 'Down',
                        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ),
                    AdwActionRow(
                      title: 'Last local activity',
                      trailing: Text(
                        device.lanLastSeenUnix == null ? 'Never' : relayLastSeenLabel(device.lanLastSeenUnix, now: DateTime.now()),
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    AdwActionRow(
                      title: 'Last remote activity',
                      trailing: Text(
                        device.wanLastSeenUnix == null ? 'Never' : relayLastSeenLabel(device.wanLastSeenUnix, now: DateTime.now()),
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    if (device.platform != null)
                      AdwActionRow(
                        title: 'Platform',
                        trailing: Text(
                          [device.platform, device.platformVersion].whereType<String>().join(' '),
                          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                      ),
                    if (device.relayVersion != null)
                      AdwActionRow(
                        title: 'Protocol version',
                        trailing: Text(
                          device.relayVersion!,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                      ),
                    AdwActionRow(
                      title: 'Features',
                      subtitle: _featureSummary(device),
                    ),
                  ],
                ),
              ],

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
