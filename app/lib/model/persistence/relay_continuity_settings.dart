/// Per-device continuity consent, persisted locally.
///
/// This is deliberately a different record from [RelayPairedAddress]. That one
/// answers "can we route to this device"; this one answers "is this device
/// trusted, and what did the user allow it to see". Pairing writes the first
/// and never the second.
library;

/// How clipboard content moves with one device.
enum ClipboardSharingMode {
  off,
  ask,
  automatic
  ;

  static ClipboardSharingMode parse(Object? raw) => switch (raw) {
    'ask' => ClipboardSharingMode.ask,
    'automatic' => ClipboardSharingMode.automatic,
    _ => ClipboardSharingMode.off,
  };

  String get wireName => name;

  String get label => switch (this) {
    ClipboardSharingMode.off => 'Off',
    ClipboardSharingMode.ask => 'Ask each time',
    ClipboardSharingMode.automatic => 'Automatic',
  };

  bool get isEnabled => this != ClipboardSharingMode.off;
}

/// The capabilities a user can grant per device.
enum ContinuityCapabilityKind {
  battery,
  clipboard,
  notifications,
  messages,
  phone
  ;

  static ContinuityCapabilityKind? tryParse(Object? raw) {
    for (final value in ContinuityCapabilityKind.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }

  String get label => switch (this) {
    ContinuityCapabilityKind.battery => 'Battery status',
    ContinuityCapabilityKind.clipboard => 'Clipboard sharing',
    ContinuityCapabilityKind.notifications => 'Notifications',
    ContinuityCapabilityKind.messages => 'Messages',
    ContinuityCapabilityKind.phone => 'Phone',
  };
}

class RelayContinuitySettings {
  static const currentVersion = 1;

  final int version;
  final String relayId;

  /// Whether the user marked this proven device as trusted for continuity.
  ///
  /// A stored route does not imply this, and it can never be set by a network
  /// message.
  final bool trusted;

  final Set<ContinuityCapabilityKind> granted;
  final ClipboardSharingMode clipboardMode;

  const RelayContinuitySettings({
    this.version = currentVersion,
    required this.relayId,
    this.trusted = false,
    this.granted = const {},
    this.clipboardMode = ClipboardSharingMode.off,
  });

  bool isEnabled(ContinuityCapabilityKind capability) {
    if (!trusted || !granted.contains(capability)) {
      return false;
    }
    // A granted clipboard with the mode switched off is honestly disabled.
    if (capability == ContinuityCapabilityKind.clipboard) {
      return clipboardMode.isEnabled;
    }
    return true;
  }

  bool get hasAnyCapability => ContinuityCapabilityKind.values.any(isEnabled);

  RelayContinuitySettings copyWith({
    bool? trusted,
    Set<ContinuityCapabilityKind>? granted,
    ClipboardSharingMode? clipboardMode,
  }) {
    return RelayContinuitySettings(
      relayId: relayId,
      trusted: trusted ?? this.trusted,
      granted: granted ?? this.granted,
      clipboardMode: clipboardMode ?? this.clipboardMode,
    );
  }

  RelayContinuitySettings withCapability(ContinuityCapabilityKind capability, bool enabled) {
    final updated = Set<ContinuityCapabilityKind>.from(granted);
    if (enabled) {
      updated.add(capability);
    } else {
      updated.remove(capability);
    }
    return copyWith(granted: updated);
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'relayId': relayId,
    'trusted': trusted,
    'granted': granted.map((capability) => capability.name).toList()..sort(),
    'clipboardMode': clipboardMode.wireName,
  };

  static RelayContinuitySettings? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final version = raw['version'];
    final relayId = raw['relayId'];
    if (version != currentVersion || relayId is! String || !_isRelayId(relayId)) {
      return null;
    }
    final grantedRaw = raw['granted'];
    final granted = <ContinuityCapabilityKind>{};
    if (grantedRaw is List) {
      for (final entry in grantedRaw) {
        final capability = ContinuityCapabilityKind.tryParse(entry);
        if (capability != null) {
          granted.add(capability);
        }
      }
    }
    return RelayContinuitySettings(
      relayId: relayId,
      // Anything unparseable falls back to denied, never to granted.
      trusted: raw['trusted'] == true,
      granted: granted,
      clipboardMode: ClipboardSharingMode.parse(raw['clipboardMode']),
    );
  }

  static bool _isRelayId(String value) => RegExp(r'^[A-F0-9]{64}$').hasMatch(value);
}
