import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Android clipboard continuity sheet.
///
/// This sheet is also the honest answer to Android's clipboard rule: an app can
/// only read the clipboard while it has focus, and while this sheet is open
/// Relay does. "Share now" therefore always works, whereas automatic sharing
/// only covers the times Relay happens to be open.
class AndroidClipboardSheet extends StatelessWidget {
  final RelayDeviceVm device;

  const AndroidClipboardSheet({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final relayId = device.relayId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.content_paste_outlined, color: palette.accent, size: 24),
              const SizedBox(width: 12),
              Text('Clipboard', style: RelayTypography.title(palette.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          if (relayId == null)
            Text(
              '${device.alias} is a Relay-compatible device, so it can only receive files.',
              style: RelayTypography.body(palette.textSecondary),
            )
          else
            _Body(relayId: relayId, alias: device.alias),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String relayId;
  final String alias;

  const _Body({required this.relayId, required this.alias});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return Consumer(
      builder: (context, ref) {
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final state = continuity.deviceFor(relayId);
        final mode = settings.clipboardMode;

        if (!settings.isEnabled(ContinuityCapabilityKind.clipboard)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Clipboard sharing is off', style: RelayTypography.heading(palette.textPrimary)),
              const SizedBox(height: 6),
              Text(
                settings.trusted ? 'Turn it on for $alias in this device’s continuity settings.' : 'Trust $alias for continuity first.',
                style: RelayTypography.body(palette.textSecondary),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sharing: ${mode.label}', style: RelayTypography.heading(palette.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Android only lets Relay read this phone’s clipboard while Relay is open, '
              'so use Share now for anything copied elsewhere.',
              style: RelayTypography.body(palette.textSecondary),
            ),
            if (state.clipboardOffer != null) ...[
              const SizedBox(height: 16),
              Text('From $alias', style: RelayTypography.sectionHeader(palette.textSecondary)),
              const SizedBox(height: 4),
              Text(_preview(state.clipboardOffer!.text), style: RelayTypography.body(palette.textPrimary)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(
                  ref
                      .redux(continuityProvider)
                      .dispatchAsync(
                        ContinuityAcceptClipboardOfferAction(relayId: relayId),
                      ),
                ),
                icon: const Icon(Icons.content_paste_go_rounded),
                label: const Text('Copy to this phone'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.connected
                  ? () => unawaited(
                      ref
                          .redux(continuityProvider)
                          .dispatchAsync(
                            ContinuityShareClipboardAction(relayId: relayId),
                          ),
                    )
                  : null,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(state.connected ? 'Share now' : '$alias is not connected'),
            ),
            if (state.lastError != null) ...[
              const SizedBox(height: 12),
              Text(state.lastError!, style: RelayTypography.caption(palette.error)),
            ],
          ],
        );
      },
    );
  }

  static String _preview(String text) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= 160 ? single : '${single.substring(0, 160)}…';
  }
}
