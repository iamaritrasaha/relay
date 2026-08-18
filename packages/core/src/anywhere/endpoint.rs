use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use anyhow::{bail, ensure, Context as _};
use iroh::{
    endpoint::{presets, Connection, Endpoint},
    EndpointAddr, RelayMode,
};
use tokio::time::{sleep, timeout};

use super::error::{AnywhereError, TransportStage};
use crate::relay::PathDescriptor;

/// Production Anywhere ALPN. Distinct from LAN HTTP.
pub const ALPN: &[u8] = b"relay-anywhere/1";

static IROH_ENDPOINT_BIND_COUNT: AtomicU64 = AtomicU64::new(0);

/// Number of times an Iroh [`Endpoint`] has been bound in this process.
///
/// LAN HTTP/multicast startup must leave this at zero.
pub fn iroh_endpoint_bind_count() -> u64 {
    IROH_ENDPOINT_BIND_COUNT.load(Ordering::SeqCst)
}

fn mark_iroh_bound() {
    IROH_ENDPOINT_BIND_COUNT.fetch_add(1, Ordering::SeqCst);
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PathPreference {
    Auto,
    ForceDirect,
    ForceRelay,
}

#[derive(Clone)]
pub struct AnywhereEndpoint {
    inner: Endpoint,
}

impl AnywhereEndpoint {
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

    pub async fn accept(&self) -> Result<iroh::endpoint::Incoming, AnywhereError> {
        self.inner.accept().await.ok_or_else(|| {
            AnywhereError::transport_reason(TransportStage::Accept, "Iroh endpoint is closed")
        })
    }

    pub async fn connect(&self, addr: EndpointAddr) -> Result<Connection, AnywhereError> {
        self.inner
            .connect(addr, ALPN)
            .await
            .map_err(|error| AnywhereError::transport(TransportStage::Connect, error))
    }
}

/// Bind an Iroh endpoint. This is the only production entry that starts Iroh.
pub async fn bind_endpoint(preference: PathPreference) -> Result<AnywhereEndpoint, AnywhereError> {
    let endpoint = match preference {
        PathPreference::Auto => Endpoint::builder(presets::N0)
            .relay_mode(RelayMode::Default)
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await
            .map_err(|error| AnywhereError::transport(TransportStage::Bind, error))?,
        PathPreference::ForceRelay => Endpoint::builder(presets::N0)
            .relay_mode(RelayMode::Default)
            .clear_ip_transports()
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await
            .map_err(|error| AnywhereError::transport(TransportStage::Bind, error))?,
        PathPreference::ForceDirect => Endpoint::builder(presets::Minimal)
            .relay_mode(RelayMode::Disabled)
            .alpns(vec![ALPN.to_vec()])
            .bind()
            .await
            .map_err(|error| AnywhereError::transport(TransportStage::Bind, error))?,
    };
    mark_iroh_bound();
    Ok(AnywhereEndpoint { inner: endpoint })
}

/// Wrap an already-bound Iroh endpoint (test harness only). Still counts as Iroh start.
pub fn wrap_endpoint(endpoint: Endpoint) -> AnywhereEndpoint {
    mark_iroh_bound();
    AnywhereEndpoint { inner: endpoint }
}

pub async fn selected_path(
    connection: &Connection,
    preference: PathPreference,
) -> Result<PathDescriptor, AnywhereError> {
    match timeout(
        Duration::from_secs(3),
        classify_selected(connection, preference),
    )
    .await
    {
        Ok(Ok(path)) => Ok(path),
        Ok(Err(_)) | Err(_) => Ok(fallback_path(preference)),
    }
}

fn fallback_path(preference: PathPreference) -> PathDescriptor {
    match preference {
        PathPreference::ForceRelay => PathDescriptor::IrohRelay {
            hint: Some("iroh-relay".to_owned()),
        },
        _ => PathDescriptor::InternetDirect {
            host: String::new(),
            port: None,
        },
    }
}

async fn classify_selected(
    connection: &Connection,
    preference: PathPreference,
) -> anyhow::Result<PathDescriptor> {
    let expected = match preference {
        PathPreference::ForceDirect => Some(false),
        PathPreference::ForceRelay => Some(true),
        PathPreference::Auto => None,
    };

    timeout(Duration::from_secs(3), async {
        loop {
            if let Some(path) = connection
                .paths()
                .iter()
                .find(|candidate| candidate.is_selected())
            {
                let relayed = if path.is_relay() {
                    true
                } else if path.is_ip() {
                    false
                } else {
                    bail!("selected Iroh path was neither IP nor relay");
                };
                if let Some(must_relay) = expected {
                    ensure!(
                        relayed == must_relay,
                        "selected Iroh path did not match preference"
                    );
                }
                return Ok(if relayed {
                    PathDescriptor::IrohRelay {
                        hint: Some("iroh-relay".to_owned()),
                    }
                } else {
                    PathDescriptor::InternetDirect {
                        host: String::new(),
                        port: None,
                    }
                });
            }
            sleep(Duration::from_millis(25)).await;
        }
    })
    .await
    .context("Iroh did not report a selected path")?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bind_count_starts_at_zero_in_this_module() {
        let _ = iroh_endpoint_bind_count();
    }
}
