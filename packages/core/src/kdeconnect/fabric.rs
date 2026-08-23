//! The Relay Device Fabric: one authoritative record per logical device.
//!
//! A physical device has exactly **one** identity in the product. LAN and Relay
//! WAN are routes *to* that device, never devices of their own, so nothing here
//! ever yields a "Phone (LAN)" and a "Phone (WAN)".
//!
//! # Why this module exists
//!
//! Connection state used to be re-derived independently by several surfaces --
//! the overview, device details, the messages view and the GNOME status pill
//! each inspected a display string. That is how a device came to be labelled
//! `Local` while it was actually offline. [`RelayConnectionState::derive`] is now
//! the single place that decision is made; everything else consumes it.
//!
//! # What belongs here, and what does not
//!
//! The fabric owns identity, trust, routes, connection and the capability set.
//! It deliberately does **not** own message bodies, notification lists or
//! transfer byte counters: those live in their own stores, keyed by the same
//! logical device id. Keeping them out avoids one giant mutable object while
//! still giving every store a common key.
//!
//! Trust persists. Route availability is runtime truth, recomputed from live
//! evidence and never restored from disk -- a remembered device is not a
//! connected one.

use std::collections::BTreeSet;

/// Physical form factor, normalised from whatever the peer called itself.
///
/// Peers describe themselves inconsistently ("phone", "smartphone",
/// "computer"), and letting those strings reach the UI produces subtly
/// different behaviour per platform. Mapping once, here, keeps the comparison
/// in a single tested place.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum RelayDeviceClass {
    Desktop,
    Laptop,
    Phone,
    Tablet,
    Tv,
    Other,
}

impl RelayDeviceClass {
    /// Maps a KDE Connect / Relay `deviceType` string onto the Relay enum.
    ///
    /// Unknown values become [`RelayDeviceClass::Other`] rather than guessing:
    /// showing a laptop icon for something Relay has never heard of is worse
    /// than showing a neutral one.
    pub fn from_peer_string(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "desktop" | "computer" | "pc" => RelayDeviceClass::Desktop,
            "laptop" | "notebook" => RelayDeviceClass::Laptop,
            "phone" | "smartphone" | "mobile" => RelayDeviceClass::Phone,
            "tablet" => RelayDeviceClass::Tablet,
            "tv" | "television" => RelayDeviceClass::Tv,
            _ => RelayDeviceClass::Other,
        }
    }

    /// Whether this is a handheld, for surfaces that only present mobiles.
    pub fn is_mobile(self) -> bool {
        matches!(self, RelayDeviceClass::Phone | RelayDeviceClass::Tablet)
    }

    pub fn as_str(self) -> &'static str {
        match self {
            RelayDeviceClass::Desktop => "desktop",
            RelayDeviceClass::Laptop => "laptop",
            RelayDeviceClass::Phone => "phone",
            RelayDeviceClass::Tablet => "tablet",
            RelayDeviceClass::Tv => "tv",
            RelayDeviceClass::Other => "other",
        }
    }
}

/// How a device is reachable right now.
///
/// The single source of truth for "is this device Local, Remote or Offline".
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RelayConnectionState {
    Offline,
    Local,
    RemoteDirect,
    RemoteRelay,
    Reconnecting,
}

impl RelayConnectionState {
    /// The one derivation. LAN always wins when it is healthy.
    ///
    /// `reconnecting` only applies when nothing is currently usable: a device
    /// with a working route is connected, whatever a reconnect attempt is doing
    /// in the background.
    pub fn derive(lan_healthy: bool, wan_healthy: bool, wan_relayed: bool, reconnecting: bool) -> Self {
        if lan_healthy {
            return RelayConnectionState::Local;
        }
        if wan_healthy {
            return if wan_relayed {
                RelayConnectionState::RemoteRelay
            } else {
                RelayConnectionState::RemoteDirect
            };
        }
        if reconnecting {
            return RelayConnectionState::Reconnecting;
        }
        RelayConnectionState::Offline
    }

    /// Whether the device can carry traffic right now.
    pub fn is_connected(self) -> bool {
        matches!(
            self,
            RelayConnectionState::Local
                | RelayConnectionState::RemoteDirect
                | RelayConnectionState::RemoteRelay
        )
    }

