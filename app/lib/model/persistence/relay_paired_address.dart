/// Versioned, non-secret routing metadata for a previously authenticated Relay device.
///
/// This is explicitly not a trust record. A `RelayId` is the only stable key;
/// display labels and route addresses are replaceable metadata.
class RelayPairedAddress {
  static const currentVersion = 1;

  final int version;
  final String relayId;
  final String? displayLabel;
  final String relayAddress;
  final DateTime updatedAt;

  const RelayPairedAddress({
    this.version = currentVersion,
    required this.relayId,
    required this.displayLabel,
    required this.relayAddress,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() => {
    'version': version,
    'relayId': relayId,
    'displayLabel': displayLabel,
    'relayAddress': relayAddress,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
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
    if (version != currentVersion ||
        relayId is! String ||
        !_isRelayId(relayId) ||
        (displayLabel != null && displayLabel is! String) ||
        relayAddress is! String ||
        !relayAddress.startsWith('RELAY1.') ||
        updatedAt is! String) {
      return null;
    }
    final parsedUpdatedAt = DateTime.tryParse(updatedAt);
    if (parsedUpdatedAt == null) {
      return null;
    }
    return RelayPairedAddress(
      relayId: relayId,
      displayLabel: displayLabel,
      relayAddress: relayAddress,
      updatedAt: parsedUpdatedAt.toUtc(),
    );
  }

  static bool _isRelayId(String value) => RegExp(r'^[A-F0-9]{64}$').hasMatch(value);
}
