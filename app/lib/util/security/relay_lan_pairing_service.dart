import 'dart:typed_data';

import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_app/util/security/relay_paired_address_store.dart';
import 'package:relay_isolates/rust/api/http.dart' as rust_http;
import 'package:relay_isolates/rust/api/model.dart' as rust_model;

/// The Rust-side mutual LAN pairing handshake.
abstract interface class RelayLanPairingApi {
  Stream<rust_http.RsRelayLanPairingEvent> pair({
    required Uint8List privateKeyPem,
    required String relayId,
    required String clientPrivateKey,
    required String clientCertificate,
    required rust_model.ProtocolType protocol,
    required String ip,
    required int port,
    required String certificateFingerprint,
    required String alias,
    String? expectedRelayId,
  });
}

class RustRelayLanPairingApi implements RelayLanPairingApi {
  const RustRelayLanPairingApi();

  @override
  Stream<rust_http.RsRelayLanPairingEvent> pair({
    required Uint8List privateKeyPem,
    required String relayId,
    required String clientPrivateKey,
    required String clientCertificate,
    required rust_model.ProtocolType protocol,
    required String ip,
    required int port,
    required String certificateFingerprint,
    required String alias,
    String? expectedRelayId,
  }) => rust_http.relayLanPair(
    privateKeyPem: privateKeyPem,
    relayId: relayId,
    clientPrivateKey: clientPrivateKey,
    clientCertificate: clientCertificate,
    version: rust_http.LsHttpClientVersion.v2,
    protocol: protocol,
    ip: ip,
    port: port,
    certificateFingerprint: certificateFingerprint,
    alias: alias,
    expectedRelayId: expectedRelayId,
  );
}

sealed class RelayLanPairingResult {
  const RelayLanPairingResult();
}

/// Both devices proved their identity and the remote user accepted.
///
/// [relayId] is the proven identity, never a claim from discovery.
final class RelayLanPaired extends RelayLanPairingResult {
  final String relayId;
  final String alias;

  const RelayLanPaired({required this.relayId, required this.alias});
}

/// The remote user declined. Nothing was stored on this device.
final class RelayLanPairingRejected extends RelayLanPairingResult {
  const RelayLanPairingRejected();
}

/// The peer is not a Relay device, or is too old to pair.
final class RelayLanPairingUnsupported extends RelayLanPairingResult {
  const RelayLanPairingUnsupported();
}

/// The peer is already asking its user about another device.
final class RelayLanPairingBusy extends RelayLanPairingResult {
  const RelayLanPairingBusy();
}

/// The peer did not prove the identity it was asked to prove, or the exchange
/// never completed. Either way, nothing may be concluded and nothing is stored.
final class RelayLanPairingFailed extends RelayLanPairingResult {
  const RelayLanPairingFailed();
}

/// Pairs with a Relay device on the local network.
///
/// The service stores a pairing only when the handshake reports both a proven
/// remote RelayId *and* the remote user's acceptance. A discovery observation,
/// an IP, a certificate fingerprint or an alias never reaches persistence.
class RelayLanPairingService {
  final RelayIdentityCoordinator _identityCoordinator;
  final RelayPairedAddressStore _pairedAddressStore;
  final RelayLanPairingApi _api;
  final Future<void> Function()? _onPairingSaved;

  RelayLanPairingService({
    required RelayIdentityCoordinator identityCoordinator,
    required RelayPairedAddressStore pairedAddressStore,
    required RelayLanPairingApi api,
    Future<void> Function()? onPairingSaved,
  }) : _identityCoordinator = identityCoordinator,
       _pairedAddressStore = pairedAddressStore,
       _api = api,
       _onPairingSaved = onPairingSaved;

  /// Runs the handshake against one discovered device.
  ///
  /// [certificateFingerprint] and [ip] select which socket is spoken to; they
  /// are not identity. [expectedRelayId] is the identity the user meant to pair
  /// with, when re-pairing a device that is already known.
  ///
  /// [onVerificationCode] fires while the remote user is still deciding, so the
  /// code can be displayed on both devices at the same time.
  Future<RelayLanPairingResult> pair({
    required String ip,
    required int port,
    required bool https,
    required String certificateFingerprint,
    required String clientPrivateKey,
    required String clientCertificate,
    required String alias,
    String? displayLabel,
    String? expectedRelayId,
    void Function(String code)? onVerificationCode,
  }) async {
    if (!https) {
      // The proofs are bound to the TLS certificates of the connection, so
      // there is nothing to bind to without TLS.
      return const RelayLanPairingUnsupported();
    }

    final result = await _identityCoordinator.withPrivateKey(
      (privateKey, identity) => _run(
        privateKey: privateKey,
        localRelayId: identity.relayId,
        ip: ip,
        port: port,
        certificateFingerprint: certificateFingerprint,
        clientPrivateKey: clientPrivateKey,
        clientCertificate: clientCertificate,
        alias: alias,
        expectedRelayId: expectedRelayId,
        onVerificationCode: onVerificationCode,
      ),
    );
    if (result == null) {
      return const RelayLanPairingFailed();
    }
    if (result is! RelayLanPaired) {
      return result;
    }

    final label = displayLabel?.trim();
    final saved = await _pairedAddressStore.recordLanPairing(
      authenticatedRelayId: result.relayId,
      remoteApproved: true,
      displayLabel: switch (label) {
        null || '' => result.alias.isEmpty ? null : result.alias,
        final value => value,
      },
    );
    if (!saved) {
      return const RelayLanPairingFailed();
    }
    // Publish before reporting success, so every consumer resolves the same
    // RelayId-keyed device immediately.
    await _onPairingSaved?.call();
    return result;
  }

  Future<RelayLanPairingResult> _run({
    required Uint8List privateKey,
    required String localRelayId,
    required String ip,
    required int port,
    required String certificateFingerprint,
    required String clientPrivateKey,
    required String clientCertificate,
    required String alias,
    required String? expectedRelayId,
    required void Function(String code)? onVerificationCode,
  }) async {
    RelayLanPairingResult outcome = const RelayLanPairingFailed();
    try {
      await for (final event in _api.pair(
        privateKeyPem: privateKey,
        relayId: localRelayId,
        clientPrivateKey: clientPrivateKey,
        clientCertificate: clientCertificate,
        protocol: rust_model.ProtocolType.https,
        ip: ip,
        port: port,
        certificateFingerprint: certificateFingerprint,
        alias: alias,
        expectedRelayId: expectedRelayId,
      )) {
        switch (event) {
          case rust_http.RsRelayLanPairingEvent_VerificationCode(:final code):
            onVerificationCode?.call(code);
          case rust_http.RsRelayLanPairingEvent_Paired(:final remoteRelayId, :final remoteAlias):
            outcome = RelayLanPaired(relayId: remoteRelayId, alias: remoteAlias);
          case rust_http.RsRelayLanPairingEvent_Declined():
            outcome = const RelayLanPairingRejected();
          case rust_http.RsRelayLanPairingEvent_Unsupported():
            outcome = const RelayLanPairingUnsupported();
          case rust_http.RsRelayLanPairingEvent_Busy():
            outcome = const RelayLanPairingBusy();
          case rust_http.RsRelayLanPairingEvent_AuthenticationFailed():
          case rust_http.RsRelayLanPairingEvent_TransportFailed():
            outcome = const RelayLanPairingFailed();
        }
      }
    } catch (_) {
      return const RelayLanPairingFailed();
    }
    return outcome;
  }
}
