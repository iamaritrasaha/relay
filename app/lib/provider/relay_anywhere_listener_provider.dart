import 'dart:async';

import 'package:relay_app/provider/network/server/server_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/provider/relay_identity_provider.dart';
import 'package:relay_app/util/security/relay_anywhere_listener_service.dart';
import 'package:relay_app/util/security/relay_anywhere_pairing_service.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:relay_app/util/security/relay_routing_key_coordinator.dart';
import 'package:relay_app/util/security/relay_routing_key_secret_store_factory.dart';
import 'package:relay_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;
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
      // The listener establishes/authenticates transport only. Every payload
      // event is handed to the same normal receive controller that presents
      // decisions, chooses platform save targets, updates progress and writes
      // receive history for LAN transfers.
      switch (event) {
        case rust_relay_anywhere.RsRelayAnywhereListenerEvent_SessionIncomingBatch(
          :final sessionId,
          :final transferId,
          :final remoteRelayId,
          :final files,
        ):
          unawaited(
            ref
                .notifier(serverProvider)
                .onRelayAnywhereIncoming(
                  sessionId: sessionId,
                  transferId: transferId,
                  remoteRelayId: remoteRelayId,
                  files: files,
                ),
          );
        case rust_relay_anywhere.RsRelayAnywhereListenerEvent_SessionTransferring(:final sessionId, :final bytes, :final total):
          ref.notifier(serverProvider).onRelayAnywhereProgress(sessionId: sessionId, bytes: bytes, total: total);
        case rust_relay_anywhere.RsRelayAnywhereListenerEvent_SessionCompleted(:final sessionId):
          unawaited(ref.notifier(serverProvider).onRelayAnywhereCompleted(sessionId: sessionId));
        case rust_relay_anywhere.RsRelayAnywhereListenerEvent_SessionCancelled(:final sessionId):
          ref.notifier(serverProvider).onRelayAnywhereTerminal(sessionId: sessionId, cancelled: true);
        case rust_relay_anywhere.RsRelayAnywhereListenerEvent_SessionFailed(:final sessionId):
          ref.notifier(serverProvider).onRelayAnywhereTerminal(sessionId: sessionId, cancelled: false);
        default:
          _logger.fine('Anywhere listener event: $event');
      }
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
