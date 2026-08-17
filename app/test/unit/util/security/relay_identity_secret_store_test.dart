import 'dart:typed_data';

import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:test/test.dart';

void main() {
  group('RelayIdentitySecretStore contract', () {
    test('found carries the exact secret bytes', () {
      final secret = Uint8List.fromList([1, 2, 3]);
      final result = RelaySecretFound(secret);

      expect(result.secret, orderedEquals([1, 2, 3]));
    });

    test('load result states are distinguishable', () {
      expect(const RelaySecretNotFound(), isA<RelaySecretNotFound>());
      expect(const RelaySecretLocked(), isA<RelaySecretLocked>());
      expect(const RelaySecretNotAvailable(), isA<RelaySecretNotAvailable>());
      expect(const RelaySecretPermissionDenied(), isA<RelaySecretPermissionDenied>());
      expect(const RelaySecretCorrupt(), isA<RelaySecretCorrupt>());
      expect(const RelaySecretFailed(), isA<RelaySecretFailed>());
    });

    test('found secrets are redacted from textual representations', () {
      final secret = Uint8List.fromList('private relay key'.codeUnits);
      final result = RelaySecretFound(secret);

      expect(result.toString(), isNot(contains('private relay key')));
      expect(result.toString(), contains('<redacted>'));
    });

    test('fake save then load returns the saved secret', () async {
      final store = _FakeRelayIdentitySecretStore();
      final secret = Uint8List.fromList([1, 2, 3]);

      expect(await store.save(secret), isA<RelaySecretStoreSuccess>());
      final loaded = await store.load();

      expect(loaded, isA<RelaySecretFound>());
      expect((loaded as RelaySecretFound).secret, orderedEquals(secret));
    });

    test('fake delete makes load return not found', () async {
      final store = _FakeRelayIdentitySecretStore(secret: Uint8List.fromList([1]));

      expect(await store.delete(), isA<RelaySecretStoreSuccess>());
      expect(await store.load(), isA<RelaySecretNotFound>());
    });

    test('fake delete is idempotent', () async {
      final store = _FakeRelayIdentitySecretStore();

      expect(await store.delete(), isA<RelaySecretStoreSuccess>());
      expect(await store.delete(), isA<RelaySecretStoreSuccess>());
      expect(await store.load(), isA<RelaySecretNotFound>());
    });

    test('fake simulates backend failures and load states', () async {
      final store = _FakeRelayIdentitySecretStore(
        loadOverride: const RelaySecretLocked(),
        saveResult: const RelaySecretStorePermissionDenied(),
        deleteResult: const RelaySecretStoreFailed(),
      );

      expect(await store.load(), isA<RelaySecretLocked>());
      expect(await store.save(Uint8List.fromList([1])), isA<RelaySecretStorePermissionDenied>());
      expect(await store.delete(), isA<RelaySecretStoreFailed>());
    });
  });
}

class _FakeRelayIdentitySecretStore implements RelayIdentitySecretStore {
  Uint8List? _secret;
  RelaySecretLoadResult? loadOverride;
  RelaySecretStoreResult saveResult;
  RelaySecretStoreResult deleteResult;

  _FakeRelayIdentitySecretStore({
    Uint8List? secret,
    this.loadOverride,
    this.saveResult = const RelaySecretStoreSuccess(),
    this.deleteResult = const RelaySecretStoreSuccess(),
  }) : _secret = secret == null ? null : Uint8List.fromList(secret);

  @override
  Future<RelaySecretLoadResult> load() async =>
      loadOverride ?? (_secret == null ? const RelaySecretNotFound() : RelaySecretFound(Uint8List.fromList(_secret!)));

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) async {
    if (saveResult is RelaySecretStoreSuccess) {
      _secret = Uint8List.fromList(secret);
    }
    return saveResult;
  }

  @override
  Future<RelaySecretStoreResult> delete() async {
    if (deleteResult is RelaySecretStoreSuccess) {
      _secret = null;
    }
    return deleteResult;
  }
}
