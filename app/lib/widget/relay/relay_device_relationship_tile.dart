import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/ui/relay_device_vm.dart';
import 'package:relay_app/provider/network/nearby_devices_provider.dart';
import 'package:relay_app/provider/relay_paired_routes_provider.dart';
import 'package:relay_app/provider/relay_pairing_provider.dart';
import 'package:relay_app/util/security/relay_lan_pairing_service.dart';
import 'package:relay_isolates/model/device.dart';

/// Pair with, or remove, one device.
///
/// This is the whole relationship lifecycle in one place. It deliberately says
/// nothing about trust or capabilities: those are separate decisions with their
/// own controls, and pairing never makes them for the user.
class RelayDeviceRelationshipTile extends StatefulWidget {
  final RelayDeviceVm device;

  const RelayDeviceRelationshipTile({super.key, required this.device});

  @override
  State<RelayDeviceRelationshipTile> createState() => _RelayDeviceRelationshipTileState();
}

class _RelayDeviceRelationshipTileState extends State<RelayDeviceRelationshipTile> with Refena {
  bool _busy = false;

  /// The live discovery observation for this device, if it is on the network
  /// right now. Pairing needs an address to talk to; it never takes identity
  /// from one.
  Device? _observation() {
    final fingerprint = widget.device.lanFingerprint;
    if (fingerprint == null) {
      return null;
    }
    return ref.read(nearbyDevicesProvider).devices[fingerprint];
  }

  Future<void> _pair() async {
    final observation = _observation();
    if (observation == null) {
      _report('${widget.device.alias} is not on this network right now.');
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .redux(relayPairingProvider)
        .dispatchAsyncTakeResult(
          RelayPairLanDeviceAction.forDevice(observation, expectedRelayId: widget.device.relayId),
        );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _report(switch (result) {
      RelayLanPaired(:final alias) => '$alias is paired. Choose what it can access below.',
      RelayLanPairingRejected() => '${widget.device.alias} declined. Nothing was paired.',
      RelayLanPairingBusy() => '${widget.device.alias} is already answering another pairing request.',
      RelayLanPairingUnsupported() => '${widget.device.alias} cannot pair with Relay.',
      RelayLanPairingFailed() => 'Could not verify ${widget.device.alias}. Nothing was paired.',
    });
  }

  Future<void> _forget(String relayId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.device.alias}?'),
        content: const Text(
          'This device stops sharing anything with it: everything you allowed is turned off and any open connection ends. '
          'Pairing again later needs both devices to agree again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    await ref.redux(relayPairingProvider).dispatchAsync(RelayForgetDeviceAction(relayId: relayId));
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _report('${widget.device.alias} was removed.');
  }

  void _report(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final relayId = widget.device.relayId;
    if (relayId == null) {
      // A Relay-compatible peer has no Relay identity, so there is no
      // relationship to establish. It stays a file-transfer target only.
      return const SizedBox.shrink();
    }

    final paired = ref.watch(relayPairedRoutesProvider).any((route) => route.relayId == relayId);
    if (paired) {
      return ListTile(
        leading: const Icon(Icons.link_off_rounded),
        title: const Text('Remove this device'),
        subtitle: const Text('Ends the pairing and turns off everything it was allowed to access.'),
        enabled: !_busy,
        onTap: _busy ? null : () => unawaited(_forget(relayId)),
      );
    }

    // While the other device is deciding, show the code so the two people can
    // check they are looking at the same pairing.
    final code = ref.watch(relayPairingProvider).outgoing?.verificationCode;

    return ListTile(
      leading: const Icon(Icons.link_rounded),
      title: Text(_busy ? 'Waiting for ${widget.device.alias}…' : 'Pair with this device'),
      subtitle: Text(
        switch ((_busy, code)) {
          (true, final String value) => 'Check that ${widget.device.alias} shows ${formatRelayPairingCode(value)}.',
          (true, _) => 'Checking who ${widget.device.alias} is…',
          _ => 'Both devices have to agree. Pairing on its own shares nothing beyond files.',
        },
      ),
      enabled: !_busy,
      onTap: _busy ? null : () => unawaited(_pair()),
    );
  }
}
