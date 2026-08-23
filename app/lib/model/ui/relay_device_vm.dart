import 'package:relay_app/model/ui/relay_connection_state.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_isolates/model/device.dart';

enum RelayDevicePhase {
  idle,
  waiting,
  verifying,
  sending,
  success,
  failed,
  cancelled,
}

/// UI target namespace. Nearby observations remain unresolved LAN candidates;
/// a paired route is keyed by an authenticated RelayId and is never folded
/// into a Relay compatibility peer.
enum RelayDeviceTargetKind { unresolvedLan, verifiedRelay, pairedRelay, kdeConnect }

/// Immutable, presentation-only description of a Relay target device.
class RelayDeviceVm {
  // NOTE: reachability lives in [connectionState]. Do not re-derive it from
  // [detail] — see RelayConnectionState for why that produced wrong answers.

  final String key;
  final String alias;
  final DeviceType deviceType;
  final RelayDevicePhase phase;
  final double? progress;
  final String detail;

  /// How this device is reachable, from the core's single derivation.
  ///
  /// Null for view models built without core transport data — continuity
  /// devices, and fixtures that predate this field. [connectionState] falls back
  /// for those; read that, never this.
  final RelayConnectionState? explicitConnectionState;
  final RelayDeviceTargetKind targetKind;
  final String? relayId;
  final String? lanFingerprint;
  final RelayConnectionType connectionType;
  final RelaySecurityState securityState;
  final RelayBatteryVm battery;
  final String? networkType;
  final int? signalLevel;
  final bool connectivityStale;
  final bool canPing;
  final bool canFindDevice;
  final bool canSendSms;
  final bool canMuteRinger;

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

  /// How this device is reachable. **The** answer — every surface reads this.
  ///
  /// A KDE device carries the core's authoritative state in
  /// [explicitConnectionState]. Anything else (a continuity peer, a test
  /// fixture) has no transport state to report, so it falls back to the coarse
  /// connected/not-connected meaning of [detail]. The fallback deliberately
  /// cannot distinguish Local from Remote: only the core knows that, and
  /// guessing here is exactly the mistake this type exists to prevent.
  RelayConnectionState get connectionState =>
      explicitConnectionState ??
      (detail == 'Connected' ? RelayConnectionState.local : RelayConnectionState.offline);

  const RelayDeviceVm({
    required this.key,
    required this.alias,
    required this.deviceType,
    required this.phase,
    required this.progress,
    required this.detail,
    this.explicitConnectionState,
    this.targetKind = RelayDeviceTargetKind.unresolvedLan,
    this.relayId,
    this.lanFingerprint,
    this.connectionType = RelayConnectionType.local,
    this.securityState = RelaySecurityState.verifiedRelay,
    this.battery = const RelayBatteryVm(),
    this.networkType,
    this.signalLevel,
    this.connectivityStale = false,
    this.canPing = false,
    this.canFindDevice = false,
    this.canSendSms = false,
    this.canMuteRinger = false,
    this.capabilities = const {},
    this.continuityConnected = false,
    this.ip,
    this.port,
    this.deviceModel,
  });

  bool get isCompatibilityPeer => targetKind == RelayDeviceTargetKind.unresolvedLan;
  bool get isKdeConnect => targetKind == RelayDeviceTargetKind.kdeConnect;
  bool get isVerifiedRelay => targetKind == RelayDeviceTargetKind.verifiedRelay;
  bool get isPairedRelay => targetKind == RelayDeviceTargetKind.pairedRelay;
  bool get isPaired => isPairedRelay || (isKdeConnect && (detail == 'Paired' || detail == 'Connected'));
  bool get isAuthenticatedRelay => isVerifiedRelay || isPairedRelay;

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
    if (phase == RelayDevicePhase.cancelled) {
      return 'Transfer cancelled';
    }
    if (phase == RelayDevicePhase.success) {
      return 'Transfer complete';
    }
    if (isKdeConnect) {
      if (detail == 'Connected') {
        return switch (connectionType) {
          RelayConnectionType.local => 'Local',
          RelayConnectionType.direct || RelayConnectionType.relayed => 'Remote',
          RelayConnectionType.unspecified => 'Reconnecting',
        };
      }
      if (detail == 'Paired') {
        return 'Offline';
      }
      return 'Nearby';
    }
    if (isCompatibilityPeer) {
      return 'LocalSend compatible · Nearby';
    }
    if (continuityConnected) {
      // "Connected" means an authenticated continuity session is live, which is
      // strictly more than being reachable.
      return connectionType == RelayConnectionType.local ? 'Connected · Local' : 'Connected';
    }
    if (isPairedRelay && connectionType != RelayConnectionType.local) {
      return 'Paired · Remote';
    }
    return 'Nearby · Local';
  }

  /// Whether the device is reachable right now, as opposed to merely known.
  ///
  /// A trusted device that has gone away keeps its place in the UI and reads as
  /// offline; it is never dropped just because discovery stopped seeing it.
  bool get isPresent {
    final summary = statusSummary;
    return summary == 'Local' ||
        summary == 'Remote' ||
        summary.startsWith('Connected') ||
        summary.startsWith('Nearby') ||
        summary.startsWith('Transferring') ||
        summary == 'Paired';
  }

  /// Capability states for display.
  ///
  /// Relay-compatible peers get files and nothing else: continuity never
  /// reaches a peer that cannot prove a RelayId.
  Map<RelayCapability, CapabilityStatus> get capabilityStatuses {
    if (isKdeConnect) {
      return {
        RelayCapability.files: CapabilityStatus.unavailable,
        RelayCapability.clipboard: capabilities[RelayCapability.clipboard] ?? CapabilityStatus.unavailable,
        RelayCapability.battery: capabilities[RelayCapability.battery] ?? CapabilityStatus.unavailable,
        // Derived from the peer's own advertised SMS capabilities, like every
        // other row here. Pinning this to unavailable hid the Messages action
        // and told the GNOME pill the phone had no messages at all, on peers
        // whose conversations Relay was reading at the same moment.
        RelayCapability.messages: capabilities[RelayCapability.messages] ?? CapabilityStatus.unavailable,
        RelayCapability.notifications: capabilities[RelayCapability.notifications] ?? CapabilityStatus.unavailable,
        RelayCapability.phone: capabilities[RelayCapability.phone] ?? CapabilityStatus.unavailable,
      };
    }
    if (isCompatibilityPeer) {
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
        if (capability != RelayCapability.files) capability: capabilities[capability] ?? CapabilityStatus.disabled,
    };
  }
}
