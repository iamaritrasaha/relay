import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_app/util/security/relay_identity_metadata_store.dart';
import 'package:relay_app/util/security/relay_identity_secret_store_factory.dart';
import 'package:relay_app/util/security/relay_server_signer_port.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Lazily composes Relay identity recovery. It is intentionally not tied to UI
/// state; callers request [RelayIdentityCoordinator.initialize] when needed.
final relayIdentityCoordinatorProvider = Provider<RelayIdentityCoordinator>((ref) {
  return RelayIdentityCoordinator(
    secureStore: createRelayIdentitySecretStore(),
    identityApi: RustRelayIdentityApi(),
    metadataStore: PersistenceRelayIdentityMetadataStore(ref.read(persistenceProvider)),
    signerPort: IsolateRelayServerSignerPort(ref),
  );
});
