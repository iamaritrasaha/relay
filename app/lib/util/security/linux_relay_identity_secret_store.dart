import 'package:flutter/services.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';

const _channelName = 'org.localsend.localsend_app/relay_identity_secret';
const _channel = MethodChannel(_channelName);

/// Linux implementation backed by the runner-owned native MethodChannel,
/// which stores the secret in the desktop Secret Service (libsecret).
class LinuxRelayIdentitySecretStore implements RelayIdentitySecretStore {
  @override
  Future<RelaySecretLoadResult> load() async {
    final response = await _invoke('relayIdentitySecretLoad');
    return switch (response['state']) {
      'found' => _found(response),
      'notFound' => const RelaySecretNotFound(),
      'locked' => const RelaySecretLocked(),
      'notAvailable' => const RelaySecretNotAvailable(),
      'permissionDenied' => const RelaySecretPermissionDenied(),
      'corrupt' => const RelaySecretCorrupt(),
      'failed' => const RelaySecretFailed(),
      _ => const RelaySecretFailed(),
    };
  }

  @override
  Future<RelaySecretStoreResult> save(Uint8List secret) => _write('relayIdentitySecretSave', {'secret': Uint8List.fromList(secret)});

  @override
  Future<RelaySecretStoreResult> delete() => _write('relayIdentitySecretDelete', null);

  Future<Map<Object?, Object?>> _invoke(String method, [Object? arguments]) async {
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(method, arguments);
      return response ?? const {};
    } catch (_) {
      return const {'state': 'failed'};
    }
  }

  RelaySecretLoadResult _found(Map<Object?, Object?> response) {
    final secret = response['secret'];
    if (secret is! Uint8List) {
      return const RelaySecretFailed();
    }
    return RelaySecretFound(Uint8List.fromList(secret));
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
