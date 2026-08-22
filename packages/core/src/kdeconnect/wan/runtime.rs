//! Ties the Relay WAN endpoint, binding registry, and transport router
//! together: accepts inbound Iroh connections, rejects anything not already
//! in the [`WanBindingRegistry`], negotiates the WAN hello, and only then
//! exposes a [`WanLink`] to the [`TransportRouter`].

use std::sync::Arc;

use anyhow::Context as _;
use iroh::{endpoint::Connection, EndpointId};

use super::binding::WanBindingRegistry;
use super::endpoint::{bind_wan_endpoint, WanEndpoint};
use super::identity::WanIdentity;
use super::payload::{validate_payload_size, WanPayloadTransferInfo};
use super::protocol::{self, WanHello, WAN_PROTOCOL_VERSION};
use super::transport::{
    LinkFuture, PayloadOutcome, PayloadRequest, TransportKind, TransportLink, TransportMetadata,
    TransportState,
};
use crate::kdeconnect::packet::{NetworkPacket, PROTOCOL_VERSION as KDE_PROTOCOL_VERSION};

/// One inbound event on a [`WanLink`]: either a control-stream KDE packet, or
/// a fully-received payload (correlated by `relay_payload_id` to a control
/// packet's `payloadTransferInfo`). Buffered fully in memory rather than
/// exposed as a raw stream -- the 20 MiB [`super::payload::MAX_WAN_PAYLOAD_BYTES`]
/// cap makes that a bounded, simple choice, matching the Android WAN link.
#[derive(Debug)]
pub enum WanIncomingEvent {
    Packet(NetworkPacket),
    Payload {
        relay_payload_id: String,
        payload_size: u64,
        data: Vec<u8>,
    },
}

#[derive(Debug, Clone, Eq, PartialEq, thiserror::Error)]
pub enum WanAcceptError {
    /// The connection's authenticated `EndpointId` is not in the binding
    /// registry. This is a hard rejection: an unknown Internet peer must
    /// never trigger a KDE pairing request or any other trust-adjacent
    /// behavior.
    #[error("unknown Relay WAN EndpointId, connection rejected")]
    UnknownEndpoint,
    #[error("Relay WAN hello was invalid: {0}")]
    InvalidHello(String),
    #[error("Relay WAN transport error: {0}")]
    Transport(String),
}

pub struct WanRuntimeConfig {
    pub identity: WanIdentity,
    pub kde_device_id: String,
    pub device_name: String,
    pub device_type: String,
    pub app_version: String,
    pub capability_digest: String,
}

pub struct WanRuntime {
    endpoint: WanEndpoint,
    bindings: Arc<WanBindingRegistry>,
    config: WanRuntimeConfig,
}

impl WanRuntime {
    pub async fn start(
        config: WanRuntimeConfig,
        bindings: Arc<WanBindingRegistry>,
    ) -> anyhow::Result<Self> {
        let endpoint = bind_wan_endpoint(&config.identity).await?;
        Ok(Self {
            endpoint,
            bindings,
            config,
        })
    }

    pub fn endpoint(&self) -> WanEndpoint {
        self.endpoint.clone()
    }

    pub fn endpoint_id(&self) -> EndpointId {
        self.config.identity.endpoint_id()
    }

    fn local_hello(&self) -> WanHello {
        WanHello {
            wan_protocol_version: WAN_PROTOCOL_VERSION,
            kde_device_id: self.config.kde_device_id.clone(),
            endpoint_id: self.config.identity.endpoint_id().to_string(),
            device_name: self.config.device_name.clone(),
            device_type: self.config.device_type.clone(),
            kde_protocol_version: KDE_PROTOCOL_VERSION,
            capability_digest: self.config.capability_digest.clone(),
            app_version: self.config.app_version.clone(),
        }
    }

