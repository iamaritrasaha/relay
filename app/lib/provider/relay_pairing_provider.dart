import 'dart:async';

import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:relay_app/provider/continuity/continuity_provider.dart';
import 'package:relay_app/provider/persistence_provider.dart';
import 'package:relay_app/provider/relay_identity_provider.dart';
import 'package:relay_app/provider/relay_paired_routes_provider.dart';
import 'package:relay_app/provider/security_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/security/relay_lan_pairing_service.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:relay_isolates/isolate.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/model/stored_security_context.dart';

final _logger = Logger('RelayPairing');

/// A pairing another Relay device is asking this device's user to approve.
///
/// [relayId] is proven: the request only exists because a mutual identity proof
/// already succeeded. [alias] is the peer's own label and is display text only.
class RelayIncomingPairRequest {
  final String relayId;
  final String alias;
  final String? ip;

  /// The six digits both devices show. The users compare them; the code is not
  /// a secret and is not what makes the pairing safe.
  final String verificationCode;

  const RelayIncomingPairRequest({
    required this.relayId,
    required this.alias,
    required this.ip,
    required this.verificationCode,
  });
}

enum RelayOutgoingPairingPhase {
  /// Proving both identities. Nothing has been shown to the other user yet.
  proving,

  /// The other device is showing the request and its user is deciding.
  awaitingRemote,
}

/// A pairing this device started and is waiting on.
class RelayOutgoingPairRequest {
  final String deviceLabel;
  final RelayOutgoingPairingPhase phase;
  final String? verificationCode;

  const RelayOutgoingPairRequest({
    required this.deviceLabel,
    required this.phase,
    this.verificationCode,
  });
}

/// The device relationship lifecycle.
///
/// Four facts are kept apart and answering one never answers another:
/// a device can be *discovered* without being *paired*, *paired* without being
/// *trusted*, and *trusted* without any capability being granted.
class RelayPairingState {
  final RelayIncomingPairRequest? incoming;
  final RelayOutgoingPairRequest? outgoing;

  const RelayPairingState({this.incoming, this.outgoing});

  RelayPairingState copyWith({
    RelayIncomingPairRequest? incoming,
    RelayOutgoingPairRequest? outgoing,
    bool clearIncoming = false,
    bool clearOutgoing = false,
  }) => RelayPairingState(
    incoming: clearIncoming ? null : incoming ?? this.incoming,
    outgoing: clearOutgoing ? null : outgoing ?? this.outgoing,
  );

  @override
  String toString() => 'RelayPairingState(incoming: ${incoming?.relayId}, outgoing: ${outgoing?.deviceLabel})';
}

final relayPairingProvider = ReduxProvider<RelayPairingService, RelayPairingState>((ref) {
  final pairedAddressStore = RelayPairedAddressStore(PersistenceRelayPairedAddressPersistence(ref.read(persistenceProvider)));
  return RelayPairingService(
    pairedAddressStore: pairedAddressStore,
    lanPairingService: RelayLanPairingService(
      identityCoordinator: ref.read(relayIdentityCoordinatorProvider),
      pairedAddressStore: pairedAddressStore,
      api: const RustRelayLanPairingApi(),
      onPairingSaved: () => ref.notifier(relayPairedRoutesProvider).refresh(),
    ),
    isolateController: ref.notifier(parentIsolateProvider),
    continuityService: ref.notifier(continuityProvider),
    pairedRoutes: ref.notifier(relayPairedRoutesProvider),
    securityContext: () => ref.read(securityProvider),
    localAlias: () => ref.read(settingsProvider).alias,
  );
});

class RelayPairingService extends ReduxNotifier<RelayPairingState> {
  final RelayPairedAddressStore _pairedAddressStore;
  final RelayLanPairingService _lanPairingService;
  final IsolateController _isolateController;
  final ContinuityService _continuityService;
  final RelayPairedRoutesNotifier _pairedRoutes;
  final StoredSecurityContext Function() _securityContext;
  final String Function() _localAlias;

