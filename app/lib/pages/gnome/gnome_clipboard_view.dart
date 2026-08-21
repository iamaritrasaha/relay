import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/relay_motion/relay_section_reveal.dart';
import 'package:yaru/yaru.dart';

/// GNOME clipboard continuity surface.
///
/// Deliberately not a clipboard history manager: it shows the sharing mode, the
/// most recent text, anything the phone has offered, and any platform
/// limitation, and nothing else.
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
    final theme = Theme.of(context);
    final relayId = device.relayId;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  YaruBackButton(onPressed: onBack),
                  const SizedBox(width: 10),
                  Text('Clipboard', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 20),
              if (relayId == null)
                Text(
                  'Clipboard sharing needs a paired Relay device. '
                  '${device.alias} is a Relay-compatible peer, which can only receive files.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                )
              else
                _ClipboardBody(relayId: relayId, alias: device.alias),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipboardBody extends StatelessWidget {
  final String relayId;
  final String alias;

  const _ClipboardBody({required this.relayId, required this.alias});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer(
      builder: (context, ref) {
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final device = continuity.deviceFor(relayId);
        final remote = device.remoteCapabilities[ContinuityCapabilityKind.clipboard];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RelaySectionReveal(
              index: 0,
              child: AdwPreferencesGroup(
                title: 'Sharing',
                description: settings.trusted ? null : 'Trust $alias for continuity before clipboard sharing can be turned on.',
                uppercaseTitle: false,
                children: [
                  for (final mode in ClipboardSharingMode.values)
                    AdwActionRow(
                      leading: Icon(_iconFor(mode)),
                      title: mode.label,
                      subtitle: _descriptionFor(mode, alias),
                      trailing: settings.clipboardMode == mode ? Icon(YaruIcons.ok, color: colorScheme.primary) : null,
                      onTap: settings.trusted ? () => _setMode(ref, mode) : null,
                    ),
                ],
              ),
            ),

            if (remote != null && remote.reason != null && remote.reason!.isNotEmpty)
              RelaySectionReveal(
                index: 1,
                child: AdwPreferencesGroup(
                  title: 'On $alias',
                  uppercaseTitle: false,
                  children: [
                    AdwActionRow(
                      leading: const Icon(YaruIcons.information),
                      title: remote.label,
                      subtitle: remote.reason,
                    ),
                  ],
                ),
              ),

            if (device.clipboardOffer != null)
              RelaySectionReveal(
                index: 1,
                child: AdwPreferencesGroup(
                  title: 'Shared from $alias',
                  uppercaseTitle: false,
                  children: [
                    AdwActionRow(
                      leading: const Icon(YaruIcons.paste),
                      title: _preview(device.clipboardOffer!.text),
                      subtitle: 'Copy this to your clipboard?',
                      trailing: FilledButton(
                        onPressed: () => ref
                            .redux(continuityProvider)
                            .dispatchAsync(
                              ContinuityAcceptClipboardOfferAction(relayId: relayId),
                            ),
                        child: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
              ),

            if (device.lastClipboardText != null)
              RelaySectionReveal(
                index: 2,
                child: AdwPreferencesGroup(
                  title: 'Last synchronised',
                  uppercaseTitle: false,
                  children: [
                    AdwActionRow(
                      leading: const Icon(YaruIcons.clock),
                      title: _preview(device.lastClipboardText!),
                    ),
                  ],
                ),
              ),

            if (settings.isEnabled(ContinuityCapabilityKind.clipboard)) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: device.connected
                    ? () => ref.redux(continuityProvider).dispatchAsync(ContinuityShareClipboardAction(relayId: relayId))
                    : null,
                child: const Text('Share this computer’s clipboard'),
              ),
              if (!device.connected) ...[
                const SizedBox(height: 8),
                Text(
                  '$alias is not connected right now.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ],

            if (device.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                device.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _setMode(WatchableRef ref, ClipboardSharingMode mode) async {
    final dispatcher = ref.redux(continuityProvider);
    await dispatcher.dispatchAsync(
      ContinuitySetCapabilityAction(
        relayId: relayId,
        capability: ContinuityCapabilityKind.clipboard,
        enabled: mode.isEnabled,
      ),
    );
    await dispatcher.dispatchAsync(ContinuitySetClipboardModeAction(relayId: relayId, mode: mode));
  }

  static IconData _iconFor(ClipboardSharingMode mode) => switch (mode) {
    ClipboardSharingMode.off => YaruIcons.window_close,
    ClipboardSharingMode.ask => YaruIcons.question,
    ClipboardSharingMode.automatic => YaruIcons.refresh,
  };

  static String _descriptionFor(ClipboardSharingMode mode, String alias) => switch (mode) {
    ClipboardSharingMode.off => 'Nothing is sent or received.',
    ClipboardSharingMode.ask => 'Content from $alias waits here until you copy it.',
    ClipboardSharingMode.automatic => 'Text copied on either device appears on the other.',
  };

  static String _preview(String text) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= 120 ? single : '${single.substring(0, 120)}…';
  }
}
