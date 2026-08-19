import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Android messages continuity page.
///
/// A phone provides messages rather than consuming them, so for a computer peer
/// this page says so plainly instead of showing an empty inbox.
class AndroidMessagesPage extends StatelessWidget {
  final RelayDeviceVm device;

  const AndroidMessagesPage({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final relayId = device.relayId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Messages', style: RelayTypography.title(palette.textPrimary)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: relayId == null
              ? _message(
                  context,
                  icon: Icons.sms_outlined,
                  title: 'Not a Relay device',
                  body: '${device.alias} is a Relay-compatible device and can only receive files.',
                )
              : Consumer(
                  builder: (context, ref) {
                    final continuity = ref.watch(continuityProvider);
                    final settings = continuity.settingsFor(relayId);
                    final state = continuity.deviceFor(relayId);
                    final remote = state.remoteCapabilities[ContinuityCapabilityKind.messages];

                    if (!settings.isEnabled(ContinuityCapabilityKind.messages)) {
                      return _message(
                        context,
                        icon: Icons.sms_outlined,
                        title: 'Messages are off',
                        body: settings.trusted
                            ? 'Turn on Messages for ${device.alias} in its continuity settings.'
                            : 'Trust ${device.alias} for continuity first.',
                      );
                    }
                    if (!state.connected) {
                      return _message(
                        context,
                        icon: Icons.cloud_off_rounded,
                        title: '${device.alias} is not connected',
                        body: 'Conversations appear once the device reconnects.',
                      );
                    }
                    if (remote != null && !remote.isUsable) {
                      return _message(
                        context,
                        icon: Icons.info_outline_rounded,
                        title: remote.needsPermission ? 'Permission needed on ${device.alias}' : 'Nothing to show',
                        // The peer's own honest reason, e.g. a computer has no
                        // messaging service of its own.
                        body: remote.reason ?? '${device.alias} does not share messages.',
                      );
                    }
                    if (state.conversations.isEmpty) {
                      return _message(
                        context,
                        icon: Icons.forum_outlined,
                        title: 'No conversations',
                        body: 'Nothing has been shared from ${device.alias} yet.',
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final conversation in state.conversations)
                          ListTile(
                            leading: Icon(
                              conversation.unread ? Icons.mark_chat_unread_outlined : Icons.chat_bubble_outline,
                            ),
                            title: Text(conversation.title),
                            subtitle: conversation.snippet == null ? null : Text(conversation.snippet!),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _message(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final palette = Theme.of(context).relayPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.accent.withValues(alpha: 0.12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 36, color: palette.accent),
        ),
        const SizedBox(height: 20),
        Text(title, style: RelayTypography.title(palette.textPrimary), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(body, style: RelayTypography.body(palette.textSecondary), textAlign: TextAlign.center),
      ],
    );
  }
}
