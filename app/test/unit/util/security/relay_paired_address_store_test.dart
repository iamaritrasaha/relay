import 'package:localsend_app/model/persistence/relay_paired_address.dart';
import 'package:localsend_app/util/security/relay_paired_address_store.dart';
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
