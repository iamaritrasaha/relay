import 'dart:async';

import 'package:flutter/material.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/continuity/continuity_runtime.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/widget/gnome/adw_action_row.dart';
import 'package:relay_app/widget/gnome/adw_boxed_list.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:relay_app/widget/gnome/adw_status_page.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// GNOME messages continuity surface: conversations, one thread, and a reply
/// box. Every state it can be in is a real one — there are no sample chats.
class GnomeMessagesView extends StatefulWidget {
  final RelayDeviceVm device;
  final VoidCallback onBack;

  const GnomeMessagesView({
    super.key,
    required this.device,
    required this.onBack,
  });

  @override
  State<GnomeMessagesView> createState() => _GnomeMessagesViewState();
}

class _GnomeMessagesViewState extends State<GnomeMessagesView> {
  final TextEditingController _reply = TextEditingController();
  String? _openConversationId;
  bool _requested = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  String? get _relayId => widget.device.relayId;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;
    final relayId = _relayId;

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
                  AdwButton.flat(
                    icon: Icons.arrow_back_rounded,
                    label: _openConversationId == null ? 'Back' : 'Conversations',
                    onPressed: _openConversationId == null ? widget.onBack : () => setState(() => _openConversationId = null),
                  ),
                  const SizedBox(width: 12),
                  Text('Messages', style: RelayTypography.largeTitle(palette.textPrimary, isGnome: true)),
                ],
              ),
              const SizedBox(height: 24),
              if (relayId == null)
                AdwStatusPage(
                  icon: Icons.sms_outlined,
                  title: 'Not a Relay device',
                  description: '${widget.device.alias} is a Relay-compatible peer. Messages need a paired Relay device.',
                )
              else
                _body(context, relayId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String relayId) {
    return Consumer(
      builder: (context, ref) {
        final continuity = ref.watch(continuityProvider);
        final settings = continuity.settingsFor(relayId);
        final device = continuity.deviceFor(relayId);

        if (!settings.isEnabled(ContinuityCapabilityKind.messages)) {
          return AdwStatusPage(
            icon: Icons.sms_outlined,
            title: 'Messages are off',
            description: 'Turn on Messages for ${widget.device.alias} to read and reply to its conversations here.',
            action: AdwButton(
              label: settings.trusted ? 'Turn on Messages' : 'Trust this device first',
              isPill: true,
              onPressed: settings.trusted
                  ? () => ref
                        .redux(continuityProvider)
                        .dispatchAsync(
                          ContinuitySetCapabilityAction(
                            relayId: relayId,
                            capability: ContinuityCapabilityKind.messages,
                            enabled: true,
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
            description: 'Messages appear here once the device reconnects.',
          );
        }

        final remote = device.remoteCapabilities[ContinuityCapabilityKind.messages];
        if (remote != null && !remote.isUsable) {
          return AdwStatusPage(
            icon: Icons.lock_outline_rounded,
            title: remote.needsPermission ? 'Permission needed on ${widget.device.alias}' : 'Not available',
            description: remote.reason ?? 'That phone cannot share its messages.',
          );
        }

        // Ask once per open; the peer answers with a bounded page.
        if (!_requested) {
          _requested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(
              ref
                  .redux(continuityProvider)
                  .dispatchAsync(
                    ContinuityLoadConversationsAction(relayId: relayId),
                  ),
            );
          });
        }

        final openId = _openConversationId;
        if (openId != null) {
          return _thread(context, ref, relayId, device, openId);
        }
        return _conversations(context, ref, relayId, device);
      },
    );
  }

  Widget _conversations(BuildContext context, WatchableRef ref, String relayId, DeviceContinuity device) {
    final palette = Theme.of(context).relayPalette;
    if (device.conversations.isEmpty) {
      return const AdwStatusPage(
        icon: Icons.forum_outlined,
        title: 'No conversations yet',
        description: 'Conversations load from the phone as they are needed.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdwPreferencesGroup(
          children: [
            for (final conversation in device.conversations)
              AdwActionRow(
                leading: Icon(conversation.unread ? Icons.mark_chat_unread_outlined : Icons.chat_bubble_outline),
                title: conversation.title,
                subtitle: conversation.snippet,
                trailing: Text(
                  _timeLabel(conversation.lastMessageAt),
                  style: RelayTypography.caption(palette.textSecondary, isGnome: true),
                ),
                onTap: () {
                  setState(() => _openConversationId = conversation.conversationId);
                  unawaited(
                    ref
                        .redux(continuityProvider)
                        .dispatchAsync(
                          ContinuityLoadMessagesAction(
                            relayId: relayId,
                            conversationId: conversation.conversationId,
                          ),
                        ),
                  );
                },
              ),
          ],
        ),
        if (device.conversationsHasMore)
          AdwButton.flat(
            label: 'Load older conversations',
            onPressed: () => ref
                .redux(continuityProvider)
                .dispatchAsync(
                  ContinuityLoadConversationsAction(
                    relayId: relayId,
                    beforeMs: device.conversations.last.lastMessageAt.millisecondsSinceEpoch,
                  ),
                ),
          ),
      ],
    );
  }

  Widget _thread(
    BuildContext context,
    WatchableRef ref,
    String relayId,
    DeviceContinuity device,
    String conversationId,
  ) {
    final palette = Theme.of(context).relayPalette;
    final messages = device.messages[conversationId] ?? const <RemoteMessage>[];
    final conversation = device.conversations.where((entry) => entry.conversationId == conversationId).firstOrNull;
    final recipients = conversation?.addresses ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conversation != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              conversation.title,
              style: RelayTypography.title(palette.textPrimary, isGnome: true),
            ),
          ),
        if (messages.isEmpty)
          const AdwStatusPage(
            icon: Icons.chat_outlined,
            title: 'Loading messages…',
            description: 'The phone is sending this conversation.',
          )
        else
          AdwPreferencesGroup(
            children: [
              for (final message in messages.reversed)
                AdwActionRow(
                  leading: Icon(message.outgoing ? Icons.call_made_rounded : Icons.call_received_rounded),
                  title: message.body,
                  subtitle: _timeLabel(message.sentAt),
                ),
            ],
          ),
        if ((device.messagesHasMore[conversationId] ?? false) && messages.isNotEmpty)
          AdwButton.flat(
            label: 'Load older messages',
            onPressed: () => ref
                .redux(continuityProvider)
                .dispatchAsync(
                  ContinuityLoadMessagesAction(
                    relayId: relayId,
                    conversationId: conversationId,
                    beforeMs: messages.last.sentAt.millisecondsSinceEpoch,
                  ),
                ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _reply,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Reply…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            AdwButton(
              label: 'Send',
              isPill: true,
              onPressed: recipients.isEmpty ? null : () => _send(ref, relayId, conversationId, recipients),
            ),
          ],
        ),
        if (device.lastError != null) ...[
          const SizedBox(height: 12),
          Text(device.lastError!, style: RelayTypography.caption(palette.error, isGnome: true)),
        ],
      ],
    );
  }

  void _send(WatchableRef ref, String relayId, String conversationId, List<String> recipients) {
    final body = _reply.text.trim();
    if (body.isEmpty) {
      return;
    }
    unawaited(
      ref
          .redux(continuityProvider)
          .dispatchAsync(
            ContinuitySendMessageAction(
              relayId: relayId,
              conversationId: conversationId,
              recipients: recipients,
              body: body,
            ),
          ),
    );
    _reply.clear();
  }

  static String _timeLabel(DateTime moment) {
    final now = DateTime.now();
    final sameDay = now.year == moment.year && now.month == moment.month && now.day == moment.day;
    final hour = moment.hour.toString().padLeft(2, '0');
    final minute = moment.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hour:$minute';
    }
    return '${moment.day}/${moment.month} $hour:$minute';
  }
}