    /// Whether the active route is a remote one, which is what the file
    /// size policy keys off.
    pub fn is_remote(self) -> bool {
        matches!(
            self,
            RelayConnectionState::RemoteDirect | RelayConnectionState::RemoteRelay
        )
    }

    /// The word a normal user sees. Direct and relayed are both simply
    /// "Remote" -- the distinction is diagnostics, not something to reason about.
    pub fn user_label(self) -> &'static str {
        match self {
            RelayConnectionState::Local => "Local",
            RelayConnectionState::RemoteDirect | RelayConnectionState::RemoteRelay => "Remote",
            RelayConnectionState::Reconnecting => "Reconnecting",
            RelayConnectionState::Offline => "Offline",
        }
    }

    /// The precise state, for the diagnostics surface only.
    pub fn diagnostic_label(self) -> &'static str {
        match self {
            RelayConnectionState::Local => "KDE LAN",
            RelayConnectionState::RemoteDirect => "Relay WAN · Direct",
            RelayConnectionState::RemoteRelay => "Relay WAN · Relay",
            RelayConnectionState::Reconnecting => "Reconnecting",
            RelayConnectionState::Offline => "Offline",
        }
    }
}

/// Per-route runtime facts. Never persisted: a remembered route is not a live one.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RelayRoutes {
    pub lan_available: bool,
    pub wan_available: bool,
    /// Whether a WAN `EndpointId` is bound for this device, i.e. whether remote
    /// reachability is even possible. Distinct from `wan_available`, which is
    /// about right now.
    pub wan_bound: bool,
    pub wan_relayed: bool,
    /// Unix seconds of the last authenticated activity on each route, kept
    /// separate so WAN traffic can never make a dead LAN link look alive.
    pub lan_last_seen: Option<i64>,
    pub wan_last_seen: Option<i64>,
}

impl RelayRoutes {
    /// The device's aggregate last-seen: the most recent genuine activity on
    /// any route.
    ///
    /// Deliberately derived rather than stored, so it cannot drift from the
    /// route timestamps or be refreshed by something that was not real traffic.
    pub fn last_seen(&self) -> Option<i64> {
        match (self.lan_last_seen, self.wan_last_seen) {
            (Some(lan), Some(wan)) => Some(lan.max(wan)),
            (Some(lan), None) => Some(lan),
            (None, Some(wan)) => Some(wan),
            (None, None) => None,
        }
    }
}

/// A feature Relay can offer for a device.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, PartialOrd, Ord)]
pub enum RelayFeature {
    Notifications,
    Messages,
    Media,
    Commands,
    RemoteInput,
    Clipboard,
    Files,
    Battery,
    Ping,
}

impl RelayFeature {
    pub fn as_str(self) -> &'static str {
        match self {
            RelayFeature::Notifications => "notifications",
            RelayFeature::Messages => "messages",
            RelayFeature::Media => "media",
            RelayFeature::Commands => "commands",
            RelayFeature::RemoteInput => "remoteInput",
            RelayFeature::Clipboard => "clipboard",
            RelayFeature::Files => "files",
            RelayFeature::Battery => "battery",
            RelayFeature::Ping => "ping",
        }
    }
}

/// Whether a feature can be used with a device *right now*, and if not, why.
///
/// The distinction from "supported" matters: a Remote device still *supports*
/// Files even when a particular 30 MB file needs a local network. Marking the
/// whole capability unsupported in that case would be wrong and would hide the
/// feature permanently.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FeatureAvailability {
    Available,
    /// The peer never advertised it.
    Unsupported,
    /// Supported, but the device is not reachable at the moment.
    NotConnected,
    /// Supported and reachable, but the user switched it off.
    Disabled,
    /// Supported and reachable, but an OS-level permission is missing.
    NeedsPermission,
    /// Supported and reachable, but nothing is set up to use yet.
    NotConfigured,
}

impl FeatureAvailability {
    pub fn is_available(self) -> bool {
        matches!(self, FeatureAvailability::Available)
    }

    /// Whether the feature should still be shown, in a disabled form, rather
    /// than hidden. Only genuinely unsupported features disappear.
    pub fn is_visible(self) -> bool {
        !matches!(self, FeatureAvailability::Unsupported)
    }
}

