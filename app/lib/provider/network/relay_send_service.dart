import 'dart:typed_data';

import 'package:relay_app/model/cross_file.dart';
import 'package:relay_app/model/persistence/relay_paired_address.dart';
import 'package:relay_app/provider/http_provider.dart';
import 'package:relay_app/provider/network/send_provider.dart';
import 'package:relay_app/provider/relay_identity_provider.dart';
import 'package:relay_app/provider/relay_remote_transfer_provider.dart';
import 'package:relay_app/provider/settings_provider.dart';
import 'package:relay_app/util/security/relay_identity_coordinator.dart';
import 'package:relay_isolates/model/device.dart';
import 'package:relay_isolates/rust/api/cancel.dart' as rust_cancel;
import 'package:relay_isolates/rust/api/http.dart' as rust_http;
import 'package:relay_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;
import 'package:relay_isolates/util/android_channel.dart' show getFileDescriptorAndroid;
import 'package:relay_isolates/util/file_hash.dart';
import 'package:relay_isolates/util/rust.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Product send entrypoint used by Relay Home.
///
/// The notifier remains the presentation state holder, while its normal LAN
/// execution is driven by the Rust canonical transfer events.  This gateway is
/// deliberately transport-agnostic: Home supplies a logical target and a
/// payload; transport selection never belongs in the widget tree.
final relaySendServiceProvider = Provider<RelaySendService>((ref) {
  return RelaySendService(
    ref,
    identityCoordinator: ref.read(relayIdentityCoordinatorProvider),
  );
});

class RelaySendFailure implements Exception {
  final String category;

  const RelaySendFailure(this.category);
}

class RelaySendService {
  final Ref _ref;
  final RelayIdentityCoordinator _identityCoordinator;

  RelaySendService(this._ref, {required RelayIdentityCoordinator identityCoordinator}) : _identityCoordinator = identityCoordinator;

  Future<void> send({
    required Device target,
    required List<CrossFile> files,
    required bool background,
  }) => _ref
      .notifier(sendProvider)
      .startSession(
        target: target,
        files: files,
        background: background,
      );

  /// Resolves one proven Relay identity without exposing transport selection to
  /// Home. A verified LAN candidate is tried first. Only a pre-auth transport
  /// failure may move to the paired authenticated Anywhere route; a proof
  /// mismatch is terminal and never falls back.
  Future<void> sendRelayDevice({
    required String relayId,
    required Device? verifiedLanTarget,
    required RelayPairedAddress? pairedRoute,
    required List<CrossFile> files,
    required bool background,
  }) async {
    if (verifiedLanTarget != null) {
      final lanResult = await _verifyLanRelayId(target: verifiedLanTarget, expectedRelayId: relayId);
      switch (lanResult) {
        case _LanRelayVerification.verified:
          return send(target: verifiedLanTarget, files: files, background: background);
        case _LanRelayVerification.identityFailure:
          throw const RelaySendFailure('identity');
        case _LanRelayVerification.unavailable:
          if (pairedRoute == null) {
            throw const RelaySendFailure('connection');
          }
      }
    }
    if (pairedRoute == null) {
      throw const RelaySendFailure('connection');
    }
    return sendPaired(route: pairedRoute, files: files);
  }

  Future<_LanRelayVerification> _verifyLanRelayId({required Device target, required String expectedRelayId}) async {
    try {
      final result = await _ref
          .read(httpProvider)
          .pinnedTo(target.fingerprint)
          .authenticateRelayServer(
            protocol: target.getProtocolType(),
            ip: target.ip!,
            port: target.port,
          );
      return switch (result) {
        rust_http.RsRelayPeerAuth_Authenticated(:final relayId) =>
          relayId == expectedRelayId ? _LanRelayVerification.verified : _LanRelayVerification.identityFailure,
        rust_http.RsRelayPeerAuth_Malformed() ||
        rust_http.RsRelayPeerAuth_RoleMismatch() ||
        rust_http.RsRelayPeerAuth_ChallengeMismatch() ||
        rust_http.RsRelayPeerAuth_CryptoInvalid() => _LanRelayVerification.identityFailure,
        rust_http.RsRelayPeerAuth_NotAttempted() ||
        rust_http.RsRelayPeerAuth_Unsupported() ||
        rust_http.RsRelayPeerAuth_TransportUnauthenticated() ||
        rust_http.RsRelayPeerAuth_SignerUnavailable() => _LanRelayVerification.unavailable,
      };
    } catch (_) {
      return _LanRelayVerification.unavailable;
    }
  }

