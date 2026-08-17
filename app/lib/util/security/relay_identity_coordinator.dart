import 'dart:async';
import 'dart:typed_data';

import 'package:localsend_app/model/persistence/relay_public_identity.dart';
import 'package:localsend_app/util/security/relay_identity_metadata_store.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
import 'package:localsend_app/util/security/relay_server_signer_port.dart';
import 'package:localsend_isolates/rust/api/crypto.dart' as rust_crypto;
import 'package:logging/logging.dart';

final _logger = Logger('RelayIdentityCoordinator');

abstract interface class RelayIdentityApi {
  Future<rust_crypto.RelayIdentityMaterial> generate();

  Future<rust_crypto.RelayIdentityMaterial> restore(Uint8List privateKey);
}

class RustRelayIdentityApi implements RelayIdentityApi {
  @override
  Future<rust_crypto.RelayIdentityMaterial> generate() => rust_crypto.generateRelayIdentity();

  @override
  Future<rust_crypto.RelayIdentityMaterial> restore(Uint8List privateKey) => rust_crypto.restoreRelayIdentity(privateKey: privateKey);
}

sealed class RelayIdentityState {
  const RelayIdentityState();
}

final class RelayIdentityReady extends RelayIdentityState {
  final RelayPublicIdentity identity;

  const RelayIdentityReady(this.identity);

  @override
  String toString() => 'RelayIdentityReady($identity)';
}

final class RelayIdentityLocked extends RelayIdentityState {
  const RelayIdentityLocked();
}

final class RelayIdentityNotAvailable extends RelayIdentityState {
  const RelayIdentityNotAvailable();
}

final class RelayIdentityPermissionDenied extends RelayIdentityState {
  const RelayIdentityPermissionDenied();
}

final class RelayIdentityCorrupt extends RelayIdentityState {
  const RelayIdentityCorrupt();
}

final class RelayIdentityFailed extends RelayIdentityState {
  const RelayIdentityFailed();
}

sealed class RelayIdentityResetResult {
  const RelayIdentityResetResult();
}

final class RelayIdentityResetSuccess extends RelayIdentityResetResult {
  const RelayIdentityResetSuccess();
}

final class RelayIdentityResetLocked extends RelayIdentityResetResult {
  const RelayIdentityResetLocked();
}

final class RelayIdentityResetNotAvailable extends RelayIdentityResetResult {
  const RelayIdentityResetNotAvailable();
}

final class RelayIdentityResetPermissionDenied extends RelayIdentityResetResult {
  const RelayIdentityResetPermissionDenied();
}

final class RelayIdentityResetFailed extends RelayIdentityResetResult {
  const RelayIdentityResetFailed();
}

/// The running server signer could not be confirmed as revoked, so the
/// authoritative secure identity was deliberately left untouched.
final class RelayIdentityResetSignerActive extends RelayIdentityResetResult {
  const RelayIdentityResetSignerActive();
}

sealed class RelaySignerActivationResult {
  const RelaySignerActivationResult();
}

final class RelaySignerActivationInstalled extends RelaySignerActivationResult {
  final String relayId;

  const RelaySignerActivationInstalled(this.relayId);
}

final class RelaySignerActivationNotReady extends RelaySignerActivationResult {
  const RelaySignerActivationNotReady();
}

final class RelaySignerActivationSecretUnavailable extends RelaySignerActivationResult {
  const RelaySignerActivationSecretUnavailable();
}

final class RelaySignerActivationServerNotRunning extends RelaySignerActivationResult {
  const RelaySignerActivationServerNotRunning();
}

final class RelaySignerActivationFailed extends RelaySignerActivationResult {
  const RelaySignerActivationFailed();
}

class _RelaySignerInitialization {
  final RelayIdentityState state;
  final RelaySignerActivationResult result;

  const _RelaySignerInitialization({
    required this.state,
    required this.result,
  });
}

