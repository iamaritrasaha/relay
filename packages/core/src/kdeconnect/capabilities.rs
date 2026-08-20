//! Canonical capability registry for KDE Connect (single source of truth).

pub const PACKET_TYPE_IDENTITY: &str = "kdeconnect.identity";
pub const PACKET_TYPE_PAIR: &str = "kdeconnect.pair";
pub const PACKET_TYPE_BATTERY: &str = "kdeconnect.battery";
pub const PACKET_TYPE_CONNECTIVITY_REPORT: &str = "kdeconnect.connectivity_report";
pub const PACKET_TYPE_CLIPBOARD: &str = "kdeconnect.clipboard";
pub const PACKET_TYPE_CLIPBOARD_CONNECT: &str = "kdeconnect.clipboard.connect";
pub const PACKET_TYPE_PING: &str = "kdeconnect.ping";
pub const PACKET_TYPE_FINDMYPHONE_REQUEST: &str = "kdeconnect.findmyphone.request";
pub const PACKET_TYPE_NOTIFICATION: &str = "kdeconnect.notification";
pub const PACKET_TYPE_NOTIFICATION_REQUEST: &str = "kdeconnect.notification.request";

/// Capabilities that Relay Linux can RECEIVE from KDE Connect peers.
pub fn canonical_incoming_capabilities() -> Vec<String> {
    vec![
        PACKET_TYPE_BATTERY.to_string(),
        PACKET_TYPE_CONNECTIVITY_REPORT.to_string(),
        PACKET_TYPE_CLIPBOARD.to_string(),
        PACKET_TYPE_CLIPBOARD_CONNECT.to_string(),
        PACKET_TYPE_PING.to_string(),
        PACKET_TYPE_NOTIFICATION.to_string(),
    ]
}

/// Capabilities that Relay Linux can SEND to KDE Connect peers.
pub fn canonical_outgoing_capabilities() -> Vec<String> {
    vec![
        PACKET_TYPE_CLIPBOARD.to_string(),
        PACKET_TYPE_CLIPBOARD_CONNECT.to_string(),
        PACKET_TYPE_PING.to_string(),
        PACKET_TYPE_FINDMYPHONE_REQUEST.to_string(),
        PACKET_TYPE_NOTIFICATION_REQUEST.to_string(),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_capabilities_are_non_empty_and_valid() {
        let incoming = canonical_incoming_capabilities();
        let outgoing = canonical_outgoing_capabilities();

        assert!(incoming.contains(&PACKET_TYPE_BATTERY.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_CONNECTIVITY_REPORT.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_CLIPBOARD.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_CLIPBOARD_CONNECT.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_PING.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_NOTIFICATION.to_string()));

        assert!(outgoing.contains(&PACKET_TYPE_CLIPBOARD.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_CLIPBOARD_CONNECT.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_PING.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_FINDMYPHONE_REQUEST.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_NOTIFICATION_REQUEST.to_string()));

        // Battery is receive only on Linux desktop
        assert!(!outgoing.contains(&PACKET_TYPE_BATTERY.to_string()));
        assert!(!outgoing.contains(&PACKET_TYPE_CONNECTIVITY_REPORT.to_string()));
        // Find phone request is send only on Linux desktop
        assert!(!incoming.contains(&PACKET_TYPE_FINDMYPHONE_REQUEST.to_string()));
    }
}
