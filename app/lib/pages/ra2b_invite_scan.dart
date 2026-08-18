/// Development-only invite shape checks used by Join paste/scan.
///
/// RA2B invite = test addressing package, not production trust.
const ra2bInvitePrefix = 'RA2B1.';
const ra2bMaxInviteLength = 16 * 1024;

/// Returns a reject reason, or null if the payload may be a v1 invite.
String? ra2bInviteShapeError(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'malformed invite: empty';
  }
  if (trimmed.length > ra2bMaxInviteLength) {
    return 'invite exceeds $ra2bMaxInviteLength bytes';
  }
  if (trimmed.startsWith('RA2B') && !trimmed.startsWith(ra2bInvitePrefix)) {
    return 'unsupported invite version';
  }
  if (!trimmed.startsWith(ra2bInvitePrefix)) {
    return 'unrelated QR: missing RA2B1 prefix';
  }
  return null;
}

bool ra2bLooksLikeInvite(String raw) => ra2bInviteShapeError(raw) == null;