/// Coordinates the authoritative private identity in secure storage with a
/// non-secret public metadata cache.
class RelayIdentityCoordinator {
  final RelayIdentitySecretStore _secureStore;
  final RelayIdentityApi _identityApi;
  final RelayIdentityMetadataStore _metadataStore;
  final RelayServerSignerPort _signerPort;

  RelayIdentityReady? _ready;
  Future<RelayIdentityState>? _initializing;
  Future<RelayIdentityResetResult>? _resetting;
  Future<void> _signerOp = Future.value();
  String? _installedRelayId;

  RelayIdentityCoordinator({
    required RelayIdentitySecretStore secureStore,
    required RelayIdentityApi identityApi,
    required RelayIdentityMetadataStore metadataStore,
    required RelayServerSignerPort signerPort,
  }) : _secureStore = secureStore,
       _identityApi = identityApi,
       _metadataStore = metadataStore,
       _signerPort = signerPort;

  Future<RelayIdentityState> initialize() async {
    final reset = _resetting;
    if (reset != null) {
      await reset;
    }

    final ready = _ready;
    if (ready != null) {
      return ready;
    }
    final existing = _initializing;
    if (existing != null) {
      return existing;
    }

    late final Future<RelayIdentityState> operation;
    operation = _initialize();
    _initializing = operation;
    try {
      final result = await operation;
      if (result case RelayIdentityReady()) {
        _ready = result;
      }
      return result;
    } finally {
      if (identical(_initializing, operation)) {
        _initializing = null;
      }
    }
  }

  Future<RelayIdentityState> _initialize() async {
    final load = await _loadSecret();
    return switch (load) {
      RelaySecretFound(:final secret) => _restoreAndWipe(secret),
      RelaySecretNotFound() => _create(),
      RelaySecretLocked() => const RelayIdentityLocked(),
      RelaySecretNotAvailable() => const RelayIdentityNotAvailable(),
      RelaySecretPermissionDenied() => const RelayIdentityPermissionDenied(),
      RelaySecretCorrupt() => const RelayIdentityCorrupt(),
      RelaySecretFailed() => const RelayIdentityFailed(),
    };
  }

  Future<RelayIdentityState> _restoreAndWipe(Uint8List secret) async {
    try {
      return await _restore(secret);
    } finally {
      _wipe(secret);
    }
  }

  Future<RelaySecretLoadResult> _loadSecret() async {
    try {
      return await _secureStore.load();
    } catch (_) {
      return const RelaySecretFailed();
    }
  }

  Future<RelayIdentityState> _restore(Uint8List secret) async {
    try {
      late RelayPublicIdentity publicIdentity;
      {
        final material = await _identityApi.restore(secret);
        publicIdentity = RelayPublicIdentity(relayId: material.relayId, publicKey: material.publicKey);
      }
      await _repairMetadata(publicIdentity);
      return RelayIdentityReady(publicIdentity);
    } catch (_) {
      // A found but invalid private key is corrupt. Do not delete or replace it.
      return const RelayIdentityCorrupt();
    }
  }

  Future<RelayIdentityState> _create() async {
    Uint8List? privateKey;
    try {
      final material = await _identityApi.generate();
      privateKey = material.privateKey;
      final save = await _saveSecret(privateKey);
      final failedState = _stateForStoreResult(save);
      if (failedState != null) {
        return failedState;
      }
      final publicIdentity = RelayPublicIdentity(relayId: material.relayId, publicKey: material.publicKey);
      await _repairMetadata(publicIdentity);
      return RelayIdentityReady(publicIdentity);
    } catch (_) {
      return const RelayIdentityFailed();
    } finally {
      if (privateKey != null) {
        _wipe(privateKey);
      }
    }
  }

  /// Loads the secure private key once for this activation, installs it on the
  /// running Rust server, and then wipes the Dart buffer.
  Future<RelaySignerActivationResult> activateSigner() {
    return _serializeSignerOperation(_activateSigner);
  }