    /// Runs the full inbound-connection algorithm on an already-accepted Iroh
    /// [`Connection`]:
    /// 1. read the authenticated remote `EndpointId` off the connection,
    /// 2. look it up in the binding registry,
    /// 3. reject outright if unknown,
    /// 4. resolve it to the bound KDE device id,
    /// 5. negotiate the WAN hello,
    /// 6. only on success, hand back a [`WanLink`] ready to register with the
    ///    [`TransportRouter`].
    pub async fn negotiate_inbound(&self, connection: Connection) -> Result<WanLink, WanAcceptError> {
        let remote_endpoint_id = connection.remote_id();

        let binding = self
            .bindings
            .by_endpoint_id(&remote_endpoint_id)
            .ok_or(WanAcceptError::UnknownEndpoint)?;

        let (mut send, mut recv) = connection
            .accept_bi()
            .await
            .map_err(|error| WanAcceptError::Transport(error.to_string()))?;

        let remote_hello = read_and_validate_hello(&mut recv, &binding.kde_device_id, &remote_endpoint_id).await?;
        write_hello(&mut send, &self.local_hello())
            .await
            .map_err(|error| WanAcceptError::Transport(error.to_string()))?;

        self.bindings.record_connection(
            &binding.kde_device_id,
            "iroh",
            now_unix(),
        );

        Ok(WanLink::new(
            binding.kde_device_id,
            connection,
            send,
            recv,
            remote_hello,
        ))
    }

    /// Outbound counterpart: dials a device we already have a binding for and
    /// runs the same hello negotiation as the initiator. Relay WAN never
    /// dials an `EndpointId` it does not already have a binding for.
    pub async fn connect_outbound(
        &self,
        target_kde_device_id: &str,
        addr: iroh::EndpointAddr,
    ) -> Result<WanLink, WanAcceptError> {
        let binding = self
            .bindings
            .by_kde_device_id(target_kde_device_id)
            .ok_or(WanAcceptError::UnknownEndpoint)?;

        let connection = self
            .endpoint
            .connect(addr)
            .await
            .map_err(|error| WanAcceptError::Transport(error.to_string()))?;

        let (mut send, mut recv) = connection
            .open_bi()
            .await
            .map_err(|error| WanAcceptError::Transport(error.to_string()))?;

        write_hello(&mut send, &self.local_hello())
            .await
            .map_err(|error| WanAcceptError::Transport(error.to_string()))?;
        let remote_hello =
            read_and_validate_hello(&mut recv, &binding.kde_device_id, &binding.endpoint_id).await?;

        self.bindings.record_connection(&binding.kde_device_id, "iroh", now_unix());

        Ok(WanLink::new(binding.kde_device_id, connection, send, recv, remote_hello))
    }
}

async fn read_and_validate_hello(
    recv: &mut iroh::endpoint::RecvStream,
    expected_kde_device_id: &str,
    expected_endpoint_id: &EndpointId,
) -> Result<WanHello, WanAcceptError> {
    let bytes = protocol::read_frame(recv, protocol::MAX_HELLO_FRAME_BYTES)
        .await
        .map_err(|error| WanAcceptError::Transport(error.to_string()))?;
    let hello: WanHello =
        serde_json::from_slice(&bytes).map_err(|error| WanAcceptError::InvalidHello(error.to_string()))?;
    hello
        .validate(expected_kde_device_id, expected_endpoint_id)
        .map_err(|error| WanAcceptError::InvalidHello(error.to_string()))?;
    Ok(hello)
}

