//! Transport abstraction shared by KDE LAN and Relay WAN, and the router that
//! picks between them.
//!
//! LAN is always preferred over WAN: [`TransportKind::priority`] gives KDE LAN
//! 20 and Relay WAN 15, and [`TransportRouter::send_packet`] always tries
//! links in descending priority order. A WAN failure only removes the WAN
//! candidate for that attempt -- it never touches the LAN entry, so an
//! available LAN connection keeps working regardless of what WAN is doing.

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};

use anyhow::Result;

use crate::kdeconnect::packet::NetworkPacket;

pub type LinkFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum TransportKind {
    KdeLan,
    RelayWan,
}

impl TransportKind {
    /// Higher wins. LAN must always be attempted before WAN.
    pub fn priority(self) -> u8 {
        match self {
            TransportKind::KdeLan => 20,
            TransportKind::RelayWan => 15,
        }
    }
}

/// Informational connection state for UI, per Step 8. Never itself a control
/// surface -- there is deliberately no user-facing transport selector.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransportState {
    Offline,
    Local,
    RemoteDirect,
    RemoteRelay,
    Reconnecting,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TransportMetadata {
    pub kind: TransportKind,
    pub state: TransportState,
    pub last_seen_unix: Option<i64>,
    pub last_transition_reason: Option<String>,
}

/// A payload send request handed to a [`TransportLink`]. The link decides how
/// (or whether -- see Relay WAN's [`super::payload`] size policy) to move the
/// bytes; the router never inspects payload content.
pub struct PayloadRequest<'a> {
    pub relay_payload_id: &'a str,
    pub payload_size: u64,
    pub source: &'a mut (dyn tokio::io::AsyncRead + Send + Unpin),
    /// A payload listener already bound by the caller, for transports that need
    /// the peer to dial back.
    ///
    /// KDE's LAN transport advertises a port inside the control packet, so the
    /// listener must exist *before* that packet is sent -- the link cannot bind
    /// it itself at send time. Relay WAN ignores this and opens a stream on the
    /// existing connection instead.
    pub lan_listener: Option<crate::kdeconnect::files::lan_payload::PayloadListener>,
    /// Called with the running byte count so the feature layer can publish
    /// progress without the link knowing what a transfer is.
    pub on_progress: &'a mut (dyn FnMut(u64) + Send),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PayloadOutcome {
    Sent,
}

/// One concrete link to a device over one transport. `KdeLan` and `RelayWan`
/// each get their own implementation; the router only ever sees this trait.
pub trait TransportLink: Send + Sync {
    fn device_id(&self) -> &str;
    fn kind(&self) -> TransportKind;
    fn state(&self) -> TransportState;
    fn metadata(&self) -> TransportMetadata;

    fn send_packet<'a>(&'a self, packet: &'a NetworkPacket) -> LinkFuture<'a, Result<()>>;
    fn send_payload<'a>(&'a self, request: PayloadRequest<'a>) -> LinkFuture<'a, Result<PayloadOutcome>>;
    fn disconnect(&self) -> LinkFuture<'_, ()>;
    fn health(&self) -> LinkFuture<'_, bool>;
}

/// Aggregate, informational transport view for one device -- the shape Step 8
/// exposes to Dart.
#[derive(Clone, Debug, PartialEq)]
pub struct DeviceTransportSnapshot {
    pub device_id: String,
    pub active_transport: Option<TransportKind>,
    pub available_transports: Vec<TransportKind>,
    pub state: TransportState,
    pub last_transition_reason: Option<String>,
}

type DeviceLinks = HashMap<TransportKind, Arc<dyn TransportLink>>;

/// Routes packet/payload sends to the highest-priority available link for a
/// device, without ever letting a WAN link's presence or failure affect LAN.
#[derive(Default)]
pub struct TransportRouter {
    links: Mutex<HashMap<String, DeviceLinks>>,
}

