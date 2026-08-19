//! Lazy, reusable production listener for Relay Anywhere.
//!
//! Starting this listener is the only inbound operation that binds Iroh. It
//! owns a stable routing endpoint, while every accepted connection receives a
//! fresh session id and fresh receive approval through [`AnywhereRuntime`].

use std::sync::Arc;

use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::continuity_link::{accept_continuity, spawn_link, ContinuityLink, CONTINUITY_ALPN};
use super::endpoint::{bind_endpoint_with_key, AnywhereEndpoint, PathPreference};
use super::transfer::{
    receive_on_connection, wait_online, AnywhereEvent, AnywhereEventSink, AnywhereReceiveRequest,
};
use super::{
    AnywhereError, AnywhereIdentity, AnywhereRoutingKey, AnywhereRuntime, AnywhereSessionId,
    RelayAddressV1,
};

/// Everything the listener needs to serve an inbound continuity connection.
///
/// The factory is called once per accepted connection so each session gets its
/// own event sink and host channel; the trust directory and permission store it
/// closes over are shared and read live, which is what makes revoking a
/// capability take effect on the next message rather than the next restart.
#[derive(Clone)]
pub struct ContinuityAcceptConfig {
    pub session_config: Arc<dyn Fn() -> crate::continuity::ContinuitySessionConfig + Send + Sync>,
    pub links: tokio::sync::mpsc::Sender<crate::continuity::ContinuitySessionHandle>,
}

/// Listener configuration. The Routing key is separate from the Relay
/// identity and remains an opaque platform-secret-store value.
///
/// `continuity` is `None` unless the user has enabled at least one continuity
/// capability, so an install that only transfers files never serves the
/// continuity ALPN.
#[derive(Clone)]
pub struct AnywhereListenerConfig {
    pub identity: AnywhereIdentity,
    pub routing_key: AnywhereRoutingKey,
    pub preference: PathPreference,
    pub alias: String,
    pub continuity: Option<ContinuityAcceptConfig>,
}

/// Transport-neutral listener events. Transfer progress and completion are
/// forwarded from the existing v2 authenticated-stream implementation.
#[derive(Clone, Debug)]
pub enum AnywhereListenerEvent {
    AddressReady {
        address: String,
        local_relay_id: String,
    },
    Session {
        session_id: AnywhereSessionId,
        event: AnywhereEvent,
    },
    SessionFailed {
        session_id: AnywhereSessionId,
        category: String,
        stage: Option<String>,
    },
    Stopped,
}

pub type AnywhereListenerEventSink = Arc<dyn Fn(AnywhereListenerEvent) + Send + Sync>;

/// A running listener. Dropping it does not silently keep the endpoint alive;
/// callers must invoke [`Self::shutdown`] as part of service shutdown.
pub struct AnywhereListener {
    endpoint: AnywhereEndpoint,
    address: String,
    local_relay_id: String,
    cancel: CancellationToken,
    accept_task: JoinHandle<()>,
}

