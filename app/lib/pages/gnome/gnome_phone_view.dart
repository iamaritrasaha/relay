import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/continuity/continuity_runtime.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_status_page.dart';
import 'package:relay_isolates/rust/api/continuity.dart' as rust;
import 'package:yaru/yaru.dart';

/// GNOME phone continuity surface.
///
/// Restrained on purpose: idle is one line, and controls appear only for
/// actions the phone actually reported it can perform.
class GnomePhoneView extends StatefulWidget {
  final RelayDeviceVm device;
  final VoidCallback onBack;

  const GnomePhoneView({super.key, required this.device, required this.onBack});

  @override
  State<GnomePhoneView> createState() => _GnomePhoneViewState();
}

class _GnomePhoneViewState extends State<GnomePhoneView> {
  final TextEditingController _number = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relayId = widget.device.relayId;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  YaruBackButton(onPressed: widget.onBack),
                  const SizedBox(width: 10),
                  Text('Phone', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 20),
              if (relayId == null)
                AdwStatusPage(
                  icon: YaruIcons.phone,
                  title: 'Not a Relay device',
                  description: '${widget.device.alias} is a Relay-compatible peer.',
                )
              else
                _body(relayId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(String relayId) {
    return Consumer(
      builder: (context, ref) {
        final theme = Theme.of(context);
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final device = continuity.deviceFor(relayId);

        if (!settings.isEnabled(ContinuityCapabilityKind.phone)) {
          return AdwStatusPage(
            icon: YaruIcons.phone,
            title: 'Phone is off',
            description: 'Turn on Phone for ${widget.device.alias} to see call status here.',
            action: FilledButton(
              onPressed: settings.trusted
                  ? () => unawaited(
                      ref
                          .redux(continuityProvider)
                          .dispatchAsync(
                            ContinuitySetCapabilityAction(
                              relayId: relayId,
                              capability: ContinuityCapabilityKind.phone,
                              enabled: true,
                            ),
                          ),
                    )
                  : null,
              child: Text(settings.trusted ? 'Turn on Phone' : 'Trust this device first'),
            ),
          );
        }

        if (!device.connected) {
          return AdwStatusPage(
            icon: YaruIcons.network_offline,
            title: '${widget.device.alias} is not connected',
            description: 'Call status appears here once the device reconnects.',
          );
        }

        final remote = device.remoteCapabilities[ContinuityCapabilityKind.phone];
        final call = device.call;
        final ringing = call?.phase == RemoteCallPhase.ringing;
        final onCall = call?.phase == RemoteCallPhase.active || call?.phase == RemoteCallPhase.dialing;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdwPreferencesGroup(
              title: 'Call Status',
              uppercaseTitle: false,
              children: [
                AdwActionRow(
                  leading: Icon(ringing ? YaruIcons.bell : YaruIcons.phone),
                  title: call == null || call.isIdle ? widget.device.alias : call.title,
                  subtitle: call == null || call.isIdle ? 'No active call' : call.statusLabel,
                  trailing: switch (call?.activeDuration) {
                    final Duration duration => Text(
                      _duration(duration),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                    null => null,
                  },
                ),
              ],
            ),

            // Only actions the phone can genuinely perform are offered.
            if (ringing)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _act(ref, relayId, rust.RsCallAction.reject),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _act(ref, relayId, rust.RsCallAction.answer),
                      child: const Text('Answer'),
                    ),
                  ),
                ],
              )
            else if (onCall)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: () => _act(ref, relayId, rust.RsCallAction.hangUp),
                child: const Text('Hang up'),
              )
            else
              AdwPreferencesGroup(
                title: 'Call from this computer',
                description: 'The call is placed on ${widget.device.alias}.',
                uppercaseTitle: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _number,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: 'Phone number',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => _dial(ref, relayId),
                          child: const Text('Call'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),
            Padding(
              key: const ValueKey('relay-phone-inline-info-note'),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(YaruIcons.information, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Call audio remains on your phone',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          remote?.reason ?? 'Android only allows capturing call audio with a system-only permission, so the call stays on the phone.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (device.lastError != null) Text(device.lastError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        );
      },
    );
  }

  void _act(WatchableRef ref, String relayId, rust.RsCallAction action) {
    unawaited(
      ref
          .redux(continuityProvider)
          .dispatchAsync(
            ContinuityCallAction(relayId: relayId, action: action),
          ),
    );
  }

  void _dial(WatchableRef ref, String relayId) {
    final number = _number.text.trim();
    if (number.isEmpty) {
      return;
    }
    unawaited(
      ref
          .redux(continuityProvider)
          .dispatchAsync(
            ContinuityCallAction(relayId: relayId, action: rust.RsCallAction.dial, address: number),
          ),
    );
    _number.clear();
  }

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
