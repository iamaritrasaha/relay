//! Production Anywhere addressing.
//!
//! An address bundle carries **routing** (Iroh endpoint) plus a **claimed**
//! RelayId. The claim exists so the initiator knows which identity to demand;
//! it is never evidence of identity or of trust. Only the mutual
//! `RelayIdentityProofV1` exchange proves who the peer is, and only a user
//! decision creates trust.
//!
//! There is no account, directory, or presence service behind this type: an
//! address is transferred out of band (QR or link) by the user.

use anyhow::{bail, ensure, Context as _, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use iroh::EndpointAddr;
use serde::{Deserialize, Serialize};

/// Visible version token. Any other prefix is rejected.
pub const RELAY_ADDRESS_PREFIX: &str = "RELAY1.";
pub const RELAY_ADDRESS_VERSION: u32 = 1;
/// Hard cap so a pasted or scanned blob cannot exhaust memory.
pub const MAX_RELAY_ADDRESS_LEN: usize = 16 * 1024;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct RelayAddressWire {
    v: u32,
    #[serde(rename = "claimedRelayId")]
    claimed_relay_id: String,
    endpoint: serde_json::Value,
}

/// A routing bundle plus the RelayId its publisher claims to hold.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayAddressV1 {
    pub version: u32,
    /// Claimed only. Must be proven by the session before any trust decision.
    pub claimed_relay_id: String,
    /// Routing material. Never identity.
    pub endpoint: EndpointAddr,
}

impl RelayAddressV1 {
    pub fn new(claimed_relay_id: String, endpoint: EndpointAddr) -> Result<Self> {
        validate_relay_id(&claimed_relay_id)?;
        Ok(Self {
            version: RELAY_ADDRESS_VERSION,
            claimed_relay_id,
            endpoint,
        })
    }

    pub fn encode(&self) -> Result<String> {
        ensure!(
            self.version == RELAY_ADDRESS_VERSION,
            "unsupported Relay address version"
        );
        validate_relay_id(&self.claimed_relay_id)?;
        let endpoint = serde_json::to_value(&self.endpoint)
            .context("encode Iroh endpoint routing descriptor")?;
        let wire = RelayAddressWire {
            v: self.version,
            claimed_relay_id: self.claimed_relay_id.clone(),
            endpoint,
        };
        let json = serde_json::to_vec(&wire).context("encode Relay address")?;
        let encoded = format!("{RELAY_ADDRESS_PREFIX}{}", URL_SAFE_NO_PAD.encode(json));
        ensure!(
            encoded.len() <= MAX_RELAY_ADDRESS_LEN,
            "Relay address exceeds {MAX_RELAY_ADDRESS_LEN} bytes"
        );
        Ok(encoded)
    }

    pub fn decode(raw: &str) -> Result<Self> {
        parse_relay_address(raw)
    }
}

pub fn parse_relay_address(raw: &str) -> Result<RelayAddressV1> {
    let trimmed = raw.trim();
    ensure!(!trimmed.is_empty(), "Relay address is empty");
    ensure!(
        trimmed.len() <= MAX_RELAY_ADDRESS_LEN,
        "Relay address exceeds {MAX_RELAY_ADDRESS_LEN} bytes"
    );
    let Some(payload) = trimmed.strip_prefix(RELAY_ADDRESS_PREFIX) else {
        if trimmed.starts_with("RELAY") {
            bail!("unsupported Relay address version");
        }
        bail!("malformed Relay address: missing RELAY1 prefix");
    };
    let json = URL_SAFE_NO_PAD
        .decode(payload)
        .context("Relay address payload is not base64url")?;
    let wire: RelayAddressWire =
        serde_json::from_slice(&json).context("Relay address payload is not valid JSON")?;
    ensure!(
        wire.v == RELAY_ADDRESS_VERSION,
        "unsupported Relay address version"
    );
    validate_relay_id(&wire.claimed_relay_id)?;
    let endpoint: EndpointAddr = serde_json::from_value(wire.endpoint)
        .context("Relay address has no usable Iroh endpoint")?;
    Ok(RelayAddressV1 {
        version: wire.v,
        claimed_relay_id: wire.claimed_relay_id,
        endpoint,
    })
}

pub fn validate_relay_id(relay_id: &str) -> Result<()> {
    ensure!(
        relay_id.len() == 64
            && relay_id
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_lowercase()),
        "invalid RelayId"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use iroh::{SecretKey, TransportAddr};

    use super::*;

    fn endpoint() -> EndpointAddr {
        EndpointAddr::from_parts(
            SecretKey::generate().public(),
            [TransportAddr::Ip("127.0.0.1:1234".parse().unwrap())],
        )
    }

    fn relay_id() -> String {
        "A".repeat(64)
    }

    #[test]
    fn roundtrip_preserves_claim_and_routing() {
        let address = RelayAddressV1::new(relay_id(), endpoint()).unwrap();
        let decoded = RelayAddressV1::decode(&address.encode().unwrap()).unwrap();
        assert_eq!(decoded, address);
    }

    #[test]
    fn foreign_prefix_and_bad_relay_id_are_rejected() {
        assert!(parse_relay_address("RA2B1.abcd").is_err());
        assert!(parse_relay_address("RELAY9.abcd").is_err());
        assert!(RelayAddressV1::new("aaaa".to_owned(), endpoint()).is_err());
        assert!(RelayAddressV1::new("a".repeat(64), endpoint()).is_err());
    }

    #[test]
    fn oversized_address_is_rejected() {
        let oversized = format!(
            "{RELAY_ADDRESS_PREFIX}{}",
            "A".repeat(MAX_RELAY_ADDRESS_LEN)
        );
        assert!(parse_relay_address(&oversized).is_err());
    }
}
