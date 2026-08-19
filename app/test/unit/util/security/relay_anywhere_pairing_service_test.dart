import 'dart:typed_data';

import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/persistence/relay_public_identity.dart';
import 'package:relay_app/util/security/relay_anywhere_pairing_service.dart';
import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_app/util/security/relay_identity_metadata_store.dart';
import 'package:relay_app/util/security/relay_identity_secret_store.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:relay_app/util/security/relay_server_signer_port.dart';
import 'package:relay_isolates/rust/api/crypto.dart';
import 'package:relay_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;
import 'package:test/test.dart';

const _relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _address = 'RELAY1.test-address';

void main() {
  RelayAnywherePairingService service({
    required _FakePairingApi api,
    required _FakePersistence persistence,
  }) => RelayAnywherePairingService(
    identityCoordinator: _coordinator(),
    pairedAddressStore: RelayPairedAddressStore(persistence),
    api: api,
  );

  test('persists an address only after its claimed RelayId is proven', () async {
    final persistence = _FakePersistence();
    final api = _FakePairingApi(
      events: [
        rust_relay_anywhere.RsRelayAnywhereEvent.peerAuthenticated(remoteRelayId: _relayId),
        rust_relay_anywhere.RsRelayAnywhereEvent.completed(
          path: 'direct',
          bytes: BigInt.zero,
          localRelayId: _relayId,
          remoteRelayId: _relayId,
          durationMs: BigInt.zero,
        ),
      ],
    );

    final result = await service(api: api, persistence: persistence).pair(address: _address, displayLabel: 'Office laptop');

    expect(result, isA<RelayPairingSucceeded>());
    expect(persistence.entries, hasLength(1));
    expect(persistence.entries.single.relayId, _relayId);
    expect(persistence.entries.single.relayAddress, _address);
    expect(persistence.entries.single.displayLabel, 'Office laptop');
  });

  test('publishes the authenticated route after persistence succeeds', () async {
    final persistence = _FakePersistence();
    var published = false;
    final api = _FakePairingApi(
      events: [
        rust_relay_anywhere.RsRelayAnywhereEvent.peerAuthenticated(remoteRelayId: _relayId),
        rust_relay_anywhere.RsRelayAnywhereEvent.completed(
          path: 'direct',
          bytes: BigInt.zero,
          localRelayId: _relayId,
          remoteRelayId: _relayId,
          durationMs: BigInt.zero,
        ),
      ],
    );
    final pairing = RelayAnywherePairingService(
      identityCoordinator: _coordinator(),
      pairedAddressStore: RelayPairedAddressStore(persistence),
      api: api,
      onRouteSaved: () async => published = true,
    );

    await pairing.pair(address: _address);

    expect(persistence.entries, hasLength(1));
    expect(published, isTrue);
  });

  test('authentication failure leaves the paired-address store untouched', () async {
    final persistence = _FakePersistence();
    final api = _FakePairingApi(
      events: [
        rust_relay_anywhere.RsRelayAnywhereEvent.failed(
          message: 'proof rejected',
          category: 'proof',
        ),
      ],
    );

    final result = await service(api: api, persistence: persistence).pair(address: _address);

    expect(result, isA<RelayPairingAuthenticationFailed>());
    expect(persistence.entries, isEmpty);
  });
}

RelayIdentityCoordinator _coordinator() {
  final material = RelayIdentityMaterial(
    privateKey: Uint8List.fromList([1, 2, 3]),
    relayId: _relayId,
    publicKey: 'test-public-key',
  );
  return RelayIdentityCoordinator(
    secureStore: _FakeSecretStore(),
    identityApi: _FakeIdentityApi(material),
    metadataStore: _FakeMetadataStore(),
    signerPort: _FakeSignerPort(),
  );
}

class _FakePairingApi implements RelayAnywherePairingApi {
  final List<rust_relay_anywhere.RsRelayAnywhereEvent> events;

  _FakePairingApi({required this.events});

  @override
  Stream<rust_relay_anywhere.RsRelayAnywhereEvent> authenticateAddress({
    required BigInt sessionId,
    required Uint8List privateKeyPem,
    required String relayId,
    required String address,
  }) => Stream.fromIterable(events);

  @override
  BigInt openSession() => BigInt.one;

  @override
  rust_relay_anywhere.RsRelayAddress parseAddress(String address) => const rust_relay_anywhere.RsRelayAddress(
    version: 1,
    claimedRelayId: _relayId,
    routingAvailable: true,
  );
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

class _FakeSecretStore implements RelayIdentitySecretStore {
  @override
  Future<RelaySecretLoadResult> load() async => RelaySecretFound(Uint8List.fromList([1, 2, 3]));

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) async => const RelaySecretStoreSuccess();

  @override
  Future<RelaySecretStoreResult> delete() async => const RelaySecretStoreSuccess();
}

class _FakeIdentityApi implements RelayIdentityApi {
  final RelayIdentityMaterial _material;

  _FakeIdentityApi(this._material);

  @override
  Future<RelayIdentityMaterial> generate() async => _material;

  @override
  Future<RelayIdentityMaterial> restore(Uint8List privateKey) async => _material;
}

class _FakeMetadataStore implements RelayIdentityMetadataStore {
  @override
  Future<void> clear() async {}

  @override
  Future<RelayPublicIdentity?> load() async => null;

  @override
  Future<void> save(RelayPublicIdentity identity) async {}
}

class _FakeSignerPort implements RelayServerSignerPort {
  @override
  Future<RelaySignerInstallOutcome> install(Uint8List privateKey, String expectedRelayId) async => RelaySignerInstallInstalled(expectedRelayId);

  @override
  Future<RelaySignerRevokeOutcome> revoke() async => const RelaySignerRevokeServerNotRunning();
}
