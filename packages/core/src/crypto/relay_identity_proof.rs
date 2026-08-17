//! Relay identity proof-of-possession primitive.
//!
//! Challenge storage, expiry, and single-use consumption are deliberately
//! outside this module. Integration must decode a proof, look up and consume
//! `proof.nonce`, then call [`verify_relay_identity_proof`].

use anyhow::bail;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};

use super::relay_identity::{
    relay_id_digest_from_public_key, relay_id_from_public_key, RelayIdentity,
};

/// Domain separator for Relay identity proof version 1.
pub const DOMAIN_SEPARATOR: &[u8; 20] = b"RelayIdentityProofV1";
/// Version emitted and accepted by this proof format.
pub const VERSION: u8 = 0x01;
pub const TRANSCRIPT_LEN: usize = 121;
pub const PROOF_LEN: usize = 130;

const NONCE_LEN: u8 = 32;
const RELAY_ID_DIGEST_LEN: u8 = 32;
const TLS_FINGERPRINT_LEN: u8 = 32;

/// The direction in which a proof is made. It is part of the signed transcript.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum RelayProofRole {
    Server = 0x01,
    Client = 0x02,
}

impl TryFrom<u8> for RelayProofRole {
    type Error = anyhow::Error;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0x01 => Ok(Self::Server),
            0x02 => Ok(Self::Client),
            _ => bail!("unsupported Relay identity proof role"),
        }
    }
}

/// Fixed-size version 1 Relay identity proof.
///
/// `public_key` contains raw 32-byte Ed25519 verifying-key bytes and
/// `signature` contains a raw 64-byte Ed25519 signature. The nonce is carried
/// by the proof so callers cannot supply a divergent verifier nonce.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayIdentityProofV1 {
    pub version: u8,
    pub role: RelayProofRole,
    pub nonce: [u8; 32],
    pub public_key: [u8; 32],
    pub signature: [u8; 64],
}

impl RelayIdentityProofV1 {
    /// Encodes this proof as exactly `VERSION | ROLE | NONCE | PUBLIC_KEY | SIGNATURE`.
    pub fn encode(&self) -> [u8; PROOF_LEN] {
        let mut encoded = [0_u8; PROOF_LEN];
        encoded[0] = self.version;
        encoded[1] = self.role as u8;
        encoded[2..34].copy_from_slice(&self.nonce);
        encoded[34..66].copy_from_slice(&self.public_key);
        encoded[66..130].copy_from_slice(&self.signature);
        encoded
    }

    /// Decodes only the fixed version 1 proof representation.
    pub fn decode(encoded: &[u8]) -> anyhow::Result<Self> {
        if encoded.len() != PROOF_LEN {
            bail!("invalid Relay identity proof length");
        }
        if encoded[0] != VERSION {
            bail!("unsupported Relay identity proof version");
        }

        let role = RelayProofRole::try_from(encoded[1])?;
        let mut nonce = [0_u8; 32];
        let mut public_key = [0_u8; 32];
        let mut signature = [0_u8; 64];
        nonce.copy_from_slice(&encoded[2..34]);
        public_key.copy_from_slice(&encoded[34..66]);
        signature.copy_from_slice(&encoded[66..130]);
        Ok(Self {
            version: VERSION,
            role,
            nonce,
            public_key,
            signature,
        })
    }
}

/// Creates a Relay identity proof over the supplied TLS certificate fingerprint.
///
/// This is an internal crypto primitive. Transport code must obtain the
/// fingerprint from Rust-owned TLS context, never from a peer claim.
pub fn create_relay_identity_proof(
    identity: &RelayIdentity,
    role: RelayProofRole,
    nonce: [u8; 32],
    trusted_tls_fingerprint: [u8; 32],
) -> anyhow::Result<RelayIdentityProofV1> {
    let public_key = identity.public_key();
    let relay_id_digest = relay_id_digest_from_public_key(&public_key)?;
    let transcript = build_transcript(role, nonce, relay_id_digest, trusted_tls_fingerprint);
    let signature = identity.sign(&transcript).to_bytes();

    Ok(RelayIdentityProofV1 {
        version: VERSION,
        role,
        nonce,
        public_key: public_key.to_bytes(),
        signature,
    })
}

