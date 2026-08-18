import 'dart:typed_data';

import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_routing_key_coordinator.dart';
import 'package:localsend_app/util/security/relay_routing_key_secret_store.dart';
import 'package:test/test.dart';

void main() {
  RelayRoutingKeyCoordinator coordinator({
    _FakeStore? store,
    _FakeRoutingKeyApi? api,
  }) => RelayRoutingKeyCoordinator(
    secureStore: store ?? _FakeStore(),
    routingKeyApi: api ?? _FakeRoutingKeyApi(),
  );

  group('RelayRoutingKeyCoordinator', () {
    test('fresh installation generates and securely stores an opaque routing key', () async {
      final store = _FakeStore();
      final api = _FakeRoutingKeyApi(generated: Uint8List.fromList([1, 2, 3]));
      Uint8List? observed;

      final result = await coordinator(store: store, api: api).withRoutingKey((routingKey) async {
        observed = Uint8List.fromList(routingKey);
        return 'bound';
      });

      expect(result, isA<RelayRoutingKeyAccessed<String>>());
      expect((result as RelayRoutingKeyAccessed<String>).value, 'bound');
      expect(api.generateCalls, 1);
      expect(store.saveCalls, 1);
      expect(store.secret, orderedEquals([1, 2, 3]));
      expect(observed, orderedEquals([1, 2, 3]));
    });

    test('restart reloads the same routing key without generating a replacement', () async {
      final store = _FakeStore(secret: Uint8List.fromList([7, 8, 9]));
      final api = _FakeRoutingKeyApi(generated: Uint8List.fromList([1, 2, 3]));
      Uint8List? observed;

      await coordinator(store: store, api: api).withRoutingKey((routingKey) async {
        observed = Uint8List.fromList(routingKey);
        return null;
      });

      expect(observed, orderedEquals([7, 8, 9]));
      expect(api.generateCalls, 0);
      expect(store.saveCalls, 0);
    });

    test('corrupt routing secret is replaced without changing any Relay identity state', () async {
      final store = _FakeStore(loadOverride: const RelaySecretCorrupt());
      final api = _FakeRoutingKeyApi(generated: Uint8List.fromList([4, 5, 6]));

      await coordinator(store: store, api: api).withRoutingKey((_) async => null);

      expect(api.generateCalls, 1);
      expect(store.secret, orderedEquals([4, 5, 6]));
      expect(store.deleteCalls, 0);
    });

    test('invalid key bytes are replaced before an endpoint can use them', () async {
      final store = _FakeStore(secret: Uint8List.fromList([0]));
      final api = _FakeRoutingKeyApi(
        generated: Uint8List.fromList([9, 9, 9]),
        invalid: {
          ListEquality<int>().hash([0]),
        },
      );
      Uint8List? observed;

      await coordinator(store: store, api: api).withRoutingKey((routingKey) async {
        observed = Uint8List.fromList(routingKey);
        return null;
      });

      expect(observed, orderedEquals([9, 9, 9]));
      expect(store.secret, orderedEquals([9, 9, 9]));
    });

    test('store unavailability leaves remote capability off', () async {
      var called = false;
      final result =
          await coordinator(
            store: _FakeStore(loadOverride: const RelaySecretNotAvailable()),
          ).withRoutingKey((_) async {
            called = true;
          });

      expect(result, isA<RelayRoutingKeyUnavailable>());
      expect(called, isFalse);
    });

    test('operation buffer is wiped after the endpoint operation returns', () async {
      Uint8List? passedToOperation;
      final result = await coordinator().withRoutingKey((routingKey) async {
        passedToOperation = routingKey;
        return null;
      });

      expect(result, isA<RelayRoutingKeyAccessed<void>>());
      expect(passedToOperation, everyElement(0));
    });
  });
}

class _FakeStore implements RelayRoutingKeySecretStore {
  Uint8List? secret;
  RelaySecretLoadResult? loadOverride;
  RelaySecretStoreResult saveResult;
  int saveCalls = 0;
  int deleteCalls = 0;

  _FakeStore({
    Uint8List? secret,
    this.loadOverride,
  }) : saveResult = const RelaySecretStoreSuccess(),
       secret = secret == null ? null : Uint8List.fromList(secret);

  @override
  Future<RelaySecretLoadResult> load() async =>
      loadOverride ?? (secret == null ? const RelaySecretNotFound() : RelaySecretFound(Uint8List.fromList(secret!)));

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
    secret = null;
    return const RelaySecretStoreSuccess();
  }
}

class _FakeRoutingKeyApi implements RelayRoutingKeyApi {
  final Uint8List generated;
  final Set<int> invalid;
  int generateCalls = 0;

  _FakeRoutingKeyApi({
    Uint8List? generated,
    this.invalid = const {},
  }) : generated = generated ?? Uint8List.fromList([1, 2, 3]);

  @override
  Uint8List generate() {
    generateCalls++;
    return Uint8List.fromList(generated);
  }

  @override
  void validate(Uint8List routingKey) {
    if (invalid.contains(ListEquality<int>().hash(routingKey))) {
      throw StateError('invalid routing key');
    }
  }
}

class ListEquality<T> {
  const ListEquality();

  int hash(Iterable<T> values) => Object.hashAll(values);
}