/// Local policy that gates features regardless of what a peer supports.
#[derive(Clone, Copy, Debug, Default)]
pub struct LocalFeaturePolicy {
    pub clipboard_enabled: bool,
    pub remote_input_enabled: bool,
    pub remote_input_authorized: bool,
    pub has_configured_commands: bool,
}

/// One logical device, as the product understands it.
#[derive(Clone, Debug, PartialEq)]
pub struct RelayDeviceRecord {
    /// The stable logical id. The KDE device id is reused as the key for
    /// compatibility with existing pairings; an Iroh `EndpointId` is a route
    /// detail and is never the product identity.
    pub id: String,
    pub display_name: String,
    pub class: RelayDeviceClass,
    /// Peer-reported platform, e.g. "android". Never a machine inventory.
    pub platform: Option<String>,
    pub platform_version: Option<String>,
    pub relay_version: Option<String>,
    /// Trust persists across restarts and is independent of connectivity.
    pub trusted: bool,
    pub routes: RelayRoutes,
    pub connection: RelayConnectionState,
    /// Everything this device advertised it can do, independent of route.
    pub capabilities: BTreeSet<RelayFeature>,
    pub battery_percent: Option<i32>,
    pub charging: Option<bool>,
}

impl RelayDeviceRecord {
    /// A trusted device Relay remembers but has no live route to.
    ///
    /// Used when hydrating from persistence: restored trust must never present
    /// as connected until runtime evidence says so.
    pub fn remembered(id: impl Into<String>, display_name: impl Into<String>, class: RelayDeviceClass) -> Self {
        Self {
            id: id.into(),
            display_name: display_name.into(),
            class,
            platform: None,
            platform_version: None,
            relay_version: None,
            trusted: true,
            routes: RelayRoutes::default(),
            connection: RelayConnectionState::Offline,
            capabilities: BTreeSet::new(),
            battery_percent: None,
            charging: None,
        }
    }

    /// Recomputes [`Self::connection`] from the current routes.
    ///
    /// The only way the field is ever set, so it cannot disagree with the routes
    /// it is supposed to summarise.
    pub fn refresh_connection(&mut self, reconnecting: bool) {
        self.connection = RelayConnectionState::derive(
            self.routes.lan_available,
            self.routes.wan_available,
            self.routes.wan_relayed,
            reconnecting,
        );
    }

    pub fn supports(&self, feature: RelayFeature) -> bool {
        self.capabilities.contains(&feature)
    }

    /// The central answer to "can I do X with this device right now?".
    ///
    /// Having one implementation stops widgets inventing their own slightly
    /// different rules, which is how a feature ends up enabled in one place and
    /// greyed out in another for the same device.
    pub fn availability(&self, feature: RelayFeature, policy: &LocalFeaturePolicy) -> FeatureAvailability {
        if !self.trusted || !self.supports(feature) {
            return FeatureAvailability::Unsupported;
        }
        if !self.connection.is_connected() {
            return FeatureAvailability::NotConnected;
        }
        match feature {
            RelayFeature::Clipboard if !policy.clipboard_enabled => FeatureAvailability::Disabled,
            RelayFeature::RemoteInput if !policy.remote_input_enabled => FeatureAvailability::Disabled,
            RelayFeature::RemoteInput if !policy.remote_input_authorized => {
                FeatureAvailability::NeedsPermission
            }
            RelayFeature::Commands if !policy.has_configured_commands => {
                FeatureAvailability::NotConfigured
            }
            _ => FeatureAvailability::Available,
        }
    }

    /// Aggregate last-seen, derived from route activity.
    pub fn last_seen(&self) -> Option<i64> {
        self.routes.last_seen()
    }
}

