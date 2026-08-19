import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:test/test.dart';

void main() {
  const relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const otherRelayId = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

  group('RelayPairedAddressStore', () {
    test('authenticated route refresh stores only non-secret routing metadata', () async {
      final persistence = _FakePersistence();
      final saved = await RelayPairedAddressStore(persistence).refreshAfterAuthenticatedSession(
        authenticatedRelayId: relayId,
        claimedRelayId: relayId,
        relayAddress: 'RELAY1.routing-metadata',
        displayLabel: 'Office laptop',
        now: DateTime.utc(2026, 8, 18),
      );

      expect(saved, isTrue);
      expect(persistence.entries, hasLength(1));
      expect(persistence.entries.single.relayId, relayId);
      expect(persistence.entries.single.displayLabel, 'Office laptop');
      expect(persistence.entries.single.relayAddress, 'RELAY1.routing-metadata');
    });

    test('address claim with another RelayId cannot refresh metadata', () async {
      final persistence = _FakePersistence();

      final saved = await RelayPairedAddressStore(persistence).refreshAfterAuthenticatedSession(
        authenticatedRelayId: relayId,
        claimedRelayId: otherRelayId,
        relayAddress: 'RELAY1.untrusted-claim',
      );

      expect(saved, isFalse);
      expect(persistence.entries, isEmpty);
    });

    test('EndpointId rotation replaces a route without changing Relay identity', () async {
      final persistence = _FakePersistence()
        ..entries = [
          RelayPairedAddress(
            relayId: relayId,
            displayLabel: 'Office laptop',
            relayAddress: 'RELAY1.old-route',
            pairedAt: DateTime.utc(2026, 8, 17),
            updatedAt: DateTime.utc(2026, 8, 17),
          ),
        ];

      await RelayPairedAddressStore(persistence).refreshAfterAuthenticatedSession(
        authenticatedRelayId: relayId,
        claimedRelayId: relayId,
        relayAddress: 'RELAY1.new-route',
        now: DateTime.utc(2026, 8, 18),
      );

      expect(persistence.entries, hasLength(1));
      expect(persistence.entries.single.relayId, relayId);
      expect(persistence.entries.single.relayAddress, 'RELAY1.new-route');
      // Re-authenticating an existing device refreshes the route, not the
      // relationship: the pairing date is the original one.
      expect(persistence.entries.single.pairedAt, DateTime.utc(2026, 8, 17));
    });

    test('a LAN pairing is stored only when the remote user approved', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);

      final rejected = await store.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: false,
        now: DateTime.utc(2026, 8, 18),
      );

      expect(rejected, isFalse);
      expect(persistence.entries, isEmpty);
      expect(store.isPaired(relayId), isFalse);
    });

    test('a LAN pairing stores an identity and no route to point anywhere', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);

      final saved = await store.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        displayLabel: 'Redmi',
        now: DateTime.utc(2026, 8, 18),
      );

      expect(saved, isTrue);
      expect(persistence.entries.single.relayId, relayId);
      expect(persistence.entries.single.relayAddress, isNull);
      expect(persistence.entries.single.origin, RelayPairedAddress.originLan);
      expect(store.isPaired(relayId), isTrue);
    });

    test('a fresh LAN pairing invents no Anywhere route', () async {
      final persistence = _FakePersistence();

      await RelayPairedAddressStore(persistence).recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        now: DateTime.utc(2026, 8, 18),
      );

      expect(persistence.entries.single.relayAddress, isNull);
      expect(persistence.entries.single.hasAnywhereRoute, isFalse);
    });

    test('re-pairing over the LAN keeps an existing Anywhere route', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);
      await store.refreshAfterAuthenticatedSession(
        authenticatedRelayId: relayId,
        claimedRelayId: relayId,
        relayAddress: 'RELAY1.remote-route',
        displayLabel: 'Office laptop',
        now: DateTime.utc(2026, 8, 17),
      );

      await store.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        now: DateTime.utc(2026, 8, 18),
      );

      // Proving the device on this network says nothing about whether its
      // remote route still works, so the fallback survives.
      expect(persistence.entries, hasLength(1));
      expect(persistence.entries.single.relayAddress, 'RELAY1.remote-route');
      expect(persistence.entries.single.displayLabel, 'Office laptop');
    });

    test('re-pairing over the LAN keeps the original pairing date', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);
      await store.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        now: DateTime.utc(2026, 8, 17),
      );

      await store.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        now: DateTime.utc(2026, 8, 18),
      );

      expect(persistence.entries.single.pairedAt, DateTime.utc(2026, 8, 17));
      expect(persistence.entries.single.updatedAt, DateTime.utc(2026, 8, 18));
    });

    test('an authenticated Anywhere session enriches an existing LAN pairing', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);
      await store.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        displayLabel: 'Redmi',
        now: DateTime.utc(2026, 8, 17),
      );

      final saved = await store.refreshAfterAuthenticatedSession(
        authenticatedRelayId: relayId,
        claimedRelayId: relayId,
        relayAddress: 'RELAY1.remote-route',
        now: DateTime.utc(2026, 8, 18),
      );

      expect(saved, isTrue);
      expect(persistence.entries, hasLength(1));
      final entry = persistence.entries.single;
      expect(entry.relayAddress, 'RELAY1.remote-route');
      // The same relationship gained a route; it did not restart, and where it
      // began is provenance that does not move.
      expect(entry.pairedAt, DateTime.utc(2026, 8, 17));
      expect(entry.origin, RelayPairedAddress.originLan);
      expect(entry.displayLabel, 'Redmi');
    });

    test('a stored LAN pairing with no Anywhere route still loads', () {
      final parsed = RelayPairedAddress.tryParse({
        'version': RelayPairedAddress.currentVersion,
        'relayId': relayId,
        'displayLabel': 'Redmi',
        'relayAddress': null,
        'pairedAt': '2026-08-17T00:00:00Z',
        'updatedAt': '2026-08-18T00:00:00Z',
        'origin': RelayPairedAddress.originLan,
      });

      expect(parsed, isNotNull);
      expect(parsed!.hasAnywhereRoute, isFalse);
      expect(parsed.pairedAt, DateTime.utc(2026, 8, 17));
    });

    test('forgetting one device leaves every other pairing untouched', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);
      await store.recordLanPairing(authenticatedRelayId: relayId, remoteApproved: true);
      await store.recordLanPairing(authenticatedRelayId: otherRelayId, remoteApproved: true);

      final removed = await store.forget(relayId);

      expect(removed, isTrue);
      expect(store.isPaired(relayId), isFalse);
      expect(store.isPaired(otherRelayId), isTrue);
      expect(persistence.entries.single.relayId, otherRelayId);
    });

    test('forgetting a device that is not paired changes nothing', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);
      await store.recordLanPairing(authenticatedRelayId: otherRelayId, remoteApproved: true);

      expect(await store.forget(relayId), isFalse);
      expect(persistence.entries.single.relayId, otherRelayId);
    });

    test('a forgotten device has to be paired again from nothing', () async {
      final persistence = _FakePersistence();
      final store = RelayPairedAddressStore(persistence);
      await store.recordLanPairing(authenticatedRelayId: relayId, remoteApproved: true);
      await store.forget(relayId);

      // Re-arriving without a fresh approval restores nothing: the only thing
      // that can bring the relationship back is another accepted handshake.
      expect(await store.recordLanPairing(authenticatedRelayId: relayId, remoteApproved: false), isFalse);
      expect(store.isPaired(relayId), isFalse);

      expect(await store.recordLanPairing(authenticatedRelayId: relayId, remoteApproved: true), isTrue);
      expect(store.isPaired(relayId), isTrue);
    });

    test('version 1 records keep their route and gain a pairing date', () {
      final parsed = RelayPairedAddress.tryParse({
        'version': 1,
        'relayId': relayId,
        'displayLabel': 'Office laptop',
        'relayAddress': 'RELAY1.route',
        'updatedAt': '2026-08-18T00:00:00Z',
      });

      expect(parsed, isNotNull);
      expect(parsed!.relayAddress, 'RELAY1.route');
      expect(parsed.pairedAt, DateTime.utc(2026, 8, 18));
      expect(parsed.origin, RelayPairedAddress.originAnywhere);
    });

    test('a record whose Anywhere route is malformed is rejected', () {
      expect(
        RelayPairedAddress.tryParse({
          'version': RelayPairedAddress.currentVersion,
          'relayId': relayId,
          'displayLabel': null,
          'relayAddress': 'http://192.168.1.24',
          'pairedAt': '2026-08-18T00:00:00Z',
          'updatedAt': '2026-08-18T00:00:00Z',
          'origin': RelayPairedAddress.originAnywhere,
        }),
        isNull,
      );
    });

    test('malformed records are not accepted from normal metadata storage', () {
      expect(
        RelayPairedAddress.tryParse({
          'version': 1,
          'relayId': 'not-an-id',
          'relayAddress': 'RELAY1.route',
          'updatedAt': '2026-08-18T00:00:00Z',
        }),
        isNull,
      );
    });
  });
}

class _FakePersistence implements RelayPairedAddressPersistence {
  List<RelayPairedAddress> entries = [];

  @override
  List<RelayPairedAddress> getRelayPairedAddresses() => List.of(entries);

  @override
  Future<void> setRelayPairedAddresses(List<RelayPairedAddress> addresses) async {
    entries = List.of(addresses);
  }
}
