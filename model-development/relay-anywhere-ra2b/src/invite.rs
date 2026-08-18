//! RA2B development invite.
//!
//! **RA2B invite = test convenience / addressing package.**
//! It is **not** production trust architecture, pairing, or a favorite.
//! Transferring this string (copy/paste or QR) is the explicit development
//! test action that tells Join which host RelayId and Iroh endpoint to use.

use anyhow::{Context as _, Result, bail, ensure};
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use iroh::EndpointAddr;
use serde::{Deserialize, Serialize};

use crate::endpoint_codec::{decode_endpoint_addr, encode_endpoint_addr};

/// Visible version token. Join rejects any other prefix.
pub const INVITE_PREFIX: &str = "RA2B1.";
pub const INVITE_VERSION: u32 = 1;
/// Hard cap so a pasted blob cannot blow memory or QR buffers.
pub const MAX_INVITE_LEN: usize = 16 * 1024;
const CAPABILITY: &str = "ra2b-dev-proof-1mib";

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
struct Ra2bInviteV1Wire {
    v: u32,
    #[serde(rename = "hostRelayId")]
    host_relay_id: String,
    endpoint: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cap: Option<String>,
}

/// Development-only host invite. Not a production pairing document.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Ra2bInviteV1 {
    pub version: u32,
    pub host_relay_id: String,
    pub endpoint: EndpointAddr,
    pub capability: Option<String>,
}

impl Ra2bInviteV1 {
    pub fn new(host_relay_id: String, endpoint: EndpointAddr) -> Result<Self> {
        validate_relay_id(&host_relay_id)?;
        Ok(Self {
            version: INVITE_VERSION,
            host_relay_id,
            endpoint,
            capability: Some(CAPABILITY.to_owned()),
        })
    }

    pub fn encode(&self) -> Result<String> {
        ensure!(self.version == INVITE_VERSION, "unsupported invite version");
        validate_relay_id(&self.host_relay_id)?;
        let endpoint = serde_json::from_str(&encode_endpoint_addr(&self.endpoint)?)
            .context("endpoint descriptor is not JSON")?;
        let wire = Ra2bInviteV1Wire {
            v: self.version,
            host_relay_id: self.host_relay_id.clone(),
            endpoint,
            cap: self.capability.clone(),
        };
        let json = serde_json::to_vec(&wire).context("encode RA2B invite")?;
        let encoded = format!("{INVITE_PREFIX}{}", URL_SAFE_NO_PAD.encode(json));
        ensure!(
            encoded.len() <= MAX_INVITE_LEN,
            "invite exceeds {MAX_INVITE_LEN} bytes"
        );
        Ok(encoded)
    }

    pub fn decode(raw: &str) -> Result<Self> {
        parse_invite(raw)
    }
}

pub fn parse_invite(raw: &str) -> Result<Ra2bInviteV1> {
    let trimmed = raw.trim();
    ensure!(!trimmed.is_empty(), "invite is empty");
    ensure!(
        trimmed.len() <= MAX_INVITE_LEN,
        "invite exceeds {MAX_INVITE_LEN} bytes"
    );
    let Some(payload) = trimmed.strip_prefix(INVITE_PREFIX) else {
        if trimmed.starts_with("RA2B") {
            bail!("unsupported invite version");
        }
        bail!("malformed invite: missing RA2B1 prefix");
    };
    let json = URL_SAFE_NO_PAD
        .decode(payload.as_bytes())
        .context("malformed invite: invalid encoding")?;
    let wire: Ra2bInviteV1Wire =
        serde_json::from_slice(&json).context("malformed invite: invalid descriptor")?;
    if wire.v != INVITE_VERSION {
        bail!("unsupported invite version");
    }
    validate_relay_id(&wire.host_relay_id)?;
    if wire.endpoint.is_null() {
        bail!("malformed invite: missing endpoint");
    }
    let endpoint_json =
        serde_json::to_string(&wire.endpoint).context("malformed invite: endpoint")?;
    let endpoint = decode_endpoint_addr(&endpoint_json)?;
    Ok(Ra2bInviteV1 {
        version: wire.v,
        host_relay_id: wire.host_relay_id,
        endpoint,
        capability: wire.cap,
    })
}