  Future<RelaySignerActivationResult> _activateSigner() async {
    final ready = _ready;
    if (ready != null) {
      return _loadAndInstall(ready);
    }

    final initializing = _initializing;
    if (initializing != null) {
      final initialized = await initializing;
      return switch (initialized) {
        RelayIdentityReady() => _loadAndInstall(initialized),
        _ => const RelaySignerActivationNotReady(),
      };
    }

    final initialized = Completer<RelayIdentityState>();
    _initializing = initialized.future;
    try {
      final result = await _initializeAndInstall();
      if (result.state case RelayIdentityReady()) {
        _ready = result.state as RelayIdentityReady;
      }
      initialized.complete(result.state);
      return result.result;
    } catch (_) {
      const failed = RelayIdentityFailed();
      initialized.complete(failed);
      return const RelaySignerActivationFailed();
    } finally {
      if (identical(_initializing, initialized.future)) {
        _initializing = null;
      }
    }
  }

  Future<_RelaySignerInitialization> _initializeAndInstall() async {
    final load = await _loadSecret();
    switch (load) {
      case RelaySecretFound(:final secret):
        try {
          final state = await _restore(secret);
          return switch (state) {
            RelayIdentityReady() => _RelaySignerInitialization(
              state: state,
              result: await _install(secret, state.identity.relayId),
            ),
            _ => _RelaySignerInitialization(
              state: state,
              result: const RelaySignerActivationNotReady(),
            ),
          };
        } finally {
          _wipe(secret);
        }
      case RelaySecretNotFound():
        return _createAndInstall();
      case RelaySecretLocked() || RelaySecretNotAvailable() || RelaySecretPermissionDenied() || RelaySecretCorrupt() || RelaySecretFailed():
        return const _RelaySignerInitialization(
          state: RelayIdentityFailed(),
          result: RelaySignerActivationSecretUnavailable(),
        );
    }
  }

  Future<_RelaySignerInitialization> _createAndInstall() async {
    Uint8List? privateKey;
    try {
      final material = await _identityApi.generate();
      privateKey = material.privateKey;
      final save = await _saveSecret(privateKey);
      final failedState = _stateForStoreResult(save);
      if (failedState != null) {
        return _RelaySignerInitialization(
          state: failedState,
          result: const RelaySignerActivationNotReady(),
        );
      }
      final publicIdentity = RelayPublicIdentity(relayId: material.relayId, publicKey: material.publicKey);
      await _repairMetadata(publicIdentity);
      final ready = RelayIdentityReady(publicIdentity);
      return _RelaySignerInitialization(
        state: ready,
        result: await _install(privateKey, publicIdentity.relayId),
      );
    } catch (_) {
      return const _RelaySignerInitialization(
        state: RelayIdentityFailed(),
        result: RelaySignerActivationFailed(),
      );
    } finally {
      if (privateKey != null) {
        _wipe(privateKey);
      }
    }
  }

  Future<RelaySignerActivationResult> _loadAndInstall(RelayIdentityReady ready) async {
    final load = await _loadSecret();
    if (load is! RelaySecretFound) {
      return const RelaySignerActivationSecretUnavailable();
    }
    final secret = load.secret;
    try {
      return await _install(secret, ready.identity.relayId);
    } finally {
      _wipe(secret);
    }
  }

  Future<RelaySignerActivationResult> _install(Uint8List privateKey, String expectedRelayId) async {
    final installedRelayId = _installedRelayId;
    if (installedRelayId != null && installedRelayId != expectedRelayId) {
      final revoked = await _revoke();
      if (revoked is! RelaySignerRevokeRevoked && revoked is! RelaySignerRevokeServerNotRunning) {
        return const RelaySignerActivationFailed();
      }
    }

    final RelaySignerInstallOutcome result;
    try {
      result = await _signerPort.install(privateKey, expectedRelayId);
    } catch (_) {
      return const RelaySignerActivationFailed();
    }
    switch (result) {
      case RelaySignerInstallInstalled(:final relayId) when relayId == expectedRelayId:
        _installedRelayId = relayId;
        return RelaySignerActivationInstalled(relayId);
      case RelaySignerInstallInstalled():
        await _revoke();
        return const RelaySignerActivationFailed();
      case RelaySignerInstallServerNotRunning():
        return const RelaySignerActivationServerNotRunning();
      case RelaySignerInstallFailed():
        return const RelaySignerActivationFailed();
    }
  }

