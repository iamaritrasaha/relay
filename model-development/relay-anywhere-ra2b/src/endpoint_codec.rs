use anyhow::{Context as _, Result};
use iroh::EndpointAddr;

pub fn encode_endpoint_addr(addr: &EndpointAddr) -> Result<String> {
    serde_json::to_string(addr).context("encode Iroh endpoint descriptor")
}

pub fn decode_endpoint_addr(encoded: &str) -> Result<EndpointAddr> {
    serde_json::from_str(encoded).context("decode Iroh endpoint descriptor JSON")
}

#[cfg(test)]
mod tests {
    use iroh::{EndpointAddr, SecretKey, TransportAddr};

    use super::*;

    #[test]
    fn endpoint_roundtrip_preserves_id_and_addrs() {
        let id = SecretKey::generate().public();
        let original =
            EndpointAddr::from_parts(id, [TransportAddr::Ip("127.0.0.1:1234".parse().unwrap())]);
        let encoded = encode_endpoint_addr(&original).unwrap();
        let decoded = decode_endpoint_addr(&encoded).unwrap();
        assert_eq!(decoded, original);
    }
}
