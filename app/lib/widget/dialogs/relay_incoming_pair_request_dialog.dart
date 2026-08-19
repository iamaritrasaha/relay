import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/relay_pairing_provider.dart';

/// Asks this device's user about a pairing another Relay device requested.
///
/// By the time this appears, both devices have already proved their identity to
/// each other. What is left is the part cryptography cannot answer: whether the
/// person here actually wants a relationship with that device.
///
/// Accepting establishes the pairing and nothing more — no capability is
/// enabled by it.
class RelayIncomingPairRequestDialog extends StatefulWidget {
  final RelayIncomingPairRequest request;

  const RelayIncomingPairRequestDialog({super.key, required this.request});

  @override
  State<RelayIncomingPairRequestDialog> createState() => _RelayIncomingPairRequestDialogState();
}

class _RelayIncomingPairRequestDialogState extends State<RelayIncomingPairRequestDialog> with Refena {
  bool _answering = false;

  Future<void> _answer(bool accepted) async {
    setState(() => _answering = true);
    await ref
        .redux(relayPairingProvider)
        .dispatchAsync(
          RelayAnswerIncomingPairAction(relayId: widget.request.relayId, accepted: accepted),
        );
    if (mounted) {
      Navigator.of(context).pop(accepted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.request.alias.isEmpty ? 'A Relay device' : widget.request.alias;

    return AlertDialog(
      title: Text('$name wants to pair'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Check that the other device shows the same code.'),
          const SizedBox(height: 16),
          Center(
            child: SelectableText(
              formatRelayPairingCode(widget.request.verificationCode),
              style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pairing lets you choose what this device can access. Nothing is shared until you turn it on.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _answering ? null : () => unawaited(_answer(false)),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _answering ? null : () => unawaited(_answer(true)),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

/// Shows the pairing prompt whenever one arrives, wherever the user is.
///
/// A request that is never answered is not a pairing: the far side times out as
/// a decline, so dismissing this by leaving is safe.
class RelayIncomingPairRequestHost extends StatefulWidget {
  final Widget child;

  const RelayIncomingPairRequestHost({super.key, required this.child});

  @override
  State<RelayIncomingPairRequestHost> createState() => _RelayIncomingPairRequestHostState();
}

class _RelayIncomingPairRequestHostState extends State<RelayIncomingPairRequestHost> with Refena {
  String? _showingRelayId;

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(relayPairingProvider).incoming;
    if (request != null && request.relayId != _showingRelayId) {
      _showingRelayId = request.relayId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => RelayIncomingPairRequestDialog(request: request),
          ).then((_) {
            if (mounted && _showingRelayId == request.relayId) {
              _showingRelayId = null;
            }
          }),
        );
      });
    }
    return widget.child;
  }
}
