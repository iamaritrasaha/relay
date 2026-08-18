import 'package:refena_flutter/refena_flutter.dart';

enum RelayRemoteTransferPhase { preparing, sending, completed, failed, cancelled }

class RelayRemoteTransfer {
  final String sessionId;
  final String relayId;
  final String alias;
  final RelayRemoteTransferPhase phase;
  final int bytes;
  final int totalBytes;
  final String? origin;

  const RelayRemoteTransfer({
    required this.sessionId,
    required this.relayId,
    required this.alias,
    required this.phase,
    required this.bytes,
    required this.totalBytes,
    this.origin,
  });

  RelayRemoteTransfer copyWith({
    RelayRemoteTransferPhase? phase,
    int? bytes,
    int? totalBytes,
    String? origin,
  }) => RelayRemoteTransfer(
    sessionId: sessionId,
    relayId: relayId,
    alias: alias,
    phase: phase ?? this.phase,
    bytes: bytes ?? this.bytes,
    totalBytes: totalBytes ?? this.totalBytes,
    origin: origin ?? this.origin,
  );
}

/// Product-facing state for authenticated Anywhere transfers. This contains
/// presentation state only; Rust remains the owner of transfer semantics.
final relayRemoteTransfersProvider = NotifierProvider<RelayRemoteTransfersNotifier, Map<String, RelayRemoteTransfer>>((ref) {
  return RelayRemoteTransfersNotifier();
});

class RelayRemoteTransfersNotifier extends Notifier<Map<String, RelayRemoteTransfer>> {
  @override
  Map<String, RelayRemoteTransfer> init() => {};

  void put(RelayRemoteTransfer transfer) => state = {...state, transfer.sessionId: transfer};

  void update(String sessionId, RelayRemoteTransfer Function(RelayRemoteTransfer current) transform) {
    final current = state[sessionId];
    if (current != null) {
      state = {...state, sessionId: transform(current)};
    }
  }

  bool has(String sessionId) => state.containsKey(sessionId);
}
