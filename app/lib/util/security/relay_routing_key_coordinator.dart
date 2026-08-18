import 'dart:typed_data';

import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_routing_key_secret_store.dart';
import 'package:localsend_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;

/// Minimal Rust boundary for opaque Anywhere routing-key material.
abstract interface class RelayRoutingKeyApi {
  Uint8List generate();

  void validate(Uint8List routingKey);
}

class RustRelayRoutingKeyApi implements RelayRoutingKeyApi {
  @override
  Uint8List generate() => rust_relay_anywhere.relayAnywhereGenerateRoutingKey();

  @override
  void validate(Uint8List routingKey) => rust_relay_anywhere.relayAnywhereValidateRoutingKey(routingKey: routingKey);
}

sealed class RelayRoutingKeyAccessResult {
  const RelayRoutingKeyAccessResult();
}

final class RelayRoutingKeyAccessed<T> extends RelayRoutingKeyAccessResult {
  final T value;

  const RelayRoutingKeyAccessed(this.value);
}

/// The secure platform store is unavailable, locked, or declined the write.
/// Remote capability must remain off in these states.
final class RelayRoutingKeyUnavailable extends RelayRoutingKeyAccessResult {
  const RelayRoutingKeyUnavailable();
}

/// Loads a stable Anywhere routing key only for the duration of an operation.
///
/// Missing or unreadable key material is replaced with a fresh secret key.
/// The Relay identity is never read, derived, or altered by this coordinator.
class RelayRoutingKeyCoordinator {
  final RelayRoutingKeySecretStore _secureStore;
  final RelayRoutingKeyApi _routingKeyApi;

  RelayRoutingKeyCoordinator({
    required RelayRoutingKeySecretStore secureStore,
    required RelayRoutingKeyApi routingKeyApi,
  }) : _secureStore = secureStore,
       _routingKeyApi = routingKeyApi;

  /// Invokes [operation] with validated private key bytes and wipes the Dart
  /// buffer immediately afterwards. The operation must not retain the bytes.
  Future<RelayRoutingKeyAccessResult> withRoutingKey<T>(Future<T> Function(Uint8List routingKey) operation) async {
    final routingKey = await _loadOrReplace();
    if (routingKey == null) {
      return const RelayRoutingKeyUnavailable();
    }
    try {
      return RelayRoutingKeyAccessed(await operation(routingKey));
    } finally {
      routingKey.fillRange(0, routingKey.length, 0);
    }
  }

  Future<Uint8List?> _loadOrReplace() async {
    final loaded = await _load();
    switch (loaded) {
      case RelaySecretFound(:final secret):
        try {
          _routingKeyApi.validate(secret);
          return secret;
        } catch (_) {
          secret.fillRange(0, secret.length, 0);
          return _createAndStore();
        }
      case RelaySecretNotFound() || RelaySecretCorrupt():
        return _createAndStore();
      case RelaySecretLocked() || RelaySecretNotAvailable() || RelaySecretPermissionDenied() || RelaySecretFailed():
        return null;
    }
  }

  Future<RelaySecretLoadResult> _load() async {
    try {
      return await _secureStore.load();
    } catch (_) {
      return const RelaySecretFailed();
    }
  }

  Future<Uint8List?> _createAndStore() async {
    Uint8List? routingKey;
    try {
      routingKey = _routingKeyApi.generate();
      _routingKeyApi.validate(routingKey);
      final result = await _secureStore.save(routingKey);
      if (result is RelaySecretStoreSuccess) {
        return routingKey;
      }
    } catch (_) {
      // The unavailable result below keeps remote capability disabled.
    }
    routingKey?.fillRange(0, routingKey.length, 0);
    return null;
  }
}
