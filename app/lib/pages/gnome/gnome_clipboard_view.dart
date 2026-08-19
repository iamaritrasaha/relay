import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/persistence/relay_continuity_settings.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/provider/continuity/continuity_provider.dart';
import 'package:localsend_app/widget/gnome/adw_action_row.dart';
import 'package:localsend_app/widget/gnome/adw_boxed_list.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';
import 'package:refena_flutter/refena_flutter.dart';

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
    final palette = Theme.of(context).relayPalette;
    final relayId = device.relayId;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AdwButton.flat(icon: Icons.arrow_back_rounded, label: 'Back', onPressed: onBack),
                  const SizedBox(width: 12),
                  Text('Clipboard', style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true)),
                ],
              ),
              const SizedBox(height: 24),
              if (relayId == null)
                Text(
                  'Clipboard sharing needs a paired Relay device. '
                  '${device.alias} is a LocalSend-compatible peer, which can only receive files.',
                  style: RelayTypography.body(palette.textSecondary, isGnome: true),
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
    final palette = Theme.of(context).relayPalette;

    return Consumer(
      builder: (context, ref) {
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final device = continuity.deviceFor(relayId);
        final remote = device.remoteCapabilities[ContinuityCapabilityKind.clipboard];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdwPreferencesGroup(
              title: 'Sharing',
              description: settings.trusted
                  ? null
                  : 'Trust $alias for continuity before clipboard sharing can be turned on.',
              children: [
                for (final mode in ClipboardSharingMode.values)
                  AdwActionRow(
                    leading: Icon(_iconFor(mode)),
                    title: mode.label,
                    subtitle: _descriptionFor(mode, alias),
                    trailing: settings.clipboardMode == mode
                        ? Icon(Icons.check_rounded, color: palette.accent)
                        : null,
                    onTap: settings.trusted ? () => _setMode(ref, mode) : null,
                  ),
              ],
            ),

            // The phone's own limitation, quoted rather than paraphrased.
            if (remote != null && remote.reason != null && remote.reason!.isNotEmpty)
              AdwPreferencesGroup(
                title: 'On $alias',
                children: [
                  AdwActionRow(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: remote.label,
                    subtitle: remote.reason,
                  ),
                ],
              ),

            if (device.clipboardOffer != null)
              AdwPreferencesGroup(
                title: 'Shared from $alias',
                children: [
                  AdwActionRow(
                    leading: const Icon(Icons.content_paste_go_rounded),
                    title: _preview(device.clipboardOffer!.text),
                    subtitle: 'Copy this to your clipboard?',
                    trailing: AdwButton(
                      label: 'Copy',
                      onPressed: () => ref.redux(continuityProvider).dispatchAsync(
                            ContinuityAcceptClipboardOfferAction(relayId: relayId),
                          ),
                    ),
                  ),
                ],
              ),

            if (device.lastClipboardText != null)
              AdwPreferencesGroup(
                title: 'Last synchronised',
                children: [
                  AdwActionRow(
                    leading: const Icon(Icons.history_rounded),
                    title: _preview(device.lastClipboardText!),
                  ),
                ],
              ),

            if (settings.isEnabled(ContinuityCapabilityKind.clipboard)) ...[
              const SizedBox(height: 4),
              AdwButton(
                label: 'Share this computer’s clipboard',
                isPill: true,
                onPressed: device.connected
                    ? () => ref.redux(continuityProvider).dispatchAsync(ContinuityShareClipboardAction(relayId: relayId))
                    : null,
              ),
              if (!device.connected) ...[
                const SizedBox(height: 8),
                Text(
                  '$alias is not connected right now.',
                  style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                ),
              ],
            ],

            if (device.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                device.lastError!,
                style: RelayTypography.caption(palette.error, isGnome: true),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _setMode(WatchableRef ref, ClipboardSharingMode mode) async {
    final dispatcher = ref.redux(continuityProvider);
    // Turning the mode on is what grants the capability; there is no separate
    // switch to forget.
    await dispatcher.dispatchAsync(ContinuitySetCapabilityAction(
      relayId: relayId,
      capability: ContinuityCapabilityKind.clipboard,
      enabled: mode.isEnabled,
    ));
    await dispatcher.dispatchAsync(ContinuitySetClipboardModeAction(relayId: relayId, mode: mode));
  }

  static IconData _iconFor(ClipboardSharingMode mode) => switch (mode) {
        ClipboardSharingMode.off => Icons.block_rounded,
        ClipboardSharingMode.ask => Icons.help_outline_rounded,
        ClipboardSharingMode.automatic => Icons.sync_rounded,
      };

  static String _descriptionFor(ClipboardSharingMode mode, String alias) => switch (mode) {
        ClipboardSharingMode.off => 'Nothing is sent or received.',
        ClipboardSharingMode.ask => 'Content from $alias waits here until you copy it.',
        ClipboardSharingMode.automatic => 'Text copied on either device appears on the other.',
      };

  /// A short preview. Clipboard content is shown, never logged.
  static String _preview(String text) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= 120 ? single : '${single.substring(0, 120)}…';
  }
}
