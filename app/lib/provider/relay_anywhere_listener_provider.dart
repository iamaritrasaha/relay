import 'package:localsend_app/provider/relay_identity_provider.dart';
import 'package:localsend_app/util/security/relay_anywhere_listener_service.dart';
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
