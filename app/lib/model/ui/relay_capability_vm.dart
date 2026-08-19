import 'package:flutter/material.dart';

enum RelayCapability {
  files,
  clipboard,
  battery,
  messages,
  notifications,
  phone;

  IconData get icon => switch (this) {
        RelayCapability.files => Icons.folder_outlined,
        RelayCapability.clipboard => Icons.content_paste_rounded,
        RelayCapability.battery => Icons.battery_std_rounded,
        RelayCapability.messages => Icons.sms_outlined,
        RelayCapability.notifications => Icons.notifications_none_rounded,
        RelayCapability.phone => Icons.call_outlined,
      };

  String get title => switch (this) {
        RelayCapability.files => 'Files',
        RelayCapability.clipboard => 'Clipboard',
        RelayCapability.battery => 'Battery',
        RelayCapability.messages => 'Messages',
        RelayCapability.notifications => 'Notifications',
        RelayCapability.phone => 'Phone',
      };
}

/// What a capability can actually do right now.
///
/// There is deliberately no "coming soon": every capability here is implemented,
/// so the only honest states are about permission, platform limits, and whether
/// the user turned it on.
enum CapabilityStatus {
  /// Implemented, permitted and enabled.
  available,

  /// Usable, but the platform restricts it in a way the user must be told about.
  limited,

  /// Implemented, but a platform permission or role is missing.
  permissionRequired,

  /// Implemented and permitted, but the user has not enabled it for this device.
  disabled,

  /// Not possible on one of the two devices.
  unavailable,
}

enum RelayConnectionType {
  local,
  direct,
  relayed,
  unspecified;

  String get label => switch (this) {
        RelayConnectionType.local => 'Local',
        RelayConnectionType.direct => 'Direct',
        RelayConnectionType.relayed => 'Relayed',
        RelayConnectionType.unspecified => 'Network',
      };
}

enum RelaySecurityState {
  verifiedRelay,
  localSendCompatible,
  unauthenticated;

  String get label => switch (this) {
        RelaySecurityState.verifiedRelay => 'Verified Relay',
        RelaySecurityState.localSendCompatible => 'LocalSend-compatible',
        RelaySecurityState.unauthenticated => 'Unverified',
      };
}

@immutable
class RelayBatteryVm {
  final int? percentage;
  final bool isCharging;
  final bool isFull;

  /// Whether this is the last known value rather than a live one. A device that
  /// went away keeps its reading visible, but never pretends it is current.
  final bool isStale;

  const RelayBatteryVm({
    this.percentage,
    this.isCharging = false,
    this.isFull = false,
    this.isStale = false,
  });

  bool get hasInfo => percentage != null;

  String get displayString {
    if (percentage == null) {
      return 'Not reported';
    }
    if (isStale) {
      return '$percentage% · last known';
    }
    if (isFull) {
      return '$percentage% · Charged';
    }
    return isCharging ? '$percentage% · Charging' : '$percentage%';
  }
}

@immutable
class RelayCapabilityInfo {
  final RelayCapability capability;
  final CapabilityStatus status;
  final String title;
  final String description;
  final IconData icon;

  /// The exact platform or permission reason, when there is one. Shown verbatim
  /// so the UI never has to invent an explanation.
  final String? reason;

  const RelayCapabilityInfo({
    required this.capability,
    required this.status,
    required this.title,
    required this.description,
    required this.icon,
    this.reason,
  });

  bool get isAvailable => status == CapabilityStatus.available || status == CapabilityStatus.limited;
  bool get needsPermission => status == CapabilityStatus.permissionRequired;
  bool get isDisabled => status == CapabilityStatus.disabled;

  String get statusBadge => switch (status) {
        CapabilityStatus.available => 'Available',
        CapabilityStatus.limited => 'Limited',
        CapabilityStatus.permissionRequired => 'Permission required',
        CapabilityStatus.disabled => 'Off',
        CapabilityStatus.unavailable => 'Unavailable',
      };
}
