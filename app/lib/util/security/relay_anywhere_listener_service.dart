import 'dart:async';
import 'dart:typed_data';

import 'package:localsend_app/model/persistence/relay_public_identity.dart';
import 'package:localsend_app/util/security/relay_identity_coordinator.dart';
import 'package:localsend_app/util/security/relay_routing_key_coordinator.dart';
import 'package:localsend_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;

abstract interface class RelayAnywhereListenerApi {
  Stream<rust_relay_anywhere.RsRelayAnywhereListenerEvent> start({
    required Uint8List privateKeyPem,
    required String relayId,
    required Uint8List routingKey,
    required String alias,
  });

  Future<void> stop();
}

class RustRelayAnywhereListenerApi implements RelayAnywhereListenerApi {
  @override
  Stream<rust_relay_anywhere.RsRelayAnywhereListenerEvent> start({
    required Uint8List privateKeyPem,
    required String relayId,
    required Uint8List routingKey,
    required String alias,
  }) => rust_relay_anywhere.relayAnywhereStartListener(
    privateKeyPem: privateKeyPem,
    relayId: relayId,
    routingKey: routingKey,
    alias: alias,
  );

  @override
  Future<void> stop() => rust_relay_anywhere.relayAnywhereStopListener();
}

sealed class RelayAnywhereListenerStartResult {
  const RelayAnywhereListenerStartResult();
}

final class RelayAnywhereListenerStarted extends RelayAnywhereListenerStartResult {
  final String address;

  const RelayAnywhereListenerStarted(this.address);
}

final class RelayAnywhereListenerInactive extends RelayAnywhereListenerStartResult {
  const RelayAnywhereListenerInactive();
}

final class RelayAnywhereListenerStartFailed extends RelayAnywhereListenerStartResult {
  const RelayAnywhereListenerStartFailed();
}

/// Owns the normal application's single remote listener subscription.
///
/// Its `enabled` gate is checked before any identity/key access, so ordinary
/// LAN-only startup never initializes Iroh. Listener events retain their
/// independent session IDs for the existing receive decision layer.
class RelayAnywhereListenerService {
  final RelayIdentityCoordinator _identityCoordinator;
  final RelayRoutingKeyCoordinator _routingKeyCoordinator;
  final RelayAnywhereListenerApi _listenerApi;
  final void Function(rust_relay_anywhere.RsRelayAnywhereListenerEvent) _onEvent;

  StreamSubscription<rust_relay_anywhere.RsRelayAnywhereListenerEvent>? _subscription;
  Future<RelayAnywhereListenerStartResult>? _starting;
  String? _address;

  RelayAnywhereListenerService({
    required RelayIdentityCoordinator identityCoordinator,
    required RelayRoutingKeyCoordinator routingKeyCoordinator,
    required RelayAnywhereListenerApi listenerApi,
    required void Function(rust_relay_anywhere.RsRelayAnywhereListenerEvent) onEvent,
  }) : _identityCoordinator = identityCoordinator,
       _routingKeyCoordinator = routingKeyCoordinator,
       _listenerApi = listenerApi,
       _onEvent = onEvent;

  Future<RelayAnywhereListenerStartResult> startIfEnabled({
    required bool enabled,
    required String alias,
  }) {
    if (!enabled) {
      return Future.value(const RelayAnywhereListenerInactive());
    }
    if (_subscription != null) {
      return Future.value(RelayAnywhereListenerStarted(_address ?? ''));
    }
    return _starting ??= _start(alias).whenComplete(() => _starting = null);
  }

  Future<RelayAnywhereListenerStartResult> _start(String alias) async {
    final identityResult = await _identityCoordinator.withPrivateKey((privateKey, identity) async {
      final routingResult = await _routingKeyCoordinator.withRoutingKey(
        (routingKey) => _startWithSecrets(
          privateKey: privateKey,
          identity: identity,
          routingKey: routingKey,
          alias: alias,
        ),
      );
      return switch (routingResult) {
        RelayRoutingKeyAccessed(:final value) => value as RelayAnywhereListenerStartResult,
        RelayRoutingKeyUnavailable() => const RelayAnywhereListenerInactive(),
      };
    });
    return identityResult ?? const RelayAnywhereListenerInactive();
  }

  Future<RelayAnywhereListenerStartResult> _startWithSecrets({
    required Uint8List privateKey,
    required RelayPublicIdentity identity,
    required Uint8List routingKey,
    required String alias,
  }) async {
    final ready = Completer<RelayAnywhereListenerStartResult>();
    late final StreamSubscription<rust_relay_anywhere.RsRelayAnywhereListenerEvent> subscription;
    subscription = _listenerApi
        .start(
          privateKeyPem: privateKey,
          relayId: identity.relayId,
          routingKey: routingKey,
          alias: alias,
        )
        .listen(
          (event) {
            _onEvent(event);
            switch (event) {
              case rust_relay_anywhere.RsRelayAnywhereListenerEvent_AddressReady(:final address):
                _address = address;
                if (!ready.isCompleted) {
                  ready.complete(RelayAnywhereListenerStarted(address));
                }
              case rust_relay_anywhere.RsRelayAnywhereListenerEvent_SessionFailed():
                break;
              case rust_relay_anywhere.RsRelayAnywhereListenerEvent_Stopped():
                _address = null;
                if (identical(_subscription, subscription)) {
                  _subscription = null;
                }
                if (!ready.isCompleted) {
                  ready.complete(const RelayAnywhereListenerStartFailed());
                }
              default:
                break;
            }
          },
          onError: (error, stackTrace) {
            if (!ready.isCompleted) {
              ready.complete(const RelayAnywhereListenerStartFailed());
            }
          },
          cancelOnError: false,
        );
    _subscription = subscription;
    final result = await ready.future;
    if (result is! RelayAnywhereListenerStarted) {
      await subscription.cancel();
      if (identical(_subscription, subscription)) {
        _subscription = null;
      }
    }
    return result;
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    _address = null;
    await subscription?.cancel();
    await _listenerApi.stop();
  }
}
