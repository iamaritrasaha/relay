import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_motion/relay_breath.dart';
import 'package:relay_app/widget/relay_motion/relay_edge_sweep.dart';

/// Telephony and call-awareness surface for KDE Connect peers.
///
/// Surfaces real-time call states (incoming ringing, in-call, missed calls) and
/// provides ringer muting when supported by the connected companion.
/// Does not offer fake outbound dial/answer controls.
class GnomeKdePhoneView extends StatelessWidget {
  final RelayDeviceVm device;
  final VoidCallback onBack;

  const GnomeKdePhoneView({
    super.key,
    required this.device,
    required this.onBack,
  });

  String get _deviceId => device.key.replaceFirst('kdeconnect:', '');

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final kdeState = context.watch(kdeConnectProvider);
    final activeCall = kdeState.activeCalls[_deviceId];
    final recentEvents = kdeState.recentTelephonyEvents[_deviceId] ?? const <KdeTelephonyState>[];

    final isRinging = activeCall?.event == 'ringing';
    final isInCall = activeCall?.event == 'talking';
    final hasActive = activeCall != null && !activeCall.isCancel;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, palette),
              const SizedBox(height: 24),
              _buildActiveCallCard(context, palette, activeCall, isRinging, isInCall, hasActive),
              const SizedBox(height: 20),
              _buildCallLimitationsNote(palette),
              const SizedBox(height: 28),
              _buildRecentActivity(palette, recentEvents),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, RelayPalette palette) {
    return Row(
      children: [
        AdwButton.flat(
          icon: Icons.arrow_back_rounded,
          label: 'Devices',
          onPressed: onBack,
        ),
        const SizedBox(width: 14),
        Text('Phone & Calls', style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true)),
      ],
    );
  }

  Widget _buildActiveCallCard(
    BuildContext context,
    RelayPalette palette,
    KdeTelephonyState? activeCall,
    bool isRinging,
    bool isInCall,
    bool hasActive,
  ) {
    final caller = activeCall?.contactName ?? activeCall?.phoneNumber ?? 'Unknown caller';
    final number = activeCall?.phoneNumber;

    final cardContent = RelaySurface(
      radius: RelayRadius.card,
      accented: hasActive,
      outlined: true,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isRinging
                      ? palette.accent.withValues(alpha: 0.18)
                      : (isInCall ? palette.success.withValues(alpha: 0.18) : palette.softSurface),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRinging ? Icons.ring_volume_rounded : (isInCall ? Icons.phone_in_talk_rounded : Icons.phone_outlined),
                  color: isRinging ? palette.accent : (isInCall ? palette.success : palette.textSecondary),
                  size: 24,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRinging ? 'Incoming Call…' : (isInCall ? 'In Call' : 'No Active Call'),
                      style: RelayTypography.caption(
                        isRinging ? palette.accent : (isInCall ? palette.success : palette.textTertiary),
                        isGnome: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasActive ? caller : device.alias,
                      style: RelayTypography.title(palette.textPrimary, isGnome: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasActive && number != null && number != caller) ...[
                      const SizedBox(height: 2),
                      Text(
                        number,
                        style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isRinging && device.canMuteRinger) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AdwButton(
                    icon: Icons.volume_off_rounded,
                    label: 'Mute Phone Ringer',
                    style: AdwButtonStyle.destructive,
                    isPill: true,
                    onPressed: () => unawaited(
                      context
                          .redux(kdeConnectProvider)
                          .dispatchAsync(
                            KdeConnectMuteCallAction(_deviceId),
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (hasActive) {
      // A ringing phone is a state, not an event: the segment travels for as
      // long as it rings. In call the card only breathes, which is calmer and
      // stops the page competing with the conversation.
      return RelayEdgeSweep(
        ambient: isRinging,
        radius: RelayRadius.card,
        child: RelayBreath(
          active: true,
          radius: RelayRadius.card,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }

  Widget _buildCallLimitationsNote(RelayPalette palette) {
    return RelaySurface(
      radius: RelayRadius.panel,
      inset: true,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: palette.textTertiary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Call audio & dialing remain on your phone',
                  style: RelayTypography.heading(palette.textSecondary, isGnome: true),
                ),
                const SizedBox(height: 4),
                Text(
                  'Standard companion protocols broadcast call events and ringer control. Cellular voice audio is handled directly by ${device.alias}.',
                  style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(RelayPalette palette, List<KdeTelephonyState> recentEvents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RelaySectionLabel(label: 'Recent Call Activity (This Session)'),
        const SizedBox(height: 12),
        if (recentEvents.isEmpty)
          RelaySurface(
            radius: RelayRadius.panel,
            inset: true,
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No recent calls observed during this session',
                style: RelayTypography.body(palette.textTertiary, isGnome: true),
              ),
            ),
          )
        else
          RelaySurface(
            radius: RelayRadius.panel,
            outlined: true,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentEvents.length.clamp(0, 15),
              separatorBuilder: (_, __) => Divider(color: palette.hairline, height: 1),
              itemBuilder: (context, index) {
                final item = recentEvents[index];
                final isMissed = item.event == 'missedCall';
                final isTalking = item.event == 'talking';
                final title = item.contactName ?? item.phoneNumber ?? 'Unknown caller';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Icon(
                    isMissed ? Icons.phone_missed_rounded : (isTalking ? Icons.phone_in_talk_rounded : Icons.ring_volume_rounded),
                    color: isMissed ? palette.error : (isTalking ? palette.success : palette.accent),
                    size: 20,
                  ),
                  title: Text(
                    title,
                    style: RelayTypography.heading(palette.textPrimary, isGnome: true),
                  ),
                  subtitle: Text(
                    isMissed ? 'Missed call' : (isTalking ? 'Call connected' : 'Ringing'),
                    style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                  ),
                  trailing: Text(
                    _formatTime(item.timestamp),
                    style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  static String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
