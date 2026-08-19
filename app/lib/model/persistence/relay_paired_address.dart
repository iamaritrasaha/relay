/// The record of a paired Relay device: a proven identity, plus whatever route
/// metadata is known for it.
///
/// This is explicitly not a trust record and not a capability grant. A `RelayId`
/// is the only stable key; display labels and route addresses are replaceable
/// metadata.
///
/// Routes accumulate. The same relationship can be reachable on the local
/// network *and* through a stored Relay Anywhere address, so proving the peer
/// over one transport is never evidence that another route stopped working.
/// Nothing here removes a route; only unpairing removes the record.
class RelayPairedAddress {
  static const currentVersion = 2;

  /// How the relationship *began*. Both origins are mutually authenticated.
  ///
  /// This is provenance, not routing: an [originLan] record that later learns a
  /// Relay Anywhere address keeps saying `lan`, because that is still where the
  /// relationship started. Ask [hasAnywhereRoute] about reachability instead.
  static const originAnywhere = 'anywhere';
  static const originLan = 'lan';

  final int version;
  final String relayId;
  final String? displayLabel;

  /// The Relay Anywhere address, when one is known.
  ///
  /// `null` means only that no address has been learned yet — a device paired
  /// over the local network is still reached through live discovery plus a
  /// fresh proof each time.
  final String? relayAddress;

  /// When the relationship was established. Distinct from [updatedAt], which
  /// moves whenever route metadata is refreshed. Re-pairing an existing device
  /// does not move it: the relationship was not established twice.
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
    // A record with no Anywhere address is still a real relationship: the peer
    // is reachable on the local network. Requiring an address here would treat
    // the origin as transport exclusivity and quietly drop a valid pairing.
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
