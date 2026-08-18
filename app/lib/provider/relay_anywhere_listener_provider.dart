import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/relay_identity_provider.dart';
import 'package:localsend_app/util/security/relay_anywhere_listener_service.dart';
import 'package:localsend_app/util/security/relay_anywhere_pairing_service.dart';
import 'package:localsend_app/util/security/relay_paired_address_store.dart';
import 'package:localsend_app/util/security/relay_routing_key_coordinator.dart';
import 'package:localsend_app/util/security/relay_routing_key_secret_store_factory.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('RelayAnywhereListener');

/// Production composition only. Constructing it performs no Iroh operation.
final relayAnywhereListenerServiceProvider = Provider<RelayAnywhereListenerService>((ref) {
  return RelayAnywhereListenerService(
    identityCoordinator: ref.read(relayIdentityCoordinatorProvider),
    routingKeyCoordinator: RelayRoutingKeyCoordinator(
      secureStore: createRelayRoutingKeySecretStore(),
      routingKeyApi: RustRelayRoutingKeyApi(),
    ),
    listenerApi: RustRelayAnywhereListenerApi(),
    onEvent: (event) {
      // Session IDs and typed failure stages are retained at the bridge. The
      // normal receive controller will consume this stream as it is unified.
      _logger.fine('Anywhere listener event: $event');
    },
  );
});

/// Authenticated pairing composition. Parsing an address has no persistence or
/// trust effect; the service saves route metadata only after the peer proves
/// its claimed RelayId.
final relayAnywherePairingServiceProvider = Provider<RelayAnywherePairingService>((ref) {
  return RelayAnywherePairingService(
    identityCoordinator: ref.read(relayIdentityCoordinatorProvider),
    pairedAddressStore: RelayPairedAddressStore(PersistenceRelayPairedAddressPersistence(ref.read(persistenceProvider))),
    api: RustRelayAnywherePairingApi(),
  );
});
