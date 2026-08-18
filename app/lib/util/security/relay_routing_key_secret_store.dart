import 'dart:typed_data';

import 'package:localsend_app/util/security/relay_identity_secret_store.dart';

/// Secure storage for the opaque 32-byte Anywhere routing key.
///
/// The result taxonomy is shared with Relay identity storage because both use
/// the same platform secret-store boundary. The stored material is separate:
/// this key only stabilizes an Iroh EndpointId and must never be treated as a
/// Relay identity, trust record, or general application preference.
abstract interface class RelayRoutingKeySecretStore {
  Future<RelaySecretLoadResult> load();

  Future<RelaySecretStoreResult> save(Uint8List secret);

  Future<RelaySecretStoreResult> delete();
}
