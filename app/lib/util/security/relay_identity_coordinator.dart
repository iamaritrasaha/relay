import 'dart:typed_data';

import 'package:localsend_app/model/persistence/relay_public_identity.dart';
import 'package:localsend_app/util/security/relay_identity_metadata_store.dart';
import 'package:localsend_app/util/security/relay_identity_secret_store.dart';
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

/// Coordinates the authoritative private identity in secure storage with a
/// non-secret public metadata cache.
class RelayIdentityCoordinator {
  final RelayIdentitySecretStore _secureStore;
  final RelayIdentityApi _identityApi;
  final RelayIdentityMetadataStore _metadataStore;

  RelayIdentityReady? _ready;
  Future<RelayIdentityState>? _initializing;
  Future<RelayIdentityResetResult>? _resetting;

  RelayIdentityCoordinator({
    required RelayIdentitySecretStore secureStore,
    required RelayIdentityApi identityApi,
    required RelayIdentityMetadataStore metadataStore,
  }) : _secureStore = secureStore,
       _identityApi = identityApi,
       _metadataStore = metadataStore;

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
      RelaySecretFound(:final secret) => _restore(secret),
      RelaySecretNotFound() => _create(),
      RelaySecretLocked() => const RelayIdentityLocked(),
      RelaySecretNotAvailable() => const RelayIdentityNotAvailable(),
      RelaySecretPermissionDenied() => const RelayIdentityPermissionDenied(),
      RelaySecretCorrupt() => const RelayIdentityCorrupt(),
      RelaySecretFailed() => const RelayIdentityFailed(),
    };
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
    try {
      late RelayPublicIdentity publicIdentity;
      {
        final material = await _identityApi.generate();
        final save = await _saveSecret(material.privateKey);
        final failedState = _stateForStoreResult(save);
        if (failedState != null) {
          return failedState;
        }
        publicIdentity = RelayPublicIdentity(relayId: material.relayId, publicKey: material.publicKey);
      }
      await _repairMetadata(publicIdentity);
      return RelayIdentityReady(publicIdentity);
    } catch (_) {
      return const RelayIdentityFailed();
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
    final initializing = _initializing;
    if (initializing != null) {
      await initializing;
    }

    final deleted = await _deleteSecret();
    final failure = _resetForStoreResult(deleted);
    if (failure != null) {
      return failure;
    }

    _ready = null;
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
}
