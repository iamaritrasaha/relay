import 'dart:typed_data';

import 'package:localsend_app/model/persistence/relay_public_identity.dart';
import 'package:localsend_app/util/security/relay_identity_coordinator.dart';
import 'package:localsend_app/util/security/relay_identity_metadata_store.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:localsend_isolates/rust/api/crypto.dart';
import 'package:test/test.dart';

void main() {
  final identity = _material(secret: [1, 2, 3], relayId: 'derived-id', publicKey: 'derived-spki');

  RelayIdentityCoordinator coordinator({
    _FakeSecretStore? store,
    _FakeIdentityApi? api,
    _FakeMetadataStore? metadata,
  }) => RelayIdentityCoordinator(
    secureStore: store ?? _FakeSecretStore(),
    identityApi: api ?? _FakeIdentityApi(generated: identity),
    metadataStore: metadata ?? _FakeMetadataStore(),
  );

  group('RelayIdentityCoordinator', () {
    test('found valid secret becomes ready with Rust-derived public identity', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));
      final api = _FakeIdentityApi(restored: identity);

      final result = await coordinator(store: store, api: api).initialize();

      expect(result, isA<RelayIdentityReady>());
      expect((result as RelayIdentityReady).identity, const RelayPublicIdentity(relayId: 'derived-id', publicKey: 'derived-spki'));
      expect(api.generateCalls, 0);
    });

    test('found secret repairs stale public metadata from the restored identity', () async {
      final metadata = _FakeMetadataStore(
        value: const RelayPublicIdentity(relayId: 'stale', publicKey: 'wrong'),
      );

      final result = await coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        api: _FakeIdentityApi(restored: identity),
        metadata: metadata,
      ).initialize();

      expect(result, isA<RelayIdentityReady>());
      expect(metadata.value, const RelayPublicIdentity(relayId: 'derived-id', publicKey: 'derived-spki'));
      expect(metadata.saveCalls, 1);
    });

    test('public metadata write failure does not invalidate a secure identity', () async {
      final result = await coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        api: _FakeIdentityApi(restored: identity),
        metadata: _FailingMetadataStore(),
      ).initialize();

      expect(result, isA<RelayIdentityReady>());
    });

    test('found secret rejected by Rust is corrupt without deletion or generation', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));
      final api = _FakeIdentityApi(restoreError: StateError('invalid'));

      expect(await coordinator(store: store, api: api).initialize(), isA<RelayIdentityCorrupt>());
      expect(store.deleteCalls, 0);
      expect(api.generateCalls, 0);
    });

    test('not found generates, saves, and becomes ready', () async {
      final store = _FakeSecretStore();
      final api = _FakeIdentityApi(generated: identity);

      expect(await coordinator(store: store, api: api).initialize(), isA<RelayIdentityReady>());
      expect(api.generateCalls, 1);
      expect(store.saveCalls, 1);
      expect(store.secret, orderedEquals([1, 2, 3]));
    });

    test('not found and locked save does not expose generated identity', () async {
      final api = _FakeIdentityApi(generated: identity);

      expect(
        await coordinator(
          store: _FakeSecretStore(saveResult: const RelaySecretStoreLocked()),
          api: api,
        ).initialize(),
        isA<RelayIdentityLocked>(),
      );
      expect(api.generateCalls, 1);
    });

    test('not found and unavailable save is not available', () async {
      expect(
        await coordinator(
          store: _FakeSecretStore(saveResult: const RelaySecretStoreNotAvailable()),
          api: _FakeIdentityApi(generated: identity),
        ).initialize(),
        isA<RelayIdentityNotAvailable>(),
      );
    });

    test('locked load is retryable and can later become ready', () async {
      final store = _FakeSecretStore(loadOverride: const RelaySecretLocked());
      final subject = coordinator(
        store: store,
        api: _FakeIdentityApi(restored: identity),
      );

      expect(await subject.initialize(), isA<RelayIdentityLocked>());
      store.loadOverride = null;
      store.secret = Uint8List.fromList([1]);
      expect(await subject.initialize(), isA<RelayIdentityReady>());
    });

    test('unavailable load is retryable and can later become ready', () async {
      final store = _FakeSecretStore(loadOverride: const RelaySecretNotAvailable());
      final subject = coordinator(
        store: store,
        api: _FakeIdentityApi(restored: identity),
      );

      expect(await subject.initialize(), isA<RelayIdentityNotAvailable>());
      store.loadOverride = null;
      store.secret = Uint8List.fromList([1]);
      expect(await subject.initialize(), isA<RelayIdentityReady>());
    });

    test('permission denied load stays permission denied', () async {
      expect(
        await coordinator(store: _FakeSecretStore(loadOverride: const RelaySecretPermissionDenied())).initialize(),
        isA<RelayIdentityPermissionDenied>(),
      );
    });

    test('failed load stays failed', () async {
      expect(await coordinator(store: _FakeSecretStore(loadOverride: const RelaySecretFailed())).initialize(), isA<RelayIdentityFailed>());
    });

    test('corrupt load does not generate', () async {
      final api = _FakeIdentityApi(generated: identity);

      expect(
        await coordinator(
          store: _FakeSecretStore(loadOverride: const RelaySecretCorrupt()),
          api: api,
        ).initialize(),
        isA<RelayIdentityCorrupt>(),
      );
      expect(api.generateCalls, 0);
    });

    test('concurrent not-found initialization generates and saves exactly once', () async {
      final store = _FakeSecretStore();
      final api = _FakeIdentityApi(generated: identity);
      final subject = coordinator(store: store, api: api);

      final results = await Future.wait([subject.initialize(), subject.initialize()]);

      expect(results, everyElement(isA<RelayIdentityReady>()));
      expect(api.generateCalls, 1);
      expect(store.saveCalls, 1);
    });

    test('ready initialization is memoized without another secure load', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));
      final subject = coordinator(
        store: store,
        api: _FakeIdentityApi(restored: identity),
      );

      await subject.initialize();
      await subject.initialize();

      expect(store.loadCalls, 1);
    });

    test('successful reset deletes the secret then clears public metadata', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));
      final metadata = _FakeMetadataStore(
        value: const RelayPublicIdentity(relayId: 'id', publicKey: 'key'),
      );
      final subject = coordinator(store: store, metadata: metadata);

      expect(await subject.resetIdentity(), isA<RelayIdentityResetSuccess>());
      expect(store.deleteCalls, 1);
      expect(metadata.clearCalls, 1);
      expect(metadata.value, isNull);
    });

    test('failed reset deletion leaves public metadata intact', () async {
      final metadata = _FakeMetadataStore(
        value: const RelayPublicIdentity(relayId: 'id', publicKey: 'key'),
      );
      final result = await coordinator(
        store: _FakeSecretStore(deleteResult: const RelaySecretStoreFailed()),
        metadata: metadata,
      ).resetIdentity();

      expect(result, isA<RelayIdentityResetFailed>());
      expect(metadata.clearCalls, 0);
      expect(metadata.value, isNotNull);
    });

    test('after a successful reset, the next initialize may generate a new identity', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([9]));
      final api = _FakeIdentityApi(
        restored: identity,
        generated: _material(secret: [4], relayId: 'new-id', publicKey: 'new-spki'),
      );
      final subject = coordinator(store: store, api: api);

      await subject.initialize();
      expect(await subject.resetIdentity(), isA<RelayIdentityResetSuccess>());
      expect(await subject.initialize(), isA<RelayIdentityReady>());
      expect(api.generateCalls, 1);
    });

    test('coordinator states and errors do not reveal private bytes', () async {
      final secret = Uint8List.fromList('private relay key'.codeUnits);
      final result = await coordinator(
        store: _FakeSecretStore(secret: secret),
        api: _FakeIdentityApi(restoreError: StateError('invalid')),
      ).initialize();

      expect(result.toString(), isNot(contains('private relay key')));
    });
  });
}