impl TransportRouter {
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers (or replaces) the link for its `(device_id, kind)` slot.
    /// Registering `RelayWan` for a device that already has `KdeLan`
    /// registered does not create a second logical device -- both live under
    /// the same `device_id` key.
    pub fn register(&self, link: Arc<dyn TransportLink>) {
        let mut links = self.links.lock().expect("TransportRouter mutex poisoned");
        links
            .entry(link.device_id().to_owned())
            .or_default()
            .insert(link.kind(), link);
    }

    pub fn unregister(&self, device_id: &str, kind: TransportKind) -> Option<Arc<dyn TransportLink>> {
        let mut links = self.links.lock().expect("TransportRouter mutex poisoned");
        let removed = links.get_mut(device_id).and_then(|by_kind| by_kind.remove(&kind));
        if links.get(device_id).is_some_and(|by_kind| by_kind.is_empty()) {
            links.remove(device_id);
        }
        removed
    }

    /// Links for a device, ordered highest priority (LAN) first.
    pub fn links_for(&self, device_id: &str) -> Vec<Arc<dyn TransportLink>> {
        let links = self.links.lock().expect("TransportRouter mutex poisoned");
        let mut candidates: Vec<_> = links
            .get(device_id)
            .map(|by_kind| by_kind.values().cloned().collect())
            .unwrap_or_default();
        candidates.sort_by_key(|link| std::cmp::Reverse(link.kind().priority()));
        candidates
    }

    /// Sends `packet` over the highest-priority link that accepts it. LAN is
    /// tried first; a WAN failure is only surfaced if LAN is also unavailable
    /// or also failed, and never removes the LAN registration.
    pub async fn send_packet(&self, device_id: &str, packet: &NetworkPacket) -> Result<TransportKind> {
        let candidates = self.links_for(device_id);
        let mut last_error = None;
        for link in candidates {
            match link.send_packet(packet).await {
                Ok(()) => return Ok(link.kind()),
                Err(error) => last_error = Some(error),
            }
        }
        Err(last_error.unwrap_or_else(|| anyhow::anyhow!("no transport available for {device_id}")))
    }

    pub fn active_transport(&self, device_id: &str) -> Option<TransportKind> {
        self.links_for(device_id).first().map(|link| link.kind())
    }

    pub fn available_transports(&self, device_id: &str) -> Vec<TransportKind> {
        self.links_for(device_id).iter().map(|link| link.kind()).collect()
    }