impl AnywhereListener {
    /// Starts one endpoint and an accept loop. Constructing configuration alone
    /// never binds Iroh; this explicit call is the capability activation point.
    pub async fn start(
        runtime: Arc<AnywhereRuntime>,
        config: AnywhereListenerConfig,
        events: AnywhereListenerEventSink,
    ) -> Result<Self, AnywhereError> {
        let endpoint =
            bind_endpoint_with_key(config.preference, Some(config.routing_key.secret_key()))
                .await?;
        let cancel = CancellationToken::new();
        wait_online(&endpoint, config.preference, &cancel).await?;
        let address = RelayAddressV1::new(config.identity.relay_id().to_owned(), endpoint.addr())
            .and_then(|address| address.encode())
            .map_err(|error| AnywhereError::transport(super::TransportStage::Bind, error))?;
        (events)(AnywhereListenerEvent::AddressReady {
            address: address.clone(),
            local_relay_id: config.identity.relay_id().to_owned(),
        });

        let accept_endpoint = endpoint.clone();
        let accept_cancel = cancel.clone();
        let accept_events = events.clone();
        let accept_config = config.clone();
        let accept_task = tokio::spawn(async move {
            loop {
                let incoming = tokio::select! {
                    _ = accept_cancel.cancelled() => break,
                    incoming = accept_endpoint.accept() => match incoming {
                        Ok(incoming) => incoming,
                        Err(error) => {
                            tracing::warn!("Anywhere listener accept failed: {error}");
                            continue;
                        }
                    },
                };
                let runtime = runtime.clone();
                let config = accept_config.clone();
                let events = accept_events.clone();
                let listener_cancel = accept_cancel.clone();
                tokio::spawn(async move {
                    let connection = tokio::select! {
                        _ = listener_cancel.cancelled() => return,
                        connection = incoming => match connection {
                            Ok(connection) => connection,
                            Err(error) => {
                                tracing::warn!("Anywhere listener connection failed: {error}");
                                return;
                            }
                        },
                    };

                    // Continuity and transfer are separate protocols on one
                    // endpoint. Dispatching on the negotiated ALPN keeps the
                    // transfer wire format untouched.
                    if connection.alpn() == CONTINUITY_ALPN {
                        let Some(continuity) = config.continuity.clone() else {
                            // Continuity is not enabled on this device; refuse
                            // rather than half-serving it.
                            connection.close(0_u32.into(), b"continuity disabled");
                            return;
                        };
                        serve_continuity(connection, &config, continuity, listener_cancel).await;
                        return;
                    }

                    let (session_id, session_cancel) = runtime.open_session();
                    let event_sink: AnywhereEventSink = Arc::new({
                        let events = events.clone();
                        move |event| {
                            events(AnywhereListenerEvent::Session { session_id, event });
                        }
                    });
                    let result = tokio::select! {
                        _ = listener_cancel.cancelled() => Err(AnywhereError::Cancelled),
                        _ = session_cancel.cancelled() => Err(AnywhereError::Cancelled),
                        outcome = receive_on_connection(
                            runtime.clone(),
                            session_id,
                            session_cancel.clone(),
                            AnywhereReceiveRequest {
                                identity: config.identity,
                                preference: config.preference,
                                alias: config.alias,
                                expected_remote_relay_id: None,
                            },
                            connection,
                            event_sink,
                        ) => outcome,
                    };
                    if let Err(error) = result {
                        events(AnywhereListenerEvent::SessionFailed {
                            session_id,
                            category: error.category().to_owned(),
                            stage: error.stage().map(str::to_owned),
                        });
                    }
                    runtime.close_session(session_id);
                });
            }
            accept_events(AnywhereListenerEvent::Stopped);
        });

        Ok(Self {
            endpoint,
            address,
            local_relay_id: config.identity.relay_id().to_owned(),
            cancel,
            accept_task,
        })
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    pub fn local_relay_id(&self) -> &str {
        &self.local_relay_id
    }

    /// Cancels only the listener accept loop and closes its endpoint. Existing
    /// inbound sessions have their own runtime cancellation handles.
    pub async fn shutdown(self) {
        self.cancel.cancel();
        self.endpoint.close().await;
        let _ = self.accept_task.await;
    }
}

/// Authenticates and serves one inbound continuity connection.
///
/// Authorization is *not* performed here: `run_session` re-checks the trust
/// record and the per-capability grant against the proven RelayId, so there is
/// exactly one place that decides.
async fn serve_continuity(
    connection: iroh::endpoint::Connection,
    config: &AnywhereListenerConfig,
    continuity: ContinuityAcceptConfig,
    cancel: CancellationToken,
) {
    let accepted = accept_continuity(connection, &config.identity, config.preference).await;
    let (session, stream) = match accepted {
        Ok(accepted) => accepted,
        Err(error) => {
            tracing::warn!("continuity authentication failed: {}", error.category());
            return;
        }
    };
    let link: ContinuityLink = spawn_link(stream, session, (continuity.session_config)(), cancel);
    let _ = continuity.links.send(link.handle().clone()).await;
    let _ = link.shutdown().await;
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use crate::anywhere::{iroh_endpoint_bind_count, RelayAddressV1};
    use crate::crypto::relay_identity::RelayIdentity;

    use super::*;

    #[tokio::test]
    async fn listener_starts_lazily_with_the_persisted_routing_endpoint() {
        let runtime = Arc::new(AnywhereRuntime::new());
        let identity = AnywhereIdentity::from_identity(RelayIdentity::generate()).unwrap();
        let routing_key = AnywhereRoutingKey::generate();
        let expected_endpoint_id = routing_key.endpoint_id();
        let events = Arc::new(Mutex::new(Vec::new()));
        let event_sink: AnywhereListenerEventSink = Arc::new({
            let events = events.clone();
            move |event| events.lock().unwrap().push(event)
        });
        let before = iroh_endpoint_bind_count();
        let listener = AnywhereListener::start(
            runtime,
            AnywhereListenerConfig {
                identity: identity.clone(),
                routing_key,
                preference: PathPreference::ForceDirect,
                alias: "listener-test".to_owned(),
                continuity: None,
            },
            event_sink,
        )
        .await
        .unwrap();

        assert_eq!(iroh_endpoint_bind_count(), before + 1);
        let address = RelayAddressV1::decode(listener.address()).unwrap();
        assert_eq!(address.endpoint.id, expected_endpoint_id);
        assert_eq!(listener.local_relay_id(), identity.relay_id());
        listener.shutdown().await;
        assert!(events
            .lock()
            .unwrap()
            .iter()
            .any(|event| matches!(event, AnywhereListenerEvent::Stopped)));
    }
}
