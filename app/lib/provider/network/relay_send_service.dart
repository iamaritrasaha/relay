import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/persistence/relay_paired_address.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/relay_identity_provider.dart';
import 'package:localsend_app/provider/relay_remote_transfer_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/security/relay_identity_coordinator.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart' as rust_cancel;
import 'package:localsend_isolates/rust/api/relay_anywhere.dart' as rust_relay_anywhere;
import 'package:localsend_isolates/util/android_channel.dart' show getFileDescriptorAndroid;
import 'package:localsend_isolates/util/file_hash.dart';
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
    final result = await _identityCoordinator.withPrivateKey((privateKey, identity) async {
      final sources = await _anywhereSources(files);
      await for (final event in rust_relay_anywhere.relayAnywhereSend(
        sessionId: sessionId,
        privateKeyPem: privateKey,
        relayId: identity.relayId,
        address: route.relayAddress,
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
    if (result != true) {
      transfers.update(sessionKey, (transfer) => transfer.copyWith(phase: RelayRemoteTransferPhase.failed));
      throw const RelaySendFailure('identity');
    }
  }

  Future<List<rust_relay_anywhere.RsRelayAnywhereFile>> _anywhereSources(List<CrossFile> files) async {
    final result = <rust_relay_anywhere.RsRelayAnywhereFile>[];
    final hashCancelToken = rust_cancel.createCancellationToken();
    for (final file in files) {
      final path = file.path;
      final isContentUri = path?.startsWith('content://') ?? false;
      if (path == null && file.bytes != null) {
        // The native v2 source is intentionally streaming-only. The normal
        // picker produces a path/descriptor for files and folders.
        throw StateError('Relay remote send requires a streaming file source');
      }
      result.add(
        rust_relay_anywhere.RsRelayAnywhereFile(
          path: isContentUri ? null : path,
          fileDescriptor: isContentUri ? await getFileDescriptorAndroid(uri: path!) : null,
          name: file.name,
          size: BigInt.from(file.size),
          fileType: file.fileType.name,
          sha256: await calculateFileHash(path: file.path, bytes: file.bytes, cancelToken: hashCancelToken),
        ),
      );
    }
    return result;
  }
}
