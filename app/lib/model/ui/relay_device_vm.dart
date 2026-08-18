import 'package:localsend_isolates/model/device.dart';

enum RelayDevicePhase {
  idle,
  waiting,
  verifying,
  sending,
  success,
  failed,
}

/// UI target namespace. Nearby observations remain unresolved LAN candidates;
/// a paired route is keyed by an authenticated RelayId and is never folded
/// into a LocalSend compatibility peer.
enum RelayDeviceTargetKind { unresolvedLan, verifiedRelay, pairedRelay }

/// Immutable, presentation-only description of a nearby Relay target.
class RelayDeviceVm {
  final String key;
  final String alias;
  final DeviceType deviceType;
  final RelayDevicePhase phase;
  final double? progress;
  final String detail;
  final RelayDeviceTargetKind targetKind;
  final String? relayId;
  final String? lanFingerprint;

  const RelayDeviceVm({
    required this.key,
    required this.alias,
    required this.deviceType,
    required this.phase,
    required this.progress,
    required this.detail,
    this.targetKind = RelayDeviceTargetKind.unresolvedLan,
    this.relayId,
    this.lanFingerprint,
  });
}
