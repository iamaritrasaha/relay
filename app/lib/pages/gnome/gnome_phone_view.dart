import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/relay_brand.dart';
import 'package:localsend_app/model/continuity/continuity_runtime.dart';
import 'package:localsend_app/model/persistence/relay_continuity_settings.dart';
import 'package:localsend_app/model/ui/relay_device_vm.dart';
import 'package:localsend_app/provider/continuity/continuity_provider.dart';
import 'package:localsend_app/widget/gnome/adw_action_row.dart';
import 'package:localsend_app/widget/gnome/adw_boxed_list.dart';
import 'package:localsend_app/widget/gnome/adw_button.dart';
import 'package:localsend_app/widget/gnome/adw_status_page.dart';
import 'package:localsend_isolates/rust/api/continuity.dart' as rust;
import 'package:refena_flutter/refena_flutter.dart';

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
    final palette = Theme.of(context).relayPalette;
    final relayId = widget.device.relayId;

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
                  AdwButton.flat(icon: Icons.arrow_back_rounded, label: 'Back', onPressed: widget.onBack),
                  const SizedBox(width: 12),
                  Text('Phone', style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true)),
                ],
              ),
              const SizedBox(height: 24),
              if (relayId == null)
                AdwStatusPage(
                  icon: Icons.call_outlined,
                  title: 'Not a Relay device',
                  description: '${widget.device.alias} is a LocalSend-compatible peer.',
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
        final palette = Theme.of(context).relayPalette;
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final device = continuity.deviceFor(relayId);

        if (!settings.isEnabled(ContinuityCapabilityKind.phone)) {
          return AdwStatusPage(
            icon: Icons.call_outlined,
            title: 'Phone is off',
            description: 'Turn on Phone for ${widget.device.alias} to see call status here.',
            action: AdwButton(
              label: settings.trusted ? 'Turn on Phone' : 'Trust this device first',
              isPill: true,
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
            ),
          );
        }

        if (!device.connected) {
          return AdwStatusPage(
            icon: Icons.cloud_off_rounded,
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
              children: [
                AdwActionRow(
                  leading: Icon(ringing ? Icons.ring_volume_rounded : Icons.call_outlined),
                  title: call == null || call.isIdle ? 'No active call' : call.title,
                  subtitle: call?.statusLabel,
                  trailing: switch (call?.activeDuration) {
                    final Duration duration => Text(
                      _duration(duration),
                      style: RelayTypography.caption(palette.textSecondary, isGnome: true),
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
                    child: AdwButton(
                      label: 'Decline',
                      isPill: true,
                      onPressed: () => _act(ref, relayId, rust.RsCallAction.reject),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdwButton(
                      label: 'Answer',
                      isPill: true,
                      onPressed: () => _act(ref, relayId, rust.RsCallAction.answer),
                    ),
                  ),
                ],
              )
            else if (onCall)
              AdwButton(
                label: 'Hang up',
                isPill: true,
                onPressed: () => _act(ref, relayId, rust.RsCallAction.hangUp),
              )
            else
              AdwPreferencesGroup(
                title: 'Call from this computer',
                description: 'The call is placed on ${widget.device.alias}.',
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
                        AdwButton(
                          label: 'Call',
                          isPill: true,
                          onPressed: () => _dial(ref, relayId),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),
            // The one limitation worth stating plainly, and only once.
            AdwPreferencesGroup(
              children: [
                AdwActionRow(
                  leading: const Icon(Icons.headset_off_outlined),
                  title: 'Call audio on this computer — not available',
                  subtitle:
                      remote?.reason ??
                      'Android only allows capturing call audio with a system-only permission, '
                          'so the call stays on the phone.',
                ),
              ],
            ),

            if (device.lastError != null) Text(device.lastError!, style: RelayTypography.caption(palette.error, isGnome: true)),
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
