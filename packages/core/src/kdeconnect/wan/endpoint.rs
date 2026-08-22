//! Relay WAN Iroh endpoint: incoming/outgoing connections on ALPN
//! `relay-wan/1`, using the standard Iroh/n0 relay infrastructure (no custom
//! signaling server). Direct QUIC is used when available; Iroh's relay is the
//! fallback; path migration is handled internally by Iroh -- none of that is
//! reimplemented here.

use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{Context, Result};
use iroh::{
    endpoint::{presets, Connection, Endpoint, Incoming},
    EndpointAddr, RelayMode,
};

use super::identity::WanIdentity;

/// Relay WAN ALPN. Distinct from LAN HTTP, Relay Anywhere (`relay-anywhere/1`),
/// and continuity -- a Relay WAN dial can never land in another protocol's
/// accept path.
pub const WAN_ALPN: &[u8] = b"relay-wan/1";

static WAN_IROH_ENDPOINT_BIND_COUNT: AtomicU64 = AtomicU64::new(0);

/// Number of times a Relay WAN Iroh endpoint has been bound in this process.
/// KDE LAN startup ([`crate::kdeconnect::KdeConnectHandle::start`]) must leave
/// this at zero: Iroh is only started by an explicit Relay WAN operation.
pub fn wan_iroh_endpoint_bind_count() -> u64 {
    WAN_IROH_ENDPOINT_BIND_COUNT.load(Ordering::SeqCst)
}

fn mark_bound() {
    WAN_IROH_ENDPOINT_BIND_COUNT.fetch_add(1, Ordering::SeqCst);
}

#[derive(Clone)]
pub struct WanEndpoint {
    inner: Endpoint,
}

impl WanEndpoint {
    pub fn inner(&self) -> &Endpoint {
        &self.inner
    }

    pub fn addr(&self) -> EndpointAddr {
        self.inner.addr()
    }

    pub async fn online(&self) {
        self.inner.online().await;
    }

    pub async fn close(self) {
        self.inner.close().await;
    }

    pub async fn accept(&self) -> Result<Incoming> {
        self.inner
            .accept()
            .await
            .context("Relay WAN Iroh endpoint is closed")
    }

    pub async fn connect(&self, addr: EndpointAddr) -> Result<Connection> {
        self.inner
            .connect(addr, WAN_ALPN)
            .await
            .context("Relay WAN connect failed")
    }
}

/// Binds the persistent Relay WAN endpoint using the installation's
/// [`WanIdentity`]. Direct QUIC + Iroh relay fallback via the default n0
/// preset; no custom signaling server is involved.
pub async fn bind_wan_endpoint(identity: &WanIdentity) -> Result<WanEndpoint> {
    let endpoint = Endpoint::builder(presets::N0)
        .relay_mode(RelayMode::Default)
        .alpns(vec![WAN_ALPN.to_vec()])
        .secret_key(identity.secret_key())
        .bind()
        .await
        .context("bind Relay WAN Iroh endpoint")?;
    mark_bound();
    Ok(WanEndpoint { inner: endpoint })
}

/// Wraps an already-bound endpoint for test harnesses. Still counts as a bind.
#[cfg(test)]
pub fn wrap_endpoint_for_test(endpoint: Endpoint) -> WanEndpoint {
    mark_bound();
    WanEndpoint { inner: endpoint }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bind_count_is_readable_in_this_module() {
        let _ = wan_iroh_endpoint_bind_count();
    }
}
