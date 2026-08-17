/// Public, reconstructible Relay identity data cached in ordinary persistence.
///
/// This deliberately contains no private-key material and is never used to
/// recreate an identity.
class RelayPublicIdentity {
  static const currentVersion = 1;

  final int version;
  final String relayId;
  final String publicKey;

  const RelayPublicIdentity({
    this.version = currentVersion,
    required this.relayId,
    required this.publicKey,
  });

  @override
  bool operator ==(Object other) =>
      other is RelayPublicIdentity && other.version == version && other.relayId == relayId && other.publicKey == publicKey;

  @override
  int get hashCode => Object.hash(version, relayId, publicKey);

  @override
  String toString() => 'RelayPublicIdentity(version: $version, relayId: $relayId, publicKey: $publicKey)';
}
