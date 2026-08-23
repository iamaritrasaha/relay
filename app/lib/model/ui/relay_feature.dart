import 'package:relay_isolates/rust/api/kdeconnect.dart';

/// A feature Relay can offer for a device.
///
/// Mirrors the core's `RelayFeature`. Distinct from [RelayCapability], which is
/// the older presentation grouping used by the capability rows; this enum is
/// the *policy* vocabulary and is the one the core answers questions about.
enum RelayFeature {
  notifications,
  messages,
  media,
  commands,
  remoteInput,
  clipboard,
  files,
  battery,
  ping
  ;

  static RelayFeature fromCore(RsRelayFeature raw) => switch (raw) {
    RsRelayFeature.notifications => RelayFeature.notifications,
    RsRelayFeature.messages => RelayFeature.messages,
    RsRelayFeature.media => RelayFeature.media,
    RsRelayFeature.commands => RelayFeature.commands,
    RsRelayFeature.remoteInput => RelayFeature.remoteInput,
    RsRelayFeature.clipboard => RelayFeature.clipboard,
    RsRelayFeature.files => RelayFeature.files,
    RsRelayFeature.battery => RelayFeature.battery,
    RsRelayFeature.ping => RelayFeature.ping,
  };

  String get title => switch (this) {
    RelayFeature.notifications => 'Notifications',
    RelayFeature.messages => 'Messages',
    RelayFeature.media => 'Media',
    RelayFeature.commands => 'Commands',
    RelayFeature.remoteInput => 'Remote input',
    RelayFeature.clipboard => 'Clipboard',
    RelayFeature.files => 'Files',
    RelayFeature.battery => 'Battery',
    RelayFeature.ping => 'Ping',
  };
}

/// Whether a feature can be used with a device right now, and if not, why.
///
/// The core answers this once per device per feature. No screen re-derives it:
/// scattering the rules is how the same feature came to be enabled on one
/// surface and greyed out on another for the same device.
enum RelayFeatureAvailability {
  available,
  unsupported,
  notConnected,
  disabled,
  needsPermission,
  notConfigured
  ;

  static RelayFeatureAvailability fromCore(RsFeatureAvailability raw) => switch (raw) {
    RsFeatureAvailability.available => RelayFeatureAvailability.available,
    RsFeatureAvailability.unsupported => RelayFeatureAvailability.unsupported,
    RsFeatureAvailability.notConnected => RelayFeatureAvailability.notConnected,
    RsFeatureAvailability.disabled => RelayFeatureAvailability.disabled,
    RsFeatureAvailability.needsPermission => RelayFeatureAvailability.needsPermission,
    RsFeatureAvailability.notConfigured => RelayFeatureAvailability.notConfigured,
  };

  bool get isAvailable => this == RelayFeatureAvailability.available;

  /// Whether the feature should still be shown, in a disabled form, rather than
  /// hidden. Only a genuinely unsupported feature disappears: a phone that does
  /// Messages should still show Messages while it is offline.
  bool get isVisible => this != RelayFeatureAvailability.unsupported;

  /// The short reason shown next to a feature the user cannot use right now.
  /// Null when the feature is available, or hidden entirely.
  String? get reason => switch (this) {
    RelayFeatureAvailability.available => null,
    RelayFeatureAvailability.unsupported => null,
    RelayFeatureAvailability.notConnected => 'Unavailable while offline',
    RelayFeatureAvailability.disabled => 'Turned off',
    RelayFeatureAvailability.needsPermission => 'Permission required',
    RelayFeatureAvailability.notConfigured => 'Not set up yet',
  };
}

/// Reads the core's answers into a map keyed by feature.
///
/// A feature the core did not report becomes [RelayFeatureAvailability.unsupported]
/// rather than defaulting to available: claiming a capability Relay cannot back
/// up is the more damaging error.
Map<RelayFeature, RelayFeatureAvailability> relayFeatureAvailability(List<RsRelayFeatureState> states) => {
  for (final state in states) RelayFeature.fromCore(state.feature): RelayFeatureAvailability.fromCore(state.availability),
};
