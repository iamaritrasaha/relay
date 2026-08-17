import 'dart:typed_data';

/// Stores the UTF-8 PKCS#8 PEM private-key bytes for a Relay identity.
///
/// Implementations treat [secret] as opaque material. They do not create or
/// validate identities, derive RelayIds, or make trust decisions.
abstract interface class RelayIdentitySecretStore {
  /// Loads the stored private-key bytes, or reports why they are unavailable.
  Future<RelaySecretLoadResult> load();

  /// Saves private-key bytes. Callers must already have validated the secret.
  Future<RelaySecretStoreResult> save(Uint8List secret);

  /// Deletes private-key bytes. A successful delete is idempotent.
  Future<RelaySecretStoreResult> delete();
}

sealed class RelaySecretLoadResult {
  const RelaySecretLoadResult();
}

/// A private-key secret was loaded successfully.
final class RelaySecretFound extends RelaySecretLoadResult {
  final Uint8List secret;

  const RelaySecretFound(this.secret);

  @override
  String toString() => 'RelaySecretFound(<redacted>)';
}

/// No private-key secret has been stored.
final class RelaySecretNotFound extends RelaySecretLoadResult {
  const RelaySecretNotFound();

  @override
  String toString() => 'RelaySecretNotFound()';
}

/// The platform secret store is locked.
final class RelaySecretLocked extends RelaySecretLoadResult {
  const RelaySecretLocked();

  @override
  String toString() => 'RelaySecretLocked()';
}

/// The platform does not provide a usable secret store.
final class RelaySecretNotAvailable extends RelaySecretLoadResult {
  const RelaySecretNotAvailable();

  @override
  String toString() => 'RelaySecretNotAvailable()';
}

/// The platform denied access to the secret store.
final class RelaySecretPermissionDenied extends RelaySecretLoadResult {
  const RelaySecretPermissionDenied();

  @override
  String toString() => 'RelaySecretPermissionDenied()';
}

/// Stored secret material could not be read safely.
final class RelaySecretCorrupt extends RelaySecretLoadResult {
  const RelaySecretCorrupt();

  @override
  String toString() => 'RelaySecretCorrupt()';
}

/// The store failed for a reason not represented by a more specific result.
final class RelaySecretFailed extends RelaySecretLoadResult {
  const RelaySecretFailed();

  @override
  String toString() => 'RelaySecretFailed()';
}

sealed class RelaySecretStoreResult {
  const RelaySecretStoreResult();
}

/// A save or delete operation completed successfully.
final class RelaySecretStoreSuccess extends RelaySecretStoreResult {
  const RelaySecretStoreSuccess();

  @override
  String toString() => 'RelaySecretStoreSuccess()';
}

/// A save or delete operation could not proceed because the store is locked.
final class RelaySecretStoreLocked extends RelaySecretStoreResult {
  const RelaySecretStoreLocked();

  @override
  String toString() => 'RelaySecretStoreLocked()';
}

/// A save or delete operation could not proceed because no secret store exists.
final class RelaySecretStoreNotAvailable extends RelaySecretStoreResult {
  const RelaySecretStoreNotAvailable();

  @override
  String toString() => 'RelaySecretStoreNotAvailable()';
}

/// A save or delete operation was denied by the platform.
final class RelaySecretStorePermissionDenied extends RelaySecretStoreResult {
  const RelaySecretStorePermissionDenied();

  @override
  String toString() => 'RelaySecretStorePermissionDenied()';
}

/// A save or delete operation failed for an unspecified reason.
final class RelaySecretStoreFailed extends RelaySecretStoreResult {
  const RelaySecretStoreFailed();

  @override
  String toString() => 'RelaySecretStoreFailed()';
}
