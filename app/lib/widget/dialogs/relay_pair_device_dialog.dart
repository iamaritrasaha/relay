import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/pages/relay_qr_scanner_page.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/provider/relay_anywhere_listener_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/security/relay_anywhere_listener_service.dart';
import 'package:relay_app/util/security/relay_anywhere_pairing_service.dart';
import 'package:relay_app/widget/relay/relay_pairing_qr.dart';

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
      // A newly published authenticated route may complete an already-enabled
      // continuity target. The event stream updates its connected bit.
      unawaited(ref.redux(continuityProvider).dispatchAsync(ContinuityConnectEnabledDevicesAction()));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _pairing = false;
      _error = result is RelayPairingInvalidAddress ? 'That Relay address is not valid.' : 'Could not verify this Relay device. Nothing was paired.';
    });
  }

  Future<void> _scan() async {
    final address = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RelayQrScannerPage(
          title: 'Scan Relay QR',
          instruction: 'Scan a Relay device address. It will still be authenticated before it is saved.',
          validate: (raw) => raw.startsWith('RELAY1.') ? null : 'This is not a Relay device QR.',
        ),
      ),
    );
    if (!mounted || address == null) {
      return;
    }
    _addressController.text = address;
    await _pair();
  }

  Future<void> _showOwnAddress() async {
    final result = await ref.read(relayAnywhereListenerServiceProvider).startIfEnabled(enabled: true, alias: ref.read(settingsProvider).alias);
    if (!mounted) {
      return;
    }
    if (result case RelayAnywhereListenerStarted(:final address)) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Your Relay QR'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RelayPairingQr(address: address),
              const SizedBox(height: 16),
              const Text('Scan this on another Relay device. It contains a public routing address, not a private key.'),
              const SizedBox(height: 12),
              SelectableText(address),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not prepare your Relay address.')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Relay device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste a Relay address to verify and pair a device. Once it is paired you choose what it can access — pairing on its own shares nothing beyond files.',
          ),
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
        TextButton(onPressed: _pairing ? null : _showOwnAddress, child: const Text('My QR')),
        TextButton(onPressed: _pairing ? null : _scan, child: const Text('Scan QR')),
        TextButton(onPressed: _pairing ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _pairing ? null : _pair, child: Text(_pairing ? 'Verifying…' : 'Pair')),
      ],
    );
  }
}
