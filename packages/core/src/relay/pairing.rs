//! Mutual LAN pairing: the human-verifiable half of the Relay LAN handshake.
//!
//! The cryptographic relationship is established entirely by the two
//! `RelayIdentityProofV1` exchanges in [`super::coordinator`]. Nothing in this
//! module authenticates anybody. Its only job is to fold the already-proven
//! transcript into a short code both sides can read aloud, so a user can tell
//! *this* pairing apart from a concurrent one.
//!
//! The code is therefore a confirmation of an existing cryptographic fact, not
//! a credential: it is derived from material that is already public to both
//! ends, it is never sent on the wire, and knowing it grants nothing.

use super::id::RelayId;

/// Domain separator for the pairing verification code.
const VERIFICATION_DOMAIN: &[u8; 21] = b"RelayLanPairVerifyV1\x00";

/// How many decimal digits the verification code has.
pub const VERIFICATION_CODE_DIGITS: u32 = 6;

/// The bilateral decision a user makes on the responding device.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RelayPairingDecision {
    Accepted,
    Declined,
}

impl RelayPairingDecision {
    pub fn is_accepted(self) -> bool {
        matches!(self, Self::Accepted)
    }
}

/// Result of a LAN pairing attempt as seen by the initiator.
///
/// Only [`RelayLanPairingOutcome::Paired`] may be persisted, and it carries the
/// **proven** remote RelayId — never a claim taken from discovery, an address,
/// or the peer's own payload.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RelayLanPairingOutcome {
    /// Both identities were proven and the remote user accepted.
    Paired {
        remote_relay_id: String,
        remote_alias: String,
        verification_code: String,
    },
    /// Both identities were proven and the remote user rejected. Nothing may be
    /// stored: a rejected request leaves no relationship on either side.
    Declined,
    /// The peer does not serve the Relay LAN pairing endpoints.
    Unsupported,
    /// The peer is already showing a pairing prompt for somebody else.
    Busy,
    /// A proof was missing, malformed, of the wrong role, bound to the wrong
    /// certificate, or did not match the identity we demanded.
    AuthenticationFailed,
    /// The exchange never completed. No conclusion may be drawn about identity.
    TransportFailed,
}

/// Derives the shared six-digit verification code for one pairing attempt.
///
/// Both nonces enter the transcript so a code is bound to this exchange rather
/// than to the pair of identities, which makes a replayed or concurrent attempt
/// display a different number. The two RelayIds are sorted so the initiator and
/// the responder compute the same value without agreeing on who is who.
pub fn verification_code(
    server_nonce: &[u8; 32],
    client_nonce: &[u8; 32],
    one: &RelayId,
    other: &RelayId,
) -> String {
    let (low, high) = {
        let (a, b) = (one.as_hex(), other.as_hex());
        if a <= b {
            (a, b)
        } else {
            (b, a)
        }
    };

    let mut transcript = Vec::with_capacity(VERIFICATION_DOMAIN.len() + 64 + 128);
    transcript.extend_from_slice(VERIFICATION_DOMAIN);
    transcript.extend_from_slice(server_nonce);
    transcript.extend_from_slice(client_nonce);
    transcript.extend_from_slice(low.as_bytes());
    transcript.extend_from_slice(high.as_bytes());

    let digest = crate::crypto::hash::sha256(&transcript);
    let truncated = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    let modulus = 10_u32.pow(VERIFICATION_CODE_DIGITS);
    format!(
        "{:0width$}",
        truncated % modulus,
        width = VERIFICATION_CODE_DIGITS as usize
    )
}

/// Renders a code for display as two groups of three, e.g. `482 731`.
pub fn format_verification_code(code: &str) -> String {
    if code.len() != VERIFICATION_CODE_DIGITS as usize {
        return code.to_owned();
    }
    format!("{} {}", &code[..3], &code[3..])
}

/// Clamps an alias taken from a peer's pairing request.
///
/// The alias is untrusted display text: it is never an identity, it never keys
/// anything, and it is bounded here so it cannot be used to flood a prompt.
pub const MAX_PAIRING_ALIAS_LEN: usize = 64;

pub fn sanitize_pairing_alias(alias: &str) -> String {
    alias
        .chars()
        .filter(|character| !character.is_control())
        .take(MAX_PAIRING_ALIAS_LEN)
        .collect::<String>()
        .trim()
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::relay_identity::RelayIdentity;

    fn relay_id() -> RelayId {
        RelayId::from_local_identity(&RelayIdentity::generate()).unwrap()
    }

    #[test]
    fn both_sides_derive_the_same_code_regardless_of_argument_order() {
        let (a, b) = (relay_id(), relay_id());
        let server_nonce = [0x11; 32];
        let client_nonce = [0x22; 32];

        assert_eq!(
            verification_code(&server_nonce, &client_nonce, &a, &b),
            verification_code(&server_nonce, &client_nonce, &b, &a)
        );
    }

    #[test]
    fn the_code_is_six_digits_and_bound_to_both_nonces() {
        let (a, b) = (relay_id(), relay_id());
        let code = verification_code(&[0x11; 32], &[0x22; 32], &a, &b);

        assert_eq!(code.len(), VERIFICATION_CODE_DIGITS as usize);
        assert!(code.bytes().all(|byte| byte.is_ascii_digit()));
        assert_ne!(code, verification_code(&[0x12; 32], &[0x22; 32], &a, &b));
        assert_ne!(code, verification_code(&[0x11; 32], &[0x23; 32], &a, &b));
    }

    #[test]
    fn a_different_identity_pair_derives_a_different_code() {
        let (a, b, c) = (relay_id(), relay_id(), relay_id());
        assert_ne!(
            verification_code(&[0x11; 32], &[0x22; 32], &a, &b),
            verification_code(&[0x11; 32], &[0x22; 32], &a, &c)
        );
    }

    #[test]
    fn code_formatting_splits_into_two_groups_and_leaves_odd_input_alone() {
        assert_eq!(format_verification_code("482731"), "482 731");
        assert_eq!(format_verification_code("48273"), "48273");
    }

    #[test]
    fn alias_sanitization_strips_control_characters_and_bounds_length() {
        assert_eq!(sanitize_pairing_alias(" Redmi\u{0007}\n "), "Redmi");
        assert_eq!(
            sanitize_pairing_alias(&"x".repeat(200)).len(),
            MAX_PAIRING_ALIAS_LEN
        );
    }
}