  void cancel(String sessionId) {
    if (_ref.read(relayRemoteTransfersProvider).containsKey(sessionId)) {
      rust_relay_anywhere.relayAnywhereCancel(sessionId: BigInt.parse(sessionId));
      _ref.notifier(relayRemoteTransfersProvider).update(sessionId, (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.cancelled));
      return;
    }
    _ref.notifier(sendProvider).cancelSession(sessionId);
  }

  /// Opens an authenticated Anywhere transport for a previously paired route.
  /// The Rust side performs Iroh path selection, inner TLS, proof verification,
  /// and then delegates the v2 file batch to the canonical engine.
  Future<void> sendPaired({required RelayPairedAddress route, required List<CrossFile> files}) async {
    final address = route.relayAddress;
    if (address == null) {
      // A device paired over the local network has no Anywhere route. It is
      // reached through discovery instead, so there is nothing to dial here.
      return;
    }
    final sessionId = rust_relay_anywhere.relayAnywhereOpenSession();
    final sessionKey = sessionId.toString();
    final transfers = _ref.notifier(relayRemoteTransfersProvider);
    transfers.put(
      RelayRemoteTransfer(
        sessionId: sessionKey,
        relayId: route.relayId,
        alias: route.displayLabel ?? 'Relay device',
        phase: RelayRemoteTransferPhase.preparing,
        bytes: 0,
        totalBytes: files.fold(0, (total, file) => total + file.size),
      ),
    );
    bool cancelled = false;
    final result = await _identityCoordinator.withPrivateKey((privateKey, identity) async {
      final sources = await _anywhereSources(files);
      await for (final event in rust_relay_anywhere.relayAnywhereSend(
        sessionId: sessionId,
        privateKeyPem: privateKey,
        relayId: identity.relayId,
        address: address,
        alias: _ref.read(settingsProvider).alias,
        pathPreference: rust_relay_anywhere.RsRelayPathPreference.auto,
        files: sources,
      )) {
        switch (event) {
          case rust_relay_anywhere.RsRelayAnywhereEvent_Completed():
            transfers.update(
              sessionKey,
              (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.completed, origin: event.path),
            );
            return true;
          case rust_relay_anywhere.RsRelayAnywhereEvent_Failed(:final category):
            transfers.update(sessionKey, (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.failed));
            throw RelaySendFailure(category);
          case rust_relay_anywhere.RsRelayAnywhereEvent_Cancelled():
            transfers.update(sessionKey, (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.cancelled));
            cancelled = true;
            return false;
          case rust_relay_anywhere.RsRelayAnywhereEvent_Transferring(:final bytes, :final total):
            transfers.update(
              sessionKey,
              (transfer) => transfer.copyWith(
                phase: RelayRemoteTransferPhase.sending,
                bytes: bytes.toInt(),
                totalBytes: total.toInt(),
              ),
            );
          default:
            break;
        }
      }
      return false;
    });
    if (result == true || cancelled) {
      return;
    }
    if (result == null) {
      transfers.update(sessionKey, (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.failed));
      throw const RelaySendFailure('identity');
    }
    transfers.update(sessionKey, (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.failed));
    throw const RelaySendFailure('transfer_failed');
  }

  Future<List<rust_relay_anywhere.RsRelayAnywhereFile>> _anywhereSources(List<CrossFile> files) async {
    final result = <rust_relay_anywhere.RsRelayAnywhereFile>[];
    final hashCancelToken = rust_cancel.createCancellationToken();
    for (final file in files) {
      final path = file.path;
      final isContentUri = path?.startsWith('content://') ?? false;
      result.add(
        rust_relay_anywhere.RsRelayAnywhereFile(
          path: isContentUri ? null : path,
          fileDescriptor: isContentUri ? await getFileDescriptorAndroid(uri: path!) : null,
          // This variant is only used for the pre-existing small text/share
          // source. Picker and folder data remains path/SAF streamed by Rust.
          bytes: path == null && file.bytes != null ? Uint8List.fromList(file.bytes!) : null,
          name: file.name,
          size: BigInt.from(file.size),
          fileType: file.fileType.name,
          sha256: await calculateFileHash(path: file.path, bytes: file.bytes, cancelToken: hashCancelToken),
          preview: files.length == 1 && file.fileType.name == 'text' && file.bytes != null ? String.fromCharCodes(file.bytes!) : null,
          lastModified: file.lastModified,
          lastAccessed: file.lastAccessed,
        ),
      );
    }
    return result;
  }
}

enum _LanRelayVerification { verified, unavailable, identityFailure }
