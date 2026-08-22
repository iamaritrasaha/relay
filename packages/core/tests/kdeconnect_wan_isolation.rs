//! KDE LAN startup must not bind a Relay WAN Iroh endpoint.
#![cfg(feature = "kdeconnect-wan")]

use relay_core::kdeconnect::wan::wan_iroh_endpoint_bind_count;
use relay_core::kdeconnect::{BindMode, KdeConnectConfig, KdeConnectHandle, LanConfig, LocalIdentity};

#[tokio::test]
async fn kdeconnect_lan_start_does_not_bind_relay_wan_iroh() {
    let before = wan_iroh_endpoint_bind_count();

    let identity = LocalIdentity::generate("isolation-test").unwrap();
    let handle = KdeConnectHandle::start(KdeConnectConfig {
        identity,
        trusted: vec![],
        lan: LanConfig {
            bind: BindMode::Loopback,
            allow_loopback: true,
        },
        run_commands: Vec::new(),
    })
    .await
    .unwrap();

    assert_eq!(wan_iroh_endpoint_bind_count(), before);
    handle.stop();
    assert_eq!(wan_iroh_endpoint_bind_count(), before);
}