/// Verifies a Relay identity proof and returns the canonical uppercase RelayId.
///
/// Challenge ownership is intentionally external: callers must consume the
/// single-use challenge identified by `proof.nonce` before calling this.
pub fn verify_relay_identity_proof(
    proof: &RelayIdentityProofV1,
    expected_role: RelayProofRole,
    observed_tls_fingerprint: [u8; 32],
) -> anyhow::Result<String> {
    if proof.version != VERSION {
        bail!("unsupported Relay identity proof version");
    }
    if proof.role != expected_role {
        bail!("unexpected Relay identity proof role");
    }

    let public_key = VerifyingKey::from_bytes(&proof.public_key)
        .map_err(|_| anyhow::anyhow!("invalid Relay identity proof public key"))?;
    let relay_id_digest = relay_id_digest_from_public_key(&public_key)?;
    let transcript = build_transcript(
        proof.role,
        proof.nonce,
        relay_id_digest,
        observed_tls_fingerprint,
    );
    let signature = Signature::from_bytes(&proof.signature);
    public_key
        .verify(&transcript, &signature)
        .map_err(|_| anyhow::anyhow!("invalid Relay identity proof signature"))?;
    relay_id_from_public_key(&public_key)
}

fn build_transcript(
    role: RelayProofRole,
    nonce: [u8; 32],
    relay_id_digest: [u8; 32],
    tls_fingerprint: [u8; 32],
) -> [u8; TRANSCRIPT_LEN] {
    let mut transcript = [0_u8; TRANSCRIPT_LEN];
    transcript[0..20].copy_from_slice(DOMAIN_SEPARATOR);
    transcript[20] = VERSION;
    transcript[21] = role as u8;
    transcript[22] = NONCE_LEN;
    transcript[23..55].copy_from_slice(&nonce);
    transcript[55] = RELAY_ID_DIGEST_LEN;
    transcript[56..88].copy_from_slice(&relay_id_digest);
    transcript[88] = TLS_FINGERPRINT_LEN;
    transcript[89..121].copy_from_slice(&tls_fingerprint);
    transcript
}

#[cfg(test)]
mod tests {
    use ed25519_dalek::Verifier;

    use super::*;
    use crate::crypto::{hash, relay_identity::RelayIdentity};
    use ed25519_dalek::pkcs8::EncodePublicKey;

    const NONCE: [u8; 32] = [0x11; 32];
    const TLS_FINGERPRINT: [u8; 32] = [0x22; 32];

    fn proof(role: RelayProofRole) -> (RelayIdentity, RelayIdentityProofV1) {
        let identity = RelayIdentity::generate();
        let proof = create_relay_identity_proof(&identity, role, NONCE, TLS_FINGERPRINT).unwrap();
        (identity, proof)
    }

    #[test]
    fn server_proof_verifies_and_returns_identity_relay_id() {
        let (identity, proof) = proof(RelayProofRole::Server);
        assert_eq!(
            verify_relay_identity_proof(&proof, RelayProofRole::Server, TLS_FINGERPRINT).unwrap(),
            identity.relay_id().unwrap()
        );
    }

    #[test]
    fn client_proof_verifies() {
        let (_, proof) = proof(RelayProofRole::Client);
        assert!(
            verify_relay_identity_proof(&proof, RelayProofRole::Client, TLS_FINGERPRINT).is_ok()
        );
    }

    #[test]
    fn wrong_fingerprint_role_nonce_public_key_and_signature_fail() {
        let (_, proof) = proof(RelayProofRole::Server);
        assert!(verify_relay_identity_proof(&proof, RelayProofRole::Server, [0x23; 32]).is_err());
        assert!(
            verify_relay_identity_proof(&proof, RelayProofRole::Client, TLS_FINGERPRINT).is_err()
        );
        let mut changed_nonce = proof.clone();
        changed_nonce.nonce[0] ^= 1;
        assert!(verify_relay_identity_proof(
            &changed_nonce,
            RelayProofRole::Server,
            TLS_FINGERPRINT
        )
        .is_err());
        let mut changed_key = proof.clone();
        changed_key.public_key[0] ^= 1;
        assert!(
            verify_relay_identity_proof(&changed_key, RelayProofRole::Server, TLS_FINGERPRINT)
                .is_err()
        );
        let mut changed_signature = proof;
        changed_signature.signature[0] ^= 1;
        assert!(verify_relay_identity_proof(
            &changed_signature,
            RelayProofRole::Server,
            TLS_FINGERPRINT
        )
        .is_err());
    }

    #[test]
    fn decode_rejects_unknown_version_role_and_wrong_lengths() {
        let (_, proof) = proof(RelayProofRole::Server);
        let mut encoded = proof.encode();
        encoded[0] = 2;
        assert!(RelayIdentityProofV1::decode(&encoded).is_err());
        assert!(verify_relay_identity_proof(
            &RelayIdentityProofV1 {
                version: 2,
                ..proof.clone()
            },
            RelayProofRole::Server,
            TLS_FINGERPRINT
        )
        .is_err());
        let mut encoded = proof.encode();
        encoded[1] = 3;
        assert!(RelayIdentityProofV1::decode(&encoded).is_err());
        assert!(RelayIdentityProofV1::decode(&proof.encode()[..129]).is_err());
        let mut too_long = proof.encode().to_vec();
        too_long.push(0);
        assert!(RelayIdentityProofV1::decode(&too_long).is_err());
    }

