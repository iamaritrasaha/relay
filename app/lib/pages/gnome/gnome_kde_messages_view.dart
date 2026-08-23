import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/ui/relay_connection_state.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/config/relay_motion.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';
import 'package:yaru/yaru.dart';

/// Full-height desktop split Messages continuity surface for KDE Connect peers.
///
/// Features a dedicated conversation sidebar, thread history with date separators,
/// and a multiline SMS composer with Ctrl+Enter shortcut and optimistic state updates.
///
/// Composer metrics live here rather than inline so the layout test asserts the
/// same numbers the widget is built from.

/// Height of the input at rest. A desktop composer, not a search field.
const double relayComposerFieldMinHeight = 52;
const double relayComposerFieldRadius = 12;
const double relayComposerSendHeight = 52;
const double relayComposerSendWidth = 88;
const double relayComposerGap = 12;
const double relayComposerVerticalPadding = 18;
const double relayComposerHorizontalPadding = 18;

final _smsLogger = Logger('RelaySmsBridge');

class GnomeKdeMessagesView extends StatefulWidget {
  final RelayDeviceVm device;
  final VoidCallback onBack;

  const GnomeKdeMessagesView({
    super.key,
    required this.device,
    required this.onBack,
  });

  @override
  State<GnomeKdeMessagesView> createState() => _GnomeKdeMessagesViewState();
}

class _GnomeKdeMessagesViewState extends State<GnomeKdeMessagesView> {
  int? _threadId;
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _draftsByThread = {};
  bool _hasInitialScrolled = false;
  String? _lastSmsKeyTrace;

  String get _deviceId => kdeConnectDeviceIdFromKey(widget.device.key);
  bool get _connected => widget.device.connectionState.isConnected;
  bool get _canSend => _connected && widget.device.canSendSms;

  /// Why the composer is closed, so a disabled Send is never a mystery.
  String? get _sendBlockedReason {
    if (!_connected) return 'Reconnect to ${widget.device.alias} to send messages.';
    if (!widget.device.canSendSms) return '${widget.device.alias} does not accept send requests from Relay.';
    return null;
  }

  bool _requestedConversations = false;

