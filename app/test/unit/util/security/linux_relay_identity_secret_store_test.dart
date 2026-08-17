import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/security/linux_relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';

const _channelName = 'org.localsend.localsend_app/relay_identity_secret';
const _channel = MethodChannel(_channelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LinuxRelayIdentitySecretStore store;

  setUp(() {
    store = LinuxRelayIdentitySecretStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  test('load found returns exact copied bytes', () async {
    _respond({
      'state': 'found',
      'secret': Uint8List.fromList([1, 2, 3]),
    });

    final loaded = await store.load();

    expect(loaded, isA<RelaySecretFound>());
    expect((loaded as RelaySecretFound).secret, orderedEquals([1, 2, 3]));
  });

  test('load maps each non-secret state', () async {
    final expected = <String, Type>{
      'notFound': RelaySecretNotFound,
      'locked': RelaySecretLocked,
      'notAvailable': RelaySecretNotAvailable,
      'permissionDenied': RelaySecretPermissionDenied,
      'corrupt': RelaySecretCorrupt,
      'failed': RelaySecretFailed,
    };

    for (final entry in expected.entries) {
      _respond({'state': entry.key});
      expect((await store.load()).runtimeType, entry.value);
    }
  });

  test('save maps success and failures without exposing secret bytes', () async {
    final secret = Uint8List.fromList('private relay key'.codeUnits);
    final expected = <String, Type>{
      'success': RelaySecretStoreSuccess,
      'locked': RelaySecretStoreLocked,
      'notAvailable': RelaySecretStoreNotAvailable,
      'permissionDenied': RelaySecretStorePermissionDenied,
      'failed': RelaySecretStoreFailed,
    };

    for (final entry in expected.entries) {
      _respond({'state': entry.key});
      final result = await store.save(secret);
      expect(result.runtimeType, entry.value);
      expect(result.toString(), isNot(contains('private relay key')));
    }
  });

  test('delete maps success and failures', () async {
    final expected = <String, Type>{
      'success': RelaySecretStoreSuccess,
      'locked': RelaySecretStoreLocked,
      'notAvailable': RelaySecretStoreNotAvailable,
      'permissionDenied': RelaySecretStorePermissionDenied,
      'failed': RelaySecretStoreFailed,
    };

    for (final entry in expected.entries) {
      _respond({'state': entry.key});
      expect((await store.delete()).runtimeType, entry.value);
    }
  });

  test('malformed native responses fail safely', () async {
    _respond({'state': 'found'});
    expect(await store.load(), isA<RelaySecretFailed>());

    _respond({'state': 'unknown'});
    expect(await store.save(Uint8List.fromList([1])), isA<RelaySecretStoreFailed>());
  });

  test('channel errors are treated as failed rather than thrown', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (_) async {
      throw PlatformException(code: 'unexpected');
    });

    expect(await store.load(), isA<RelaySecretFailed>());
    expect(await store.delete(), isA<RelaySecretStoreFailed>());
  });
}

void _respond(Map<String, Object?> response) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _channel,
    (_) async => response,
  );
}
