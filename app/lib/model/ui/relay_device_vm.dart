import 'package:relay_app/model/ui/relay_connection_state.dart';
import 'package:relay_app/model/ui/relay_capability_vm.dart';
import 'package:relay_app/model/ui/relay_feature.dart';
import 'package:relay_app/model/ui/relay_last_seen.dart';
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

  // --- Device Fabric ---------------------------------------------------------
  // Everything below comes straight from the core's authoritative record. None
  // of it is inferred here, and nothing here may be re-derived from [detail].

  /// The core's form factor. Null for devices that have no fabric record —
  /// LocalSend peers, continuity peers, fixtures.
  final RelayDeviceClass? deviceClass;

  /// Whether the core holds a trust record for this device. Independent of
  /// connectivity: a remembered device that is offline is still trusted.
  final bool fabricTrusted;

  /// Whether this device has a fabric record at all. A discovered but unpaired
  /// peer does not, which is what separates "My Devices" from pairing candidates.
  final bool hasFabricRecord;

  final bool lanAvailable;
  final bool wanAvailable;

  /// Whether a WAN binding exists at all. Remembered reachability, not current.
  final bool wanBound;

  /// "direct" or "relay" while a WAN route is up. Diagnostics only — never the
  /// product identity of the connection.
  final String? wanPath;

  final int? lanLastSeenUnix;
  final int? wanLastSeenUnix;

  /// The most recent genuine route activity, from the core. Never a rebuild time.
  final int? lastSeenUnix;

  final String? platform;
  final String? platformVersion;
  final String? relayVersion;

  /// What the core says can be done with this device right now, per feature.
  ///
  /// The one place feature policy is answered. A screen asks this map; it does
  /// not assemble its own conditions from connection state and capability lists.
  final Map<RelayFeature, RelayFeatureAvailability> featureAvailability;

  /// How this device is reachable. **The** answer — every surface reads this.
  ///
  /// A KDE device carries the core's authoritative state in
  /// [explicitConnectionState]. Anything else (a continuity peer, a test
  /// fixture) has no transport state to report, so it falls back to the coarse
  /// connected/not-connected meaning of [detail]. The fallback deliberately
  /// cannot distinguish Local from Remote: only the core knows that, and
  /// guessing here is exactly the mistake this type exists to prevent.
  RelayConnectionState get connectionState =>
      explicitConnectionState ?? (detail == 'Connected' ? RelayConnectionState.local : RelayConnectionState.offline);

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
    this.deviceClass,
    this.fabricTrusted = false,
    this.hasFabricRecord = false,
    this.lanAvailable = false,
    this.wanAvailable = false,
    this.wanBound = false,
    this.wanPath,
    this.lanLastSeenUnix,
    this.wanLastSeenUnix,
    this.lastSeenUnix,
    this.platform,
    this.platformVersion,
    this.relayVersion,
    this.featureAvailability = const {},
  });

  /// What the core says about one feature for this device.
  ///
  /// A device with no fabric record reports [RelayFeatureAvailability.unsupported]
  /// rather than guessing: only the fabric knows, and inventing an answer here
  /// is the mistake the whole model exists to prevent.
  RelayFeatureAvailability availabilityOf(RelayFeature feature) => featureAvailability[feature] ?? RelayFeatureAvailability.unsupported;

  bool canUse(RelayFeature feature) => availabilityOf(feature).isAvailable;

  /// How long ago the core last heard from this device.
  String lastSeenLabel({required DateTime now}) => relayLastSeenLabel(lastSeenUnix, now: now);

  bool get isCompatibilityPeer => targetKind == RelayDeviceTargetKind.unresolvedLan;
  bool get isKdeConnect => targetKind == RelayDeviceTargetKind.kdeConnect;
  bool get isVerifiedRelay => targetKind == RelayDeviceTargetKind.verifiedRelay;
  bool get isPairedRelay => targetKind == RelayDeviceTargetKind.pairedRelay;

  /// Whether Relay holds a trust relationship with this device.
  ///
  /// For a KDE device this is the fabric's trust record, never a display string:
  /// trust persists across restarts and across going offline, and `detail` knows
  /// nothing about either.
  bool get isPaired => isPairedRelay || (isKdeConnect && fabricTrusted);
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
      // Straight from the Device Fabric. A device Relay does not know yet has no
      // record and is a pairing candidate, which is a different thing from a
      // trusted device that happens to be offline.
      return hasFabricRecord ? connectionState.userLabel : 'Nearby';
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

  /// One capability row, presented from the core's availability answer.
  CapabilityStatus _statusOf(RelayFeature feature) => switch (availabilityOf(feature)) {
    RelayFeatureAvailability.available => CapabilityStatus.available,
    RelayFeatureAvailability.needsPermission => CapabilityStatus.permissionRequired,
    RelayFeatureAvailability.disabled => CapabilityStatus.disabled,
    // Supported but out of reach right now: the row stays, greyed out, so the
    // user still sees that their phone does this.
    RelayFeatureAvailability.notConnected => CapabilityStatus.disabled,
    RelayFeatureAvailability.notConfigured => CapabilityStatus.disabled,
    RelayFeatureAvailability.unsupported => CapabilityStatus.unavailable,
  };

  /// Capability states for display.
  ///
  /// Relay-compatible peers get files and nothing else: continuity never
  /// reaches a peer that cannot prove a RelayId.
  Map<RelayCapability, CapabilityStatus> get capabilityStatuses {
    if (isKdeConnect) {
      // A KDE device with a fabric record takes every row from the core's one
      // availability rule. The rows are a presentation of that answer, not a
      // second policy: reimplementing the conditions per widget is how the same
      // feature ended up enabled on one screen and greyed out on another.
      if (hasFabricRecord) {
        return {
          RelayCapability.files: _statusOf(RelayFeature.files),
          RelayCapability.clipboard: _statusOf(RelayFeature.clipboard),
          RelayCapability.battery: _statusOf(RelayFeature.battery),
          RelayCapability.messages: _statusOf(RelayFeature.messages),
          RelayCapability.notifications: _statusOf(RelayFeature.notifications),
          RelayCapability.phone: capabilities[RelayCapability.phone] ?? CapabilityStatus.unavailable,
        };
      }
      return {
        RelayCapability.files: CapabilityStatus.unavailable,
        RelayCapability.clipboard: capabilities[RelayCapability.clipboard] ?? CapabilityStatus.unavailable,
        RelayCapability.battery: capabilities[RelayCapability.battery] ?? CapabilityStatus.unavailable,
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
