/// The record of a paired Relay device: a proven identity, plus whatever route
/// metadata is known for it.
///
/// This is explicitly not a trust record and not a capability grant. A `RelayId`
/// is the only stable key; display labels and route addresses are replaceable
/// metadata, and [relayAddress] is absent for a device paired purely over the
/// local network, which is reached through live discovery rather than through a
/// stored address.
class RelayPairedAddress {
  static const currentVersion = 2;

  /// How the relationship was established. Both are mutually authenticated;
  /// they differ only in what route metadata they leave behind.
  static const originAnywhere = 'anywhere';
  static const originLan = 'lan';

  final int version;
  final String relayId;
  final String? displayLabel;

  /// The Relay Anywhere address, when one is known. `null` for a device that
  /// was paired over the local network only.
  final String? relayAddress;

  /// When the relationship was established. Distinct from [updatedAt], which
  /// moves whenever route metadata is refreshed.
  final DateTime pairedAt;
  final DateTime updatedAt;
  final String origin;

  const RelayPairedAddress({
    this.version = currentVersion,
    required this.relayId,
    required this.displayLabel,
    required this.relayAddress,
    required this.pairedAt,
    required this.updatedAt,
    this.origin = originAnywhere,
  });

  /// Whether this device can be dialled through Relay Anywhere.
  bool get hasAnywhereRoute => relayAddress != null;

  RelayPairedAddress copyWith({
    String? displayLabel,
    String? relayAddress,
    DateTime? updatedAt,
    String? origin,
  }) => RelayPairedAddress(
    relayId: relayId,
    displayLabel: displayLabel ?? this.displayLabel,
    relayAddress: relayAddress ?? this.relayAddress,
    pairedAt: pairedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    origin: origin ?? this.origin,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'relayId': relayId,
    'displayLabel': displayLabel,
    'relayAddress': relayAddress,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'origin': origin,
  };

  static RelayPairedAddress? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final version = raw['version'];
    final relayId = raw['relayId'];
    final displayLabel = raw['displayLabel'];
    final relayAddress = raw['relayAddress'];
    final updatedAt = raw['updatedAt'];
    if (relayId is! String || !_isRelayId(relayId) || (displayLabel != null && displayLabel is! String) || updatedAt is! String) {
      return null;
    }
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);
    if (parsedUpdatedAt == null) {
      return null;
    }

    return switch (version) {
      // Version 1 only ever stored Anywhere routes, and only after an
      // authenticated session, so it migrates to a pairing of that origin.
      1 =>
        relayAddress is String && relayAddress.startsWith('RELAY1.')
            ? RelayPairedAddress(
                relayId: relayId,
                displayLabel: displayLabel as String?,
                relayAddress: relayAddress,
                pairedAt: parsedUpdatedAt.toUtc(),
                updatedAt: parsedUpdatedAt.toUtc(),
                origin: originAnywhere,
              )
            : null,
      currentVersion => _parseCurrent(
        relayId: relayId,
        displayLabel: displayLabel as String?,
        relayAddress: relayAddress,
        pairedAt: raw['pairedAt'],
        updatedAt: parsedUpdatedAt.toUtc(),
        origin: raw['origin'],
      ),
      _ => null,
    };
  }

  static RelayPairedAddress? _parseCurrent({
    required String relayId,
    required String? displayLabel,
    required Object? relayAddress,
    required Object? pairedAt,
    required DateTime updatedAt,
    required Object? origin,
  }) {
    if (relayAddress != null && (relayAddress is! String || !relayAddress.startsWith('RELAY1.'))) {
      return null;
    }
    if (origin != originAnywhere && origin != originLan) {
      return null;
    }
    // An Anywhere-origin record without its address is not a route we can act
    // on, so it is dropped rather than silently downgraded to a LAN pairing.
    if (origin == originAnywhere && relayAddress == null) {
      return null;
    }
    final parsedPairedAt = pairedAt is String ? DateTime.tryParse(pairedAt) : null;
    if (parsedPairedAt == null) {
      return null;
    }
    return RelayPairedAddress(
      relayId: relayId,
      displayLabel: displayLabel,
      relayAddress: relayAddress as String?,
      pairedAt: parsedPairedAt.toUtc(),
      updatedAt: updatedAt,
      origin: origin as String,
    );
  }

  static bool _isRelayId(String value) => RegExp(r'^[A-F0-9]{64}$').hasMatch(value);
}
