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

/// Stores pairings only after the caller's authenticated session has
/// established [authenticatedRelayId]. This store does not create trust and
/// does not grant capabilities; a route claim alone is rejected even if it is
/// well formed.
class RelayPairedAddressStore {
  final RelayPairedAddressPersistence _persistence;

  RelayPairedAddressStore(this._persistence);

  List<RelayPairedAddress> load() => _persistence.getRelayPairedAddresses();

  RelayPairedAddress? find(String relayId) => load().where((entry) => entry.relayId == relayId).firstOrNull;

  bool isPaired(String relayId) => find(relayId) != null;

  /// Records, or refreshes, the Relay Anywhere address of a proven device.
  ///
  /// Called after an authenticated Anywhere session. If the device is already
  /// paired — including a device first paired over the local network — this
  /// adds the address to that existing relationship rather than starting a new
  /// one: the original pairing date and origin are kept.
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
    return _store(
      relayId: authenticatedRelayId,
      displayLabel: displayLabel,
      relayAddress: relayAddress,
      origin: RelayPairedAddress.originAnywhere,
      now: now,
    );
  }

  /// Records a pairing established over the local network.
  ///
  /// [authenticatedRelayId] is the RelayId the mutual proof exchange produced,
  /// and [remoteApproved] is whether the *other* device's user accepted. Both
  /// are required: a proof without approval, or approval without a proof, must
  /// leave nothing behind.
  ///
  /// No route address is *learned* here: a LAN peer is reached through live
  /// discovery plus a fresh proof every time, so there is nothing an attacker
  /// could point at a different machine. An address the device already has is
  /// left alone — pairing over one transport says nothing about another.
  Future<bool> recordLanPairing({
    required String authenticatedRelayId,
    required bool remoteApproved,
    String? displayLabel,
    DateTime? now,
  }) async {
    if (!remoteApproved) {
      return false;
    }
    return _store(
      relayId: authenticatedRelayId,
      displayLabel: displayLabel,
      relayAddress: null,
      origin: RelayPairedAddress.originLan,
      now: now,
    );
  }

  /// Removes a paired device.
  ///
  /// This only drops the routing record. Revoking trust, clearing capability
  /// grants and disconnecting live sessions are separate steps that the unpair
  /// action performs alongside this one, because they are separate facts.
  Future<bool> forget(String relayId) async {
    final current = load();
    final next = current.where((entry) => entry.relayId != relayId).toList();
    if (next.length == current.length) {
      return false;
    }
    await _persistence.setRelayPairedAddresses(next);
    return true;
  }

  /// Writes the record for one proven identity, merging with what is already
  /// stored for it.
  ///
  /// Every field here is *additive*. Proving a device over one transport is
  /// never evidence that its other route, its label, or its pairing date is
  /// wrong, so an omitted value keeps the stored one instead of erasing it.
  /// Only [forget] removes anything.
  Future<bool> _store({
    required String relayId,
    required String? displayLabel,
    required String? relayAddress,
    required String origin,
    required DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final existing = find(relayId);
    final record = RelayPairedAddress(
      relayId: relayId,
      displayLabel: displayLabel ?? existing?.displayLabel,
      // A LAN re-pairing carries no address; it must not drop the Anywhere
      // route the device already had, which is its fallback when the two are
      // no longer on the same network.
      relayAddress: relayAddress ?? existing?.relayAddress,
      // Re-pairing an already paired device keeps the original date; the
      // relationship was not established twice.
      pairedAt: existing?.pairedAt ?? timestamp,
      updatedAt: timestamp,
      // Where the relationship began never changes once it exists.
      origin: existing?.origin ?? origin,
    );
    if (RelayPairedAddress.tryParse(record.toJson()) == null) {
      return false;
    }

    final next = [...load()];
    final existingIndex = next.indexWhere((entry) => entry.relayId == relayId);
    if (existingIndex < 0) {
      next.add(record);
    } else {
      next[existingIndex] = record;
    }
    await _persistence.setRelayPairedAddresses(next);
    return true;
  }
}
