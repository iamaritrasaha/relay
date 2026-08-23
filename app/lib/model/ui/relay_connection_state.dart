/// How a logical Relay device is reachable right now.
///
/// This is the product's single source of truth for Local / Remote / Offline.
/// It is derived once, from the core's transport state, and every surface reads
/// it — the overview, device details, messages and the GNOME status pill.
///
/// Previously each of those re-derived reachability from a display string
/// (`detail == 'Connected'`), which collapsed Local and Remote together and let
/// an *offline* device be labelled "Local" through a catch-all branch. Having
/// one mapping is what makes that class of bug impossible rather than merely
/// fixed.
enum RelayConnectionState {
  offline,
  local,
  remoteDirect,
  remoteRelay,
  reconnecting;

  /// Maps the core's transport-state string.
  ///
  /// An unrecognised value becomes [offline] rather than defaulting to a
  /// connected state: claiming reachability Relay cannot back up is the more
  /// damaging error, since every feature gate keys off it.
  static RelayConnectionState fromCore(String? raw) => switch (raw) {
    'local' => RelayConnectionState.local,
    'remoteDirect' => RelayConnectionState.remoteDirect,
    'remoteRelay' => RelayConnectionState.remoteRelay,
    'reconnecting' => RelayConnectionState.reconnecting,
    _ => RelayConnectionState.offline,
  };

  /// Whether the device can carry traffic right now.
  bool get isConnected =>
      this == RelayConnectionState.local ||
      this == RelayConnectionState.remoteDirect ||
      this == RelayConnectionState.remoteRelay;

  /// Whether the active route is remote, which the file size policy keys off.
  bool get isRemote =>
      this == RelayConnectionState.remoteDirect || this == RelayConnectionState.remoteRelay;

  /// What a normal user reads. Direct and relayed are both simply "Remote" —
  /// the difference is a diagnostic detail, not something to reason about.
  String get userLabel => switch (this) {
    RelayConnectionState.local => 'Local',
    RelayConnectionState.remoteDirect || RelayConnectionState.remoteRelay => 'Remote',
    RelayConnectionState.reconnecting => 'Reconnecting',
    RelayConnectionState.offline => 'Offline',
  };

  /// The precise route, for the diagnostics surface only. Normal users should
  /// never have to reason about transports.
  String get diagnosticLabel => switch (this) {
    RelayConnectionState.local => 'KDE LAN',
    RelayConnectionState.remoteDirect => 'Relay WAN · Direct',
    RelayConnectionState.remoteRelay => 'Relay WAN · Relay',
    RelayConnectionState.reconnecting => 'Reconnecting',
    RelayConnectionState.offline => 'Offline',
  };
}