  Future<RelaySecretStoreResult> _saveSecret(Uint8List secret) async {
    try {
      return await _secureStore.save(secret);
    } catch (_) {
      return const RelaySecretStoreFailed();
    }
  }

  RelayIdentityState? _stateForStoreResult(RelaySecretStoreResult result) => switch (result) {
    RelaySecretStoreSuccess() => null,
    RelaySecretStoreLocked() => const RelayIdentityLocked(),
    RelaySecretStoreNotAvailable() => const RelayIdentityNotAvailable(),
    RelaySecretStorePermissionDenied() => const RelayIdentityPermissionDenied(),
    RelaySecretStoreFailed() => const RelayIdentityFailed(),
  };

  Future<void> _repairMetadata(RelayPublicIdentity authoritative) async {
    try {
      final cached = await _metadataStore.load();
      if (cached != authoritative) {
        await _metadataStore.save(authoritative);
      }
    } catch (_) {
      // The secret store remains authoritative. Retry this cache repair later.
      _logger.warning('Could not persist Relay identity public metadata.');
    }
  }

  /// Explicitly removes the secure identity, then its public cache. It does not
  /// generate a replacement; a later [initialize] may do so from not-found.
  Future<RelayIdentityResetResult> resetIdentity() {
    final existing = _resetting;
    if (existing != null) {
      return existing;
    }

    late final Future<RelayIdentityResetResult> operation;
    operation = _reset();
    _resetting = operation;
    return operation.whenComplete(() {
      if (identical(_resetting, operation)) {
        _resetting = null;
      }
    });
  }

  Future<RelayIdentityResetResult> _reset() async {
    final revoke = await _serializeSignerOperation(() async {
      final initializing = _initializing;
      if (initializing != null) {
        await initializing;
      }
      return _revoke();
    });
    if (revoke is! RelaySignerRevokeRevoked && revoke is! RelaySignerRevokeServerNotRunning) {
      return const RelayIdentityResetSignerActive();
    }

    final deleted = await _deleteSecret();
    final failure = _resetForStoreResult(deleted);
    if (failure != null) {
      return failure;
    }

    _ready = null;
    _installedRelayId = null;
    try {
      await _metadataStore.clear();
      return const RelayIdentityResetSuccess();
    } catch (_) {
      _logger.warning('Could not clear Relay identity public metadata after secure deletion.');
      return const RelayIdentityResetFailed();
    }
  }

  Future<RelaySecretStoreResult> _deleteSecret() async {
    try {
      return await _secureStore.delete();
    } catch (_) {
      return const RelaySecretStoreFailed();
    }
  }

  RelayIdentityResetResult? _resetForStoreResult(RelaySecretStoreResult result) => switch (result) {
    RelaySecretStoreSuccess() => null,
    RelaySecretStoreLocked() => const RelayIdentityResetLocked(),
    RelaySecretStoreNotAvailable() => const RelayIdentityResetNotAvailable(),
    RelaySecretStorePermissionDenied() => const RelayIdentityResetPermissionDenied(),
    RelaySecretStoreFailed() => const RelayIdentityResetFailed(),
  };

  Future<RelaySignerRevokeOutcome> _revoke() async {
    try {
      return await _signerPort.revoke();
    } catch (_) {
      return const RelaySignerRevokeUnreachable();
    }
  }

  Future<T> _serializeSignerOperation<T>(Future<T> Function() operation) async {
    final previous = _signerOp;
    final current = Completer<void>();
    _signerOp = current.future;
    await previous;
    try {
      return await operation();
    } finally {
      current.complete();
    }
  }

  void _wipe(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }
}
