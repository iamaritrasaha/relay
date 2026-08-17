import 'dart:async';
import 'dart:typed_data';

import 'package:localsend_app/model/persistence/relay_public_identity.dart';
import 'package:localsend_app/util/security/relay_identity_coordinator.dart';
import 'package:localsend_app/util/security/relay_identity_metadata_store.dart';
import 'package:localsend_app/util/security/relay_identity_reset_service.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_server_signer_port.dart';
import 'package:localsend_isolates/rust/api/crypto.dart';
import 'package:test/test.dart';

void main() {
  final identity = _material(secret: [1, 2, 3], relayId: 'derived-id', publicKey: 'derived-spki');

  RelayIdentityCoordinator coordinator({
    _FakeSecretStore? store,
    _FakeIdentityApi? api,
    _FakeMetadataStore? metadata,
    _FakeSignerPort? signer,
  }) => RelayIdentityCoordinator(
    secureStore: store ?? _FakeSecretStore(),
    identityApi: api ?? _FakeIdentityApi(generated: identity),
    metadataStore: metadata ?? _FakeMetadataStore(),
    signerPort: signer ?? _FakeSignerPort(),
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

    test('ready identity installs the loaded secret with its RelayId', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));
      final signer = _FakeSignerPort();
      final subject = coordinator(
        store: store,
        api: _FakeIdentityApi(restored: identity),
        signer: signer,
      );

      await subject.initialize();
      final result = await subject.activateSigner();

      expect(result, isA<RelaySignerActivationInstalled>());
      expect(signer.installedExpectedRelayId, 'derived-id');
      expect(signer.installCalls, 1);
    });

    test('matching installed RelayId activates successfully', () async {
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        api: _FakeIdentityApi(restored: identity),
        signer: _FakeSignerPort(installResult: const RelaySignerInstallInstalled('derived-id')),
      );

      expect(await subject.activateSigner(), isA<RelaySignerActivationInstalled>());
    });

    test('mismatched installed RelayId fails safely and revokes it', () async {
      final signer = _FakeSignerPort(installResult: const RelaySignerInstallInstalled('wrong-id'));
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        api: _FakeIdentityApi(restored: identity),
        signer: signer,
      );

      expect(await subject.activateSigner(), isA<RelaySignerActivationFailed>());
      expect(signer.revokeCalls, 1);
    });

    test('activation wipes the loaded secret after successful install', () async {
      final loaded = Uint8List.fromList([7, 8, 9]);
      final store = _FakeSecretStore(
        secret: Uint8List.fromList([1]),
        loadOverride: RelaySecretFound(loaded),
      );
      final subject = coordinator(
        store: store,
        api: _FakeIdentityApi(restored: identity),
      );

      expect(await subject.activateSigner(), isA<RelaySignerActivationInstalled>());
      expect(loaded, orderedEquals([0, 0, 0]));
    });

    test('activation wipes the loaded secret after failed install', () async {
      final loaded = Uint8List.fromList([7, 8, 9]);
      final subject = coordinator(
        store: _FakeSecretStore(
          secret: Uint8List.fromList([1]),
          loadOverride: RelaySecretFound(loaded),
        ),
        api: _FakeIdentityApi(restored: identity),
        signer: _FakeSignerPort(installResult: const RelaySignerInstallFailed()),
      );

      expect(await subject.activateSigner(), isA<RelaySignerActivationFailed>());
      expect(loaded, orderedEquals([0, 0, 0]));
    });

    test('activation wipes the loaded secret after a thrown install', () async {
      final loaded = Uint8List.fromList([7, 8, 9]);
      final subject = coordinator(
        store: _FakeSecretStore(
          secret: Uint8List.fromList([1]),
          loadOverride: RelaySecretFound(loaded),
        ),
        api: _FakeIdentityApi(restored: identity),
        signer: _FakeSignerPort(installError: StateError('server control path failed')),
      );

      expect(await subject.activateSigner(), isA<RelaySignerActivationFailed>());
      expect(loaded, orderedEquals([0, 0, 0]));
    });

    test('a thrown install after readiness returns a narrow activation failure', () async {
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        api: _FakeIdentityApi(restored: identity),
        signer: _FakeSignerPort(installError: StateError('server control path failed')),
      );

      await subject.initialize();
      expect(await subject.activateSigner(), isA<RelaySignerActivationFailed>());
    });

    for (final load in <RelaySecretLoadResult>[
      const RelaySecretLocked(),
      const RelaySecretNotAvailable(),
      const RelaySecretPermissionDenied(),
      const RelaySecretCorrupt(),
      const RelaySecretFailed(),
    ]) {
      test('activation with $load does not install or generate a fallback identity', () async {
        final api = _FakeIdentityApi(generated: identity);
        final signer = _FakeSignerPort();

        final result = await coordinator(
          store: _FakeSecretStore(loadOverride: load),
          api: api,
          signer: signer,
        ).activateSigner();

        expect(result, isA<RelaySignerActivationSecretUnavailable>());
        expect(signer.installCalls, 0);
        expect(api.generateCalls, 0);
      });
    }

    test('activation initializes once and installs without a second secure load', () async {
      final store = _FakeSecretStore();
      final api = _FakeIdentityApi(generated: identity);
      final signer = _FakeSignerPort();

      expect(await coordinator(store: store, api: api, signer: signer).activateSigner(), isA<RelaySignerActivationInstalled>());
      expect(api.generateCalls, 1);
      expect(store.loadCalls, 1);
      expect(signer.installCalls, 1);
    });

    test('reset revokes before deleting the secure secret', () async {
      final events = <String>[];
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]), events: events);
      final signer = _FakeSignerPort(
        revokeResult: const RelaySignerRevokeRevoked(),
        events: events,
      );

      expect(await coordinator(store: store, signer: signer).resetIdentity(), isA<RelayIdentityResetSuccess>());
      expect(events, orderedEquals(['revoke', 'delete']));
    });

    test('server-not-running revoke permits reset deletion', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));

      expect(await coordinator(store: store).resetIdentity(), isA<RelayIdentityResetSuccess>());
      expect(store.deleteCalls, 1);
    });

    test('unreachable revoke never deletes the secure secret', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));

      expect(
        await coordinator(
          store: store,
          signer: _FakeSignerPort(revokeResult: const RelaySignerRevokeUnreachable()),
        ).resetIdentity(),
        isA<RelayIdentityResetSignerActive>(),
      );
      expect(store.deleteCalls, 0);
    });

    test('thrown revoke never deletes the secure secret', () async {
      final store = _FakeSecretStore(secret: Uint8List.fromList([1]));

      expect(
        await coordinator(
          store: store,
          signer: _FakeSignerPort(revokeError: StateError('control path failed')),
        ).resetIdentity(),
        isA<RelayIdentityResetSignerActive>(),
      );
      expect(store.deleteCalls, 0);
    });

    test('reset waits for activation install before revoking and deleting', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final signer = _FakeSignerPort(
        events: events,
        installGate: gate,
        revokeResult: const RelaySignerRevokeRevoked(),
      );
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1]), events: events),
        api: _FakeIdentityApi(restored: identity),
        signer: signer,
      );

      final activation = subject.activateSigner();
      await signer.installStarted.future;
      final reset = subject.resetIdentity();
      gate.complete();

      expect(await activation, isA<RelaySignerActivationInstalled>());
      expect(await reset, isA<RelayIdentityResetSuccess>());
      expect(events, orderedEquals(['load', 'install', 'revoke', 'delete']));
    });

    test('failed revoke leaves ready identity and public metadata intact', () async {
      final metadata = _FakeMetadataStore();
      final signer = _FakeSignerPort(revokeResult: const RelaySignerRevokeUnreachable());
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        api: _FakeIdentityApi(restored: identity),
        metadata: metadata,
        signer: signer,
      );

      await subject.initialize();
      expect(await subject.resetIdentity(), isA<RelayIdentityResetSignerActive>());
      expect(await subject.initialize(), isA<RelayIdentityReady>());
      expect(metadata.value, const RelayPublicIdentity(relayId: 'derived-id', publicKey: 'derived-spki'));
    });

    test('reset service stops once and retries once after an unconfirmed revoke', () async {
      final signer = _FakeSignerPort(revokeResult: const RelaySignerRevokeUnreachable());
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        signer: signer,
      );
      var stopCalls = 0;
      final reset = RelayIdentityResetService(
        coordinator: subject,
        stopServer: () async {
          stopCalls++;
          signer.revokeResult = const RelaySignerRevokeServerNotRunning();
        },
      );

      expect(await reset.reset(), isA<RelayIdentityResetSuccess>());
      expect(stopCalls, 1);
      expect(signer.revokeCalls, 2);
    });

    test('reset service does not loop when the post-stop revoke remains unreachable', () async {
      final signer = _FakeSignerPort(revokeResult: const RelaySignerRevokeUnreachable());
      final subject = coordinator(
        store: _FakeSecretStore(secret: Uint8List.fromList([1])),
        signer: signer,
      );
      var stopCalls = 0;
      final reset = RelayIdentityResetService(
        coordinator: subject,
        stopServer: () async {
          stopCalls++;
        },
      );

      expect(await reset.reset(), isA<RelayIdentityResetSignerActive>());
      expect(stopCalls, 1);
      expect(signer.revokeCalls, 2);
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
  final List<String>? events;
  int loadCalls = 0;
  int saveCalls = 0;
  int deleteCalls = 0;

  _FakeSecretStore({
    this.secret,
    this.loadOverride,
    this.saveResult = const RelaySecretStoreSuccess(),
    this.deleteResult = const RelaySecretStoreSuccess(),
    this.events,
  });

  @override
  Future<RelaySecretLoadResult> load() async {
    loadCalls++;
    events?.add('load');
    return loadOverride ?? (secret == null ? const RelaySecretNotFound() : RelaySecretFound(Uint8List.fromList(secret!)));
  }

  @override
  Future<RelaySecretStoreResult> save(Uint8List value) async {
    saveCalls++;
    if (saveResult is RelaySecretStoreSuccess) {
      secret = Uint8List.fromList(value);
    }
    return saveResult;
  }

  @override
  Future<RelaySecretStoreResult> delete() async {
    deleteCalls++;
    events?.add('delete');
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

class _FakeSignerPort implements RelayServerSignerPort {
  RelaySignerInstallOutcome installResult;
  RelaySignerRevokeOutcome revokeResult;
  Object? installError;
  Object? revokeError;
  Uint8List? installedPrivateKey;
  String? installedExpectedRelayId;
  int installCalls = 0;
  int revokeCalls = 0;
  final List<String>? events;
  Completer<void>? installGate;
  Completer<void> installStarted = Completer<void>();

  _FakeSignerPort({
    this.installResult = const RelaySignerInstallInstalled('derived-id'),
    this.revokeResult = const RelaySignerRevokeServerNotRunning(),
    this.installError,
    this.revokeError,
    this.events,
    this.installGate,
  });

  @override
  Future<RelaySignerInstallOutcome> install(Uint8List privateKey, String expectedRelayId) async {
    installCalls++;
    installedPrivateKey = privateKey;
    installedExpectedRelayId = expectedRelayId;
    events?.add('install');
    if (!installStarted.isCompleted) {
      installStarted.complete();
    }
    await installGate?.future;
    if (installError != null) {
      throw installError!;
    }
    return installResult;
  }

  @override
  Future<RelaySignerRevokeOutcome> revoke() async {
    revokeCalls++;
    events?.add('revoke');
    if (revokeError != null) {
      throw revokeError!;
    }
    return revokeResult;
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
