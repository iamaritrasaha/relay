import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/animation_provider.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:yaru/yaru.dart';

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
    final theme = Theme.of(context);
    final kdeState = context.watch(kdeConnectProvider);
    final activeCall = kdeState.activeCalls[_deviceId];
    final recentEvents = kdeState.recentTelephonyEvents[_deviceId] ?? const <KdeTelephonyState>[];
    final animationsEnabled = context.watch(animationProvider) && !MediaQuery.disableAnimationsOf(context);

    final isRinging = activeCall?.event == 'ringing';
    final isInCall = activeCall?.event == 'talking';
    final hasActive = activeCall != null && !activeCall.isCancel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('phone-document'),
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme),
              const SizedBox(height: 24),
              _buildCallStatus(
                context,
                theme,
                activeCall,
                isRinging: isRinging,
                isInCall: isInCall,
                hasActive: hasActive,
                animationsEnabled: animationsEnabled,
              ),
              const SizedBox(height: 14),
              _buildCallLimitationsNote(theme),
              const SizedBox(height: 26),
              _buildRecentCalls(theme, recentEvents),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        YaruBackButton(onPressed: onBack),
        const SizedBox(width: 10),
        Text('Phone & Calls', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildCallStatus(
    BuildContext context,
    ThemeData theme,
    KdeTelephonyState? activeCall, {
    required bool isRinging,
    required bool isInCall,
    required bool hasActive,
    required bool animationsEnabled,
  }) {
    final caller = activeCall?.contactName ?? activeCall?.phoneNumber ?? 'Unknown caller';
    final number = activeCall?.phoneNumber;
    final stateLabel = isRinging ? 'Incoming call' : (isInCall ? 'In call' : 'No active call');
    final subtitle = hasActive && number != null && number != caller ? '$stateLabel · $number' : stateLabel;
    final stateKey = hasActive ? '${activeCall!.event}-${activeCall.timestamp}' : 'idle';

    final devicePalette = RelayDevicePalette.fromDevice(device, brightness: theme.brightness);

    return AdwPreferencesGroup(
      key: const ValueKey('phone-call-status-section'),
      title: 'Call Status',
      uppercaseTitle: false,
      margin: EdgeInsets.zero,
      rowPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      rowMinHeight: 68,
      children: [
        AnimatedSwitcher(
          key: const ValueKey('phone-call-state-switcher'),
          duration: animationsEnabled ? const Duration(milliseconds: 200) : Duration.zero,
          reverseDuration: animationsEnabled ? const Duration(milliseconds: 180) : Duration.zero,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: AdwActionRow(
            key: ValueKey('phone-call-state-$stateKey'),
            leading: _CallStateIcon(
              eventKey: stateKey,
              ringing: isRinging,
              inCall: isInCall,
              palette: devicePalette,
              animationsEnabled: animationsEnabled,
            ),
            title: hasActive ? caller : device.alias,
            subtitle: subtitle,
            trailing: isRinging && device.canMuteRinger
                ? TextButton.icon(
                    icon: const Icon(YaruIcons.speaker_muted, size: 16),
                    label: const Text('Mute'),
                    onPressed: () => unawaited(
                      context.redux(kdeConnectProvider).dispatchAsync(KdeConnectMuteCallAction(_deviceId)),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildCallLimitationsNote(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Padding(
      key: const ValueKey('phone-inline-info-note'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(YaruIcons.information, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Call audio and dialing remain on your phone',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  'Relay mirrors call events and available companion controls. Cellular voice audio stays on ${device.alias}.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCalls(ThemeData theme, List<KdeTelephonyState> recentEvents) {
    final colorScheme = theme.colorScheme;

    return AdwPreferencesGroup(
      key: const ValueKey('phone-recent-calls-section'),
      title: 'Recent Calls',
      description: 'This session',
      uppercaseTitle: false,
      margin: EdgeInsets.zero,
      rowPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      rowMinHeight: 60,
      children: [
        if (recentEvents.isEmpty)
          const AdwActionRow(
            leading: Icon(YaruIcons.phone),
            title: 'No recent calls',
            subtitle: 'Calls from this device will appear here.',
          )
        else
          for (final item in recentEvents.take(15))
            AdwActionRow(
              key: ValueKey('phone-call-history-${item.timestamp}-${item.event}'),
              leading: Icon(_callIcon(item.event)),
              title: item.contactName ?? item.phoneNumber ?? 'Unknown caller',
              subtitle: _callLabel(item.event),
              trailing: SizedBox(
                width: 48,
                child: Text(
                  _formatTime(item.timestamp),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ),
            ),
      ],
    );
  }

  static IconData _callIcon(String event) => switch (event) {
    'missedCall' => YaruIcons.call_stop,
    'talking' => YaruIcons.call_incoming,
    _ => YaruIcons.bell,
  };

  static String _callLabel(String event) => switch (event) {
    'missedCall' => 'Missed call',
    'talking' => 'Call connected',
    _ => 'Ringing',
  };

  static String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// A finite acknowledgement for a newly ringing call with subtle phone oscillation and palette tint.
class _CallStateIcon extends StatelessWidget {
  final String eventKey;
  final bool ringing;
  final bool inCall;
  final RelayDevicePalette palette;
  final bool animationsEnabled;

  const _CallStateIcon({
    required this.eventKey,
    required this.ringing,
    required this.inCall,
    required this.palette,
    required this.animationsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = ringing ? YaruIcons.bell : (inCall ? YaruIcons.call_incoming : YaruIcons.phone);
    final accent = ringing || inCall ? palette.primary : colorScheme.onSurfaceVariant;
    final motionOn = animationsEnabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

    return SizedBox(
      width: 36,
      height: 36,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('phone-call-indicator-$eventKey'),
        tween: Tween(begin: 0, end: 1),
        duration: ringing && motionOn ? const Duration(milliseconds: 750) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final angle = (ringing && motionOn && value < 1.0) ? 0.05 * math.sin(value * 4 * math.pi) : 0.0;

          return Stack(
            alignment: Alignment.center,
            children: [
              if (ringing && motionOn && value < 1.0)
                Container(
                  width: 10 + (18 * value),
                  height: 10 + (18 * value),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.45 * (1 - value)), width: 1.5),
                  ),
                ),
              Transform.rotate(
                angle: angle,
                child: child!,
              ),
            ],
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.12),
          ),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(child: Icon(icon, size: 18, color: accent)),
          ),
        ),
      ),
    );
  }
}
