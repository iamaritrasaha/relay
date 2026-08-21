import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/config/relay_brand.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';
import 'package:relay_app/widget/gnome/adw_button.dart';
import 'package:relay_app/widget/relay_carbon/relay_surface.dart';
import 'package:relay_app/widget/relay_motion/relay_edge_sweep.dart';
import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// Full-height desktop split Messages continuity surface for KDE Connect peers.
///
/// Features a dedicated conversation sidebar, thread history with date separators,
/// and a multiline SMS composer with Ctrl+Enter shortcut and optimistic state updates.
///
/// Composer metrics live here rather than inline so the layout test asserts the
/// same numbers the widget is built from.

/// Height of the input at rest. A desktop composer, not a search field.
const double relayComposerFieldMinHeight = 52;
const double relayComposerFieldRadius = 16;
const double relayComposerSendHeight = 52;
const double relayComposerSendWidth = 88;
const double relayComposerGap = 12;
const double relayComposerVerticalPadding = 18;
const double relayComposerHorizontalPadding = 18;

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

  String get _deviceId => widget.device.key.replaceFirst('kdeconnect:', '');
  bool get _connected => widget.device.detail == 'Connected';
  bool get _canSend => _connected && widget.device.canSendSms;

  /// Why the composer is closed, so a disabled Send is never a mystery.
  String? get _sendBlockedReason {
    if (!_connected) return 'Reconnect to ${widget.device.alias} to send messages.';
    if (!widget.device.canSendSms) return '${widget.device.alias} does not accept send requests from Relay.';
    return null;
  }

  @override
  void initState() {
    super.initState();
    // The field's focus border is painted by this widget, so focus changes have
    // to reach it the same way text changes do.
    _composerFocus.addListener(_onComposerFocusChanged);
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
    unawaited(context.redux(kdeConnectProvider).dispatchAsync(KdeConnectRequestSmsConversationsAction(_deviceId)));
  }

  void _onComposerFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _composerFocus.removeListener(_onComposerFocusChanged);
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
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
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
    final palette = Theme.of(context).relayPalette;
    final conversations = context.watch(kdeConnectProvider).smsConversations[_deviceId] ?? const <RsKdeSmsConversation>[];
    final selected = conversations.firstWhereOrNull((item) => item.threadId == _threadId);
    final messages = _threadId == null
        ? const <RsKdeSmsMessage>[]
        : context.watch(kdeConnectProvider).smsMessages[_deviceId]?[_threadId] ?? const <RsKdeSmsMessage>[];

    if (_threadId != null && !_hasInitialScrolled && messages.isNotEmpty) {
      _hasInitialScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(false));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, palette),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;

                if (!isWide) {
                  return selected == null
                      ? _buildConversationList(context, palette, conversations, isWide: false)
                      : _buildConversationPanel(context, palette, selected, messages, isWide: false);
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 320,
                      child: RelaySurface(
                        radius: RelayRadius.panel,
                        inset: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _buildConversationList(context, palette, conversations, isWide: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: RelaySurface(
                        radius: RelayRadius.card,
                        outlined: true,
                        child: selected == null
                            ? _buildEmptyPanel(palette)
                            : _buildConversationPanel(context, palette, selected, messages, isWide: true),
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

  Widget _buildHeader(BuildContext context, RelayPalette palette) {
    return Row(
      children: [
        AdwButton.flat(
          icon: Icons.arrow_back_rounded,
          label: 'Devices',
          onPressed: widget.onBack,
        ),
        const SizedBox(width: 14),
        Text('Messages', style: RelayTypography.title(palette.textPrimary, isGnome: true)),
        const SizedBox(width: 12),
        if (!_connected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(RelayRadius.pill),
            ),
            child: Text(
              'Offline',
              style: RelayTypography.caption(palette.warning, isGnome: true),
            ),
          ),
        const Spacer(),
        AdwButton.flat(
          icon: Icons.refresh_rounded,
          label: 'Refresh',
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

  Widget _buildEmptyPanel(RelayPalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 48, color: palette.textTertiary),
          const SizedBox(height: 14),
          Text(
            'Select a conversation',
            style: RelayTypography.heading(palette.textSecondary, isGnome: true),
          ),
          const SizedBox(height: 6),
          Text(
            'Read and reply to SMS from ${widget.device.alias}',
            style: RelayTypography.body(palette.textTertiary, isGnome: true),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(
    BuildContext context,
    RelayPalette palette,
    List<RsKdeSmsConversation> conversations, {
    required bool isWide,
  }) {
    if (conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _connected ? 'Loading conversations…' : 'No conversations cached',
            style: RelayTypography.body(palette.textSecondary, isGnome: true),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        final isSelected = conversation.threadId == _threadId;
        final latest = conversation.latestMessage;
        final participant = conversation.participants.isEmpty ? 'Unknown' : conversation.participants.join(', ');

        return Material(
          color: isSelected ? palette.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(RelayRadius.action),
          child: InkWell(
            borderRadius: BorderRadius.circular(RelayRadius.action),
            onTap: () => _onSelectThread(conversation.threadId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isSelected ? palette.accent.withValues(alpha: 0.25) : palette.softSurface,
                    child: Text(
                      participant.characters.firstOrNull?.toUpperCase() ?? '#',
                      style: TextStyle(
                        color: isSelected ? palette.accent : palette.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                participant,
                                style: RelayTypography.heading(palette.textPrimary, isGnome: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (latest != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(latest.date),
                                style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          latest?.body.isNotEmpty == true ? latest!.body : (latest?.attachments.isNotEmpty == true ? 'Attachment' : 'No preview'),
                          style: RelayTypography.caption(
                            conversation.unreadCount > 0 ? palette.textPrimary : palette.textSecondary,
                            isGnome: true,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (conversation.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: palette.accent,
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversationPanel(
    BuildContext context,
    RelayPalette palette,
    RsKdeSmsConversation conversation,
    List<RsKdeSmsMessage> messages, {
    required bool isWide,
  }) {
    final participant = conversation.participants.isEmpty ? 'Conversation' : conversation.participants.join(', ');

    // Sweeps when a message actually lands, rather than once when the thread is
    // first opened: the id changes on every new message, a bool does not.
    final latestIncoming = messages
        .where((message) => message.messageType == 1)
        .map((message) => message.id)
        .fold<int?>(
          null,
          (highest, id) => highest == null || id > highest ? id : highest,
        );

    return RelayEdgeSweep(
      burstKey: latestIncoming,
      radius: RelayRadius.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thread Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.hairline)),
            ),
            child: Row(
              children: [
                if (!isWide)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => setState(() => _threadId = null),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        participant,
                        style: RelayTypography.title(palette.textPrimary, isGnome: true),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _connected ? 'SMS via ${widget.device.alias}' : 'Phone disconnected',
                        style: RelayTypography.caption(palette.textSecondary, isGnome: true),
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
                      style: RelayTypography.body(palette.textSecondary, isGnome: true),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final showDate = index == 0 || !_isSameDay(messages[index - 1].date, msg.date);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDate) _buildDateSeparator(palette, msg.date),
                          _buildMessageBubble(palette, msg),
                        ],
                      );
                    },
                  ),
          ),

          // Composer Box
          _buildComposer(palette, conversation),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(RelayPalette palette, int timestamp) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: palette.softSurface,
            borderRadius: BorderRadius.circular(RelayRadius.pill),
          ),
          child: Text(
            _formatDateHeader(timestamp),
            style: RelayTypography.caption(palette.textTertiary, isGnome: true),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(RelayPalette palette, RsKdeSmsMessage message) {
    final isOutgoing = message.messageType == 2;
    final isPending = message.id < 0;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isOutgoing ? palette.accent.withValues(alpha: isPending ? 0.12 : 0.20) : palette.softSurface,
          borderRadius: BorderRadius.circular(RelayRadius.panel),
          border: Border.all(
            color: isOutgoing ? palette.accent.withValues(alpha: isPending ? 0.2 : 0.35) : palette.hairline,
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body.isEmpty && message.attachments.isNotEmpty ? 'Attachment' : message.body,
              style: RelayTypography.body(palette.textPrimary, isGnome: true),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.date),
                  style: RelayTypography.caption(palette.textTertiary, isGnome: true),
                ),
                if (isPending) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: palette.accent,
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

  Widget _buildComposer(RelayPalette palette, RsKdeSmsConversation conversation) {
    final hasDraft = _composerController.text.trim().isNotEmpty;
    final canSendNow = _canSend && hasDraft;
    final focused = _composerFocus.hasFocus;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        relayComposerHorizontalPadding,
        relayComposerVerticalPadding,
        relayComposerHorizontalPadding,
        relayComposerVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: palette.canvasTonalHigh,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _sendSms(conversation),
        },
        child: Row(
          // Bottom-aligned so a growing message pushes the field upwards and
          // leaves Send sitting on the same line it started on.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                key: const ValueKey('kde-composer-field'),
                constraints: const BoxConstraints(minHeight: relayComposerFieldMinHeight),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.elevated,
                    borderRadius: BorderRadius.circular(relayComposerFieldRadius),
                    // Focus is a warm border and nothing more: no glow, no ring.
                    border: Border.all(color: focused ? palette.accent.withValues(alpha: 0.55) : palette.hairline),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: TextField(
                    controller: _composerController,
                    focusNode: _composerFocus,
                    // Grows to four lines, then scrolls inside itself rather
                    // than pushing the conversation off the top of the pane.
                    maxLines: 4,
                    minLines: 1,
                    style: RelayTypography.body(palette.textPrimary, isGnome: true),
                    decoration: InputDecoration(
                      hintText: _sendBlockedReason ?? 'Message',
                      hintStyle: RelayTypography.body(palette.textTertiary, isGnome: true),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
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

class _RelaySendButtonState extends State<_RelaySendButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.96).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 50),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled || widget.onPressed == null) return;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0.0);
    }
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).relayPalette;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: SizedBox(
        key: const ValueKey('kde-composer-send'),
        height: widget.height,
        width: widget.width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.enabled ? Colors.transparent : palette.softSurface,
            borderRadius: BorderRadius.circular(RelayRadius.button),
          ),
          child: AdwButton(
            label: 'Send',
            style: AdwButtonStyle.suggested,
            padding: EdgeInsets.zero,
            onPressed: widget.enabled ? _handleTap : null,
          ),
        ),
      ),
    );
  }
}
