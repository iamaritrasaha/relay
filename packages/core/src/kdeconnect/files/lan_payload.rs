//! KDE Connect's LAN payload transport.
//!
//! This is upstream's protocol, not a Relay invention. A packet carrying a file
//! does not put the bytes on the control link; instead the **sender** opens a
//! throwaway TCP listener, advertises its port in `payloadTransferInfo`, and the
//! **receiver** dials back to that port. TLS roles are the reverse of what the
//! socket direction suggests: the sender is the TLS *server* on the payload
//! connection, the receiver the TLS *client*.
//!
//! ```text
//! sender                                   receiver
//!   bind :1739+                                |
//!   packet { payloadSize, payloadTransferInfo: { port } }  -->
//!   accept()  <-------------------------------  TCP connect to port
//!   TLS server  <-----------------------------  TLS client
//!   stream payloadSize bytes  ---------------->  read payloadSize bytes
//! ```
//!
//! Both ends pin the peer certificate to the already-paired device, so a local
//! process that merely guesses the port cannot complete the handshake. Knowing
//! the port is never sufficient to write a file.

use std::net::{IpAddr, SocketAddr};
use std::time::Duration;

use anyhow::{Context as _, Result};
use tokio::net::{TcpListener, TcpStream};

/// First port KDE Connect tries for a payload listener. Upstream's
/// `LanLinkProvider.PAYLOAD_TRANSFER_MIN_PORT`.
pub const PAYLOAD_TRANSFER_MIN_PORT: u16 = 1739;

/// How many consecutive ports to try before giving up.
const PORT_SCAN_RANGE: u16 = 128;

/// How long the sender waits for the receiver to dial back.
///
/// Matches upstream's 10 s `setSoTimeout`. Bounded so a receiver that never
/// arrives cannot leave a listener and a transfer pending forever.
pub const PAYLOAD_ACCEPT_TIMEOUT: Duration = Duration::from_secs(10);

/// How long the receiver waits to establish the payload connection.
pub const PAYLOAD_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// Streaming chunk size, matching the rest of Relay's file path.
pub const CHUNK_BYTES: usize = 64 * 1024;

/// A bound payload listener waiting for the receiver to dial back.
pub struct PayloadListener {
    listener: TcpListener,
    port: u16,
}

impl PayloadListener {
    /// Binds the first free port at or above [`PAYLOAD_TRANSFER_MIN_PORT`].
    ///
    /// A fresh listener per transfer is what upstream does, and it is also what
    /// makes concurrent transfers independent: each has its own port and its own
    /// accepted connection, so two files in flight cannot be confused.
    pub async fn bind() -> Result<Self> {
        for offset in 0..PORT_SCAN_RANGE {
            let port = PAYLOAD_TRANSFER_MIN_PORT + offset;
            match TcpListener::bind(SocketAddr::from(([0, 0, 0, 0], port))).await {
                Ok(listener) => return Ok(Self { listener, port }),
                Err(error) if error.kind() == std::io::ErrorKind::AddrInUse => continue,
                Err(error) => return Err(error).context("bind a payload listener"),
            }
        }
        anyhow::bail!("no free payload port in the KDE Connect range")
    }

    /// The port to advertise in `payloadTransferInfo`.
    pub fn port(&self) -> u16 {
        self.port
    }

    /// Waits for the receiver's connection.
    ///
    /// Returns the raw stream; the caller performs the TLS handshake, because
    /// only it holds the identity and the peer's pinned certificate.
    pub async fn accept(self) -> Result<TcpStream> {
        let (stream, _peer) = tokio::time::timeout(PAYLOAD_ACCEPT_TIMEOUT, self.listener.accept())
            .await
            .context("timed out waiting for the payload connection")?
            .context("accept the payload connection")?;
        let _ = stream.set_nodelay(true);
        Ok(stream)
    }
}

/// Dials the sender's advertised payload port.
///
/// The address deliberately comes from the *existing control link's* peer
/// address rather than from anything in the packet: a device may name a port,
/// but it may never redirect Relay to a different host.
pub async fn connect_to_payload(address: IpAddr, port: u16) -> Result<TcpStream> {
    let stream = tokio::time::timeout(
        PAYLOAD_CONNECT_TIMEOUT,
        TcpStream::connect(SocketAddr::new(address, port)),
    )
    .await
    .context("timed out connecting to the payload port")?
    .context("connect to the payload port")?;
    let _ = stream.set_nodelay(true);
    Ok(stream)
}

