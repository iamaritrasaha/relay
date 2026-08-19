import 'dart:typed_data';

import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:relay_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;

abstract interface class RelayAnywherePairingApi {
  rust_relay_anywhere.RsRelayAddress parseAddress(String address);

  BigInt openSession();

  Stream<rust_relay_anywhere.RsRelayAnywhereEvent> authenticateAddress({
    required BigInt sessionId,
    required Uint8List privateKeyPem,
    required String relayId,
    required String address,
  });
}

class RustRelayAnywherePairingApi implements RelayAnywherePairingApi {
  @override
  rust_relay_anywhere.RsRelayAddress parseAddress(String address) => rust_relay_anywhere.relayAnywhereParseAddress(address: address);

  @override
  BigInt openSession() => rust_relay_anywhere.relayAnywhereOpenSession();

  @override
  Stream<rust_relay_anywhere.RsRelayAnywhereEvent> authenticateAddress({
    required BigInt sessionId,
    required Uint8List privateKeyPem,
    required String relayId,
    required String address,
  }) => rust_relay_anywhere.relayAnywhereAuthenticateAddress(
    sessionId: sessionId,
    privateKeyPem: privateKeyPem,
    relayId: relayId,
    address: address,
    pathPreference: rust_relay_anywhere.RsRelayPathPreference.auto,
  );
}

sealed class RelayPairingResult {
  const RelayPairingResult();
}

final class RelayPairingSucceeded extends RelayPairingResult {
  final String relayId;

  const RelayPairingSucceeded(this.relayId);
}

final class RelayPairingInvalidAddress extends RelayPairingResult {
  const RelayPairingInvalidAddress();
}

/// The address was reachable but did not finish a cryptographically valid
/// proof of its claimed Relay identity. No routing metadata was retained.
final class RelayPairingAuthenticationFailed extends RelayPairingResult {
  const RelayPairingAuthenticationFailed();
}

/// Pairs a Relay address by proving its claimed RelayId before persisting
/// non-secret route metadata. It has no trust side effect.
class RelayAnywherePairingService {
  final RelayIdentityCoordinator _identityCoordinator;
  final RelayPairedAddressStore _pairedAddressStore;
  final RelayAnywherePairingApi _api;
  final Future<void> Function()? _onRouteSaved;

  RelayAnywherePairingService({
    required RelayIdentityCoordinator identityCoordinator,
    required RelayPairedAddressStore pairedAddressStore,
    required RelayAnywherePairingApi api,
    Future<void> Function()? onRouteSaved,
  }) : _identityCoordinator = identityCoordinator,
       _pairedAddressStore = pairedAddressStore,
       _api = api,
       _onRouteSaved = onRouteSaved;

  Future<RelayPairingResult> pair({required String address, String? displayLabel}) async {
    final normalizedAddress = address.trim();
    final String claimedRelayId;
    try {
      final parsed = _api.parseAddress(normalizedAddress);
      if (!parsed.routingAvailable) {
        return const RelayPairingInvalidAddress();
      }
      claimedRelayId = parsed.claimedRelayId;
    } catch (_) {
      return const RelayPairingInvalidAddress();
    }

    final provenRelayId = await _identityCoordinator.withPrivateKey(
      (privateKey, identity) => _authenticate(
        privateKey: privateKey,
        localRelayId: identity.relayId,
        address: normalizedAddress,
        claimedRelayId: claimedRelayId,
      ),
    );
    if (provenRelayId == null || provenRelayId != claimedRelayId) {
      return const RelayPairingAuthenticationFailed();
    }

    final normalizedLabel = displayLabel?.trim();
    final saved = await _pairedAddressStore.refreshAfterAuthenticatedSession(
      authenticatedRelayId: provenRelayId,
      claimedRelayId: claimedRelayId,
      relayAddress: normalizedAddress,
      displayLabel: normalizedLabel == null || normalizedLabel.isEmpty ? null : normalizedLabel,
    );
    if (saved) {
      // Persistence alone is not observable by the product state graph. Publish
      // this proof-backed route before reporting pairing success so every
      // consumer resolves the same RelayId-keyed device immediately.
      await _onRouteSaved?.call();
    }
    return saved ? RelayPairingSucceeded(provenRelayId) : const RelayPairingAuthenticationFailed();
  }

  Future<String?> _authenticate({
    required Uint8List privateKey,
    required String localRelayId,
    required String address,
    required String claimedRelayId,
  }) async {
    String? provenRelayId;
    bool completed = false;
    try {
      await for (final event in _api.authenticateAddress(
        sessionId: _api.openSession(),
        privateKeyPem: privateKey,
        relayId: localRelayId,
        address: address,
      )) {
        switch (event) {
          case rust_relay_anywhere.RsRelayAnywhereEvent_PeerAuthenticated(:final remoteRelayId):
            if (remoteRelayId != claimedRelayId) {
              return null;
            }
            provenRelayId = remoteRelayId;
          case rust_relay_anywhere.RsRelayAnywhereEvent_Completed(:final remoteRelayId):
            if (remoteRelayId != claimedRelayId) {
              return null;
            }
            completed = true;
          case rust_relay_anywhere.RsRelayAnywhereEvent_Failed() || rust_relay_anywhere.RsRelayAnywhereEvent_Cancelled():
            return null;
          default:
            break;
        }
      }
    } catch (_) {
      return null;
    }
    return completed ? provenRelayId : null;
  }
}
