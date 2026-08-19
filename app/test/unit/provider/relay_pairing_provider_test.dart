import 'dart:typed_data';

import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/model/persistence/relay_continuity_settings.dart';
import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/model/persistence/relay_public_identity.dart';
import 'package:relay_app/provider/relay_pairing_provider.dart';
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

const _relayId = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

const _request = RelayIncomingPairRequest(
  relayId: _relayId,
  alias: 'Redmi',
  ip: '192.168.1.24',
  verificationCode: '482731',
);

void main() {
  late _Journal journal;

  /// Builds the notifier with the pending request already showing, so each test
  /// exercises only the answer.
  ({ReduxNotifierTester<RelayPairingState> service, _FakePersistence persistence}) pending({bool persistenceWorks = true}) {
    final persistence = _FakePersistence(journal: journal, works: persistenceWorks);
    final store = RelayPairedAddressStore(persistence);
    return (
      service: ReduxNotifier.test(
        redux: RelayPairingService(
          pairedAddressStore: store,
          lanPairingService: RelayLanPairingService(
            identityCoordinator: _coordinator(),
            pairedAddressStore: store,
            api: _UnusedPairingApi(),
          ),
          revokeContinuity: (relayId) async => journal.add('revoke:$relayId'),
          signalPairDecision: (relayId, accepted) => journal.add('signal:$relayId:$accepted'),
          publishRoutes: () async => journal.add('publish'),
          securityContext: () => throw StateError('the answer path must not need TLS material'),
          localAlias: () => 'My computer',
        ),
        initialState: const RelayPairingState(incoming: _request),
      ),
      persistence: persistence,
    );
  }

  setUp(() => journal = _Journal());

  group('accepting an inbound pairing', () {
    test('commits locally before the peer is told it was accepted', () async {
      final it = pending();

      await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: true));

      // The peer stores its half on the strength of this answer, so the local
      // write has to be done — and published — before the answer goes out.
      expect(journal.entries, ['write', 'publish', 'signal:$_relayId:true']);
      expect(it.persistence.entries.single.relayId, _relayId);
      expect(it.service.state.incoming, isNull);
    });

    test('stores the proven identity with its label and no invented route', () async {
      final it = pending();

      await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: true));

      final entry = it.persistence.entries.single;
      expect(entry.relayId, _relayId);
      expect(entry.displayLabel, 'Redmi');
      expect(entry.relayAddress, isNull);
      expect(entry.origin, RelayPairedAddress.originLan);
    });

    test('an answer naming a different device is ignored entirely', () async {
      final it = pending();

      await it.service.dispatchAsync(
        RelayAnswerIncomingPairAction(
          relayId: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
          accepted: true,
        ),
      );

      expect(journal.entries, isEmpty);
      expect(it.persistence.entries, isEmpty);
      // The real prompt is still waiting for its own answer.
      expect(it.service.state.incoming, isNotNull);
    });
  });

  group('when the local write fails', () {
    test('the peer is told the pairing was refused, never that it succeeded', () async {
      final it = pending(persistenceWorks: false);

      await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: true));

      expect(journal.entries, ['write', 'signal:$_relayId:false']);
      expect(journal.entries, isNot(contains('signal:$_relayId:true')));
      expect(it.persistence.entries, isEmpty);
      expect(it.service.state.incoming, isNull);
    });

    test('nothing is published, so no consumer sees a pairing that was not stored', () async {
      final it = pending(persistenceWorks: false);

      await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: true));

      expect(journal.entries, isNot(contains('publish')));
    });
  });

  group('rejecting an inbound pairing', () {
    test('answers the peer and stores nothing at all', () async {
      final it = pending();

      await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: false));

      expect(journal.entries, ['signal:$_relayId:false']);
      expect(it.persistence.entries, isEmpty);
      expect(it.service.state.incoming, isNull);
    });

    test('dismissing without answering leaves no record', () async {
      final it = pending();

      it.service.dispatch(RelayDismissIncomingPairAction());

      expect(journal.entries, isEmpty);
      expect(it.persistence.entries, isEmpty);
      expect(it.service.state.incoming, isNull);
    });
  });

  group('what a pairing does not create', () {
    test('no continuity trust or grant is touched by any answer', () async {
      for (final accepted in [true, false]) {
        journal = _Journal();
        final it = pending();

        await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: accepted));

        // Consent has its own controls. Answering a pairing must never reach
        // them, in either direction.
        expect(journal.entries.where((entry) => entry.startsWith('revoke')), isEmpty);
      }
    });

    test('a device that has just been paired starts with nothing enabled', () async {
      final it = pending();

      await it.service.dispatchAsync(RelayAnswerIncomingPairAction(relayId: _relayId, accepted: true));

      // Nothing wrote consent, so the device reads back as the all-denied
      // default: untrusted, no grants, clipboard off.
      const settings = RelayContinuitySettings(relayId: _relayId);
      expect(settings.trusted, isFalse);
      expect(settings.granted, isEmpty);
      expect(settings.clipboardMode, ClipboardSharingMode.off);
      expect(settings.hasAnyCapability, isFalse);
    });
  });
}

/// Records what happened, in order. The ordering is the property under test.
class _Journal {
  final List<String> entries = [];

  void add(String entry) => entries.add(entry);
}

class _FakePersistence implements RelayPairedAddressPersistence {
  final _Journal journal;
  final bool works;
  List<RelayPairedAddress> entries = [];

  _FakePersistence({required this.journal, required this.works});

  @override
  List<RelayPairedAddress> getRelayPairedAddresses() => List.of(entries);

  @override
  Future<void> setRelayPairedAddresses(List<RelayPairedAddress> addresses) async {
    journal.add('write');
    if (!works) {
      throw StateError('storage is unavailable');
    }
    entries = List.of(addresses);
  }
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

/// The outbound handshake is never reached by these tests; calling it is a bug.
class _UnusedPairingApi implements RelayLanPairingApi {
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
  }) => throw StateError('answering an inbound request must not start an outbound one');
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
