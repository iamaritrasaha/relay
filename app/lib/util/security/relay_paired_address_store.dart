import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/provider/persistence_provider.dart';

/// The persistence boundary for non-secret paired Relay routing metadata.
abstract interface class RelayPairedAddressPersistence {
  List<RelayPairedAddress> getRelayPairedAddresses();

  Future<void> setRelayPairedAddresses(List<RelayPairedAddress> addresses);
}

class PersistenceRelayPairedAddressPersistence implements RelayPairedAddressPersistence {
  final PersistenceService _persistence;

  PersistenceRelayPairedAddressPersistence(this._persistence);

  @override
  List<RelayPairedAddress> getRelayPairedAddresses() => _persistence.getRelayPairedAddresses();

  @override
  Future<void> setRelayPairedAddresses(List<RelayPairedAddress> addresses) => _persistence.setRelayPairedAddresses(addresses);
}

/// Stores route updates only after the caller's authenticated session has
/// established [authenticatedRelayId]. This store does not create trust; a
/// route claim alone is rejected even if it is well formed.
class RelayPairedAddressStore {
  final RelayPairedAddressPersistence _persistence;

  RelayPairedAddressStore(this._persistence);

  List<RelayPairedAddress> load() => _persistence.getRelayPairedAddresses();

  Future<bool> refreshAfterAuthenticatedSession({
    required String authenticatedRelayId,
    required String claimedRelayId,
    required String relayAddress,
    String? displayLabel,
    DateTime? now,
  }) async {
    if (authenticatedRelayId != claimedRelayId) {
      return false;
    }
    final record = RelayPairedAddress(
      relayId: authenticatedRelayId,
      displayLabel: displayLabel,
      relayAddress: relayAddress,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    if (RelayPairedAddress.tryParse(record.toJson()) == null) {
      return false;
    }

    final next = [...load()];
    final existingIndex = next.indexWhere((entry) => entry.relayId == authenticatedRelayId);
    if (existingIndex < 0) {
      next.add(record);
    } else {
      next[existingIndex] = record;
    }
    await _persistence.setRelayPairedAddresses(next);
    return true;
  }
}
