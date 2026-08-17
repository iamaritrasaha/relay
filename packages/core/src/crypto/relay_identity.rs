use ed25519_dalek::pkcs8::spki::der::pem::LineEnding;
use ed25519_dalek::pkcs8::spki::der::zeroize::Zeroizing;
use ed25519_dalek::pkcs8::{DecodePrivateKey, DecodePublicKey, EncodePrivateKey, EncodePublicKey};
use ed25519_dalek::{SigningKey, VerifyingKey};

use crate::crypto::hash;

/// Relay's long-term device identity: an Ed25519 key pair, independent of
/// the TLS certificate used for transport (see `crypto::cert`).
///
/// This is the cryptographic core only. Persistence, TLS binding and
/// proof-of-possession are handled by later phases; this type is a plain
/// in-memory value.
pub struct RelayIdentity {
    signing_key: SigningKey,
}

impl RelayIdentity {
    /// Generates a new random Relay identity.
    pub fn generate() -> Self {
        let mut csprng = rand::rng();
        Self {
            signing_key: SigningKey::generate(&mut csprng),
        }
    }

    /// Reconstructs a Relay identity from a PKCS#8 PEM-encoded private key,
    /// as produced by [`RelayIdentity::private_key_export`].
    pub fn from_private_key(private_key_pem: &str) -> anyhow::Result<Self> {
        let signing_key = SigningKey::from_pkcs8_pem(private_key_pem)?;
        Ok(Self { signing_key })
    }

    /// The public key of this identity.
    pub fn public_key(&self) -> VerifyingKey {
        self.signing_key.verifying_key()
    }

    /// Exports the private key as PKCS#8 PEM. The returned buffer is
    /// zeroized on drop.
    pub fn private_key_export(&self) -> anyhow::Result<Zeroizing<String>> {
        let pem = self.signing_key.to_pkcs8_pem(LineEnding::LF)?;
        Ok(pem)
    }

    /// Exports the public key as SPKI PEM.
    pub fn public_key_export(&self) -> anyhow::Result<String> {
        let pem = self.public_key().to_public_key_pem(LineEnding::LF)?;
        Ok(pem)
    }

    /// The RelayId of this identity. See [`relay_id_from_public_key`].
    pub fn relay_id(&self) -> anyhow::Result<String> {
        relay_id_from_public_key(&self.public_key())
    }
}

/// Derives the RelayId of a public key: the SHA-256 hash of its canonical
/// SPKI DER encoding, encoded as uppercase hex (64 characters).
///
/// The DER encoding (not the PEM text) is hashed so that PEM whitespace or
/// line-wrapping differences never change the resulting id, and so that a
/// public key parsed from any valid encoding of the same key always yields
/// the same RelayId.
pub fn relay_id_from_public_key(public_key: &VerifyingKey) -> anyhow::Result<String> {
    let der = public_key.to_public_key_der()?;
    Ok(relay_id_from_public_key_der(der.as_bytes()))
}

/// Derives the RelayId directly from a public key's canonical SPKI DER bytes.
fn relay_id_from_public_key_der(public_key_der: &[u8]) -> String {
    hash::sha256(public_key_der)
        .iter()
        .map(|byte| format!("{byte:02X}"))
        .collect()
}

/// Parses a public key from SPKI PEM, as produced by
/// [`RelayIdentity::public_key_export`].
pub fn parse_public_key(public_key_pem: &str) -> anyhow::Result<VerifyingKey> {
    Ok(VerifyingKey::from_public_key_pem(public_key_pem)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, Verifier};

    #[test]
    fn test_generate_produces_valid_identity() {
        let identity = RelayIdentity::generate();

        // A valid Ed25519 keypair can sign and verify.
        let message = b"relay identity self-test";
        let signature = identity.signing_key.sign(message);
        assert!(identity.public_key().verify(message, &signature).is_ok());

        let relay_id = identity.relay_id().unwrap();
        assert_eq!(relay_id.len(), 64);
        assert!(relay_id.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_lowercase()));
    }

    #[test]
    fn test_relay_id_is_deterministic_for_same_public_key() {
        let identity = RelayIdentity::generate();

        let id_a = identity.relay_id().unwrap();
        let id_b = relay_id_from_public_key(&identity.public_key()).unwrap();

        assert_eq!(id_a, id_b);
    }

    #[test]
    fn test_private_key_round_trip_preserves_public_key_and_relay_id() {
        let identity = RelayIdentity::generate();
        let relay_id_before = identity.relay_id().unwrap();
        let public_key_before = identity.public_key();

        let exported = identity.private_key_export().unwrap();
        let reloaded = RelayIdentity::from_private_key(&exported).unwrap();

        assert_eq!(reloaded.public_key(), public_key_before);
        assert_eq!(reloaded.relay_id().unwrap(), relay_id_before);
    }

    #[test]
    fn test_public_key_export_round_trip_identifies_same_key() {
        let identity = RelayIdentity::generate();

        let exported_pem = identity.public_key_export().unwrap();
        let parsed = parse_public_key(&exported_pem).unwrap();

        assert_eq!(parsed, identity.public_key());
        assert_eq!(
            relay_id_from_public_key(&parsed).unwrap(),
            identity.relay_id().unwrap()
        );
    }

    #[test]
    fn test_generated_identities_are_distinct() {
        let a = RelayIdentity::generate();
        let b = RelayIdentity::generate();

        assert_ne!(a.public_key(), b.public_key());
        assert_ne!(a.relay_id().unwrap(), b.relay_id().unwrap());
    }

    #[test]
    fn test_relay_id_is_derived_from_der_not_pem_text() {
        let identity = RelayIdentity::generate();
        let der = identity.public_key().to_public_key_der().unwrap();

        // Directly hashing the DER bytes must match the identity's own
        // computation, independent of how the PEM text happens to be
        // formatted (line endings, wrapping, surrounding whitespace).
        let expected = relay_id_from_public_key_der(der.as_bytes());
        assert_eq!(identity.relay_id().unwrap(), expected);

        // Re-parsing from a PEM string with different incidental
        // whitespace (CRLF line endings instead of LF) still yields the
        // same RelayId, since only the DER bytes are hashed.
        let pem = identity.public_key_export().unwrap();
        let pem_with_crlf = pem.replace('\n', "\r\n");
        let reparsed = parse_public_key(&pem_with_crlf).unwrap();
        assert_eq!(
            relay_id_from_public_key(&reparsed).unwrap(),
            identity.relay_id().unwrap()
        );
    }
}
