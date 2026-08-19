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

  /// Continuity capability states for this device, already folded together from
  /// what the user enabled, what this device can do and what the peer
  /// advertised. `files` is always present; the rest appear once a continuity
  /// session has told us something real.
  final Map<RelayCapability, CapabilityStatus> capabilities;

  /// Whether a live, authenticated continuity session exists right now.
  ///
  /// A stored Relay address never makes this true.
  final bool continuityConnected;

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
    this.capabilities = const {},
    this.continuityConnected = false,
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
    if (continuityConnected) {
      // "Connected" means an authenticated continuity session is live, which is
      // strictly more than being reachable.
      return connectionType == RelayConnectionType.local ? 'Connected · Local' : 'Connected';
    }
    if (isPaired && connectionType != RelayConnectionType.local) {
      return 'Paired · Remote';
    }
    return 'Nearby · Local';
  }

  /// Capability states for display.
  ///
  /// LocalSend-compatible peers get files and nothing else: continuity never
  /// reaches a peer that cannot prove a RelayId.
  Map<RelayCapability, CapabilityStatus> get capabilityStatuses {
    if (isLocalSend) {
      return const {
        RelayCapability.files: CapabilityStatus.available,
        RelayCapability.clipboard: CapabilityStatus.unavailable,
        RelayCapability.battery: CapabilityStatus.unavailable,
        RelayCapability.messages: CapabilityStatus.unavailable,
        RelayCapability.notifications: CapabilityStatus.unavailable,
        RelayCapability.phone: CapabilityStatus.unavailable,
      };
    }
    return {
      RelayCapability.files: CapabilityStatus.available,
      for (final capability in RelayCapability.values)
        if (capability != RelayCapability.files)
          capability: capabilities[capability] ?? CapabilityStatus.disabled,
    };
  }
}
