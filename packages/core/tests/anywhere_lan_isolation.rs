//! LAN HTTP startup must not bind an Iroh endpoint.
#![cfg(feature = "anywhere")]

use localsend::anywhere::iroh_endpoint_bind_count;
use localsend::http::server::{start_with_port, ServerHandle};
use localsend::http::state::ClientInfo;
use tokio::sync::oneshot;

#[tokio::test]
async fn lan_server_start_does_not_bind_iroh() {
    let before = iroh_endpoint_bind_count();
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle: ServerHandle = start_with_port(
        0,
        None,
        ClientInfo {
            alias: "isolation".to_owned(),
            version: "2.2".to_owned(),
            device_model: None,
            device_type: None,
            token: "isolation".to_owned(),
        },
        None,
        None,
        None,
        stop_rx,
    )
    .await
    .unwrap();
    assert_eq!(iroh_endpoint_bind_count(), before);
    let _ = stop_tx.send(());
    handle.wait_stopped().await;
    assert_eq!(iroh_endpoint_bind_count(), before);
}

/// Constructing production Anywhere state must stay demand-driven: nothing
/// short of an explicit Anywhere operation may start Iroh.
#[test]
fn production_anywhere_setup_does_not_bind_iroh() {
    use localsend::anywhere::{AnywhereIdentity, AnywhereRuntime, RelayAddressV1};
    use localsend::crypto::relay_identity::RelayIdentity;

    let before = iroh_endpoint_bind_count();

    let identity = AnywhereIdentity::from_identity(RelayIdentity::generate()).unwrap();
    let runtime = AnywhereRuntime::new();
    let (session, cancel) = runtime.open_session();
    let (_request, _decision_rx) = runtime.register_incoming(session).unwrap();
    runtime.cancel(session);
    runtime.close_session(session);
    assert!(cancel.is_cancelled());
    assert!(RelayAddressV1::decode("RELAY1.not-base64!!").is_err());
    assert_eq!(identity.relay_id().len(), 64);

    assert_eq!(iroh_endpoint_bind_count(), before);
}