pub fn validate_relay_id(relay_id: &str) -> Result<()> {
    ensure!(
        relay_id.len() == 64
            && relay_id
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_lowercase()),
        "invalid RelayId"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use iroh::{EndpointAddr, SecretKey, TransportAddr};

    use super::*;

    fn sample_endpoint() -> EndpointAddr {
        let id = SecretKey::generate().public();
        EndpointAddr::from_parts(id, [TransportAddr::Ip("127.0.0.1:1234".parse().unwrap())])
    }

    fn sample_relay_id() -> String {
        "A".repeat(64)
    }

    #[test]
    fn invite_roundtrip() {
        let invite = Ra2bInviteV1::new(sample_relay_id(), sample_endpoint()).unwrap();
        let encoded = invite.encode().unwrap();
        assert!(encoded.starts_with(INVITE_PREFIX));
        let decoded = parse_invite(&encoded).unwrap();
        assert_eq!(decoded.host_relay_id, invite.host_relay_id);
        assert_eq!(decoded.endpoint, invite.endpoint);
        assert_eq!(decoded.version, INVITE_VERSION);
    }

    #[test]
    fn malformed_invite_rejected() {
        assert!(parse_invite("not-an-invite").is_err());
        assert!(parse_invite("RA2B1.%%%").is_err());
        assert!(
            parse_invite(&format!(
                "{INVITE_PREFIX}{}",
                URL_SAFE_NO_PAD.encode(b"{\"v\":1}")
            ))
            .is_err()
        );
    }

    #[test]
    fn unsupported_version_rejected() {
        let json = serde_json::json!({
            "v": 2,
            "hostRelayId": sample_relay_id(),
            "endpoint": serde_json::from_str::<serde_json::Value>(
                &encode_endpoint_addr(&sample_endpoint()).unwrap()
            ).unwrap(),
        });
        let encoded = format!(
            "{INVITE_PREFIX}{}",
            URL_SAFE_NO_PAD.encode(serde_json::to_vec(&json).unwrap())
        );
        let err = parse_invite(&encoded).unwrap_err().to_string();
        assert!(err.contains("unsupported invite version"));
        assert!(
            parse_invite("RA2B9.abc")
                .unwrap_err()
                .to_string()
                .contains("unsupported")
        );
    }

    #[test]
    fn invalid_relay_id_rejected() {
        let json = serde_json::json!({
            "v": 1,
            "hostRelayId": "not-a-relay-id",
            "endpoint": serde_json::from_str::<serde_json::Value>(
                &encode_endpoint_addr(&sample_endpoint()).unwrap()
            ).unwrap(),
        });
        let encoded = format!(
            "{INVITE_PREFIX}{}",
            URL_SAFE_NO_PAD.encode(serde_json::to_vec(&json).unwrap())
        );
        let err = parse_invite(&encoded).unwrap_err().to_string();
        assert!(err.contains("invalid RelayId"));
        assert!(Ra2bInviteV1::new("abc".into(), sample_endpoint()).is_err());
        assert!(validate_relay_id(&"a".repeat(64)).is_err());
    }

    #[test]
    fn invite_size_bound() {
        let oversized = format!("{INVITE_PREFIX}{}", "A".repeat(MAX_INVITE_LEN));
        let err = parse_invite(&oversized).unwrap_err().to_string();
        assert!(err.contains("exceeds"));
        assert!(parse_invite("").is_err());
    }

    #[test]
    fn path_class_serialization() {
        assert_eq!(crate::Ra2bPathClass::Direct.as_str(), "DIRECT");
        assert_eq!(crate::Ra2bPathClass::Relay.as_str(), "RELAY");
    }
}
