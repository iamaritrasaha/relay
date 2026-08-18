import 'package:flutter/material.dart';
import 'package:localsend_app/provider/relay_anywhere_listener_provider.dart';
import 'package:localsend_app/util/security/relay_anywhere_pairing_service.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Pairs a pasted Relay address only after the remote device proves its
/// claimed identity. The address itself is never treated as trust evidence.
class RelayPairDeviceDialog extends StatefulWidget {
  const RelayPairDeviceDialog({super.key});

  @override
  State<RelayPairDeviceDialog> createState() => _RelayPairDeviceDialogState();
}

class _RelayPairDeviceDialogState extends State<RelayPairDeviceDialog> with Refena {
  final _addressController = TextEditingController();
  bool _pairing = false;
  String? _error;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'Enter a Relay address.');
      return;
    }
    setState(() {
      _pairing = true;
      _error = null;
    });
    final result = await ref.read(relayAnywherePairingServiceProvider).pair(address: address);
    if (!mounted) {
      return;
    }
    if (result is RelayPairingSucceeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _pairing = false;
      _error = result is RelayPairingInvalidAddress ? 'That Relay address is not valid.' : 'Could not verify this Relay device. Nothing was paired.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Relay device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Paste a Relay address to verify and pair a device. Pairing does not change trust settings.'),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            autofocus: true,
            enabled: !_pairing,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Relay address'),
            onSubmitted: (_) => _pair(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _pairing ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _pairing ? null : _pair, child: Text(_pairing ? 'Verifying…' : 'Pair')),
      ],
    );
  }
}
