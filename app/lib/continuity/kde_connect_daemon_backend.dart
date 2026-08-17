import 'dart:async';
import 'dart:convert';

import 'package:localsend_app/continuity/continuity_backend.dart';
import 'package:localsend_app/continuity/kde_connect_dbus_boundary.dart';

typedef ContinuityDiagnosticSink = void Function(ContinuityDiagnostic diagnostic);

final class KdeConnectDaemonBackend implements ContinuityBackend {
  KdeConnectDaemonBackend({
    required KdeConnectDbusBoundary dbus,
    this.maxClipboardBytes = 16 * 1024,
    this.operationTimeout = const Duration(seconds: 5),
    ContinuityDiagnosticSink? diagnostics,
  }) : _dbus = dbus,
       _diagnostics = diagnostics;

  static const backendId = ContinuityBackendId('kdeconnectd');

  final KdeConnectDbusBoundary _dbus;
  final int maxClipboardBytes;
  final Duration operationTimeout;
  final ContinuityDiagnosticSink? _diagnostics;
  final _snapshotController = StreamController<ContinuityBackendSnapshot>.broadcast(sync: true);

  StreamSubscription<KdeConnectOwnerChange>? _ownerSubscription;
  ContinuityBackendSnapshot _snapshot = ContinuityBackendSnapshot(
    health: const ContinuityBackendHealth(ContinuityBackendHealthStatus.stopped),
    peers: const [],
  );
  var _generation = 0;
  var _started = false;
  var _closed = false;

  @override
  ContinuityBackendId get id => backendId;

  @override
  ContinuityBackendSnapshot get snapshot => _snapshot;

  @override
  Stream<ContinuityBackendSnapshot> get snapshots => _snapshotController.stream;

  @override
  Future<void> start() async {
    if (_closed || _started) {
      return;
    }
    _started = true;
    _ownerSubscription = _dbus.ownerChanges.listen(_handleOwnerChange);
    await refresh();
  }

  void _handleOwnerChange(KdeConnectOwnerChange change) {
    if (_closed) {
      return;
    }
    _generation++;
    _publish(
      ContinuityBackendSnapshot(
        health: ContinuityBackendHealth(
          change.serviceName == gsConnectServiceName && change.hasOwner
              ? ContinuityBackendHealthStatus.unsupportedEnvironment
              : ContinuityBackendHealthStatus.stopped,
        ),
        peers: const [],
      ),
    );
    _emit(ContinuityDiagnosticCategory.ownerChanged, stopwatch: Stopwatch()..start());
    unawaited(refresh());
  }