  RelayPairingService({
    required RelayPairedAddressStore pairedAddressStore,
    required RelayLanPairingService lanPairingService,
    required IsolateController isolateController,
    required ContinuityService continuityService,
    required RelayPairedRoutesNotifier pairedRoutes,
    required StoredSecurityContext Function() securityContext,
    required String Function() localAlias,
  }) : _pairedAddressStore = pairedAddressStore,
       _lanPairingService = lanPairingService,
       _isolateController = isolateController,
       _continuityService = continuityService,
       _pairedRoutes = pairedRoutes,
       _securityContext = securityContext,
       _localAlias = localAlias;

  @override
  RelayPairingState init() => const RelayPairingState();
}

// ------------------------------------------------------------------ inbound

/// Surfaces a pairing request that already passed the mutual identity proof.
///
/// Receiving this is not pairing. Nothing is stored and nothing is granted
/// until the local user answers.
class RelayIncomingPairRequestAction extends ReduxAction<RelayPairingService, RelayPairingState> {
  final HttpServerRelayPairRequestEvent event;

  RelayIncomingPairRequestAction(this.event);

  @override
  RelayPairingState reduce() {
    return state.copyWith(
      incoming: RelayIncomingPairRequest(
        relayId: event.relayId,
        alias: event.alias,
        ip: event.ip,
        verificationCode: event.verificationCode,
      ),
    );
  }
}

/// Answers the pending inbound pairing request.
///
/// Accepting establishes the relationship and nothing else: the device is not
/// marked trusted and no continuity capability is enabled. Declining leaves no
/// record on this device.
class RelayAnswerIncomingPairAction extends AsyncReduxAction<RelayPairingService, RelayPairingState> {
  final String relayId;
  final bool accepted;

  RelayAnswerIncomingPairAction({required this.relayId, required this.accepted});

  @override
  Future<RelayPairingState> reduce() async {
    final pending = state.incoming;
    if (pending == null || pending.relayId != relayId) {
      // The prompt this answer belongs to is gone; answering a different
      // device's request with it would be exactly the confusion to avoid.
      return state;
    }

    external(notifier._isolateController).dispatch(
      IsolateHttpServerRelayPairDecisionAction(relayId: relayId, accepted: accepted),
    );

    if (accepted) {
      final saved = await notifier._pairedAddressStore.recordLanPairing(
        authenticatedRelayId: relayId,
        remoteApproved: true,
        displayLabel: pending.alias.isEmpty ? null : pending.alias,
      );
      if (saved) {
        await notifier._pairedRoutes.refresh();
      } else {
        _logger.warning('Could not store the accepted pairing for $relayId');
      }
    }

    return state.copyWith(clearIncoming: true);
  }
}

/// Drops the pending inbound request without answering, e.g. because the peer
/// gave up. The request times out on the far side as a decline.
class RelayDismissIncomingPairAction extends ReduxAction<RelayPairingService, RelayPairingState> {
  @override
  RelayPairingState reduce() => state.copyWith(clearIncoming: true);
}

// ----------------------------------------------------------------- outbound

/// Pairs with a device discovered on the local network.
///
/// The device's IP, port and certificate fingerprint decide which socket is
/// spoken to. They are not identity: the peer still has to prove its RelayId,
/// this device still has to prove its own, and the remote user still has to
/// accept, before anything is stored.
class RelayPairLanDeviceAction extends AsyncReduxActionWithResult<RelayPairingService, RelayPairingState, RelayLanPairingResult> {
  final String? ip;
  final int port;
  final bool https;

  /// The peer's observed certificate fingerprint. It selects the socket; it is
  /// never the peer's identity.
  final String certificateFingerprint;
  final String deviceLabel;

  /// The identity this device is expected to prove, when re-pairing a device
  /// that is already known. A peer that proves anything else fails.
  final String? expectedRelayId;