    #[test]
    fn transcript_has_frozen_length_domain_and_layout() {
        let digest = [0x33; 32];
        let transcript = build_transcript(RelayProofRole::Client, NONCE, digest, TLS_FINGERPRINT);
        assert_eq!(transcript.len(), 121);
        assert_eq!(&transcript[0..20], DOMAIN_SEPARATOR);
        assert_eq!(transcript[20], VERSION);
        assert_eq!(transcript[21], RelayProofRole::Client as u8);
        assert_eq!(transcript[22], 32);
        assert_eq!(&transcript[23..55], &NONCE);
        assert_eq!(transcript[55], 32);
        assert_eq!(&transcript[56..88], &digest);
        assert_eq!(transcript[88], 32);
        assert_eq!(&transcript[89..121], &TLS_FINGERPRINT);
    }

    #[test]
    fn relay_id_digest_is_canonical_spki_sha256_and_existing_output() {
        let identity = RelayIdentity::generate();
        let der = identity.public_key().to_public_key_der().unwrap();
        let digest = relay_id_digest_from_public_key(&identity.public_key()).unwrap();
        assert_eq!(digest.as_slice(), hash::sha256(der.as_bytes()).as_slice());
        let hex: String = digest.iter().map(|byte| format!("{byte:02X}")).collect();
        assert_eq!(hex, identity.relay_id().unwrap());
    }

    #[test]
    fn proof_encoding_is_fixed_and_round_trips() {
        let (_, proof) = proof(RelayProofRole::Server);
        let encoded = proof.encode();
        assert_eq!(encoded.len(), 130);
        assert_eq!(RelayIdentityProofV1::decode(&encoded).unwrap(), proof);
    }

    #[test]
    fn identical_inputs_are_deterministic_and_each_bound_input_changes_signature() {
        let identity = RelayIdentity::generate();
        let original =
            create_relay_identity_proof(&identity, RelayProofRole::Server, NONCE, TLS_FINGERPRINT)
                .unwrap();
        let relay_id_digest = relay_id_digest_from_public_key(&identity.public_key()).unwrap();
        let original_transcript = build_transcript(
            RelayProofRole::Server,
            NONCE,
            relay_id_digest,
            TLS_FINGERPRINT,
        );
        assert_eq!(
            original.signature,
            create_relay_identity_proof(&identity, RelayProofRole::Server, NONCE, TLS_FINGERPRINT)
                .unwrap()
                .signature
        );
        assert_ne!(
            original.signature,
            create_relay_identity_proof(
                &identity,
                RelayProofRole::Server,
                [0x12; 32],
                TLS_FINGERPRINT
            )
            .unwrap()
            .signature
        );
        assert_ne!(
            original.signature,
            create_relay_identity_proof(&identity, RelayProofRole::Client, NONCE, TLS_FINGERPRINT)
                .unwrap()
                .signature
        );
        assert_ne!(
            original.signature,
            create_relay_identity_proof(&identity, RelayProofRole::Server, NONCE, [0x23; 32])
                .unwrap()
                .signature
        );
        assert_ne!(
            original_transcript,
            build_transcript(
                RelayProofRole::Server,
                [0x12; 32],
                relay_id_digest,
                TLS_FINGERPRINT,
            )
        );
        assert_ne!(
            original_transcript,
            build_transcript(
                RelayProofRole::Client,
                NONCE,
                relay_id_digest,
                TLS_FINGERPRINT,
            )
        );
        assert_ne!(
            original_transcript,
            build_transcript(RelayProofRole::Server, NONCE, relay_id_digest, [0x23; 32],)
        );
    }

    #[test]
    fn signature_does_not_verify_for_another_domain() {
        let (_, proof) = proof(RelayProofRole::Server);
        let public_key = VerifyingKey::from_bytes(&proof.public_key).unwrap();
        let digest = relay_id_digest_from_public_key(&public_key).unwrap();
        let mut transcript = build_transcript(proof.role, proof.nonce, digest, TLS_FINGERPRINT);
        transcript[0..20].copy_from_slice(b"RelayPairingProofV1!");
        assert!(public_key
            .verify(&transcript, &Signature::from_bytes(&proof.signature))
            .is_err());
    }
}