/// Chooses the one device a space-constrained surface should present.
///
/// The GNOME status pill can only show a single device. That is a deliberate
/// *presentation* choice, so the selection is explicit and deterministic here
/// rather than falling out of whichever device happened to be first in a map --
/// and it never implies the others are gone.
///
/// Preference order: an explicitly pinned device, then a connected mobile, then
/// the most recently active mobile, then any connected device.
pub fn primary_device<'a>(
    devices: &'a [RelayDeviceRecord],
    pinned_id: Option<&str>,
) -> Option<&'a RelayDeviceRecord> {
    if let Some(pinned_id) = pinned_id {
        // A pinned device stays chosen even when offline: the user asked for
        // that one, and silently swapping it would be worse than showing it
        // disconnected.
        if let Some(pinned) = devices.iter().find(|device| device.id == pinned_id) {
            return Some(pinned);
        }
    }
    let mut candidates: Vec<&RelayDeviceRecord> =
        devices.iter().filter(|device| device.trusted).collect();
    // Sort is total and deterministic, so the choice never depends on map
    // ordering. A phone outranks a tablet: "connected phone" and "other
    // connected mobile" are separate preferences, not one bucket.
    candidates.sort_by(|a, b| {
        let rank = |device: &RelayDeviceRecord| {
            let connected = device.connection.is_connected();
            match (connected, device.class) {
                (true, RelayDeviceClass::Phone) => 0,
                (true, RelayDeviceClass::Tablet) => 1,
                (true, _) => 2,
                (false, RelayDeviceClass::Phone) => 3,
                (false, RelayDeviceClass::Tablet) => 4,
                (false, _) => 5,
            }
        };
        rank(a)
            .cmp(&rank(b))
            .then_with(|| b.last_seen().cmp(&a.last_seen()))
            .then_with(|| a.id.cmp(&b.id))
    });
    candidates.into_iter().next()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(id: &str, class: RelayDeviceClass) -> RelayDeviceRecord {
        RelayDeviceRecord::remembered(id, id, class)
    }

    // --- connection derivation ---------------------------------------------

    #[test]
    fn a_healthy_lan_route_is_local_whatever_wan_is_doing() {
        assert_eq!(RelayConnectionState::derive(true, false, false, false), RelayConnectionState::Local);
        assert_eq!(RelayConnectionState::derive(true, true, false, false), RelayConnectionState::Local);
        assert_eq!(RelayConnectionState::derive(true, true, true, true), RelayConnectionState::Local);
    }

    #[test]
    fn wan_without_lan_is_remote_and_distinguishes_direct_from_relayed() {
        assert_eq!(
            RelayConnectionState::derive(false, true, false, false),
            RelayConnectionState::RemoteDirect
        );
        assert_eq!(
            RelayConnectionState::derive(false, true, true, false),
            RelayConnectionState::RemoteRelay
        );
    }

    #[test]
    fn no_route_is_offline_and_never_local() {
        // The bug this replaces: a catch-all once mapped offline onto Local, so
        // a disconnected device was presented as being on the local network.
        let state = RelayConnectionState::derive(false, false, false, false);
        assert_eq!(state, RelayConnectionState::Offline);
        assert_ne!(state, RelayConnectionState::Local);
        assert!(!state.is_connected());
        assert_eq!(state.user_label(), "Offline");
    }

    #[test]
    fn reconnecting_only_applies_when_nothing_is_usable() {
        assert_eq!(
            RelayConnectionState::derive(false, false, false, true),
            RelayConnectionState::Reconnecting
        );
        // A working route outranks a background reconnect attempt.
        assert_eq!(RelayConnectionState::derive(true, false, false, true), RelayConnectionState::Local);
        assert_eq!(
            RelayConnectionState::derive(false, true, false, true),
            RelayConnectionState::RemoteDirect
        );
    }

    #[test]
    fn both_remote_states_read_as_remote_to_a_normal_user() {
        assert_eq!(RelayConnectionState::RemoteDirect.user_label(), "Remote");
        assert_eq!(RelayConnectionState::RemoteRelay.user_label(), "Remote");
        // The precise route is diagnostics only.
        assert_eq!(RelayConnectionState::RemoteRelay.diagnostic_label(), "Relay WAN · Relay");
        assert_eq!(RelayConnectionState::Local.diagnostic_label(), "KDE LAN");
    }

    #[test]
    fn only_remote_states_report_as_remote_for_the_file_size_policy() {
        assert!(RelayConnectionState::RemoteDirect.is_remote());
        assert!(RelayConnectionState::RemoteRelay.is_remote());
        assert!(!RelayConnectionState::Local.is_remote());
        assert!(!RelayConnectionState::Offline.is_remote());
    }

    #[test]
    fn a_records_connection_always_matches_its_routes() {
        let mut device = record("phone", RelayDeviceClass::Phone);
        device.routes.lan_available = true;
        device.refresh_connection(false);
        assert_eq!(device.connection, RelayConnectionState::Local);

        // LAN dies, WAN carries on.
        device.routes.lan_available = false;
        device.routes.wan_available = true;
        device.refresh_connection(false);
        assert_eq!(device.connection, RelayConnectionState::RemoteDirect);

        // LAN returns and immediately outranks WAN again.
        device.routes.lan_available = true;
        device.refresh_connection(false);
        assert_eq!(device.connection, RelayConnectionState::Local);

        // Everything dies.
        device.routes = RelayRoutes::default();
        device.refresh_connection(false);
        assert_eq!(device.connection, RelayConnectionState::Offline);
    }

    // --- identity and class -------------------------------------------------

    #[test]
    fn peer_type_strings_normalise_onto_the_relay_classes() {
        for (raw, expected) in [
            ("phone", RelayDeviceClass::Phone),
            ("smartphone", RelayDeviceClass::Phone),
            ("Mobile", RelayDeviceClass::Phone),
            ("tablet", RelayDeviceClass::Tablet),
            ("desktop", RelayDeviceClass::Desktop),
            ("computer", RelayDeviceClass::Desktop),
            ("PC", RelayDeviceClass::Desktop),
            ("laptop", RelayDeviceClass::Laptop),
            ("notebook", RelayDeviceClass::Laptop),
            ("tv", RelayDeviceClass::Tv),
            ("  Tablet  ", RelayDeviceClass::Tablet),
        ] {
            assert_eq!(RelayDeviceClass::from_peer_string(raw), expected, "{raw}");
        }
    }

    #[test]
    fn an_unknown_device_type_becomes_other_rather_than_a_guess() {
        for raw in ["", "toaster", "watch", "???"] {
            assert_eq!(RelayDeviceClass::from_peer_string(raw), RelayDeviceClass::Other, "{raw}");
        }
    }

    #[test]
    fn only_handhelds_count_as_mobile() {
        assert!(RelayDeviceClass::Phone.is_mobile());
        assert!(RelayDeviceClass::Tablet.is_mobile());
        for class in [RelayDeviceClass::Desktop, RelayDeviceClass::Laptop, RelayDeviceClass::Tv, RelayDeviceClass::Other] {
            assert!(!class.is_mobile(), "{class:?}");
        }
    }

    // --- trust vs connectivity ---------------------------------------------

    #[test]
    fn a_remembered_device_is_trusted_but_not_connected() {
        // Restored trust must never present as a live connection.
        let device = record("phone", RelayDeviceClass::Phone);
        assert!(device.trusted);
        assert_eq!(device.connection, RelayConnectionState::Offline);
        assert!(!device.routes.lan_available && !device.routes.wan_available);
        assert_eq!(device.last_seen(), None);
    }

    // --- last seen ----------------------------------------------------------

    #[test]
    fn aggregate_last_seen_is_the_most_recent_real_route_activity() {
        let mut routes = RelayRoutes::default();
        assert_eq!(routes.last_seen(), None);

        routes.lan_last_seen = Some(100);
        assert_eq!(routes.last_seen(), Some(100));

        routes.wan_last_seen = Some(250);
        assert_eq!(routes.last_seen(), Some(250));

        // A newer LAN sample wins, and neither timestamp is disturbed.
        routes.lan_last_seen = Some(400);
        assert_eq!(routes.last_seen(), Some(400));
        assert_eq!(routes.wan_last_seen, Some(250), "route timestamps stay independent");
    }

    #[test]
    fn wan_activity_never_refreshes_the_lan_route() {
        let routes = RelayRoutes {
            lan_last_seen: Some(100),
            wan_last_seen: Some(900),
            ..RelayRoutes::default()
        };
        // The aggregate moves, but LAN's own freshness does not, which is what
        // stops a dead LAN link being classified as alive.
        assert_eq!(routes.last_seen(), Some(900));
        assert_eq!(routes.lan_last_seen, Some(100));
    }

    // --- capabilities and availability -------------------------------------

    fn connected_phone(features: &[RelayFeature]) -> RelayDeviceRecord {
        let mut device = record("phone", RelayDeviceClass::Phone);
        device.capabilities = features.iter().copied().collect();
        device.routes.lan_available = true;
        device.refresh_connection(false);
        device
    }

    #[test]
    fn a_supported_feature_on_a_connected_trusted_device_is_available() {
        let device = connected_phone(&[RelayFeature::Notifications]);
        let policy = LocalFeaturePolicy::default();
        assert_eq!(
            device.availability(RelayFeature::Notifications, &policy),
            FeatureAvailability::Available
        );
    }

    #[test]
    fn an_unadvertised_feature_is_unsupported_and_hidden() {
        let device = connected_phone(&[RelayFeature::Notifications]);
        let availability = device.availability(RelayFeature::Messages, &LocalFeaturePolicy::default());
        assert_eq!(availability, FeatureAvailability::Unsupported);
        assert!(!availability.is_visible(), "a genuinely unsupported feature is hidden");
    }

    #[test]
    fn a_supported_feature_on_a_disconnected_device_stays_visible_but_unavailable() {
        // The difference that matters: the user should still see that their
        // phone does Messages, greyed out, not have it vanish while offline.
        let mut device = connected_phone(&[RelayFeature::Messages]);
        device.routes = RelayRoutes::default();
        device.refresh_connection(false);

        let availability = device.availability(RelayFeature::Messages, &LocalFeaturePolicy::default());
        assert_eq!(availability, FeatureAvailability::NotConnected);
        assert!(availability.is_visible());
        assert!(!availability.is_available());
    }

    #[test]
    fn features_remain_supported_over_a_remote_route() {
        // Being Remote must not strip capabilities; only route-specific limits
        // such as the file size policy apply, and those are not capability facts.
        let mut device = connected_phone(&[RelayFeature::Files, RelayFeature::Messages]);
        device.routes.lan_available = false;
        device.routes.wan_available = true;
        device.refresh_connection(false);

        assert_eq!(device.connection, RelayConnectionState::RemoteDirect);
        for feature in [RelayFeature::Files, RelayFeature::Messages] {
            assert_eq!(
                device.availability(feature, &LocalFeaturePolicy::default()),
                FeatureAvailability::Available,
                "{feature:?} must survive going Remote"
            );
        }
    }

    #[test]
    fn local_policy_distinguishes_disabled_from_unsupported() {
        let device = connected_phone(&[RelayFeature::Clipboard, RelayFeature::RemoteInput, RelayFeature::Commands]);

        let off = LocalFeaturePolicy::default();
        assert_eq!(device.availability(RelayFeature::Clipboard, &off), FeatureAvailability::Disabled);
        assert_eq!(device.availability(RelayFeature::RemoteInput, &off), FeatureAvailability::Disabled);
        assert_eq!(device.availability(RelayFeature::Commands, &off), FeatureAvailability::NotConfigured);

        // Enabled but not yet authorised by the OS is its own state, so the UI
        // can offer an "Allow" affordance instead of just greying out.
        let enabled = LocalFeaturePolicy {
            clipboard_enabled: true,
            remote_input_enabled: true,
            remote_input_authorized: false,
            has_configured_commands: true,
        };
        assert_eq!(device.availability(RelayFeature::Clipboard, &enabled), FeatureAvailability::Available);
        assert_eq!(
            device.availability(RelayFeature::RemoteInput, &enabled),
            FeatureAvailability::NeedsPermission
        );
        assert_eq!(device.availability(RelayFeature::Commands, &enabled), FeatureAvailability::Available);
    }

    #[test]
    fn an_untrusted_device_offers_nothing_even_if_it_advertises_everything() {
        let mut device = connected_phone(&[RelayFeature::Notifications, RelayFeature::Files]);
        device.trusted = false;
        for feature in [RelayFeature::Notifications, RelayFeature::Files] {
            assert_eq!(
                device.availability(feature, &LocalFeaturePolicy::default()),
                FeatureAvailability::Unsupported
            );
        }
    }

    #[test]
    fn one_device_lacking_a_feature_does_not_affect_another() {
        let with_sms = connected_phone(&[RelayFeature::Messages]);
        let mut without_sms = record("tablet", RelayDeviceClass::Tablet);
        without_sms.capabilities = [RelayFeature::Files].into_iter().collect();
        without_sms.routes.lan_available = true;
        without_sms.refresh_connection(false);

        let policy = LocalFeaturePolicy::default();
        assert_eq!(with_sms.availability(RelayFeature::Messages, &policy), FeatureAvailability::Available);
        assert_eq!(
            without_sms.availability(RelayFeature::Messages, &policy),
            FeatureAvailability::Unsupported
        );
    }

    // --- primary device selection ------------------------------------------

    fn with_state(id: &str, class: RelayDeviceClass, lan: bool, wan: bool, seen: Option<i64>) -> RelayDeviceRecord {
        let mut device = record(id, class);
        device.routes.lan_available = lan;
        device.routes.wan_available = wan;
        device.routes.lan_last_seen = seen;
        device.refresh_connection(false);
        device
    }

    #[test]
    fn the_pill_prefers_a_connected_phone_over_anything_else() {
        let devices = vec![
            with_state("desktop", RelayDeviceClass::Desktop, true, false, Some(500)),
            with_state("phone", RelayDeviceClass::Phone, true, false, Some(100)),
        ];
        assert_eq!(primary_device(&devices, None).unwrap().id, "phone");
    }

    #[test]
    fn a_pinned_device_is_chosen_even_when_it_is_offline() {
        let devices = vec![
            with_state("phone-a", RelayDeviceClass::Phone, true, false, Some(500)),
            with_state("phone-b", RelayDeviceClass::Phone, false, false, Some(100)),
        ];
        // The user asked for phone-b; silently swapping would be worse than
        // showing it disconnected.
        assert_eq!(primary_device(&devices, Some("phone-b")).unwrap().id, "phone-b");
    }

    #[test]
    fn selection_falls_back_to_recency_and_is_deterministic() {
        let devices = vec![
            with_state("phone-a", RelayDeviceClass::Phone, false, true, Some(100)),
            with_state("phone-b", RelayDeviceClass::Phone, false, true, Some(900)),
        ];
        // Both connected mobiles: the more recently active wins, every time.
        assert_eq!(primary_device(&devices, None).unwrap().id, "phone-b");
        let reversed: Vec<_> = devices.iter().rev().cloned().collect();
        assert_eq!(primary_device(&reversed, None).unwrap().id, "phone-b");
    }

    #[test]
    fn choosing_one_device_never_discards_the_others() {
        let devices = vec![
            with_state("phone", RelayDeviceClass::Phone, true, false, Some(100)),
            with_state("tablet", RelayDeviceClass::Tablet, false, true, Some(200)),
            with_state("laptop", RelayDeviceClass::Laptop, false, false, Some(50)),
        ];
        let chosen = primary_device(&devices, None).unwrap().id.clone();
        assert_eq!(chosen, "phone");
        // The full truth is still present for every other surface.
        assert_eq!(devices.len(), 3);
        assert_eq!(devices[1].connection, RelayConnectionState::RemoteDirect);
        assert_eq!(devices[2].connection, RelayConnectionState::Offline);
    }

    #[test]
    fn a_connected_phone_outranks_a_more_recently_active_tablet() {
        // "connected phone" and "other connected mobile" are distinct
        // preferences, so recency must not let a tablet take the phone's place.
        let devices = vec![
            with_state("tablet", RelayDeviceClass::Tablet, true, false, Some(900)),
            with_state("phone", RelayDeviceClass::Phone, true, false, Some(100)),
        ];
        assert_eq!(primary_device(&devices, None).unwrap().id, "phone");
    }

    #[test]
    fn an_empty_or_untrusted_fabric_selects_nothing() {
        assert!(primary_device(&[], None).is_none());
        let mut untrusted = with_state("phone", RelayDeviceClass::Phone, true, false, None);
        untrusted.trusted = false;
        assert!(primary_device(std::slice::from_ref(&untrusted), None).is_none());
    }
}
