use std::{
    pin::Pin,
    task::{Context, Poll},
};

use iroh::endpoint::{RecvStream, SendStream};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

pub struct IrohBiStream {
    send: SendStream,
    recv: RecvStream,
}

impl IrohBiStream {
    pub fn new(send: SendStream, recv: RecvStream) -> Self {
        Self { send, recv }
    }

    #[allow(dead_code)]
    pub fn reset_send(&mut self) -> anyhow::Result<()> {
        self.send
            .reset(0_u8.into())
            .map_err(|error| anyhow::anyhow!("reset Iroh QUIC send stream: {error}"))
    }
}

impl AsyncRead for IrohBiStream {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.recv).poll_read(cx, buf)
    }
}

impl AsyncWrite for IrohBiStream {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.send)
            .poll_write(cx, buf)
            .map(|result| result.map_err(std::io::Error::other))
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.send).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.send).poll_shutdown(cx)
    }
}

pub fn client_peer_certificate_fingerprint<S>(
    stream: &tokio_rustls::client::TlsStream<S>,
) -> anyhow::Result<[u8; 32]>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    peer_certificate_fingerprint(stream.get_ref().1.peer_certificates())
}

pub fn server_peer_certificate_fingerprint<S>(
    stream: &tokio_rustls::server::TlsStream<S>,
) -> anyhow::Result<[u8; 32]>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    peer_certificate_fingerprint(stream.get_ref().1.peer_certificates())
}

fn peer_certificate_fingerprint(
    certificates: Option<&[rustls::pki_types::CertificateDer<'_>]>,
) -> anyhow::Result<[u8; 32]> {
    use localsend::crypto::cert::fingerprint_digest_from_cert_der;

    let leaf = certificates
        .and_then(|certs| certs.first())
        .ok_or_else(|| anyhow::anyhow!("inner TLS peer did not present a certificate"))?;
    Ok(fingerprint_digest_from_cert_der(leaf.as_ref()))
}
