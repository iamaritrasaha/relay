import 'package:relay_app/model/persistence/relay_public_identity.dart';
import 'package:relay_app/provider/persistence_provider.dart';

abstract interface class RelayIdentityMetadataStore {
  Future<RelayPublicIdentity?> load();

  Future<void> save(RelayPublicIdentity identity);

  Future<void> clear();
}

class PersistenceRelayIdentityMetadataStore implements RelayIdentityMetadataStore {
  final PersistenceService _persistence;

  PersistenceRelayIdentityMetadataStore(this._persistence);

  @override
  Future<RelayPublicIdentity?> load() async => _persistence.getRelayPublicIdentity();

  @override
  Future<void> save(RelayPublicIdentity identity) => _persistence.setRelayPublicIdentity(identity);

  @override
  Future<void> clear() => _persistence.clearRelayPublicIdentity();
}
