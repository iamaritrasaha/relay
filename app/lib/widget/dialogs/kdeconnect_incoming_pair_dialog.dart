import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/kdeconnect_provider.dart';

/// Incoming KDE Connect pairing request. Separate from Relay-native pairing.
class KdeConnectIncomingPairDialog extends StatefulWidget {
  final KdeConnectIncomingRequest request;

  const KdeConnectIncomingPairDialog({super.key, required this.request});

  @override
  State<KdeConnectIncomingPairDialog> createState() => _KdeConnectIncomingPairDialogState();
}

class _KdeConnectIncomingPairDialogState extends State<KdeConnectIncomingPairDialog> with Refena {
  bool _answering = false;

  Future<void> _answer(bool accepted) async {
    setState(() => _answering = true);
    final action = accepted ? KdeConnectAcceptPairAction(widget.request.deviceId) : KdeConnectRejectPairAction(widget.request.deviceId);
    await ref.redux(kdeConnectProvider).dispatchAsync(action);
    if (mounted) {
      Navigator.of(context).pop(accepted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.request.name.trim().isEmpty ? 'A device' : widget.request.name;
    return AlertDialog(
      title: Text('$name wants to pair with Relay'),
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

class KdeConnectIncomingPairHost extends StatefulWidget {
  final Widget child;

  const KdeConnectIncomingPairHost({super.key, required this.child});

  @override
  State<KdeConnectIncomingPairHost> createState() => _KdeConnectIncomingPairHostState();
}

class _KdeConnectIncomingPairHostState extends State<KdeConnectIncomingPairHost> with Refena {
  String? _showingDeviceId;

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(kdeConnectProvider).incoming;
    if (request != null && request.deviceId != _showingDeviceId) {
      _showingDeviceId = request.deviceId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => KdeConnectIncomingPairDialog(request: request),
          ).then((_) {
            if (mounted && _showingDeviceId == request.deviceId) {
              _showingDeviceId = null;
            }
          }),
        );
      });
    }
    return widget.child;
  }
}
