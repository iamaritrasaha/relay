import 'package:flutter/material.dart';

enum RelayCapability {
  files,
  clipboard,
  battery,
  messages,
  notifications,
}

enum CapabilityStatus {
  available,
  unavailable,
  comingSoon,
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
  final String? estimate;

  const RelayBatteryVm({
    this.percentage,
    this.isCharging = false,
    this.estimate,
  });

  bool get hasInfo => percentage != null;

  String get displayString {
    if (percentage == null) {
      return 'Not reported';
    }
    final chargeSymbol = isCharging ? ' · ⚡' : '';
    return '$percentage%$chargeSymbol';
  }
}

@immutable
class RelayCapabilityInfo {
  final RelayCapability capability;
  final CapabilityStatus status;
  final String title;
  final String description;
  final IconData icon;

  const RelayCapabilityInfo({
    required this.capability,
    required this.status,
    required this.title,
    required this.description,
    required this.icon,
  });

  bool get isAvailable => status == CapabilityStatus.available;
  bool get isComingSoon => status == CapabilityStatus.comingSoon;

  String get statusBadge => switch (status) {
        CapabilityStatus.available => 'Available',
        CapabilityStatus.unavailable => 'Unavailable',
        CapabilityStatus.comingSoon => 'Coming Soon',
      };
}
