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

    test('a record claiming an Anywhere route it does not have is rejected', () {
      expect(
        RelayPairedAddress.tryParse({
          'version': RelayPairedAddress.currentVersion,
          'relayId': relayId,
          'displayLabel': null,
          'relayAddress': null,
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