RelayIdentityMaterial _material({required List<int> secret, required String relayId, required String publicKey}) =>
    RelayIdentityMaterial(privateKey: Uint8List.fromList(secret), relayId: relayId, publicKey: publicKey);

class _FakeSecretStore implements RelayIdentitySecretStore {
  Uint8List? secret;
  RelaySecretLoadResult? loadOverride;
  RelaySecretStoreResult saveResult;
  RelaySecretStoreResult deleteResult;
  int loadCalls = 0;
  int saveCalls = 0;
  int deleteCalls = 0;

  _FakeSecretStore({
    this.secret,
    this.loadOverride,
    this.saveResult = const RelaySecretStoreSuccess(),
    this.deleteResult = const RelaySecretStoreSuccess(),
  });

  @override
  Future<RelaySecretLoadResult> load() async {
    loadCalls++;
    return loadOverride ?? (secret == null ? const RelaySecretNotFound() : RelaySecretFound(secret!));
  }

  @override
  Future<RelaySecretStoreResult> save(Uint8List value) async {
    saveCalls++;
    if (saveResult is RelaySecretStoreSuccess) {
      secret = value;
    }
    return saveResult;
  }

  @override
  Future<RelaySecretStoreResult> delete() async {
    deleteCalls++;
    if (deleteResult is RelaySecretStoreSuccess) {
      secret = null;
    }
    return deleteResult;
  }
}

class _FakeIdentityApi implements RelayIdentityApi {
  final RelayIdentityMaterial? generated;
  final RelayIdentityMaterial? restored;
  final Object? restoreError;
  int generateCalls = 0;

  _FakeIdentityApi({this.generated, this.restored, this.restoreError});

  @override
  Future<RelayIdentityMaterial> generate() async {
    generateCalls++;
    return generated!;
  }

  @override
  Future<RelayIdentityMaterial> restore(Uint8List privateKey) async {
    if (restoreError != null) {
      throw restoreError!;
    }
    return restored!;
  }
}

class _FakeMetadataStore implements RelayIdentityMetadataStore {
  RelayPublicIdentity? value;
  int saveCalls = 0;
  int clearCalls = 0;

  _FakeMetadataStore({this.value});

  @override
  Future<void> clear() async {
    clearCalls++;
    value = null;
  }

  @override
  Future<RelayPublicIdentity?> load() async => value;

  @override
  Future<void> save(RelayPublicIdentity identity) async {
    saveCalls++;
    value = identity;
  }
}

class _FailingMetadataStore extends _FakeMetadataStore {
  @override
  Future<void> save(RelayPublicIdentity identity) async => throw StateError('metadata unavailable');
}
