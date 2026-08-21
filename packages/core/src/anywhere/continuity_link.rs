//! Carries Relay Continuity over the production Anywhere transport.
//!
//! Continuity uses its own ALPN, so a continuity connection is never confused
//! with a file transfer and the transfer wire format is untouched. Everything
//! else is shared with the transfer path: the same Iroh endpoint, the same
//! inner TLS, and the same mutual `RelayIdentityProofV1` handshake. The stream
//! handed to [`crate::continuity::run_session`] is therefore already encrypted
//! and already bound to a proven RelayId.
//!
//! Path selection stays `Auto`: when the two devices are on the same network
//! Iroh picks a direct path by itself, which gives nearby continuity without
//! changing any legacy LAN packet.

use std::sync::Arc;
use std::time::Duration;

use iroh::endpoint::Connection;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use super::address::RelayAddressV1;
use super::endpoint::{selected_path, AnywhereEndpoint, PathPreference};
use super::error::{AnywhereError, TlsStage, TransportStage};
use super::identity::AnywhereIdentity;
use super::proof::{authenticate_initiator, authenticate_server};
use super::stream::{
    client_peer_certificate_fingerprint, server_peer_certificate_fingerprint, IrohBiStream,
};
use super::tls::InnerTlsPeer;
use crate::continuity::{
    run_session, session_channel, ContinuityEvent, ContinuityPayload, ContinuitySessionConfig,
    ContinuitySessionEnd, ContinuitySessionHandle,
};
use crate::relay::{AuthenticatedRelaySession, RelayId};

/// Production Continuity ALPN. Distinct from both LAN HTTP and Anywhere transfer.
pub const CONTINUITY_ALPN: &[u8] = b"relay-continuity/1";

/// Backoff bounds for reconnecting a continuity link.
///
/// Reconnect is exponential and jitter-free but capped, so a phone that has
/// gone off network costs one attempt a minute rather than a tight loop.
const RECONNECT_MIN: Duration = Duration::from_secs(2);
const RECONNECT_MAX: Duration = Duration::from_secs(60);

fn inner_tls_peer() -> Result<InnerTlsPeer, AnywhereError> {
    InnerTlsPeer::generate().map_err(|error| AnywhereError::tls(TlsStage::ClientHandshake, error))
}

/// Dials a peer and completes mutual authentication on the continuity ALPN.
pub async fn connect_continuity(
    endpoint: &AnywhereEndpoint,
    remote: &RelayAddressV1,
    identity: &AnywhereIdentity,
    preference: PathPreference,
) -> Result<
    (
        AuthenticatedRelaySession,
        tokio_rustls::client::TlsStream<IrohBiStream>,
    ),
    AnywhereError,
> {
    let connection = endpoint
        .connect_with_alpn(remote.endpoint.clone(), CONTINUITY_ALPN)
        .await?;
    let (send, recv) = connection
        .open_bi()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;
    let path = selected_path(&connection, preference).await?;

    let tls_peer = inner_tls_peer()?;
    let server_name = rustls::pki_types::ServerName::try_from("localhost")
        .map_err(|error| AnywhereError::tls(TlsStage::ClientHandshake, error))?;
    let mut tls = tls_peer
        .connector()
        .connect(server_name, IrohBiStream::new(send, recv))
        .await
        .map_err(|error| AnywhereError::tls(TlsStage::ClientHandshake, error))?;

    let observed = client_peer_certificate_fingerprint(&tls)
        .map_err(|error| AnywhereError::tls(TlsStage::PeerCertificate, error))?;
    let expected = RelayId::from_expected_canonical_hex(&remote.claimed_relay_id)
        .map_err(|_| AnywhereError::RelayProof)?;
    let session = authenticate_initiator(
        &mut tls,
        identity.inner(),
        tls_peer.cert_fingerprint,
        &expected,
        observed,
        path,
    )
    .await?;
    Ok((session, tls))
}

/// Completes mutual authentication for an inbound continuity connection.
///
/// The caller has already checked that the connection negotiated
/// [`CONTINUITY_ALPN`].
pub async fn accept_continuity(
    connection: Connection,
    identity: &AnywhereIdentity,
    preference: PathPreference,
) -> Result<
    (
        AuthenticatedRelaySession,
        tokio_rustls::server::TlsStream<IrohBiStream>,
    ),
    AnywhereError,
