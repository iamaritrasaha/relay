//! JSON DTOs for the Relay proof challenge and opaque proof response.

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::crypto::relay_identity_proof::{RelayIdentityProofV1, PROOF_LEN};
use crate::util::base64;

const RELAY_DTO_VERSION: u8 = 1;
const NONCE_LEN: usize = 32;

/// Version 1 Relay proof challenge.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayChallengeV1Dto {
    version: u8,
    nonce: [u8; NONCE_LEN],
}

impl RelayChallengeV1Dto {
    pub fn new(nonce: [u8; NONCE_LEN]) -> Self {
        Self {
            version: RELAY_DTO_VERSION,
            nonce,
        }
    }

    pub fn version(&self) -> u8 {
        self.version
    }

    pub fn nonce(&self) -> &[u8; NONCE_LEN] {
        &self.nonce
    }
}

impl Serialize for RelayChallengeV1Dto {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        #[derive(Serialize)]
        struct Wire<'a> {
            version: u8,
            nonce: &'a str,
        }

        let nonce = base64::encode(self.nonce);
        Wire {
            version: RELAY_DTO_VERSION,
            nonce: &nonce,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for RelayChallengeV1Dto {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct Wire {
            version: u8,
            nonce: String,
        }

        let wire = Wire::deserialize(deserializer)?;
        if wire.version != RELAY_DTO_VERSION {
            return Err(serde::de::Error::custom(
                "unsupported Relay challenge version",
            ));
        }
        let nonce = base64::decode(&wire.nonce)
            .map_err(|_| serde::de::Error::custom("invalid Relay challenge nonce base64"))?;
        let nonce: [u8; NONCE_LEN] = nonce
            .try_into()
            .map_err(|_| serde::de::Error::custom("invalid Relay challenge nonce length"))?;
        Ok(Self::new(nonce))
    }
}

/// Opaque version 1 Relay identity proof response.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayProofV1Dto {
    proof: RelayIdentityProofV1,
}

impl RelayProofV1Dto {
    pub fn new(proof: RelayIdentityProofV1) -> Self {
        Self { proof }
    }

    pub fn proof(&self) -> &RelayIdentityProofV1 {
        &self.proof
    }
}

impl Serialize for RelayProofV1Dto {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        #[derive(Serialize)]
        struct Wire<'a> {
            proof: &'a str,
        }

        let proof = base64::encode(self.proof.encode());
        Wire { proof: &proof }.serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for RelayProofV1Dto {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct Wire {
            proof: String,
        }

        let wire = Wire::deserialize(deserializer)?;
        let proof = base64::decode(&wire.proof)
            .map_err(|_| serde::de::Error::custom("invalid Relay proof base64"))?;
        if proof.len() != PROOF_LEN {
            return Err(serde::de::Error::custom("invalid Relay proof length"));
        }
        let proof = RelayIdentityProofV1::decode(&proof)
            .map_err(|_| serde::de::Error::custom("invalid Relay identity proof"))?;
        Ok(Self::new(proof))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::crypto::relay_identity_proof::{create_relay_identity_proof, RelayProofRole};

    fn proof() -> RelayIdentityProofV1 {
        create_relay_identity_proof(
            &RelayIdentity::generate(),
            RelayProofRole::Server,
            [0x33; 32],
            [0x44; 32],
        )
        .unwrap()
    }

    #[test]
    fn challenge_dto_round_trips_version_and_nonce() {
        let dto = RelayChallengeV1Dto::new([0x11; 32]);
        let encoded = serde_json::to_string(&dto).unwrap();
        let decoded: RelayChallengeV1Dto = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded.version(), 1);
        assert_eq!(decoded.nonce(), &[0x11; 32]);
        assert_eq!(
            encoded,
            format!(
                r#"{{"version":1,"nonce":"{}"}}"#,
                base64::encode([0x11; 32])
            )
        );
    }

    #[test]
    fn challenge_dto_rejects_invalid_version_lengths_and_base64() {
        for nonce in [
            base64::encode([0x01; 31]),
            base64::encode([0x01; 33]),
            "%%%".to_owned(),
        ] {
            let json = format!(r#"{{"version":1,"nonce":"{nonce}"}}"#);
            assert!(serde_json::from_str::<RelayChallengeV1Dto>(&json).is_err());
        }
        assert!(serde_json::from_str::<RelayChallengeV1Dto>(
            r#"{"version":2,"nonce":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"#
        )
        .is_err());
    }

    #[test]
    fn proof_dto_round_trips_the_exact_opaque_proof() {
        let proof = proof();
        let dto = RelayProofV1Dto::new(proof.clone());
        let encoded = serde_json::to_string(&dto).unwrap();
        let decoded: RelayProofV1Dto = serde_json::from_str(&encoded).unwrap();

        assert_eq!(decoded.proof(), &proof);
        assert_eq!(
            encoded,
            format!(r#"{{"proof":"{}"}}"#, base64::encode(proof.encode()))
        );
    }

    #[test]
    fn proof_dto_rejects_invalid_lengths_base64_and_proof_version() {
        for encoded in [
            base64::encode([0x01; 129]),
            base64::encode([0x01; 131]),
            "%%%".to_owned(),
        ] {
            let json = format!(r#"{{"proof":"{encoded}"}}"#);
            assert!(serde_json::from_str::<RelayProofV1Dto>(&json).is_err());
        }

        let mut unsupported_version = proof().encode();
        unsupported_version[0] = 2;
        let json = format!(r#"{{"proof":"{}"}}"#, base64::encode(unsupported_version));
        assert!(serde_json::from_str::<RelayProofV1Dto>(&json).is_err());

        let mut unsupported_role = proof().encode();
        unsupported_role[1] = 3;
        let json = format!(r#"{{"proof":"{}"}}"#, base64::encode(unsupported_role));
        assert!(serde_json::from_str::<RelayProofV1Dto>(&json).is_err());
    }
}
