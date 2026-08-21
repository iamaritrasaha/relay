//! KDE Connect packet framing (protocol version 8).
//!
//! Packets are one compact JSON object followed by a newline. The body is a
//! JSON object whose field types are validated; unknown types are ignored by
//! callers rather than executed.

use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

pub use super::capabilities::{
    PACKET_TYPE_BATTERY, PACKET_TYPE_CLIPBOARD, PACKET_TYPE_CLIPBOARD_CONNECT,
    PACKET_TYPE_CONNECTIVITY_REPORT, PACKET_TYPE_FINDMYPHONE_REQUEST, PACKET_TYPE_IDENTITY,
    PACKET_TYPE_NOTIFICATION, PACKET_TYPE_NOTIFICATION_REQUEST, PACKET_TYPE_PAIR, PACKET_TYPE_PING,
    PACKET_TYPE_SMS_MESSAGES, PACKET_TYPE_SMS_REQUEST, PACKET_TYPE_SMS_REQUEST_CONVERSATION,
    PACKET_TYPE_SMS_REQUEST_CONVERSATIONS, PACKET_TYPE_TELEPHONY,
    PACKET_TYPE_TELEPHONY_REQUEST_MUTE,
};
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BatteryBody {
    pub current_charge: i32,
    pub is_charging: bool,
    pub threshold_event: Option<i32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConnectivitySignal {
    pub network_type: String,
    pub signal_strength: u8,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ConnectivityReportBody {
    pub signal_strengths: BTreeMap<String, ConnectivitySignal>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClipboardBody {
    pub content: String,
    pub timestamp: Option<i64>, // milliseconds since Unix epoch
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PingBody {
    pub message: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FindMyPhoneBody;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NotificationBody {
    pub id: String,
    pub app_name: Option<String>,
    pub title: Option<String>,
    pub text: Option<String>,
    pub ticker: Option<String>,
    pub time: Option<String>,
    pub is_clearable: Option<bool>,
    pub silent: Option<bool>,
    pub is_cancel: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TelephonyBody {
    pub event: String,
    pub is_cancel: bool,
    pub phone_number: Option<String>,
    pub contact_name: Option<String>,
    pub phone_thumbnail: Option<String>,
}

const MAX_SMS_MESSAGES_PER_PACKET: usize = 200;
const MAX_SMS_BODY_BYTES: usize = 16 * 1024;
const MAX_SMS_ADDRESSES: usize = 16;
const MAX_SMS_ATTACHMENTS: usize = 16;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SmsAttachmentMetadata {
    pub part_id: String,
    pub mime_type: Option<String>,
    pub unique_identifier: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SmsMessage {
    pub id: i64,
    pub thread_id: i64,
    pub addresses: Vec<String>,
    pub body: String,
    pub date: i64,
    pub message_type: i32,
    pub read: Option<bool>,
    pub sub_id: Option<i32>,
    pub event: Option<String>,
    pub attachments: Vec<SmsAttachmentMetadata>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SmsMessagesBody {
    pub messages: Vec<SmsMessage>,
}

pub struct SmsRequestConversationsBody;

pub struct SmsRequestConversationBody {
    pub thread_id: i64,
    pub range_start_timestamp: Option<i64>,
    pub number_to_request: Option<u16>,
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

    pub fn as_battery(&self) -> Result<BatteryBody, PacketError> {
        if self.packet_type != PACKET_TYPE_BATTERY {
            return Err(PacketError("not a battery packet".into()));
        }
        BatteryBody::from_map(&self.body)
    }

    pub fn as_connectivity_report(&self) -> Result<ConnectivityReportBody, PacketError> {
        if self.packet_type != PACKET_TYPE_CONNECTIVITY_REPORT {
            return Err(PacketError("not a connectivity report packet".into()));
        }
        ConnectivityReportBody::from_map(&self.body)
    }

    pub fn as_clipboard(&self) -> Result<ClipboardBody, PacketError> {
        if self.packet_type != PACKET_TYPE_CLIPBOARD
            && self.packet_type != PACKET_TYPE_CLIPBOARD_CONNECT
        {
            return Err(PacketError("not a clipboard packet".into()));
        }
        ClipboardBody::from_map(&self.body)
    }

    pub fn as_ping(&self) -> Result<PingBody, PacketError> {
        if self.packet_type != PACKET_TYPE_PING {
            return Err(PacketError("not a ping packet".into()));
        }
        PingBody::from_map(&self.body)
    }

    pub fn as_findmyphone_request(&self) -> Result<(), PacketError> {
        if self.packet_type != PACKET_TYPE_FINDMYPHONE_REQUEST {
            return Err(PacketError("not a findmyphone request packet".into()));
        }
        Ok(())
    }

    pub fn as_notification(&self) -> Result<NotificationBody, PacketError> {
        if self.packet_type != PACKET_TYPE_NOTIFICATION {
            return Err(PacketError("not a notification packet".into()));
        }
        NotificationBody::from_map(&self.body)
    }

    pub fn as_notification_request(&self) -> Result<(), PacketError> {
        if self.packet_type != PACKET_TYPE_NOTIFICATION_REQUEST {
            return Err(PacketError("not a notification request packet".into()));
        }
        Ok(())
    }

    pub fn as_sms_messages(&self) -> Result<SmsMessagesBody, PacketError> {
        if self.packet_type != PACKET_TYPE_SMS_MESSAGES {
            return Err(PacketError("not an sms messages packet".into()));
        }
        SmsMessagesBody::from_map(&self.body)
    }

    pub fn as_telephony(&self) -> Result<TelephonyBody, PacketError> {
        if self.packet_type != PACKET_TYPE_TELEPHONY {
            return Err(PacketError("not a telephony packet".into()));
        }
        TelephonyBody::from_map(&self.body)
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

impl BatteryBody {
    pub fn new(current_charge: i32, is_charging: bool, threshold_event: Option<i32>) -> Self {
        Self {
            current_charge,
            is_charging,
            threshold_event,
        }
    }

    pub fn to_packet(&self) -> NetworkPacket {
        let mut body = Map::new();
        body.insert(
            "currentCharge".into(),
            Value::Number((self.current_charge as i64).into()),
        );
        body.insert("isCharging".into(), Value::Bool(self.is_charging));
        if let Some(threshold) = self.threshold_event {
            body.insert(
                "thresholdEvent".into(),
                Value::Number((threshold as i64).into()),
            );
        }
        NetworkPacket::new(PACKET_TYPE_BATTERY, body)
    }

    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let current_charge = match body.get("currentCharge") {
            Some(Value::Number(n)) => {
                let val = n
                    .as_i64()
                    .ok_or_else(|| PacketError("currentCharge must be an integer".into()))?;
                if !(0..=100).contains(&val) {
                    return Err(PacketError(format!("currentCharge out of range: {val}")));
                }
                val as i32
            }
            Some(_) => return Err(PacketError("currentCharge must be an integer".into())),
            None => return Err(PacketError("missing currentCharge".into())),
        };
        let is_charging = match body.get("isCharging") {
            Some(Value::Bool(b)) => *b,
            Some(_) => return Err(PacketError("isCharging must be a boolean".into())),
            None => return Err(PacketError("missing isCharging".into())),
        };
        let threshold_event = match body.get("thresholdEvent") {
            None => None,
            Some(Value::Number(n)) => {
                let val = n
                    .as_i64()
                    .ok_or_else(|| PacketError("thresholdEvent must be an integer".into()))?;
                Some(val as i32)
            }
            Some(_) => return Err(PacketError("thresholdEvent must be an integer".into())),
        };
        Ok(Self {
            current_charge,
            is_charging,
            threshold_event,
        })
    }
}

impl ConnectivityReportBody {
    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let Some(Value::Object(entries)) = body.get("signalStrengths") else {
            return Err(PacketError("missing or invalid signalStrengths".into()));
        };
        let mut signal_strengths = BTreeMap::new();
        for (key, value) in entries {
            let Some(entry) = value.as_object() else {
                continue;
            };
            let Some(network_type) = entry.get("networkType").and_then(Value::as_str) else {
                continue;
            };
            let Some(strength) = entry.get("signalStrength").and_then(Value::as_i64) else {
                continue;
            };
            if !(0..=4).contains(&strength) {
                continue;
            }
            signal_strengths.insert(
                key.clone(),
                ConnectivitySignal {
                    network_type: normalized_network_type(network_type),
                    signal_strength: strength as u8,
                },
            );
        }
        Ok(Self { signal_strengths })
    }

    /// The protocol does not identify a primary subscription. Relay therefore
    /// presents the best reported cellular connection, deterministically.
    pub fn selected_signal(&self) -> Option<(&str, &ConnectivitySignal)> {
        self.signal_strengths
            .iter()
            .max_by(|(left_key, left), (right_key, right)| {
                left.signal_strength
                    .cmp(&right.signal_strength)
                    .then_with(|| {
                        network_priority(&left.network_type)
                            .cmp(&network_priority(&right.network_type))
                    })
                    .then_with(|| right_key.cmp(left_key))
            })
            .map(|(key, signal)| (key.as_str(), signal))
    }
}

fn normalized_network_type(value: &str) -> String {
    match value {
        "GSM" | "CDMA" | "iDEN" | "UMTS" | "CDMA2000" | "EDGE" | "GPRS" | "HSPA" | "LTE" | "5G"
        | "Unknown" => value.to_string(),
        _ => "Unknown".to_string(),
    }
}

fn network_priority(value: &str) -> u8 {
    match value {
        "5G" => 8,
        "LTE" => 7,
        "HSPA" => 6,
        "UMTS" => 5,
        "EDGE" => 4,
        "GPRS" => 3,
        "GSM" => 2,
        _ => 1,
    }
}

impl ClipboardBody {
    pub fn text(content: impl Into<String>) -> NetworkPacket {
        let mut body = Map::new();
        body.insert("content".into(), Value::String(content.into()));
        NetworkPacket::new(PACKET_TYPE_CLIPBOARD, body)
    }

    pub fn connect(content: impl Into<String>, timestamp_ms: i64) -> NetworkPacket {
        let mut body = Map::new();
        body.insert("content".into(), Value::String(content.into()));
        body.insert("timestamp".into(), Value::Number(timestamp_ms.into()));
        NetworkPacket::new(PACKET_TYPE_CLIPBOARD_CONNECT, body)
    }

    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let content = required_string(body, "content")?;
        let timestamp = optional_i64(body, "timestamp");
        Ok(Self { content, timestamp })
    }
}

impl PingBody {
    pub fn new(message: Option<String>) -> NetworkPacket {
        let mut body = Map::new();
        if let Some(msg) = message {
            body.insert("message".into(), Value::String(msg));
        }
        NetworkPacket::new(PACKET_TYPE_PING, body)
    }

    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let message = optional_string(body, "message");
        Ok(Self { message })
    }
}

impl FindMyPhoneBody {
    pub fn request() -> NetworkPacket {
        NetworkPacket::new(PACKET_TYPE_FINDMYPHONE_REQUEST, Map::new())
    }
}

impl NotificationBody {
    pub fn request() -> NetworkPacket {
        let mut body = Map::new();
        body.insert("request".into(), Value::Bool(true));
        NetworkPacket::new(PACKET_TYPE_NOTIFICATION_REQUEST, body)
    }

    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let id = match body.get("id") {
            Some(Value::String(s)) => s.clone(),
            Some(Value::Number(n)) => n.to_string(),
            _ => return Err(PacketError("missing or invalid id".into())),
        };
        let app_name = optional_string(body, "appName");
        let title = optional_string(body, "title");
        let text = optional_string(body, "text");
        let ticker = optional_string(body, "ticker");
        let time = match body.get("time") {
            Some(Value::String(s)) => Some(s.clone()),
            Some(Value::Number(n)) => Some(n.to_string()),
            _ => None,
        };
        let is_clearable = body.get("isClearable").and_then(Value::as_bool);
        let silent = body.get("silent").and_then(Value::as_bool);
        let is_cancel = body
            .get("isCancel")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        Ok(Self {
            id,
            app_name,
            title,
            text,
            ticker,
            time,
            is_clearable,
            silent,
            is_cancel,
        })
    }
}

impl SmsMessagesBody {
    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let version = body.get("version").and_then(Value::as_i64).unwrap_or(2);
        if version != 2 {
            return Err(PacketError("unsupported sms messages version".into()));
        }
        let raw = body
            .get("messages")
            .and_then(Value::as_array)
            .ok_or_else(|| PacketError("messages must be an array".into()))?;
        if raw.len() > MAX_SMS_MESSAGES_PER_PACKET {
            return Err(PacketError("too many sms messages".into()));
        }
        let messages = raw.iter().filter_map(SmsMessage::from_value).collect();
        Ok(Self { messages })
    }
}

impl SmsMessage {
    fn from_value(value: &Value) -> Option<Self> {
        let map = value.as_object()?;
        let id = map.get("_id")?.as_i64()?;
        let thread_id = map.get("thread_id")?.as_i64()?;
        let date = map.get("date")?.as_i64()?;
        if date < 0 {
            return None;
        }
        let body = map.get("body").and_then(Value::as_str).unwrap_or("");
        if body.len() > MAX_SMS_BODY_BYTES {
            return None;
        }
        let message_type = map
            .get("type")
            .and_then(Value::as_i64)
            .and_then(|v| i32::try_from(v).ok())
            .unwrap_or(0);
        let read = match map.get("read") {
            None => None,
            Some(v) => match v.as_i64() {
                Some(0) => Some(false),
                Some(1) => Some(true),
                _ => return None,
            },
        };
        let addresses = map
            .get("addresses")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .take(MAX_SMS_ADDRESSES)
                    .filter_map(|entry| {
                        entry
                            .as_object()?
                            .get("address")?
                            .as_str()
                            .map(str::to_string)
                    })
                    .collect()
            })
            .unwrap_or_default();
        let attachments = map
            .get("attachments")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .take(MAX_SMS_ATTACHMENTS)
                    .filter_map(|entry| {
                        let item = entry.as_object()?;
                        Some(SmsAttachmentMetadata {
                            part_id: item.get("part_id")?.as_str()?.to_string(),
                            mime_type: item
                                .get("mime_type")
                                .and_then(Value::as_str)
                                .map(str::to_string),
                            unique_identifier: item
                                .get("unique_identifier")
                                .and_then(Value::as_str)
                                .map(str::to_string),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        Some(Self {
            id,
            thread_id,
            addresses,
            body: body.to_string(),
            date,
            message_type,
            read,
            // Android names this after the Telephony provider column, `sub_id`,
            // while the request packet going the other way spells the same
            // concept `subID`. Both are accepted here so a peer that mirrors
            // the request spelling back is not silently read as single-SIM.
            sub_id: map
                .get("sub_id")
                .or_else(|| map.get("subID"))
                .and_then(Value::as_i64)
                .and_then(|v| i32::try_from(v).ok()),
            event: map.get("event").and_then(Value::as_str).map(str::to_string),
            attachments,
        })
    }
}

impl SmsRequestConversationsBody {
    pub fn request() -> NetworkPacket {
        NetworkPacket::new(PACKET_TYPE_SMS_REQUEST_CONVERSATIONS, Map::new())
    }
}

impl SmsRequestConversationBody {
    pub fn request(
        thread_id: i64,
        range_start_timestamp: Option<i64>,
        number_to_request: Option<u16>,
    ) -> NetworkPacket {
        let mut body = Map::new();
        body.insert("threadID".into(), Value::Number(thread_id.into()));
        if let Some(value) = range_start_timestamp {
            body.insert("rangeStartTimestamp".into(), Value::Number(value.into()));
        }
        if let Some(value) = number_to_request {
            body.insert(
                "numberToRequest".into(),
                Value::Number(u64::from(value).into()),
            );
        }
        NetworkPacket::new(PACKET_TYPE_SMS_REQUEST_CONVERSATION, body)
    }
}

impl TelephonyBody {
    fn from_map(body: &Map<String, Value>) -> Result<Self, PacketError> {
        let event = required_string(body, "event")?;
        let is_cancel = body
            .get("isCancel")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let phone_number = optional_string(body, "phoneNumber");
        let contact_name = optional_string(body, "contactName");
        let phone_thumbnail = optional_string(body, "phoneThumbnail");
        Ok(Self {
            event,
            is_cancel,
            phone_number,
            contact_name,
            phone_thumbnail,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SmsRequestBody {
    pub addresses: Vec<String>,
    pub message_body: String,
    pub sub_id: Option<i32>,
}

impl SmsRequestBody {
    pub fn to_packet(&self) -> NetworkPacket {
        let mut body = Map::new();
        body.insert("version".into(), Value::Number(2.into()));
        let addrs: Vec<Value> = self
            .addresses
            .iter()
            .map(|a| {
                let mut map = Map::new();
                map.insert("address".into(), Value::String(a.clone()));
                Value::Object(map)
            })
            .collect();
        body.insert("addresses".into(), Value::Array(addrs));
        body.insert(
            "messageBody".into(),
            Value::String(self.message_body.clone()),
        );
        if let Some(sub_id) = self.sub_id {
            body.insert("subID".into(), Value::Number(sub_id.into()));
        }
        NetworkPacket::new(PACKET_TYPE_SMS_REQUEST, body)
    }
}

pub struct TelephonyRequestMuteBody;

impl TelephonyRequestMuteBody {
    pub fn request() -> NetworkPacket {
        NetworkPacket::new(PACKET_TYPE_TELEPHONY_REQUEST_MUTE, Map::new())
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

    /// The SMS v2 request is the packet that actually sends a message, so its
    /// shape is pinned field by field: `addresses` is an array of objects, not
    /// an array of strings, and the SIM is `subID` on the way out even though
    /// Android reports it as `sub_id` on the way in.
    #[test]
    fn sms_request_matches_the_v2_schema() {
        let packet = SmsRequestBody {
            addresses: vec!["+15550100".into()],
            message_body: "hello".into(),
            sub_id: Some(2),
        }
        .to_packet();

        assert_eq!(packet.packet_type, PACKET_TYPE_SMS_REQUEST);
        assert_eq!(packet.body.get("version").and_then(Value::as_i64), Some(2));
        assert_eq!(
            packet.body.get("messageBody").and_then(Value::as_str),
            Some("hello")
        );
        assert_eq!(packet.body.get("subID").and_then(Value::as_i64), Some(2));
        assert!(
            packet.body.get("sub_id").is_none(),
            "the request spells the SIM subID, not sub_id"
        );

        let addresses = packet
            .body
            .get("addresses")
            .and_then(Value::as_array)
            .expect("addresses must be an array");
        assert_eq!(addresses.len(), 1);
        assert_eq!(
            addresses[0].get("address").and_then(Value::as_str),
            Some("+15550100"),
            "each address is an object with an address field"
        );
    }

    #[test]
    fn sms_request_omits_an_unknown_sim() {
        let packet = SmsRequestBody {
            addresses: vec!["+15550100".into()],
            message_body: "hello".into(),
            sub_id: None,
        }
        .to_packet();

        assert!(
            packet.body.get("subID").is_none(),
            "an absent SIM must be omitted rather than sent as a guess"
        );
    }

    #[test]
    fn sms_request_carries_every_recipient() {
        let packet = SmsRequestBody {
            addresses: vec!["+15550100".into(), "+15550111".into()],
            message_body: "hi".into(),
            sub_id: None,
        }
        .to_packet();

        let addresses = packet
            .body
            .get("addresses")
            .and_then(Value::as_array)
            .expect("addresses must be an array");
        assert_eq!(addresses.len(), 2);
    }

    #[test]
    fn sms_request_round_trips_through_serialization() {
        let serialized = SmsRequestBody {
            addresses: vec!["+15550100".into()],
            message_body: "round trip".into(),
            sub_id: Some(1),
        }
        .to_packet()
        .serialize();

        let parsed = NetworkPacket::parse(&serialized).expect("must parse back");
        assert_eq!(parsed.packet_type, PACKET_TYPE_SMS_REQUEST);
        assert_eq!(
            parsed.body.get("messageBody").and_then(Value::as_str),
            Some("round trip")
        );
    }

    #[test]
    fn incoming_messages_accept_either_sim_spelling() {
        let snake = serde_json::json!({
            "messages": [{
                "_id": 7, "thread_id": 3, "body": "x", "date": 1,
                "type": 1, "read": 1, "sub_id": 2,
                "addresses": [{"address": "+15550100"}]
            }]
        });
        let camel = serde_json::json!({
            "messages": [{
                "_id": 7, "thread_id": 3, "body": "x", "date": 1,
                "type": 1, "read": 1, "subID": 2,
                "addresses": [{"address": "+15550100"}]
            }]
        });

        for body in [snake, camel] {
            let packet =
                NetworkPacket::new(PACKET_TYPE_SMS_MESSAGES, body.as_object().unwrap().clone());
            let parsed = packet.as_sms_messages().expect("must parse");
            assert_eq!(parsed.messages[0].sub_id, Some(2));
        }
    }

    #[test]
    fn a_message_without_a_sim_reports_none() {
        let body = serde_json::json!({
            "messages": [{
                "_id": 7, "thread_id": 3, "body": "x", "date": 1,
                "type": 1, "read": 1,
                "addresses": [{"address": "+15550100"}]
            }]
        });
        let packet =
            NetworkPacket::new(PACKET_TYPE_SMS_MESSAGES, body.as_object().unwrap().clone());

        assert_eq!(
            packet.as_sms_messages().expect("must parse").messages[0].sub_id,
            None
        );
    }

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

    #[test]
    fn battery_valid_packet_parses() {
        let body = BatteryBody::new(76, false, None);
        let packet = body.to_packet();
        let parsed = NetworkPacket::parse(&packet.serialize())
            .unwrap()
            .as_battery()
            .unwrap();
        assert_eq!(parsed.current_charge, 76);
        assert!(!parsed.is_charging);
        assert_eq!(parsed.threshold_event, None);
    }

    #[test]
    fn battery_current_charge_boundary_values() {
        let min_body = BatteryBody::new(0, false, None);
        let parsed_min = NetworkPacket::parse(&min_body.to_packet().serialize())
            .unwrap()
            .as_battery()
            .unwrap();
        assert_eq!(parsed_min.current_charge, 0);

        let max_body = BatteryBody::new(100, true, None);
        let parsed_max = NetworkPacket::parse(&max_body.to_packet().serialize())
            .unwrap()
            .as_battery()
            .unwrap();
        assert_eq!(parsed_max.current_charge, 100);
        assert!(parsed_max.is_charging);
    }

    #[test]
    fn battery_out_of_range_charge_rejected() {
        let json_negative = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":-1,"isCharging":false}}"#;
        let pkt_neg = NetworkPacket::parse(json_negative).unwrap();
        assert!(pkt_neg.as_battery().is_err());

        let json_over = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":101,"isCharging":false}}"#;
        let pkt_over = NetworkPacket::parse(json_over).unwrap();
        assert!(pkt_over.as_battery().is_err());
    }

    #[test]
    fn battery_non_integer_charge_rejected() {
        let json_str = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":"50","isCharging":false}}"#;
        assert!(NetworkPacket::parse(json_str)
            .unwrap()
            .as_battery()
            .is_err());

        let json_float = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":50.5,"isCharging":false}}"#;
        assert!(NetworkPacket::parse(json_float)
            .unwrap()
            .as_battery()
            .is_err());
    }

    #[test]
    fn battery_charging_boolean_states() {
        let charging = BatteryBody::new(50, true, None);
        assert!(
            NetworkPacket::parse(&charging.to_packet().serialize())
                .unwrap()
                .as_battery()
                .unwrap()
                .is_charging
        );

        let not_charging = BatteryBody::new(50, false, None);
        assert!(
            !NetworkPacket::parse(&not_charging.to_packet().serialize())
                .unwrap()
                .as_battery()
                .unwrap()
                .is_charging
        );
    }

    #[test]
    fn battery_malformed_boolean_rejected() {
        let json_str = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":50,"isCharging":"true"}}"#;
        assert!(NetworkPacket::parse(json_str)
            .unwrap()
            .as_battery()
            .is_err());

        let json_num =
            br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":50,"isCharging":1}}"#;
        assert!(NetworkPacket::parse(json_num)
            .unwrap()
            .as_battery()
            .is_err());
    }

    #[test]
    fn battery_threshold_event_parsed_safely() {
        let with_event = BatteryBody::new(15, false, Some(1));
        let parsed = NetworkPacket::parse(&with_event.to_packet().serialize())
            .unwrap()
            .as_battery()
            .unwrap();
        assert_eq!(parsed.threshold_event, Some(1));

        let json_bad_event = br#"{"id":1,"type":"kdeconnect.battery","body":{"currentCharge":50,"isCharging":false,"thresholdEvent":"low"}}"#;
        assert!(NetworkPacket::parse(json_bad_event)
            .unwrap()
            .as_battery()
            .is_err());
    }

    #[test]
    fn battery_unrelated_packet_rejected_as_battery() {
        let pair_pkt = PairBody::accept();
        assert!(pair_pkt.as_battery().is_err());

        let id_pkt = identity().to_packet();
        assert!(id_pkt.as_battery().is_err());
    }

    #[test]
    fn connectivity_report_parses_valid_entries_and_selects_best_connection() {
        let json = br#"{"id":1,"type":"kdeconnect.connectivity_report","body":{"signalStrengths":{"sim-b":{"networkType":"LTE","signalStrength":3},"sim-a":{"networkType":"5G","signalStrength":3},"weak":{"networkType":"GSM","signalStrength":1}}}}"#;
        let report = NetworkPacket::parse(json)
            .unwrap()
            .as_connectivity_report()
            .unwrap();
        assert_eq!(report.signal_strengths.len(), 3);
        let (key, selected) = report.selected_signal().unwrap();
        assert_eq!(key, "sim-a");
        assert_eq!(selected.network_type, "5G");
        assert_eq!(selected.signal_strength, 3);
    }

    #[test]
    fn connectivity_report_keeps_empty_reports_and_ignores_bad_entries() {
        let empty =
            br#"{"id":1,"type":"kdeconnect.connectivity_report","body":{"signalStrengths":{}}}"#;
        assert!(NetworkPacket::parse(empty)
            .unwrap()
            .as_connectivity_report()
            .unwrap()
            .selected_signal()
            .is_none());

        let mixed = br#"{"id":1,"type":"kdeconnect.connectivity_report","body":{"signalStrengths":{"negative":{"networkType":"LTE","signalStrength":-1},"large":{"networkType":"LTE","signalStrength":5},"malformed":{"networkType":3},"unknown":{"networkType":"Satellite","signalStrength":4}}}}"#;
        let report = NetworkPacket::parse(mixed)
            .unwrap()
            .as_connectivity_report()
            .unwrap();
        assert_eq!(report.signal_strengths.len(), 1);
        let (_, selected) = report.selected_signal().unwrap();
        assert_eq!(selected.network_type, "Unknown");
        assert_eq!(selected.signal_strength, 4);
    }

    #[test]
    fn clipboard_plain_and_connect_roundtrip() {
        let plain = ClipboardBody::text("Hello Linux");
        let parsed = NetworkPacket::parse(&plain.serialize())
            .unwrap()
            .as_clipboard()
            .unwrap();
        assert_eq!(parsed.content, "Hello Linux");
        assert_eq!(parsed.timestamp, None);

        let connect = ClipboardBody::connect("Sync text 123", 1_700_000_123_456);
        let parsed_conn = NetworkPacket::parse(&connect.serialize())
            .unwrap()
            .as_clipboard()
            .unwrap();
        assert_eq!(parsed_conn.content, "Sync text 123");
        assert_eq!(parsed_conn.timestamp, Some(1_700_000_123_456));
    }

    #[test]
    fn clipboard_unicode_and_large_text() {
        let unicode = "Hello 🚀 🦀 測試";
        let parsed = NetworkPacket::parse(&ClipboardBody::text(unicode).serialize())
            .unwrap()
            .as_clipboard()
            .unwrap();
        assert_eq!(parsed.content, unicode);

        let large = "a".repeat(4096);
        let parsed_large = NetworkPacket::parse(&ClipboardBody::text(&large).serialize())
            .unwrap()
            .as_clipboard()
            .unwrap();
        assert_eq!(parsed_large.content, large);
    }

    #[test]
    fn clipboard_malformed_rejected() {
        let bad = br#"{"id":1,"type":"kdeconnect.clipboard","body":{"noContent":123}}"#;
        assert!(NetworkPacket::parse(bad).unwrap().as_clipboard().is_err());
    }

    #[test]
    fn ping_roundtrip_with_and_without_message() {
        let ping_no_msg = PingBody::new(None);
        let parsed = NetworkPacket::parse(&ping_no_msg.serialize())
            .unwrap()
            .as_ping()
            .unwrap();
        assert_eq!(parsed.message, None);

        let ping_msg = PingBody::new(Some("Ping test".into()));
        let parsed_msg = NetworkPacket::parse(&ping_msg.serialize())
            .unwrap()
            .as_ping()
            .unwrap();
        assert_eq!(parsed_msg.message, Some("Ping test".into()));
    }

    #[test]
    fn findmyphone_request_roundtrip() {
        let req = FindMyPhoneBody::request();
        assert_eq!(req.packet_type, PACKET_TYPE_FINDMYPHONE_REQUEST);
        let parsed = NetworkPacket::parse(&req.serialize()).unwrap();
        assert!(parsed.as_findmyphone_request().is_ok());
    }

    #[test]
    fn notification_create_and_cancel_roundtrip() {
        let notif_json = br#"{"id":1,"type":"kdeconnect.notification","body":{"id":"123","appName":"WhatsApp","title":"Alice","text":"Hey","time":"1700000","isClearable":true,"silent":false,"isCancel":false}}"#;
        let parsed = NetworkPacket::parse(notif_json)
            .unwrap()
            .as_notification()
            .unwrap();
        assert_eq!(parsed.id, "123");
        assert_eq!(parsed.app_name, Some("WhatsApp".into()));
        assert_eq!(parsed.title, Some("Alice".into()));
        assert_eq!(parsed.text, Some("Hey".into()));
        assert_eq!(parsed.is_clearable, Some(true));
        assert_eq!(parsed.silent, Some(false));
        assert!(!parsed.is_cancel);

        let cancel_json =
            br#"{"id":2,"type":"kdeconnect.notification","body":{"id":"123","isCancel":true}}"#;
        let parsed_cancel = NetworkPacket::parse(cancel_json)
            .unwrap()
            .as_notification()
            .unwrap();
        assert_eq!(parsed_cancel.id, "123");
        assert!(parsed_cancel.is_cancel);
    }

    #[test]
    fn notification_request_roundtrip() {
        let req = NotificationBody::request();
        assert_eq!(req.packet_type, PACKET_TYPE_NOTIFICATION_REQUEST);
        let parsed = NetworkPacket::parse(&req.serialize()).unwrap();
        assert!(parsed.as_notification_request().is_ok());
    }
}