async fn write_hello(send: &mut iroh::endpoint::SendStream, hello: &WanHello) -> anyhow::Result<()> {
    let bytes = serde_json::to_vec(hello).context("encode Relay WAN hello")?;
    protocol::write_frame(send, &bytes, protocol::MAX_HELLO_FRAME_BYTES)
        .await
        .context("write Relay WAN hello frame")?;
    Ok(())
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// A negotiated Relay WAN connection to one KDE device, exposed to the
/// [`TransportRouter`] as a [`TransportLink`].
pub struct WanLink {
    kde_device_id: String,
    connection: Connection,
    send: tokio::sync::Mutex<iroh::endpoint::SendStream>,
    remote_hello: WanHello,
    incoming: tokio::sync::Mutex<tokio::sync::mpsc::Receiver<WanIncomingEvent>>,
}

impl WanLink {
    fn new(
        kde_device_id: String,
        connection: Connection,
        send: iroh::endpoint::SendStream,
        recv: iroh::endpoint::RecvStream,
        remote_hello: WanHello,
    ) -> Self {
        let (tx, rx) = tokio::sync::mpsc::channel(32);
        spawn_control_receive_loop(recv, tx.clone());
        spawn_payload_receive_loop(connection.clone(), tx);
        Self {
            kde_device_id,
            connection,
            send: tokio::sync::Mutex::new(send),
            remote_hello,
            incoming: tokio::sync::Mutex::new(rx),
        }
    }

    pub fn remote_hello(&self) -> &WanHello {
        &self.remote_hello
    }

    /// Waits for the next incoming control packet or fully-received payload.
    /// Returns `None` once the control receive loop has ended (connection
    /// closed) and no further events remain buffered.
    pub async fn recv_incoming(&self) -> Option<WanIncomingEvent> {
        self.incoming.lock().await.recv().await
    }
}

/// Continuously reads control-stream KDE packet frames off the negotiated
/// control `recv` stream and forwards them, until the stream ends (the
/// connection is closed) or the receiving end of `tx` is dropped.
fn spawn_control_receive_loop(
    mut recv: iroh::endpoint::RecvStream,
    tx: tokio::sync::mpsc::Sender<WanIncomingEvent>,
) {
    tokio::spawn(async move {
        loop {
            match protocol::read_packet_frame(&mut recv).await {
                Ok(packet) => {
                    if tx.send(WanIncomingEvent::Packet(packet)).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });
}

/// Every bi stream accepted on `connection` *after* the control stream (which
/// is claimed once during hello negotiation and never re-accepted) is a
/// payload stream. Each is handled on its own task so one slow/stalled
/// payload cannot block subsequently accepted streams.
fn spawn_payload_receive_loop(
    connection: Connection,
    tx: tokio::sync::mpsc::Sender<WanIncomingEvent>,
) {
    tokio::spawn(async move {
        loop {
            let (_send, mut recv) = match connection.accept_bi().await {
                Ok(streams) => streams,
                Err(_) => break,
            };
            let tx = tx.clone();
            tokio::spawn(async move {
                if let Some(event) = read_incoming_payload(&mut recv).await {
                    let _ = tx.send(event).await;
                }
            });
        }
    });
}

/// Reads one payload stream's header + body, enforcing the 20 MiB WAN cap
/// before allocating a buffer for the declared size. Returns `None` (and
/// drops the stream) on any malformed header or an over-limit declaration.
/// Generic over the reader so this can be unit-tested without a real Iroh
/// connection (see `tests::read_incoming_payload_*` below).
async fn read_incoming_payload<R: tokio::io::AsyncRead + Unpin>(recv: &mut R) -> Option<WanIncomingEvent> {
    let header_bytes = protocol::read_frame(recv, protocol::MAX_HELLO_FRAME_BYTES)
        .await
        .ok()?;
    let header: serde_json::Value = serde_json::from_slice(&header_bytes).ok()?;
    let relay_payload_id = header.get("relayPayloadId")?.as_str()?.to_owned();
    let payload_size = header.get("payloadSize")?.as_u64()?;
    validate_payload_size(payload_size).ok()?;

    let mut data = vec![0_u8; payload_size as usize];
    tokio::io::AsyncReadExt::read_exact(recv, &mut data).await.ok()?;
    Some(WanIncomingEvent::Payload {
        relay_payload_id,
        payload_size,
        data,
    })
}

impl TransportLink for WanLink {
    fn device_id(&self) -> &str {
        &self.kde_device_id
    }

    fn kind(&self) -> TransportKind {
        TransportKind::RelayWan
    }

    fn state(&self) -> TransportState {
        if self.connection.close_reason().is_some() {
            TransportState::Offline
        } else if self
            .connection
            .paths()
            .iter()
            .find(|path| path.is_selected())
            .is_some_and(|path| path.is_relay())
        {
            TransportState::RemoteRelay
        } else {
            TransportState::RemoteDirect
        }
    }

    fn metadata(&self) -> TransportMetadata {
        TransportMetadata {
            kind: TransportKind::RelayWan,
            state: self.state(),
            last_seen_unix: Some(now_unix()),
            last_transition_reason: None,
        }
    }

    fn send_packet<'a>(&'a self, packet: &'a NetworkPacket) -> LinkFuture<'a, anyhow::Result<()>> {
        Box::pin(async move {
            let mut send = self.send.lock().await;
            protocol::write_packet_frame(&mut *send, packet)
                .await
                .context("send KDE packet over Relay WAN")
        })
    }

    fn send_payload<'a>(
        &'a self,
        request: PayloadRequest<'a>,
    ) -> LinkFuture<'a, anyhow::Result<PayloadOutcome>> {
        Box::pin(async move {
            let info = WanPayloadTransferInfo::new(request.payload_size)
                .map_err(|error| anyhow::anyhow!(error))?;
            let (mut send, _recv) = self
                .connection
                .open_bi()
                .await
                .context("open Relay WAN payload stream")?;
            let header = serde_json::json!({
                "relayPayloadId": info.relay_payload_id,
                "payloadSize": info.payload_size,
            });
            let header_bytes = serde_json::to_vec(&header).context("encode payload header")?;
            protocol::write_frame(&mut send, &header_bytes, protocol::MAX_HELLO_FRAME_BYTES)
                .await
                .context("write Relay WAN payload header")?;

            let mut remaining = info.payload_size;
            let mut buf = vec![0_u8; 64 * 1024];
            while remaining > 0 {
                let want = buf.len().min(remaining as usize);
                let read = tokio::io::AsyncReadExt::read(request.source, &mut buf[..want])
                    .await
                    .context("read Relay WAN payload source")?;
                if read == 0 {
                    anyhow::bail!("Relay WAN payload source ended before payloadSize was reached");
                }
                tokio::io::AsyncWriteExt::write_all(&mut send, &buf[..read])
                    .await
                    .context("write Relay WAN payload bytes")?;
                remaining -= read as u64;
            }
            tokio::io::AsyncWriteExt::flush(&mut send)
                .await
                .context("flush Relay WAN payload stream")?;
            Ok(PayloadOutcome::Sent)
        })
    }

    fn disconnect(&self) -> LinkFuture<'_, ()> {
        Box::pin(async move {
            self.connection.close(0_u32.into(), b"relay wan link closed");
        })
    }

    fn health(&self) -> LinkFuture<'_, bool> {
        Box::pin(async move { self.connection.close_reason().is_none() })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kdeconnect::wan::binding::WanBinding;
    use crate::kdeconnect::wan::endpoint::WAN_ALPN;
    use iroh::endpoint::presets;
    use iroh::{Endpoint, RelayMode};

    fn runtime_config(identity: &WanIdentity, kde_device_id: &str) -> WanRuntimeConfig {
        WanRuntimeConfig {
            identity: identity.clone(),
            kde_device_id: kde_device_id.to_owned(),
            device_name: "Desktop".to_owned(),
            device_type: "desktop".to_owned(),
            app_version: "0.2.0".to_owned(),
            capability_digest: "digest".to_owned(),
        }
    }

    fn payload_header_frame(relay_payload_id: &str, payload_size: u64) -> Vec<u8> {
        let header = serde_json::json!({
            "relayPayloadId": relay_payload_id,
            "payloadSize": payload_size,
        });
        protocol::encode_frame(&serde_json::to_vec(&header).unwrap(), protocol::MAX_HELLO_FRAME_BYTES).unwrap()
    }

    #[tokio::test]
    async fn read_incoming_payload_round_trips_header_and_body() {
        let mut buf = payload_header_frame("payload-a", 5);
        buf.extend_from_slice(b"hello");
        let mut cursor = std::io::Cursor::new(buf);

        let event = read_incoming_payload(&mut cursor).await.unwrap();
        match event {
            WanIncomingEvent::Payload { relay_payload_id, payload_size, data } => {
                assert_eq!(relay_payload_id, "payload-a");
                assert_eq!(payload_size, 5);
                assert_eq!(data, b"hello");
            }
            WanIncomingEvent::Packet(_) => panic!("expected a Payload event"),
        }
    }

    #[tokio::test]
    async fn read_incoming_payload_rejects_a_declaration_over_the_wan_cap_without_reading_a_body() {
        // Declares an oversized payload but never supplies a body -- if the
        // reader tried to read the body first this would hang instead of
        // rejecting immediately from the header check.
        let buf = payload_header_frame("payload-too-big", super::super::payload::MAX_WAN_PAYLOAD_BYTES + 1);
        let mut cursor = std::io::Cursor::new(buf);

        assert!(read_incoming_payload(&mut cursor).await.is_none());
    }

    #[tokio::test]
    async fn read_incoming_payload_rejects_a_truncated_body() {
        let mut buf = payload_header_frame("payload-b", 5);
        buf.extend_from_slice(b"ab"); // fewer than the declared 5 bytes
        let mut cursor = std::io::Cursor::new(buf);

        assert!(read_incoming_payload(&mut cursor).await.is_none());
    }

    /// An in-process Iroh handshake exercising the full accept algorithm:
    /// unknown-endpoint rejection, then a real accept once bound, over a
    /// direct local QUIC path. Network path selection is environment
    /// dependent (sandboxed CI/test runners often cannot bind a UDP direct
    /// path or reach the n0 relay), so this is `#[ignore]`d like the existing
    /// Anywhere e2e Iroh tests and is meant to be run explicitly with
    /// `cargo test -- --ignored`.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    #[ignore = "requires a real local UDP path; run explicitly with --ignored"]
    async fn unknown_endpoint_is_rejected_then_a_bound_endpoint_is_accepted() {
        let server_identity = WanIdentity::generate();
        let client_identity = WanIdentity::generate();
        let client_endpoint_id = client_identity.endpoint_id();

        let bindings = Arc::new(WanBindingRegistry::new(vec![]));
        let server = WanRuntime::start(
            runtime_config(&server_identity, &"a".repeat(32)),
            bindings.clone(),
        )
        .await
        .unwrap();
        server.endpoint().online().await;
        let server_addr = server.endpoint().addr();

        let client_endpoint = Endpoint::builder(presets::N0)
            .relay_mode(RelayMode::Default)
            .alpns(vec![WAN_ALPN.to_vec()])
            .secret_key(client_identity.secret_key())
            .bind()
            .await
            .unwrap();
        client_endpoint.online().await;

        // First dial: the client's EndpointId is not yet bound, so the
        // accept side must reject it before any hello is exchanged.
        let connection = client_endpoint
            .connect(server_addr.clone(), WAN_ALPN)
            .await
            .unwrap();
        let accepted = server.endpoint().accept().await.unwrap();
        let server_conn = accepted.await.unwrap();
        let result = server.negotiate_inbound(server_conn).await;
        assert!(matches!(result, Err(WanAcceptError::UnknownEndpoint)));
        connection.close(0_u32.into(), b"unbound");

        // Now bind the client and retry -- this time it must be accepted.
        bindings.upsert(WanBinding {
            kde_device_id: "b".repeat(32),
            endpoint_id: client_endpoint_id,
            display_name: "Phone".to_owned(),
            device_type: "phone".to_owned(),
            capabilities: vec![],
            binding_version: 1,
            updated_at_unix: 0,
            last_wan_connected_at_unix: None,
            last_transport: None,
        });

        let client_hello = WanHello {
            wan_protocol_version: WAN_PROTOCOL_VERSION,
            kde_device_id: "b".repeat(32),
            endpoint_id: client_endpoint_id.to_string(),
            device_name: "Phone".to_owned(),
            device_type: "phone".to_owned(),
            kde_protocol_version: KDE_PROTOCOL_VERSION,
            capability_digest: "digest".to_owned(),
            app_version: "0.2.0".to_owned(),
        };

        let connection2 = client_endpoint
            .connect(server_addr, WAN_ALPN)
            .await
            .unwrap();
        let (mut c_send, mut c_recv) = connection2.open_bi().await.unwrap();
        write_hello(&mut c_send, &client_hello).await.unwrap();

        let accepted2 = server.endpoint().accept().await.unwrap();
        let server_conn2 = accepted2.await.unwrap();
        let link = server.negotiate_inbound(server_conn2).await.unwrap();
        assert_eq!(link.device_id(), "b".repeat(32));
        assert_eq!(link.remote_hello().kde_device_id, "b".repeat(32));

        let _server_hello_frame = protocol::read_frame(&mut c_recv, protocol::MAX_HELLO_FRAME_BYTES)
            .await
            .unwrap();

        // A control packet sent on the client's control stream must surface
        // through the server link's `recv_incoming`.
        let ping = NetworkPacket::new("kdeconnect.ping", serde_json::Map::new());
        protocol::write_packet_frame(&mut c_send, &ping).await.unwrap();
        match link.recv_incoming().await.unwrap() {
            WanIncomingEvent::Packet(received) => assert_eq!(received.packet_type, "kdeconnect.ping"),
            WanIncomingEvent::Payload { .. } => panic!("expected the control packet, not a payload"),
        }

        // A payload sent on a second bi stream (mirroring `send_payload`)
        // must also surface, fully assembled, correlated by its declared id.
        let (mut payload_send, _payload_recv) = connection2.open_bi().await.unwrap();
        let header = payload_header_frame("payload-a", 5);
        tokio::io::AsyncWriteExt::write_all(&mut payload_send, &header)
            .await
            .unwrap();
        tokio::io::AsyncWriteExt::write_all(&mut payload_send, b"hello")
            .await
            .unwrap();
        tokio::io::AsyncWriteExt::flush(&mut payload_send).await.unwrap();

        match link.recv_incoming().await.unwrap() {
            WanIncomingEvent::Payload { relay_payload_id, payload_size, data } => {
                assert_eq!(relay_payload_id, "payload-a");
                assert_eq!(payload_size, 5);
                assert_eq!(data, b"hello");
            }
            WanIncomingEvent::Packet(_) => panic!("expected the payload, not a control packet"),
        }

        client_endpoint.close().await;
    }
}