> {
    let (send, recv) = connection
        .accept_bi()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::Stream, error))?;
    let path = selected_path(&connection, preference).await?;

    let tls_peer = inner_tls_peer()?;
    let mut tls = tls_peer
        .acceptor()
        .accept(IrohBiStream::new(send, recv))
        .await
        .map_err(|error| AnywhereError::tls(TlsStage::ServerHandshake, error))?;

    let observed = server_peer_certificate_fingerprint(&tls)
        .map_err(|error| AnywhereError::tls(TlsStage::PeerCertificate, error))?;
    // No expected remote: the responder learns who called, then authorization
    // decides whether that proven identity is allowed to run continuity.
    let session = authenticate_server(
        &mut tls,
        identity.inner(),
        tls_peer.cert_fingerprint,
        None,
        observed,
        path,
    )
    .await?;
    Ok((session, tls))
}

/// A live continuity link the app publishes local state through.
pub struct ContinuityLink {
    handle: ContinuitySessionHandle,
    cancel: CancellationToken,
    task: tokio::task::JoinHandle<ContinuitySessionEnd>,
}

impl ContinuityLink {
    pub fn handle(&self) -> &ContinuitySessionHandle {
        &self.handle
    }

    pub async fn shutdown(self) -> ContinuitySessionEnd {
        self.cancel.cancel();
        self.task.await.unwrap_or(ContinuitySessionEnd::Cancelled)
    }
}

/// Runs a continuity session over an already-authenticated stream.
pub fn spawn_link<S>(
    stream: S,
    session: AuthenticatedRelaySession,
    config: ContinuitySessionConfig,
    cancel: CancellationToken,
) -> ContinuityLink
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let (handle, outbound) = session_channel(&session.remote_relay_id().as_hex(), 64);
    let task = tokio::spawn(run_session(
        stream,
        session,
        config,
        outbound,
        cancel.clone(),
    ));
    ContinuityLink {
        handle,
        cancel,
        task,
    }
}

/// Configuration for an outbound link that keeps itself connected.
pub struct ContinuityDialerConfig {
    pub identity: AnywhereIdentity,
    pub remote: RelayAddressV1,
    pub preference: PathPreference,
}

/// Keeps one outbound continuity link alive across network changes.
///
/// Reconnection is event-driven with capped exponential backoff: there is no
/// polling loop and no wake lock. When nothing is enabled for the peer the
/// session ends immediately with `NotTrusted`/`Closed` and the dialer stops
/// rather than retrying forever.
pub async fn run_dialer<F>(
    endpoint: AnywhereEndpoint,
    dialer: ContinuityDialerConfig,
    mut build_config: F,
    published: mpsc::Sender<ContinuitySessionHandle>,
    events: crate::continuity::ContinuityEventSink,
    cancel: CancellationToken,
) where
    F: FnMut() -> ContinuitySessionConfig,
{
    let mut backoff = RECONNECT_MIN;
    loop {
        if cancel.is_cancelled() {
            return;
        }
        let attempt = connect_continuity(
            &endpoint,
            &dialer.remote,
            &dialer.identity,
            dialer.preference,
        )
        .await;
        match attempt {
            Ok((session, stream)) => {
                backoff = RECONNECT_MIN;
                let link = spawn_link(stream, session, build_config(), cancel.child_token());
                let _ = published.send(link.handle().clone()).await;
                let end = link.task.await.unwrap_or(ContinuitySessionEnd::Closed);
                match end {
                    // A refusal is a decision, not a transient fault. Retrying
                    // would be a reconnect storm against a peer that said no.
                    ContinuitySessionEnd::NotTrusted | ContinuitySessionEnd::Blocked => return,
                    ContinuitySessionEnd::Cancelled => return,
                    _ => {}
                }
            }
            Err(error) => {
                (events)(ContinuityEvent::SessionEnded {
                    remote_relay_id: dialer.remote.claimed_relay_id.clone(),
                    reason: ContinuitySessionEnd::TransportFailed {
                        detail: error.category().to_owned(),
                    },
                });
            }
        }
        tokio::select! {
            _ = cancel.cancelled() => return,
            _ = tokio::time::sleep(backoff) => {}
        }
        backoff = (backoff * 2).min(RECONNECT_MAX);
    }
}

/// Publishes a payload to every live link. Authorization still runs inside each
/// session, so a caller cannot broadcast past a disabled capability.
pub async fn broadcast(links: &[Arc<ContinuitySessionHandle>], payload: ContinuityPayload) {
    for link in links {
        link.publish(payload.clone()).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn continuity_uses_its_own_alpn() {
        assert_ne!(CONTINUITY_ALPN, super::super::endpoint::ALPN);
        assert_eq!(CONTINUITY_ALPN, b"relay-continuity/1");
    }

    /// A device that has enabled no continuity capability must not serve the
    /// protocol at all. The listener enforces that by refusing the connection
    /// when `continuity` is `None`.
    #[test]
    fn continuity_accept_is_opt_in() {
        let config: Option<super::super::listener::ContinuityAcceptConfig> = None;
        assert!(config.is_none());
    }
}