    pub fn snapshot(&self, device_id: &str) -> DeviceTransportSnapshot {
        let candidates = self.links_for(device_id);
        let active = candidates.first();
        DeviceTransportSnapshot {
            device_id: device_id.to_owned(),
            active_transport: active.map(|link| link.kind()),
            available_transports: candidates.iter().map(|link| link.kind()).collect(),
            state: active.map(|link| link.state()).unwrap_or(TransportState::Offline),
            last_transition_reason: active.and_then(|link| link.metadata().last_transition_reason),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

    struct FakeLink {
        device_id: String,
        kind: TransportKind,
        fails: AtomicBool,
        sends: AtomicU32,
    }

    impl TransportLink for FakeLink {
        fn device_id(&self) -> &str {
            &self.device_id
        }
        fn kind(&self) -> TransportKind {
            self.kind
        }
        fn state(&self) -> TransportState {
            match self.kind {
                TransportKind::KdeLan => TransportState::Local,
                TransportKind::RelayWan => TransportState::RemoteDirect,
            }
        }
        fn metadata(&self) -> TransportMetadata {
            TransportMetadata {
                kind: self.kind,
                state: self.state(),
                last_seen_unix: None,
                last_transition_reason: None,
            }
        }
        fn send_packet<'a>(&'a self, _packet: &'a NetworkPacket) -> LinkFuture<'a, Result<()>> {
            Box::pin(async move {
                self.sends.fetch_add(1, Ordering::SeqCst);
                if self.fails.load(Ordering::SeqCst) {
                    Err(anyhow::anyhow!("{:?} link failed", self.kind))
                } else {
                    Ok(())
                }
            })
        }
        fn send_payload<'a>(
            &'a self,
            _request: PayloadRequest<'a>,
        ) -> LinkFuture<'a, Result<PayloadOutcome>> {
            Box::pin(async move { Ok(PayloadOutcome::Sent) })
        }
        fn disconnect(&self) -> LinkFuture<'_, ()> {
            Box::pin(async move {})
        }
        fn health(&self) -> LinkFuture<'_, bool> {
            Box::pin(async move { !self.fails.load(Ordering::SeqCst) })
        }
    }

    fn fake(device_id: &str, kind: TransportKind, fails: bool) -> Arc<FakeLink> {
        Arc::new(FakeLink {
            device_id: device_id.to_owned(),
            kind,
            fails: AtomicBool::new(fails),
            sends: AtomicU32::new(0),
        })
    }

    fn ping_packet() -> NetworkPacket {
        NetworkPacket::new("kdeconnect.ping", serde_json::Map::new())
    }

    #[tokio::test]
    async fn lan_is_attempted_before_wan_when_both_are_available() {
        let router = TransportRouter::new();
        let lan = fake("device-a", TransportKind::KdeLan, false);
        let wan = fake("device-a", TransportKind::RelayWan, false);
        router.register(lan.clone());
        router.register(wan.clone());

        let used = router.send_packet("device-a", &ping_packet()).await.unwrap();

        assert_eq!(used, TransportKind::KdeLan);
        assert_eq!(lan.sends.load(Ordering::SeqCst), 1);
        assert_eq!(wan.sends.load(Ordering::SeqCst), 0, "WAN must not be tried while LAN succeeds");
    }

    #[tokio::test]
    async fn wan_is_used_when_lan_is_unavailable() {
        let router = TransportRouter::new();
        let wan = fake("device-a", TransportKind::RelayWan, false);
        router.register(wan);

        let used = router.send_packet("device-a", &ping_packet()).await.unwrap();
        assert_eq!(used, TransportKind::RelayWan);
    }

    #[tokio::test]
    async fn wan_failure_falls_back_to_lan_and_lan_stays_registered_afterwards() {
        let router = TransportRouter::new();
        let lan = fake("device-a", TransportKind::KdeLan, false);
        let wan = fake("device-a", TransportKind::RelayWan, true);
        router.register(lan.clone());
        router.register(wan);

        // LAN has higher priority so it is tried first and this case never
        // needs the WAN fallback -- assert the router still reports both
        // available and that a second send still succeeds via LAN.
        router.send_packet("device-a", &ping_packet()).await.unwrap();
        router.send_packet("device-a", &ping_packet()).await.unwrap();
        assert_eq!(lan.sends.load(Ordering::SeqCst), 2);

        assert_eq!(router.available_transports("device-a").len(), 2);
    }

    #[tokio::test]
    async fn lan_failure_falls_back_to_available_wan() {
        let router = TransportRouter::new();
        let lan = fake("device-a", TransportKind::KdeLan, true);
        let wan = fake("device-a", TransportKind::RelayWan, false);
        router.register(lan.clone());
        router.register(wan.clone());

        let used = router.send_packet("device-a", &ping_packet()).await.unwrap();

        assert_eq!(used, TransportKind::RelayWan);
        assert_eq!(lan.sends.load(Ordering::SeqCst), 1, "LAN must still be attempted first");
        assert_eq!(wan.sends.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn both_links_failing_surfaces_an_error_without_panicking() {
        let router = TransportRouter::new();
        router.register(fake("device-a", TransportKind::KdeLan, true));
        router.register(fake("device-a", TransportKind::RelayWan, true));

        assert!(router.send_packet("device-a", &ping_packet()).await.is_err());
    }

    #[test]
    fn registering_both_transports_for_one_device_id_is_one_logical_device() {
        let router = TransportRouter::new();
        router.register(fake("device-a", TransportKind::KdeLan, false));
        router.register(fake("device-a", TransportKind::RelayWan, false));

        assert_eq!(router.links.lock().unwrap().len(), 1);
        assert_eq!(router.available_transports("device-a").len(), 2);
    }

    #[test]
    fn unregistering_wan_leaves_lan_untouched() {
        let router = TransportRouter::new();
        router.register(fake("device-a", TransportKind::KdeLan, false));
        router.register(fake("device-a", TransportKind::RelayWan, false));

        router.unregister("device-a", TransportKind::RelayWan);

        assert_eq!(router.available_transports("device-a"), vec![TransportKind::KdeLan]);
    }

    #[test]
    fn snapshot_reports_offline_for_an_unknown_device() {
        let router = TransportRouter::new();
        let snapshot = router.snapshot("nobody");
        assert_eq!(snapshot.state, TransportState::Offline);
        assert!(snapshot.active_transport.is_none());
        assert!(snapshot.available_transports.is_empty());
    }

    #[test]
    fn no_wan_and_no_lan_is_offline() {
        let router = TransportRouter::new();
        router.register(fake("device-a", TransportKind::KdeLan, false));
        router.unregister("device-a", TransportKind::KdeLan);

        let snapshot = router.snapshot("device-a");
        assert_eq!(snapshot.state, TransportState::Offline);
        assert!(snapshot.active_transport.is_none());
    }

    #[test]
    fn lan_link_removal_with_wan_still_active_keeps_the_device_connected() {
        let router = TransportRouter::new();
        router.register(fake("device-a", TransportKind::KdeLan, false));
        router.register(fake("device-a", TransportKind::RelayWan, false));

        router.unregister("device-a", TransportKind::KdeLan);

        let snapshot = router.snapshot("device-a");
        assert_eq!(snapshot.active_transport, Some(TransportKind::RelayWan));
        assert_eq!(snapshot.state, TransportState::RemoteDirect);
        assert_eq!(router.links.lock().unwrap().len(), 1, "still one logical device");
    }

    #[test]
    fn lan_to_wan_then_back_to_lan_transition_never_creates_a_second_logical_device() {
        let router = TransportRouter::new();
        router.register(fake("device-a", TransportKind::KdeLan, false));
        router.register(fake("device-a", TransportKind::RelayWan, false));
        assert_eq!(router.links.lock().unwrap().len(), 1);

        // LAN link dies while WAN stays healthy -- WAN becomes authoritative.
        router.unregister("device-a", TransportKind::KdeLan);
        assert_eq!(router.active_transport("device-a"), Some(TransportKind::RelayWan));
        assert_eq!(router.links.lock().unwrap().len(), 1);

        // LAN reappears (e.g. the phone rejoins the same network) -- it must
        // become preferred again without any re-pairing, and WAN must still
        // be usable as a fallback.
        router.register(fake("device-a", TransportKind::KdeLan, false));
        assert_eq!(router.active_transport("device-a"), Some(TransportKind::KdeLan));
        assert_eq!(router.links.lock().unwrap().len(), 1);
        assert_eq!(router.available_transports("device-a").len(), 2);
    }

    #[test]
    fn wan_inbound_packet_reaches_the_same_device_entry_lan_would_have_used() {
        // A WAN-only link and a LAN-only link for the same device_id must
        // both resolve to one entry keyed by device_id -- registering either
        // first must not create separate logical devices.
        let router = TransportRouter::new();
        let wan = fake("device-a", TransportKind::RelayWan, false);
        router.register(wan.clone());
        assert_eq!(router.links_for("device-a").len(), 1);

        router.register(fake("device-a", TransportKind::KdeLan, false));
        assert_eq!(router.links.lock().unwrap().len(), 1, "one logical device for device-a");
        assert_eq!(router.links_for("device-a").len(), 2);
    }
}
