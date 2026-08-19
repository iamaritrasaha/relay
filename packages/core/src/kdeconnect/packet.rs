//! KDE Connect packet framing (protocol version 8).
//!
//! Packets are one compact JSON object followed by a newline. The body is a
//! JSON object whose field types are validated; unknown types are ignored by
//! callers rather than executed.

use serde_json::{Map, Value};
use std::time::{SystemTime, UNIX_EPOCH};

pub const PACKET_TYPE_IDENTITY: &str = "kdeconnect.identity";
pub const PACKET_TYPE_PAIR: &str = "kdeconnect.pair";
pub const PROTOCOL_VERSION: i64 = 8;

pub const MAX_IDENTITY_PACKET_BYTES: usize = 8192;
pub const MAX_PACKET_BYTES: usize = 8192;

const NAME_INVALID: &[char] = &[
    '"', '\'', ',', ';', ':', '.', '!', '?', '(', ')', '[', ']', '<', '>',
];
const MAX_DEVICE_NAME_LEN: usize = 32;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NetworkPacket {
    pub packet_type: String,
    pub body: Map<String, Value>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdentityBody {
    pub device_id: String,
    pub device_name: String,
    pub device_type: String,
    pub protocol_version: i64,
    pub incoming_capabilities: Vec<String>,
    pub outgoing_capabilities: Vec<String>,
    pub tcp_port: Option<u16>,
    pub target_device_id: Option<String>,
    pub target_protocol_version: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PairBody {
    pub pair: bool,
    pub timestamp: Option<i64>,
}

#[derive(Debug)]
pub struct PacketError(pub String);

impl std::fmt::Display for PacketError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for PacketError {}

impl NetworkPacket {
    pub fn new(packet_type: impl Into<String>, body: Map<String, Value>) -> Self {
        Self {
            packet_type: packet_type.into(),
            body,
        }
    }

    pub fn serialize(&self) -> Vec<u8> {
        let id = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        let mut root = Map::new();
        root.insert("id".into(), Value::Number(id.into()));
        root.insert("type".into(), Value::String(self.packet_type.clone()));
        root.insert("body".into(), Value::Object(self.body.clone()));
        let mut bytes = serde_json::to_vec(&Value::Object(root)).unwrap_or_else(|_| b"{}".to_vec());
        bytes.push(b'\n');
        bytes
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, PacketError> {
        if bytes.len() > MAX_PACKET_BYTES {
            return Err(PacketError("packet exceeds size bound".into()));
        }
        let trimmed = bytes.strip_suffix(&[b'\n']).unwrap_or(bytes);
        let trimmed = trimmed.strip_suffix(&[b'\r']).unwrap_or(trimmed);
        if trimmed.is_empty() {
            return Err(PacketError("empty packet".into()));
        }
        let value: Value = serde_json::from_slice(trimmed)
            .map_err(|e| PacketError(format!("invalid json: {e}")))?;
        let object = value
            .as_object()
            .ok_or_else(|| PacketError("packet is not an object".into()))?;
        let packet_type = object
            .get("type")
            .and_then(Value::as_str)
            .ok_or_else(|| PacketError("missing type".into()))?
            .to_string();
        let body = match object.get("body") {
            Some(Value::Object(map)) => map.clone(),
            Some(_) => return Err(PacketError("body is not an object".into())),
            None => return Err(PacketError("missing body".into())),
        };
        Ok(Self { packet_type, body })
    }

    pub fn as_identity(&self) -> Result<IdentityBody, PacketError> {
        if self.packet_type != PACKET_TYPE_IDENTITY {
            return Err(PacketError("not an identity packet".into()));
        }
        IdentityBody::from_map(&self.body)
    }

    pub fn as_pair(&self) -> Result<PairBody, PacketError> {
        if self.packet_type != PACKET_TYPE_PAIR {
            return Err(PacketError("not a pair packet".into()));
        }
        PairBody::from_map(&self.body)
    }
}

impl IdentityBody {
    pub fn to_packet(&self) -> NetworkPacket {
        let mut body = Map::new();
        body.insert("deviceId".into(), Value::String(self.device_id.clone()));
        body.insert("deviceName".into(), Value::String(self.device_name.clone()));
        body.insert("deviceType".into(), Value::String(self.device_type.clone()));
        body.insert(
            "protocolVersion".into(),
            Value::Number(self.protocol_version.into()),
        );
        body.insert(
            "incomingCapabilities".into(),
            Value::Array(
                self.incoming_capabilities
                    .iter()
                    .cloned()
                    .map(Value::String)
                    .collect(),
            ),
        );
        body.insert(
            "outgoingCapabilities".into(),
            Value::Array(
                self.outgoing_capabilities
                    .iter()
                    .cloned()
                    .map(Value::String)
                    .collect(),
            ),
        );
        if let Some(port) = self.tcp_port {
            body.insert("tcpPort".into(), Value::Number(u64::from(port).into()));
        }
        if let Some(target) = &self.target_device_id {
            body.insert("targetDeviceId".into(), Value::String(target.clone()));
        }
        if let Some(version) = self.target_protocol_version {
            body.insert(
                "targetProtocolVersion".into(),
                Value::Number(version.into()),
            );
        }
        NetworkPacket::new(PACKET_TYPE_IDENTITY, body)
    }

    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let device_id = required_string(body, "deviceId")?;
        if !is_valid_device_id(&device_id) {
            return Err(PacketError("invalid deviceId".into()));
        }
        let raw_name = required_string(body, "deviceName")?;
        let device_name = filter_device_name(&raw_name);
        if device_name.is_empty() {
            return Err(PacketError("invalid deviceName".into()));
        }
        let device_type = optional_string(body, "deviceType").unwrap_or_else(|| "desktop".into());
        let protocol_version = optional_i64(body, "protocolVersion").unwrap_or(-1);
        let incoming_capabilities = optional_string_list(body, "incomingCapabilities");
        let outgoing_capabilities = optional_string_list(body, "outgoingCapabilities");
        let tcp_port = optional_u16(body, "tcpPort")?;
        let target_device_id = optional_string(body, "targetDeviceId");
        let target_protocol_version = optional_i64(body, "targetProtocolVersion");
        Ok(Self {
            device_id,
            device_name,
            device_type,
            protocol_version,
            incoming_capabilities,
            outgoing_capabilities,
            tcp_port,
            target_device_id,
            target_protocol_version,
        })
    }
}

impl PairBody {
    pub fn request(timestamp: i64) -> NetworkPacket {
        let mut body = Map::new();
        body.insert("pair".into(), Value::Bool(true));
        body.insert("timestamp".into(), Value::Number(timestamp.into()));
        NetworkPacket::new(PACKET_TYPE_PAIR, body)
    }

    pub fn accept() -> NetworkPacket {
        let mut body = Map::new();
        body.insert("pair".into(), Value::Bool(true));
        NetworkPacket::new(PACKET_TYPE_PAIR, body)
    }

    pub fn unpair() -> NetworkPacket {
        let mut body = Map::new();
        body.insert("pair".into(), Value::Bool(false));
        NetworkPacket::new(PACKET_TYPE_PAIR, body)
    }

    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let pair = body
            .get("pair")
            .and_then(Value::as_bool)
            .ok_or_else(|| PacketError("pair must be a boolean".into()))?;
        let timestamp = match body.get("timestamp") {
            None => None,
            Some(Value::Number(n)) => n.as_i64(),
            Some(_) => return Err(PacketError("timestamp must be a number".into())),
        };
        Ok(Self { pair, timestamp })
    }
}

pub fn is_valid_device_id(id: &str) -> bool {
    let len = id.len();
    (32..=38).contains(&len)
        && id
            .bytes()
            .all(|b| matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b'-'))
}

