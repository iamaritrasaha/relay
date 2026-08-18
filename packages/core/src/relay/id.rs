//! Proven vs claimed Relay identity values.
//!
//! [`RelayId`] is only constructed from local key material or from a verified
//! [`crate::crypto::relay_identity_proof::RelayIdentityProofV1`].
//! [`ClaimedRelayId`] is an unverified identity assertion and has no conversion
//! into [`RelayId`].

use crate::crypto::relay_identity::RelayIdentity;

/// Cryptographically derived Relay identity: SHA-256 of canonical SPKI DER.
///
/// The inner digest is private. There is no `From<&str>` / `From<ClaimedRelayId>`
/// constructor.
#[derive(Clone, Debug, Eq)]
pub struct RelayId {
    digest: [u8; 32],
}

impl RelayId {
    /// The RelayId of a local identity whose private key we hold.
    pub fn from_local_identity(identity: &RelayIdentity) -> anyhow::Result<Self> {
        Self::from_verified_hex(&identity.relay_id()?)
    }

    /// Parses a hex RelayId that has already been returned by proof verification.
    pub(crate) fn from_verified_hex(hex: &str) -> anyhow::Result<Self> {
        parse_canonical_hex(hex).ok_or_else(|| anyhow::anyhow!("invalid verified RelayId encoding"))
    }

    /// Canonical uppercase hex of a RelayId the local user/app targeted
    /// (invite or stored binding). This is **not** a proof that a peer is this
    /// identity; [`super::coordinator::RelayAuthCoordinator`] still requires a
    /// matching cryptographic proof.
    pub fn from_expected_canonical_hex(hex: &str) -> anyhow::Result<Self> {
        parse_canonical_hex(hex).ok_or_else(|| anyhow::anyhow!("invalid expected RelayId encoding"))
    }

    /// Uppercase hex encoding (64 characters), matching existing RelayId strings.
    pub fn as_hex(&self) -> String {
        hex_upper(&self.digest)
    }

    pub(crate) fn eq_digest(&self, other: &Self) -> bool {
        ct_eq32(&self.digest, &other.digest)
    }
}

impl PartialEq for RelayId {
    fn eq(&self, other: &Self) -> bool {
        self.eq_digest(other)
    }
}

impl std::hash::Hash for RelayId {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.digest.hash(state);
    }
}

/// An identity value that has **not** been cryptographically proven.
///
/// This type is not [`RelayId`], does not dereference to it, and cannot be
/// converted into it.
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct ClaimedRelayId {
    value: String,
}

impl ClaimedRelayId {
    /// Wraps an untrusted textual claim (protocol field, UI input, metadata).
    pub fn from_untrusted_text(value: impl Into<String>) -> Self {
        Self {
            value: value.into(),
        }
    }

    /// Legacy display/debug access only. Not a proof of identity.
    pub fn as_untrusted_text(&self) -> &str {
        &self.value
    }
}

fn parse_canonical_hex(hex: &str) -> Option<RelayId> {
    parse_sha256_hex(hex)
        .filter(|_| hex.bytes().all(|b| !b.is_ascii_lowercase()))
        .map(|digest| RelayId { digest })
}

pub(crate) fn parse_sha256_hex(hex: &str) -> Option<[u8; 32]> {
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let mut digest = [0_u8; 32];
    for (i, chunk) in hex.as_bytes().chunks_exact(2).enumerate() {
        digest[i] = u8::from_str_radix(std::str::from_utf8(chunk).ok()?, 16).ok()?;
    }
    Some(digest)
}

pub(crate) fn hex_upper(digest: &[u8; 32]) -> String {
    digest.iter().map(|byte| format!("{byte:02X}")).collect()
}

fn ct_eq32(a: &[u8; 32], b: &[u8; 32]) -> bool {
    let mut diff = 0_u8;
    for i in 0..32 {
        diff |= a[i] ^ b[i];
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::any::TypeId;

    #[test]
    fn claimed_relay_id_is_a_distinct_type_from_relay_id() {
        assert_ne!(TypeId::of::<ClaimedRelayId>(), TypeId::of::<RelayId>());
        let claimed = ClaimedRelayId::from_untrusted_text("not-a-proof");
        assert_eq!(claimed.as_untrusted_text(), "not-a-proof");
    }
}
