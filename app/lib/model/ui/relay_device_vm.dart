import 'package:localsend_app/model/ui/relay_capability_vm.dart';
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

/// Immutable, presentation-only description of a Relay target device.
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
  final RelayConnectionType connectionType;
  final RelaySecurityState securityState;
  final RelayBatteryVm battery;
  final String? ip;
  final int? port;
  final String? deviceModel;

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
    this.connectionType = RelayConnectionType.local,
    this.securityState = RelaySecurityState.verifiedRelay,
    this.battery = const RelayBatteryVm(),
    this.ip,
    this.port,
    this.deviceModel,
  });

  bool get isVerifiedRelay => targetKind == RelayDeviceTargetKind.verifiedRelay || targetKind == RelayDeviceTargetKind.pairedRelay;
  bool get isLocalSend => targetKind == RelayDeviceTargetKind.unresolvedLan;
  bool get isPaired => targetKind == RelayDeviceTargetKind.pairedRelay;

  String get statusSummary {
    if (phase == RelayDevicePhase.sending) {
      return 'Transferring…';
    }
    if (phase == RelayDevicePhase.waiting || phase == RelayDevicePhase.verifying) {
      return 'Preparing…';
    }
    if (phase == RelayDevicePhase.failed) {
      return 'Transfer failed';
    }
    if (isLocalSend) {
      return 'LocalSend · Nearby';
    }
    if (isPaired && connectionType != RelayConnectionType.local) {
      return 'Paired · Remote';
    }
    return 'Nearby · Local';
  }

  Map<RelayCapability, CapabilityStatus> get capabilityStatuses => {
        RelayCapability.files: CapabilityStatus.available,
        RelayCapability.clipboard: CapabilityStatus.comingSoon,
        RelayCapability.battery: battery.hasInfo ? CapabilityStatus.available : CapabilityStatus.unavailable,
        RelayCapability.messages: CapabilityStatus.comingSoon,
        RelayCapability.notifications: CapabilityStatus.comingSoon,
      };
}