/// Copies exactly `size` bytes from `source` to `sink`, reporting progress.
///
/// Bounded by a single reused buffer, so memory does not scale with the file.
/// Refuses to send fewer bytes than promised: a short source is an error rather
/// than a silently truncated file on the far end.
pub async fn stream_payload<R, W, F>(
    source: &mut R,
    sink: &mut W,
    size: u64,
    mut on_progress: F,
) -> Result<()>
where
    // `?Sized` so a trait object (`&mut dyn AsyncRead`) can be streamed
    // directly, which is how the transport links hand a source over.
    R: tokio::io::AsyncRead + Unpin + ?Sized,
    W: tokio::io::AsyncWrite + Unpin + ?Sized,
    F: FnMut(u64),
{
    use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
    let mut buffer = vec![0_u8; CHUNK_BYTES];
    let mut sent = 0_u64;
    while sent < size {
        let want = ((size - sent) as usize).min(CHUNK_BYTES);
        let read = source
            .read(&mut buffer[..want])
            .await
            .context("read the file being sent")?;
        if read == 0 {
            anyhow::bail!("file ended after {sent} of {size} declared bytes");
        }
        sink.write_all(&buffer[..read])
            .await
            .context("write to the payload connection")?;
        sent += read as u64;
        on_progress(sent);
    }
    sink.flush().await.context("flush the payload connection")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};

    #[tokio::test]
    async fn a_listener_binds_inside_the_kde_connect_port_range() {
        let listener = PayloadListener::bind().await.unwrap();
        assert!(listener.port() >= PAYLOAD_TRANSFER_MIN_PORT);
        assert!(listener.port() < PAYLOAD_TRANSFER_MIN_PORT + PORT_SCAN_RANGE);
    }

    #[tokio::test]
    async fn concurrent_listeners_get_distinct_ports() {
        // Each transfer owns its own port, which is what keeps two files in
        // flight from being confused for one another.
        let first = PayloadListener::bind().await.unwrap();
        let second = PayloadListener::bind().await.unwrap();
        assert_ne!(first.port(), second.port());
    }

    #[tokio::test]
    async fn a_payload_streams_over_a_real_loopback_socket_byte_for_byte() {
        let listener = PayloadListener::bind().await.unwrap();
        let port = listener.port();
        let body: Vec<u8> = (0..(CHUNK_BYTES * 2 + 777)).map(|i| (i % 251) as u8).collect();
        let expected = body.clone();

        let sender = tokio::spawn(async move {
            let mut stream = listener.accept().await.unwrap();
            let mut source = std::io::Cursor::new(body);
            let mut samples = Vec::new();
            stream_payload(&mut source, &mut stream, expected_len() as u64, |sent| {
                samples.push(sent)
            })
            .await
            .unwrap();
            stream.shutdown().await.unwrap();
            samples
        });

        let mut client = connect_to_payload(IpAddr::from([127, 0, 0, 1]), port).await.unwrap();
        let mut received = Vec::new();
        client.read_to_end(&mut received).await.unwrap();
        let samples = sender.await.unwrap();

        assert_eq!(received, expected, "every byte must survive the payload socket");
        assert!(samples.windows(2).all(|pair| pair[1] > pair[0]), "monotonic progress");
        assert_eq!(*samples.last().unwrap(), expected.len() as u64);
    }

    fn expected_len() -> usize {
        CHUNK_BYTES * 2 + 777
    }

    #[tokio::test]
    async fn a_zero_byte_payload_completes_without_reading_the_source() {
        let listener = PayloadListener::bind().await.unwrap();
        let port = listener.port();

        let sender = tokio::spawn(async move {
            let mut stream = listener.accept().await.unwrap();
            let mut source = std::io::Cursor::new(Vec::<u8>::new());
            stream_payload(&mut source, &mut stream, 0, |_| {}).await.unwrap();
            stream.shutdown().await.unwrap();
        });

        let mut client = connect_to_payload(IpAddr::from([127, 0, 0, 1]), port).await.unwrap();
        let mut received = Vec::new();
        client.read_to_end(&mut received).await.unwrap();
        sender.await.unwrap();
        assert!(received.is_empty());
    }

    #[tokio::test]
    async fn a_source_shorter_than_promised_is_an_error_not_a_truncated_send() {
        let listener = PayloadListener::bind().await.unwrap();
        let port = listener.port();

        let sender = tokio::spawn(async move {
            let mut stream = listener.accept().await.unwrap();
            let mut source = std::io::Cursor::new(vec![1_u8; 10]);
            // Promise 100 but only have 10.
            stream_payload(&mut source, &mut stream, 100, |_| {}).await
        });

        let mut client = connect_to_payload(IpAddr::from([127, 0, 0, 1]), port).await.unwrap();
        let mut sink = Vec::new();
        let _ = client.read_to_end(&mut sink).await;
        let result = sender.await.unwrap();

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("ended after 10 of 100"));
    }

    #[tokio::test]
    async fn a_receiver_that_never_arrives_times_out_rather_than_hanging() {
        let listener = PayloadListener::bind().await.unwrap();
        // Nothing ever connects. The accept must give up on its own.
        let started = std::time::Instant::now();
        let result = tokio::time::timeout(
            PAYLOAD_ACCEPT_TIMEOUT + Duration::from_secs(5),
            listener.accept(),
        )
        .await;
        assert!(result.is_ok(), "accept must not outlive its own timeout");
        assert!(result.unwrap().is_err(), "and it must report a failure");
        assert!(started.elapsed() < PAYLOAD_ACCEPT_TIMEOUT + Duration::from_secs(5));
    }

    #[tokio::test]
    async fn connecting_to_a_dead_port_fails_promptly() {
        // Bind then drop, so the port is almost certainly unused.
        let listener = PayloadListener::bind().await.unwrap();
        let port = listener.port();
        drop(listener);
        assert!(connect_to_payload(IpAddr::from([127, 0, 0, 1]), port).await.is_err());
    }
}