  // Reading a provider is reading an inherited widget, which is not allowed
  // until initState has finished. Release builds skip the assertion, so this
  // only ever surfaced as a debug-mode crash.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedConversations) {
      return;
    }
    _requestedConversations = true;
    _smsLogger.info('UI request deviceKey=${widget.device.key} providerDeviceId=$_deviceId');
    unawaited(context.redux(kdeConnectProvider).dispatchAsync(KdeConnectRequestSmsConversationsAction(_deviceId)));
  }

  @override
  void dispose() {
    _composerController.dispose();
    _composerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSelectThread(int threadId) {
    if (_threadId != null) {
      _draftsByThread[_threadId!] = _composerController.text;
    }
    setState(() {
      _threadId = threadId;
      _hasInitialScrolled = false;
      _composerController.text = _draftsByThread[threadId] ?? '';
    });
    unawaited(
      context
          .redux(kdeConnectProvider)
          .dispatchAsync(
            KdeConnectRequestSmsConversationAction(_deviceId, threadId),
          ),
    );
  }

  void _scrollToBottom([bool animated = true]) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animated && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _sendSms(RsKdeSmsConversation conversation) {
    final text = _composerController.text.trim();
    if (text.isEmpty || !_canSend) return;

    final addresses = conversation.participants.isNotEmpty ? conversation.participants : (conversation.latestMessage?.addresses ?? const <String>[]);

    if (addresses.isEmpty) return;

    final subId = conversation.latestMessage != null ? _extractSubId(conversation.latestMessage!) : null;

    _composerController.clear();
    _draftsByThread.remove(conversation.threadId);

    unawaited(
      context
          .redux(kdeConnectProvider)
          .dispatchAsync(
            KdeConnectSendSmsAction(
              deviceId: _deviceId,
              threadId: conversation.threadId,
              addresses: addresses,
              messageBody: text,
              subId: subId,
            ),
          ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// The SIM the thread is already on. Replying on a different subscription
  /// than the conversation would send from the wrong number on a dual-SIM
  /// phone, so the reply inherits whatever the last message used.
  int? _extractSubId(RsKdeSmsMessage message) => message.subId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kdeState = context.watch(kdeConnectProvider);
    final conversations = kdeState.smsConversations[_deviceId] ?? const <RsKdeSmsConversation>[];
    final trace = '${kdeState.smsConversations.keys.join(',')}|${kdeState.smsMessages.keys.join(',')}';
    if (_lastSmsKeyTrace != trace) {
      _lastSmsKeyTrace = trace;
      _smsLogger.info(
        'UI state device=$_deviceId conversationKeyMatch=${kdeState.smsConversations.containsKey(_deviceId)} '
        'messageKeyMatch=${kdeState.smsMessages.containsKey(_deviceId)} conversations=${conversations.length}',
      );
    }
    final selected = conversations.firstWhereOrNull((item) => item.threadId == _threadId);
    final messages = _threadId == null ? const <RsKdeSmsMessage>[] : kdeState.smsMessages[_deviceId]?[_threadId] ?? const <RsKdeSmsMessage>[];

    if (_threadId != null && !_hasInitialScrolled && messages.isNotEmpty) {
      _hasInitialScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(false));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, theme),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;

                if (!isWide) {
                  return selected == null
                      ? _buildConversationList(context, theme, conversations, isWide: false)
                      : _buildConversationPanel(context, theme, selected, messages, isWide: false);
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: YaruBorderContainer(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _buildConversationList(context, theme, conversations, isWide: true),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: YaruBorderContainer(
                        child: selected == null ? _buildEmptyPanel(theme) : _buildConversationPanel(context, theme, selected, messages, isWide: true),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final yaruColors = YaruColors.of(context);
    return Row(
      children: [
        YaruBackButton(
          onPressed: widget.onBack,
        ),
        const SizedBox(width: 10),
        Text('Messages', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        if (!_connected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: yaruColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(RelayRadius.pill),
            ),
            child: Text(
              'Offline',
              style: theme.textTheme.labelSmall?.copyWith(
                color: yaruColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const Spacer(),
        YaruIconButton(
          icon: const Icon(YaruIcons.refresh),
          tooltip: 'Refresh',
          onPressed: _connected
              ? () => unawaited(
                  context
                      .redux(kdeConnectProvider)
                      .dispatchAsync(
                        KdeConnectRequestSmsConversationsAction(_deviceId),
                      ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildEmptyPanel(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(YaruIcons.chat_bubble, size: 48, color: colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            'Select a conversation',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Read and reply to SMS from ${widget.device.alias}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(
    BuildContext context,
    ThemeData theme,
    List<RsKdeSmsConversation> conversations, {
    required bool isWide,
  }) {
    final colorScheme = theme.colorScheme;
    if (conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _connected ? 'Loading conversations…' : 'No conversations cached',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        final isSelected = conversation.threadId == _threadId;
        final latest = conversation.latestMessage;
        final participant = conversation.participants.isEmpty ? 'Unknown' : conversation.participants.join(', ');

        return YaruMasterTile(
          selected: isSelected,
          onTap: () => _onSelectThread(conversation.threadId),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isSelected ? colorScheme.primary.withValues(alpha: 0.25) : colorScheme.surfaceContainerHighest,
            child: Text(
              participant.characters.firstOrNull?.toUpperCase() ?? '#',
              style: TextStyle(
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(
            participant,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            latest?.body.isNotEmpty == true ? latest!.body : (latest?.attachments.isNotEmpty == true ? 'Attachment' : 'No preview'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (latest != null)
                Text(
                  _formatTime(latest.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              if (conversation.unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(RelayRadius.pill),
                  ),
                  child: Text(
                    '${conversation.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildConversationPanel(
    BuildContext context,
    ThemeData theme,
    RsKdeSmsConversation conversation,
    List<RsKdeSmsMessage> messages, {
    required bool isWide,
  }) {
    final colorScheme = theme.colorScheme;
    final participant = conversation.participants.isEmpty ? 'Conversation' : conversation.participants.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thread Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              if (!isWide)
                YaruBackButton(
                  onPressed: () => setState(() => _threadId = null),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _connected ? 'SMS via ${widget.device.alias}' : 'Phone disconnected',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Message History
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    _connected ? 'Loading messages…' : 'No history loaded',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final showDate = index == 0 || !_isSameDay(messages[index - 1].date, msg.date);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDate) _buildDateSeparator(theme, msg.date),
                        _MessageArrival(
                          key: ValueKey('message-arrival-${msg.id}'),
                          animate: _hasInitialScrolled && index == messages.length - 1,
                          child: _buildMessageBubble(theme, msg),
                        ),
                      ],
                    );
                  },
                ),
        ),

        // Composer Box
        _buildComposer(theme, conversation),
      ],
    );
  }

  Widget _buildDateSeparator(ThemeData theme, int timestamp) {
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(RelayRadius.pill),
          ),
          child: Text(
            _formatDateHeader(timestamp),
            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ThemeData theme, RsKdeSmsMessage message) {
    final colorScheme = theme.colorScheme;
    final isOutgoing = message.messageType == 2;
    final isPending = message.id < 0;
    final devicePalette = RelayDevicePalette.fromDevice(widget.device, brightness: theme.brightness);
    final accent = devicePalette.primary;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isOutgoing ? accent.withValues(alpha: isPending ? 0.10 : 0.18) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(RelayRadius.card),
          border: Border.all(
            color: isOutgoing ? accent.withValues(alpha: isPending ? 0.35 : 0.45) : theme.dividerColor,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body.isEmpty && message.attachments.isNotEmpty ? 'Attachment' : message.body,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: accent,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme, RsKdeSmsConversation conversation) {
    final colorScheme = theme.colorScheme;
    final hasDraft = _composerController.text.trim().isNotEmpty;
    final canSendNow = _canSend && hasDraft;
    final devicePalette = RelayDevicePalette.fromDevice(widget.device, brightness: theme.brightness);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        relayComposerHorizontalPadding,
        relayComposerVerticalPadding,
        relayComposerHorizontalPadding,
        relayComposerVerticalPadding,
      ),
      color: colorScheme.surface,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _sendSms(conversation),
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : RelayMotion.state,
                curve: RelayMotion.focusCurve,
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  key: const ValueKey('kde-composer-field'),
                  constraints: const BoxConstraints(minHeight: relayComposerFieldMinHeight),
                  child: TextField(
                    controller: _composerController,
                    focusNode: _composerFocus,
                    maxLines: 4,
                    minLines: 1,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: _sendBlockedReason ?? 'Message',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(relayComposerFieldRadius),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(relayComposerFieldRadius),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(relayComposerFieldRadius),
                        borderSide: BorderSide(color: devicePalette.primary, width: 1.5),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(relayComposerFieldRadius),
                        borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    enabled: _canSend,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ),
            const SizedBox(width: relayComposerGap),
            Tooltip(
              message: _sendBlockedReason ?? 'Send · Ctrl+Enter',
              child: _RelaySendButton(
                enabled: canSendNow,
                height: relayComposerSendHeight,
                width: relayComposerSendWidth,
                onPressed: () => _sendSms(conversation),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static bool _isSameDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  static String _formatDateHeader(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();
    if (_isSameDay(timestampMs, now.millisecondsSinceEpoch)) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(timestampMs, yesterday.millisecondsSinceEpoch)) {
      return 'Yesterday';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _RelaySendButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPressed;
  final double height;
  final double width;

  const _RelaySendButton({
    required this.enabled,
    required this.onPressed,
    required this.height,
    required this.width,
  });

  @override
  State<_RelaySendButton> createState() => _RelaySendButtonState();
}

class _RelaySendButtonState extends State<_RelaySendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? RelayMotion.tactileScale : 1.0,
      duration: RelayMotion.press,
      curve: RelayMotion.curve,
      child: SizedBox(
        key: const ValueKey('kde-composer-send'),
        height: widget.height,
        width: widget.width,
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: FilledButton(
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RelayRadius.button),
              ),
            ),
            onPressed: widget.enabled ? widget.onPressed : null,
            child: const Text('Send'),
          ),
        ),
      ),
    );
  }
}

/// Animates only the newest bubble once a conversation is already open.
class _MessageArrival extends StatefulWidget {
  final bool animate;
  final Widget child;

  const _MessageArrival({super.key, required this.animate, required this.child});

  @override
  State<_MessageArrival> createState() => _MessageArrivalState();
}

class _MessageArrivalState extends State<_MessageArrival> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: RelayMotion.navigation,
      value: widget.animate ? 0 : 1,
    );
    if (widget.animate) {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = RelayMotion.curve.transform(_controller.value);
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, 6 * (1 - value)), child: child),
        );
      },
    );
  }
}
