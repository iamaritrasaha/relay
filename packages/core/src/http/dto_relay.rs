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

/// Version 1 LAN pairing challenge request.
///
/// `client_nonce` is the nonce the initiator already used for the Server-role
/// proof. It is echoed here only so both devices can fold the same transcript
/// into the displayed verification code; it authenticates nothing on its own.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayPairChallengeRequestV1Dto {
    version: u8,
    client_nonce: [u8; NONCE_LEN],
}

impl RelayPairChallengeRequestV1Dto {
    pub fn new(client_nonce: [u8; NONCE_LEN]) -> Self {
        Self {
            version: RELAY_DTO_VERSION,
            client_nonce,
        }
    }

    pub fn version(&self) -> u8 {
        self.version
    }

    pub fn client_nonce(&self) -> &[u8; NONCE_LEN] {
        &self.client_nonce
    }
}

impl Serialize for RelayPairChallengeRequestV1Dto {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Wire<'a> {
            version: u8,
            client_nonce: &'a str,
        }

        let client_nonce = base64::encode(self.client_nonce);
        Wire {
            version: RELAY_DTO_VERSION,
            client_nonce: &client_nonce,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for RelayPairChallengeRequestV1Dto {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Wire {
            version: u8,
            client_nonce: String,
        }

        let wire = Wire::deserialize(deserializer)?;
        Ok(Self::new(decode_nonce::<D>(
            wire.version,
            &wire.client_nonce,
        )?))
    }
}

/// Version 1 LAN pairing challenge response: the responder's single-use nonce.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayPairChallengeResponseV1Dto {
    version: u8,
    server_nonce: [u8; NONCE_LEN],
}

impl RelayPairChallengeResponseV1Dto {
    pub fn new(server_nonce: [u8; NONCE_LEN]) -> Self {
        Self {
            version: RELAY_DTO_VERSION,
            server_nonce,
        }
    }

    pub fn server_nonce(&self) -> &[u8; NONCE_LEN] {
        &self.server_nonce
    }
}

impl Serialize for RelayPairChallengeResponseV1Dto {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Wire<'a> {
            version: u8,
            server_nonce: &'a str,
        }

        let server_nonce = base64::encode(self.server_nonce);
        Wire {
            version: RELAY_DTO_VERSION,
            server_nonce: &server_nonce,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for RelayPairChallengeResponseV1Dto {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Wire {
            version: u8,
            server_nonce: String,
        }

        let wire = Wire::deserialize(deserializer)?;
        Ok(Self::new(decode_nonce::<D>(
            wire.version,
            &wire.server_nonce,
        )?))
    }
}

/// Version 1 LAN pairing completion: the initiator's Client-role proof.
///
/// `alias` is untrusted display text shown in the responder's prompt. It is
/// never an identity and never keys anything.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayPairCompleteRequestV1Dto {
    version: u8,
    proof: RelayIdentityProofV1,
    alias: String,
}

impl RelayPairCompleteRequestV1Dto {
    pub fn new(proof: RelayIdentityProofV1, alias: impl Into<String>) -> Self {
        Self {
            version: RELAY_DTO_VERSION,
            proof,
            alias: alias.into(),
        }
    }

    pub fn proof(&self) -> &RelayIdentityProofV1 {
        &self.proof
    }

    pub fn alias(&self) -> &str {
        &self.alias
    }
}

impl Serialize for RelayPairCompleteRequestV1Dto {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        #[derive(Serialize)]
        struct Wire<'a> {
            version: u8,
            proof: &'a str,
            alias: &'a str,
        }

        let proof = base64::encode(self.proof.encode());
        Wire {
            version: RELAY_DTO_VERSION,
            proof: &proof,
            alias: &self.alias,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for RelayPairCompleteRequestV1Dto {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct Wire {
            version: u8,
            proof: String,
            #[serde(default)]
            alias: String,
        }

        let wire = Wire::deserialize(deserializer)?;
        if wire.version != RELAY_DTO_VERSION {
            return Err(serde::de::Error::custom(
                "unsupported Relay pairing version",
            ));
        }
        if wire.alias.len() > MAX_PAIRING_ALIAS_WIRE_LEN {
            return Err(serde::de::Error::custom("Relay pairing alias is too long"));
        }
        let proof = base64::decode(&wire.proof)
            .map_err(|_| serde::de::Error::custom("invalid Relay proof base64"))?;
        if proof.len() != PROOF_LEN {
            return Err(serde::de::Error::custom("invalid Relay proof length"));
        }
        let proof = RelayIdentityProofV1::decode(&proof)
            .map_err(|_| serde::de::Error::custom("invalid Relay identity proof"))?;
        Ok(Self::new(proof, wire.alias))
    }
}

/// The remote user's answer to a pairing request.
///
/// Nothing else is returned: the initiator already proved the responder's
/// RelayId through the Server-role proof, so it never needs the peer to tell it
/// who the peer is.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayPairCompleteResponseV1Dto {
    pub version: u8,
    /// `"accepted"` or `"declined"`. Any other value is treated as declined.
    pub decision: String,
    /// The responder's own display alias, for the initiator's device list.
    #[serde(default)]
    pub alias: String,
}

impl RelayPairCompleteResponseV1Dto {
    pub const ACCEPTED: &'static str = "accepted";
    pub const DECLINED: &'static str = "declined";

    pub fn accepted(alias: impl Into<String>) -> Self {
        Self {
            version: RELAY_DTO_VERSION,
            decision: Self::ACCEPTED.to_owned(),
            alias: alias.into(),
        }
    }

    pub fn declined() -> Self {
        Self {
            version: RELAY_DTO_VERSION,
            decision: Self::DECLINED.to_owned(),
            alias: String::new(),
        }
    }

    pub fn is_accepted(&self) -> bool {
        self.version == RELAY_DTO_VERSION && self.decision == Self::ACCEPTED
    }
}

/// Upper bound applied while decoding, before the alias is sanitized for
/// display. It is deliberately larger than the display cap so a legitimate
/// multi-byte alias is not rejected at the wire layer.
const MAX_PAIRING_ALIAS_WIRE_LEN: usize = 256;

fn decode_nonce<'de, D>(version: u8, encoded: &str) -> Result<[u8; NONCE_LEN], D::Error>
where
    D: Deserializer<'de>,
{
    if version != RELAY_DTO_VERSION {
        return Err(serde::de::Error::custom(
            "unsupported Relay pairing version",
        ));
    }
    let nonce = base64::decode(encoded)
        .map_err(|_| serde::de::Error::custom("invalid Relay pairing nonce base64"))?;
    nonce
        .try_into()
        .map_err(|_| serde::de::Error::custom("invalid Relay pairing nonce length"))
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