  RelayPairLanDeviceAction({
    required this.ip,
    required this.port,
    required this.https,
    required this.certificateFingerprint,
    required this.deviceLabel,
    this.expectedRelayId,
  });

  RelayPairLanDeviceAction.forDevice(Device device, {this.expectedRelayId})
    : ip = device.ip,
      port = device.port,
      https = device.https,
      certificateFingerprint = device.fingerprint,
      deviceLabel = device.alias;

  @override
  Future<(RelayPairingState, RelayLanPairingResult)> reduce() async {
    final ip = this.ip;
    if (ip == null || !https) {
      return (state, const RelayLanPairingUnsupported());
    }

    final securityContext = notifier._securityContext();
    final label = deviceLabel;
    final started = state.copyWith(
      outgoing: RelayOutgoingPairRequest(deviceLabel: label, phase: RelayOutgoingPairingPhase.proving),
    );
    dispatch(_RelayOutgoingPairStateAction(started.outgoing));

    final result = await notifier._lanPairingService.pair(
      ip: ip,
      port: port,
      https: https,
      certificateFingerprint: certificateFingerprint,
      clientPrivateKey: securityContext.privateKey,
      clientCertificate: securityContext.certificate,
      alias: notifier._localAlias(),
      displayLabel: label,
      expectedRelayId: expectedRelayId,
      onVerificationCode: (code) => dispatch(
        _RelayOutgoingPairStateAction(
          RelayOutgoingPairRequest(
            deviceLabel: label,
            phase: RelayOutgoingPairingPhase.awaitingRemote,
            verificationCode: code,
          ),
        ),
      ),
    );

    return (state.copyWith(clearOutgoing: true), result);
  }
}

class _RelayOutgoingPairStateAction extends ReduxAction<RelayPairingService, RelayPairingState> {
  final RelayOutgoingPairRequest? outgoing;

  _RelayOutgoingPairStateAction(this.outgoing);

  @override
  RelayPairingState reduce() => outgoing == null ? state.copyWith(clearOutgoing: true) : state.copyWith(outgoing: outgoing);
}

// -------------------------------------------------------------------- unpair

/// Removes a paired device: the canonical unpair.
///
/// Everything the relationship enabled goes with it — the stored route, local
/// continuity trust, every capability grant, clipboard sharing, and any live
/// session. What deliberately does *not* go is this device's own Relay
/// identity, any other device's state, or LocalSend favourites, which are a
/// separate compatibility list with no Relay identity behind them.
///
/// The removed device is not told. A best-effort notice would be a courtesy,
/// never a precondition: local removal must hold even against a peer that is
/// offline, or lying, or hostile. A device that reconnects afterwards is simply
/// unknown again and has to ask a person, from the start.
class RelayForgetDeviceAction extends AsyncReduxAction<RelayPairingService, RelayPairingState> {
  final String relayId;

  RelayForgetDeviceAction({required this.relayId});

  @override
  Future<RelayPairingState> reduce() async {
    // Trust and consent first: if anything later fails, the device is left
    // with no privileges rather than with a route and stale grants.
    await external(notifier._continuityService).dispatchAsync(
      ContinuityForgetDeviceAction(relayId: relayId),
    );

    final removed = await notifier._pairedAddressStore.forget(relayId);
    if (!removed) {
      _logger.info('No stored pairing to remove for $relayId');
    }
    await notifier._pairedRoutes.refresh();

    // A pending prompt from the same device is stale now.
    if (state.incoming?.relayId == relayId) {
      return state.copyWith(clearIncoming: true);
    }
    return state;
  }
}

/// Renders a six-digit pairing code as two groups of three, e.g. `482 731`.
///
/// The code confirms an already-proven relationship. It is not a secret, not a
/// password, and knowing it grants nothing.
String formatRelayPairingCode(String code) => code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