pub fn filter_device_name(input: &str) -> String {
    input
        .chars()
        .filter(|c| !NAME_INVALID.contains(c))
        .take(MAX_DEVICE_NAME_LEN)
        .collect::<String>()
        .trim()
        .to_string()
}

fn required_string(body: &Map<String, Value>, key: &str) -> Result<String, PacketError> {
    body.get(key)
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| PacketError(format!("{key} must be a string")))
}

fn optional_string(body: &Map<String, Value>, key: &str) -> Option<String> {
    body.get(key).and_then(Value::as_str).map(str::to_string)
}

fn optional_i64(body: &Map<String, Value>, key: &str) -> Option<i64> {
    body.get(key).and_then(Value::as_i64)
}

fn optional_u16(body: &Map<String, Value>, key: &str) -> Result<Option<u16>, PacketError> {
    match body.get(key) {
        None => Ok(None),
        Some(Value::Number(n)) => {
            let value = n
                .as_u64()
                .ok_or_else(|| PacketError("tcpPort must be a number".into()))?;
            u16::try_from(value)
                .map(Some)
                .map_err(|_| PacketError("tcpPort out of range".into()))
        }
        Some(_) => Err(PacketError("tcpPort must be a number".into())),
    }
}

fn optional_string_list(body: &Map<String, Value>, key: &str) -> Vec<String> {
    match body.get(key) {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity() -> IdentityBody {
        IdentityBody {
            device_id: "a".repeat(32),
            device_name: "Pixel 8".into(),
            device_type: "phone".into(),
            protocol_version: PROTOCOL_VERSION,
            incoming_capabilities: vec![],
            outgoing_capabilities: vec![],
            tcp_port: Some(1716),
            target_device_id: None,
            target_protocol_version: None,
        }
    }

    #[test]
    fn identity_roundtrip() {
        let packet = identity().to_packet();
        let parsed = NetworkPacket::parse(&packet.serialize())
            .unwrap()
            .as_identity()
            .unwrap();
        assert_eq!(parsed.device_id, identity().device_id);
        assert_eq!(parsed.device_name, "Pixel 8");
        assert_eq!(parsed.tcp_port, Some(1716));
        assert_eq!(parsed.protocol_version, PROTOCOL_VERSION);
    }

    #[test]
    fn malformed_identity_rejected() {
        assert!(NetworkPacket::parse(b"not json\n").is_err());
        assert!(NetworkPacket::parse(br#"{"type":"kdeconnect.identity","body":"nope"}"#).is_err());
        let mut bad = identity();
        bad.device_id = "short".into();
        assert!(NetworkPacket::parse(&bad.to_packet().serialize())
            .unwrap()
            .as_identity()
            .is_err());
        let localsend = br#"{"alias":"Phone","version":"2.1","deviceType":"mobile","fingerprint":"ABCD","port":53317,"protocol":"https"}"#;
        assert!(NetworkPacket::parse(localsend)
            .ok()
            .and_then(|p| p.as_identity().ok())
            .is_none());
    }

    #[test]
    fn pair_request_serializes_timestamp() {
        let packet = PairBody::request(1_700_000_000);
        let parsed = NetworkPacket::parse(&packet.serialize())
            .unwrap()
            .as_pair()
            .unwrap();
        assert!(parsed.pair);
        assert_eq!(parsed.timestamp, Some(1_700_000_000));
    }

    #[test]
    fn pair_reject_and_unpair_are_pair_false() {
        let parsed = NetworkPacket::parse(&PairBody::unpair().serialize())
            .unwrap()
            .as_pair()
            .unwrap();
        assert!(!parsed.pair);
        assert_eq!(parsed.timestamp, None);
    }

    #[test]
    fn identity_serializes_compact_json_newline() {
        let bytes = identity().to_packet().serialize();
        assert_eq!(*bytes.last().unwrap(), b'\n');
        assert!(std::str::from_utf8(&bytes).unwrap().starts_with('{'));
    }
}
