import 'dart:typed_data';

import 'package:relay_app/util/native/channel/android_channel.dart';
import 'package:relay_app/util/security/relay_identity_secret_store.dart';
import 'package:relay_app/util/security/relay_routing_key_secret_store.dart';

/// Android routing-key store backed by the app-owned Keystore channel.
class AndroidRelayRoutingKeySecretStore implements RelayRoutingKeySecretStore {
  @override
  Future<RelaySecretLoadResult> load() async {
    final response = await _invoke('relayRoutingKeySecretLoad');
    return switch (response['state']) {
      'found' => _found(response),
      'notFound' => const RelaySecretNotFound(),
      'locked' => const RelaySecretLocked(),
      'notAvailable' => const RelaySecretNotAvailable(),
      'permissionDenied' => const RelaySecretPermissionDenied(),
      'corrupt' => const RelaySecretCorrupt(),
      _ => const RelaySecretFailed(),
    };
  }

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) => _write('relayRoutingKeySecretSave', {'secret': Uint8List.fromList(secret)});

  @override
  Future<RelaySecretStoreResult> delete() => _write('relayRoutingKeySecretDelete', null);

  Future<Map<Object?, Object?>> _invoke(String method, [Object? arguments]) async {
    try {
      return await invokeAndroidMethod<Map<Object?, Object?>>(method, arguments) ?? const {};
    } catch (_) {
      return const {'state': 'failed'};
    }
  }

  RelaySecretLoadResult _found(Map<Object?, Object?> response) {
    final secret = response['secret'];
    return secret is Uint8List ? RelaySecretFound(Uint8List.fromList(secret)) : const RelaySecretFailed();
  }

  Future<RelaySecretStoreResult> _write(String method, Object? arguments) async {
    final response = await _invoke(method, arguments);
    return switch (response['state']) {
      'success' => const RelaySecretStoreSuccess(),
      'locked' => const RelaySecretStoreLocked(),
      'notAvailable' => const RelaySecretStoreNotAvailable(),
      'permissionDenied' => const RelaySecretStorePermissionDenied(),
      _ => const RelaySecretStoreFailed(),
    };
  }
}