  @override
  Future<void> refresh() async {
    if (_closed) {
      return;
    }
    final generation = ++_generation;
    final stopwatch = Stopwatch()..start();
    try {
      final presence = await _dbus.probePresence().timeout(operationTimeout);
      if (!_isCurrent(generation)) {
        return;
      }
      switch (presence) {
        case KdeConnectDaemonPresence.notInstalled:
          _publishHealth(ContinuityBackendHealthStatus.notInstalled);
        case KdeConnectDaemonPresence.stopped:
          _publishHealth(ContinuityBackendHealthStatus.stopped);
        case KdeConnectDaemonPresence.gsConnectOnly:
          _publishHealth(ContinuityBackendHealthStatus.unsupportedEnvironment);
        case KdeConnectDaemonPresence.running:
          final discovery = await _dbus.discoverPeers().timeout(operationTimeout);
          if (!_isCurrent(generation)) {
            return;
          }
          final peers = discovery.peers.map(_toPeer).toList(growable: false);
          _publish(
            ContinuityBackendSnapshot(
              health: ContinuityBackendHealth(
                discovery.degraded ? ContinuityBackendHealthStatus.degraded : ContinuityBackendHealthStatus.ready,
              ),
              peers: peers,
            ),
          );
      }
      _emit(ContinuityDiagnosticCategory.refreshed, stopwatch: stopwatch);
    } on TimeoutException {
      if (_isCurrent(generation)) {
        _publishHealth(ContinuityBackendHealthStatus.degraded);
        _emit(ContinuityDiagnosticCategory.timedOut, stopwatch: stopwatch);
      }
    } on KdeConnectDbusException catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      switch (error.kind) {
        case KdeConnectDbusFailureKind.unavailable:
          _publishHealth(ContinuityBackendHealthStatus.stopped);
          _emit(ContinuityDiagnosticCategory.unavailable, stopwatch: stopwatch);
        case KdeConnectDbusFailureKind.incompatibleApi:
          _publishHealth(ContinuityBackendHealthStatus.incompatibleApi);
          _emit(ContinuityDiagnosticCategory.incompatibleApi, stopwatch: stopwatch);
        case KdeConnectDbusFailureKind.timedOut:
          _publishHealth(ContinuityBackendHealthStatus.degraded);
          _emit(ContinuityDiagnosticCategory.timedOut, stopwatch: stopwatch);
        case KdeConnectDbusFailureKind.failed:
          _publishHealth(ContinuityBackendHealthStatus.degraded);
          _emit(ContinuityDiagnosticCategory.failed, stopwatch: stopwatch);
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        _publishHealth(ContinuityBackendHealthStatus.degraded);
        _emit(ContinuityDiagnosticCategory.failed, stopwatch: stopwatch);
      }
    }
  }

  ContinuityPeer _toPeer(KdeConnectPeerSnapshot peer) {
    final capabilities = <ContinuityCapability>{};
    if (peer.paired && peer.reachable && peer.clipboardTextAvailable) {
      capabilities.add(ContinuityCapability.sendClipboardText);
    }
    return ContinuityPeer(
      id: ContinuityPeerId(backendId: backendId, opaqueId: peer.opaqueId),
      displayName: peer.displayName,
      reachable: peer.reachable,
      paired: peer.paired,
      capabilities: capabilities,
    );
  }

  @override
  Future<ContinuityResult> sendClipboardText(ContinuityPeerId peerId, String text) async {
    final stopwatch = Stopwatch()..start();
    if (_closed || !_snapshot.health.canEnumeratePeers || peerId.backendId != backendId) {
      return _result(ContinuityResultStatus.backendUnavailable, ContinuityDiagnosticCategory.unavailable, peerId, stopwatch);
    }
    final peer = _findPeer(peerId);
    if (peer == null) {
      return _result(ContinuityResultStatus.peerNotFound, ContinuityDiagnosticCategory.unavailable, peerId, stopwatch);
    }
    if (!peer.paired) {
      return _result(ContinuityResultStatus.peerUnpaired, ContinuityDiagnosticCategory.unavailable, peerId, stopwatch);
    }
    if (!peer.reachable) {
      return _result(ContinuityResultStatus.peerUnreachable, ContinuityDiagnosticCategory.unavailable, peerId, stopwatch);
    }
    if (!peer.supports(ContinuityCapability.sendClipboardText)) {
      return _result(ContinuityResultStatus.unsupported, ContinuityDiagnosticCategory.incompatibleApi, peerId, stopwatch);
    }
    if (text.isEmpty) {
      return _result(ContinuityResultStatus.invalidContent, ContinuityDiagnosticCategory.failed, peerId, stopwatch);
    }
    if (utf8.encode(text).length > maxClipboardBytes) {
      return _result(ContinuityResultStatus.contentTooLarge, ContinuityDiagnosticCategory.failed, peerId, stopwatch);
    }

    try {
      await _dbus.sendClipboardText(peerId.opaqueId, text).timeout(operationTimeout);
      return _result(ContinuityResultStatus.success, ContinuityDiagnosticCategory.dispatchSucceeded, peerId, stopwatch);
    } on TimeoutException {
      return _result(ContinuityResultStatus.timedOut, ContinuityDiagnosticCategory.timedOut, peerId, stopwatch);
    } on KdeConnectDbusException catch (error) {
      switch (error.kind) {
        case KdeConnectDbusFailureKind.unavailable:
          unawaited(refresh());
          return _result(ContinuityResultStatus.backendUnavailable, ContinuityDiagnosticCategory.unavailable, peerId, stopwatch);
        case KdeConnectDbusFailureKind.incompatibleApi:
          return _result(ContinuityResultStatus.unsupported, ContinuityDiagnosticCategory.incompatibleApi, peerId, stopwatch);
        case KdeConnectDbusFailureKind.timedOut:
          return _result(ContinuityResultStatus.timedOut, ContinuityDiagnosticCategory.timedOut, peerId, stopwatch);
        case KdeConnectDbusFailureKind.failed:
          return _result(ContinuityResultStatus.failed, ContinuityDiagnosticCategory.failed, peerId, stopwatch);
      }
    } catch (_) {
      return _result(ContinuityResultStatus.failed, ContinuityDiagnosticCategory.failed, peerId, stopwatch);
    }
  }

  ContinuityPeer? _findPeer(ContinuityPeerId peerId) {
    for (final peer in _snapshot.peers) {
      if (peer.id == peerId) {
        return peer;
      }
    }
    return null;
  }

  ContinuityResult _result(
    ContinuityResultStatus status,
    ContinuityDiagnosticCategory category,
    ContinuityPeerId peerId,
    Stopwatch stopwatch,
  ) {
    _emit(category, peerId: peerId, stopwatch: stopwatch);
    return ContinuityResult(status);
  }

  bool _isCurrent(int generation) => !_closed && generation == _generation;

  void _publishHealth(ContinuityBackendHealthStatus status) {
    _publish(ContinuityBackendSnapshot(health: ContinuityBackendHealth(status), peers: const []));
  }

  void _publish(ContinuityBackendSnapshot snapshot) {
    if (_closed) {
      return;
    }
    _snapshot = snapshot;
    _snapshotController.add(snapshot);
  }

  void _emit(ContinuityDiagnosticCategory category, {ContinuityPeerId? peerId, required Stopwatch stopwatch}) {
    stopwatch.stop();
    _diagnostics?.call(ContinuityDiagnostic(backendId: backendId, category: category, peerId: peerId, elapsed: stopwatch.elapsed));
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation++;
    await _ownerSubscription?.cancel();
    await _snapshotController.close();
    await _dbus.close();
  }
}
