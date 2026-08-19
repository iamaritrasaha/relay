import 'dart:typed_data';

import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/persistence/relay_public_identity.dart';
import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_app/util/security/relay_identity_metadata_store.dart';
import 'package:relay_app/util/security/relay_identity_secret_store.dart';
import 'package:relay_app/util/security/relay_lan_pairing_service.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:relay_app/util/security/relay_server_signer_port.dart';
import 'package:relay_isolates/rust/api/crypto.dart';
import 'package:relay_isolates/rust/api/http.dart' as rust_http;
import 'package:relay_isolates/rust/api/model.dart' as rust_model;
import 'package:test/test.dart';

const _localRelayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _provenRelayId = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

void main() {
  ({RelayLanPairingService service, _FakePersistence persistence, _FakePairingApi api}) harness(
    List<rust_http.RsRelayLanPairingEvent> events, {
    Future<void> Function()? onPairingSaved,
  }) {
    final persistence = _FakePersistence();
    final api = _FakePairingApi(events);
    return (
      service: RelayLanPairingService(
        identityCoordinator: _coordinator(),
        pairedAddressStore: RelayPairedAddressStore(persistence),
        api: api,
        onPairingSaved: onPairingSaved,
      ),
      persistence: persistence,
      api: api,
    );
  }

  Future<RelayLanPairingResult> pair(
    RelayLanPairingService service, {
    bool https = true,
    String? expectedRelayId,
    void Function(String code)? onVerificationCode,
  }) => service.pair(
    ip: '192.168.1.24',
    port: 53317,
    https: https,
    certificateFingerprint: 'CERTFINGERPRINT',
    clientPrivateKey: 'client-key',
    clientCertificate: 'client-cert',
    alias: 'My computer',
    displayLabel: 'Redmi',
    expectedRelayId: expectedRelayId,
    onVerificationCode: onVerificationCode,
  );

  group('mutual approval', () {
    test('a mutual proof accepted by the remote user stores the proven identity', () async {
      final it = harness([
        const rust_http.RsRelayLanPairingEvent.verificationCode(code: '482731', remoteRelayId: _provenRelayId),
        const rust_http.RsRelayLanPairingEvent.paired(
          remoteRelayId: _provenRelayId,
          remoteAlias: 'Redmi',
          verificationCode: '482731',
        ),
      ]);

      final result = await pair(it.service);

      expect(result, isA<RelayLanPaired>());
      expect((result as RelayLanPaired).relayId, _provenRelayId);
      expect(it.persistence.entries, hasLength(1));
      // The stored key is the identity the proof produced, not the alias, the
      // IP, or the certificate fingerprint the socket was selected with.
      expect(it.persistence.entries.single.relayId, _provenRelayId);
      expect(it.persistence.entries.single.origin, RelayPairedAddress.originLan);
      // A LAN pairing leaves no address behind to point anywhere.
      expect(it.persistence.entries.single.relayAddress, isNull);
    });

    test('the verification code is published while the remote user is still deciding', () async {
      final codes = <String>[];
      final it = harness([
        const rust_http.RsRelayLanPairingEvent.verificationCode(code: '482731', remoteRelayId: _provenRelayId),
        const rust_http.RsRelayLanPairingEvent.paired(
          remoteRelayId: _provenRelayId,
          remoteAlias: 'Redmi',
          verificationCode: '482731',
        ),
      ]);

      await pair(it.service, onVerificationCode: codes.add);

      expect(codes, ['482731']);
    });

    test('the route is published only after the pairing is stored', () async {
      var publishedWith = -1;
      final it = harness(
        [
          const rust_http.RsRelayLanPairingEvent.paired(
            remoteRelayId: _provenRelayId,
            remoteAlias: 'Redmi',
            verificationCode: '482731',
          ),
        ],
      );
      final persistence = it.persistence;
      final service = RelayLanPairingService(
        identityCoordinator: _coordinator(),
        pairedAddressStore: RelayPairedAddressStore(persistence),
        api: it.api,
        onPairingSaved: () async => publishedWith = persistence.entries.length,
      );

      await pair(service);

      expect(publishedWith, 1);
    });
  });

  group('nothing is stored without both halves', () {
    test('a proof the remote user declined leaves no relationship', () async {
      final it = harness([
        const rust_http.RsRelayLanPairingEvent.verificationCode(code: '482731', remoteRelayId: _provenRelayId),
        const rust_http.RsRelayLanPairingEvent.declined(),
      ]);

      final result = await pair(it.service);

      expect(result, isA<RelayLanPairingRejected>());
      expect(it.persistence.entries, isEmpty);
    });

    test('a failed identity proof leaves no relationship', () async {
      final it = harness([const rust_http.RsRelayLanPairingEvent.authenticationFailed()]);

      final result = await pair(it.service);

      expect(result, isA<RelayLanPairingFailed>());
      expect(it.persistence.entries, isEmpty);
    });

    test('an interrupted exchange leaves no relationship', () async {
      final it = harness([const rust_http.RsRelayLanPairingEvent.transportFailed()]);

      expect(await pair(it.service), isA<RelayLanPairingFailed>());
      expect(it.persistence.entries, isEmpty);
    });

    test('a peer already answering someone else leaves no relationship', () async {
      final it = harness([const rust_http.RsRelayLanPairingEvent.busy()]);

      expect(await pair(it.service), isA<RelayLanPairingBusy>());
      expect(it.persistence.entries, isEmpty);
    });

    test('a stream that ends without any outcome is a failure, never a pairing', () async {
      final it = harness(const []);

      expect(await pair(it.service), isA<RelayLanPairingFailed>());
      expect(it.persistence.entries, isEmpty);
    });
  });

  group('the handshake is never bypassed', () {
    test('a peer reachable without TLS cannot pair at all', () async {
      final it = harness([
        const rust_http.RsRelayLanPairingEvent.paired(
          remoteRelayId: _provenRelayId,
          remoteAlias: 'Redmi',
          verificationCode: '482731',
        ),
      ]);

      final result = await pair(it.service, https: false);

      expect(result, isA<RelayLanPairingUnsupported>());
      // The handshake was never even attempted: there is no certificate for the
      // proofs to bind to.
      expect(it.api.calls, isEmpty);
      expect(it.persistence.entries, isEmpty);
    });

    test('the demanded identity is forwarded so a substituted peer fails in Rust', () async {
      final it = harness([const rust_http.RsRelayLanPairingEvent.authenticationFailed()]);

      await pair(it.service, expectedRelayId: _provenRelayId);

      expect(it.api.calls.single.expectedRelayId, _provenRelayId);
      // The socket details are passed as addressing, separately from identity.
      expect(it.api.calls.single.ip, '192.168.1.24');
      expect(it.api.calls.single.certificateFingerprint, 'CERTFINGERPRINT');
    });

    test('discovery metadata never becomes the stored identity', () async {
      final it = harness([
        const rust_http.RsRelayLanPairingEvent.paired(
          // The peer's own alias disagrees with the label discovery showed, and
          // neither has any bearing on which identity is recorded.
          remoteRelayId: _provenRelayId,
          remoteAlias: 'Some other name',
          verificationCode: '482731',
        ),
      ]);

      await pair(it.service);

      expect(it.persistence.entries.single.relayId, _provenRelayId);
      expect(it.persistence.entries.single.relayId, isNot(_localRelayId));
    });
  });
}

