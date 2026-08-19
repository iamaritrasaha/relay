import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/util/native/continuity_channel.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Material 3 continuity controls for one paired device.
///
/// Trust is a separate switch from the capabilities, because it is a separate
/// decision: a device can be reachable without being trusted, and trusted
/// without being allowed to read anything. Everything a capability needs from
/// Android is stated on the row rather than surfacing later as an error.
class AndroidContinuitySection extends StatelessWidget {
  final RelayDeviceVm device;

  const AndroidContinuitySection({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final relayId = device.relayId;
    if (relayId == null) {
      // Relay-compatible peers never get continuity.
      return const SizedBox.shrink();
    }
    final palette = Theme.of(context).relayPalette;

    return Consumer(
      builder: (context, ref) {
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final dispatcher = ref.redux(continuityProvider);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'CONTINUITY',
                style: RelayTypography.sectionHeader(palette.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: palette.softSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: palette.hairline),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.verified_user_outlined),
                    title: const Text('Trust this device'),
                    subtitle: Text(
                      settings.trusted
                          ? 'Continuity features can be turned on below.'
                          : 'Pairing lets Relay reach ${device.alias}. Trust lets it share more than files.',
                    ),
                    value: settings.trusted,
                    onChanged: (value) => unawaited(
                      dispatcher.dispatchAsync(
                        ContinuitySetTrustedAction(relayId: relayId, trusted: value),
                      ),
                    ),
                  ),
                  for (final capability in ContinuityCapabilityKind.values) ...[
                    const Divider(height: 1),
                    _CapabilityRow(
                      relayId: relayId,
                      capability: capability,
                      settings: settings,
                      platform: continuity.localCapabilities[capability.name],
                    ),
                  ],
                ],
              ),
            ),
            if (continuity.backgroundServiceRunning) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Relay keeps a connection open while continuity is on. Turning every '
                  'feature off also stops that.',
                  style: RelayTypography.caption(palette.textSecondary),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final String relayId;
  final ContinuityCapabilityKind capability;
  final RelayContinuitySettings settings;
  final PlatformCapabilityState? platform;

  const _CapabilityRow({
    required this.relayId,
    required this.capability,
    required this.settings,
    required this.platform,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = settings.isEnabled(capability);
    final blocked = platform != null && !platform!.isAvailable;

    // Clipboard is a three-way choice, not a switch, so it gets its own row.
    if (capability == ContinuityCapabilityKind.clipboard) {
      return Consumer(
        builder: (context, ref) => ListTile(
          leading: const Icon(Icons.content_paste_rounded),
          title: const Text('Clipboard sharing'),
          subtitle: Text(_subtitle(settings.clipboardMode.label)),
          trailing: DropdownButton<ClipboardSharingMode>(
            value: settings.clipboardMode,
            underline: const SizedBox.shrink(),
            onChanged: settings.trusted ? (mode) => _setClipboard(ref, mode) : null,
            items: [
              for (final mode in ClipboardSharingMode.values) DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
          ),
        ),
      );
    }

    return Consumer(
      builder: (context, ref) => SwitchListTile(
        secondary: Icon(_iconFor(capability)),
        title: Text(capability.label),
        subtitle: Text(_subtitle(null)),
        value: enabled,
        // A capability the platform cannot provide is never presented as
        // switchable; the row says why instead.
        onChanged: !settings.trusted || (blocked && !platform!.needsPermission)
            ? null
            : (value) => unawaited(
                ref
                    .redux(continuityProvider)
                    .dispatchAsync(
                      ContinuitySetCapabilityAction(
                        relayId: relayId,
                        capability: capability,
                        enabled: value,
                      ),
                    ),
              ),
      ),
    );
  }

  void _setClipboard(WatchableRef ref, ClipboardSharingMode? mode) {
    if (mode == null) {
      return;
    }
    final dispatcher = ref.redux(continuityProvider);
    unawaited(
      dispatcher
          .dispatchAsync(
            ContinuitySetCapabilityAction(
              relayId: relayId,
              capability: ContinuityCapabilityKind.clipboard,
              enabled: mode.isEnabled,
            ),
          )
          .then(
            (_) => dispatcher.dispatchAsync(
              ContinuitySetClipboardModeAction(relayId: relayId, mode: mode),
            ),
          ),
    );
  }

  String _subtitle(String? modeLabel) {
    if (!settings.trusted) {
      return 'Trust this device first.';
    }
    final state = platform;
    if (state != null && state.reason != null && state.reason!.isNotEmpty) {
      // Android's own words, not a paraphrase.
      return state.reason!;
    }
    if (modeLabel != null) {
      return modeLabel;
    }
    return settings.isEnabled(capability) ? 'On' : 'Off';
  }

  static IconData _iconFor(ContinuityCapabilityKind capability) => switch (capability) {
    ContinuityCapabilityKind.battery => Icons.battery_std_rounded,
    ContinuityCapabilityKind.clipboard => Icons.content_paste_rounded,
    ContinuityCapabilityKind.notifications => Icons.notifications_none_rounded,
    ContinuityCapabilityKind.messages => Icons.sms_outlined,
    ContinuityCapabilityKind.phone => Icons.call_outlined,
  };
}
