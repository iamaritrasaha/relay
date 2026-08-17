import 'dart:async';

enum ContinuityBackendHealthStatus { notInstalled, stopped, unsupportedEnvironment, incompatibleApi, ready, degraded }

enum ContinuityCapability { sendClipboardText }

enum ContinuityResultStatus {
  success,
  backendUnavailable,
  peerNotFound,
  peerUnpaired,
  peerUnreachable,
  unsupported,
  invalidContent,
  contentTooLarge,
  timedOut,
  failed,
}

enum ContinuityDiagnosticCategory { refreshed, ownerChanged, dispatchSucceeded, unavailable, incompatibleApi, timedOut, failed }

final class ContinuityBackendId {
  const ContinuityBackendId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is ContinuityBackendId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class ContinuityPeerId {
  const ContinuityPeerId({required this.backendId, required this.opaqueId});

  final ContinuityBackendId backendId;
  final String opaqueId;

  @override
  bool operator ==(Object other) => other is ContinuityPeerId && other.backendId == backendId && other.opaqueId == opaqueId;

  @override
  int get hashCode => Object.hash(backendId, opaqueId);

  @override
  String toString() => '${backendId.value}:$opaqueId';
}

final class ContinuityBackendHealth {
  const ContinuityBackendHealth(this.status);

  final ContinuityBackendHealthStatus status;

  bool get canEnumeratePeers => status == ContinuityBackendHealthStatus.ready || status == ContinuityBackendHealthStatus.degraded;

  @override
  bool operator ==(Object other) => other is ContinuityBackendHealth && other.status == status;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => status.name;
}

final class ContinuityPeer {
  ContinuityPeer({
    required this.id,
    required this.displayName,
    required this.reachable,
    required this.paired,
    required Set<ContinuityCapability> capabilities,
  }) : capabilities = Set.unmodifiable(capabilities);

  final ContinuityPeerId id;
  final String displayName;
  final bool reachable;
  final bool paired;
  final Set<ContinuityCapability> capabilities;

  bool supports(ContinuityCapability capability) => capabilities.contains(capability);

  @override
  String toString() => 'ContinuityPeer(id: $id, displayName: $displayName, reachable: $reachable, paired: $paired, capabilities: $capabilities)';
}

final class ContinuityBackendSnapshot {
  ContinuityBackendSnapshot({required this.health, required List<ContinuityPeer> peers}) : peers = List.unmodifiable(peers);

  final ContinuityBackendHealth health;
  final List<ContinuityPeer> peers;
}

final class ContinuityResult {
  const ContinuityResult(this.status);

  final ContinuityResultStatus status;

  bool get isSuccess => status == ContinuityResultStatus.success;

  @override
  String toString() => status.name;
}

final class ContinuityDiagnostic {
  const ContinuityDiagnostic({required this.backendId, required this.category, this.peerId, required this.elapsed});

  final ContinuityBackendId backendId;
  final ContinuityDiagnosticCategory category;
  final ContinuityPeerId? peerId;
  final Duration elapsed;

  @override
  String toString() =>
      'ContinuityDiagnostic(backend: $backendId, peer: ${peerId ?? '-'}, category: ${category.name}, elapsedMs: ${elapsed.inMilliseconds})';
}

abstract interface class ContinuityBackend {
  ContinuityBackendId get id;
  ContinuityBackendSnapshot get snapshot;
  Stream<ContinuityBackendSnapshot> get snapshots;

  Future<void> start();
  Future<void> refresh();
  Future<ContinuityResult> sendClipboardText(ContinuityPeerId peerId, String text);
  Future<void> close();
}