RelayIdentityCoordinator _coordinator() {
  final material = RelayIdentityMaterial(
    privateKey: Uint8List.fromList([1, 2, 3]),
    relayId: _localRelayId,
    publicKey: 'test-public-key',
  );
  return RelayIdentityCoordinator(
    secureStore: _FakeSecretStore(),
    identityApi: _FakeIdentityApi(material),
    metadataStore: _FakeMetadataStore(),
    signerPort: _FakeSignerPort(),
  );
}

class _PairCall {
  final String ip;
  final int port;
  final String certificateFingerprint;
  final String? expectedRelayId;

  _PairCall({
    required this.ip,
    required this.port,
    required this.certificateFingerprint,
    required this.expectedRelayId,
  });
}

class _FakePairingApi implements RelayLanPairingApi {
  final List<rust_http.RsRelayLanPairingEvent> events;
  final List<_PairCall> calls = [];

  _FakePairingApi(this.events);

  @override
  Stream<rust_http.RsRelayLanPairingEvent> pair({
    required Uint8List privateKeyPem,
    required String relayId,
    required String clientPrivateKey,
    required String clientCertificate,
    required rust_model.ProtocolType protocol,
    required String ip,
    required int port,
    required String certificateFingerprint,
    required String alias,
    String? expectedRelayId,
  }) {
    calls.add(
      _PairCall(
        ip: ip,
        port: port,
        certificateFingerprint: certificateFingerprint,
        expectedRelayId: expectedRelayId,
      ),
    );
    return Stream.fromIterable(events);
  }
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
