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
pub const PACKET_TYPE_SMS_MESSAGES: &str = "kdeconnect.sms.messages";
pub const PACKET_TYPE_SMS_REQUEST: &str = "kdeconnect.sms.request";
pub const PACKET_TYPE_SMS_REQUEST_CONVERSATIONS: &str = "kdeconnect.sms.request_conversations";
pub const PACKET_TYPE_SMS_REQUEST_CONVERSATION: &str = "kdeconnect.sms.request_conversation";
pub const PACKET_TYPE_TELEPHONY: &str = "kdeconnect.telephony";
pub const PACKET_TYPE_TELEPHONY_REQUEST_MUTE: &str = "kdeconnect.telephony.request_mute";

/// MPRIS media control. Relay Linux is the *player host*: the phone sends
/// `kdeconnect.mpris.request` and Relay answers with `kdeconnect.mpris`.
pub const PACKET_TYPE_MPRIS: &str = "kdeconnect.mpris";
pub const PACKET_TYPE_MPRIS_REQUEST: &str = "kdeconnect.mpris.request";

/// RunCommand. Relay Linux hosts the command list; the phone can only ask for
/// the list or ask to run an entry *by id*. See `commands.rs` -- remote command
/// text is never executed.
pub const PACKET_TYPE_RUNCOMMAND: &str = "kdeconnect.runcommand";
pub const PACKET_TYPE_RUNCOMMAND_REQUEST: &str = "kdeconnect.runcommand.request";

/// Remote input. Relay Linux is the *controlled* machine: the phone sends
/// `kdeconnect.mousepad.request` and Relay injects the events. Relay never
/// sends input requests, so this is incoming only.
pub const PACKET_TYPE_MOUSEPAD_REQUEST: &str = "kdeconnect.mousepad.request";

/// File transfer. Relay both receives and sends files, so this is advertised in
/// both directions -- unlike the control-only features above.
pub const PACKET_TYPE_SHARE_REQUEST: &str = "kdeconnect.share.request";

/// Relay-specific extension packets, carried over either KDE LAN or Relay WAN.
/// Namespace must match the Android side exactly -- see
/// `kdeconnect/wan/mod.rs` for the transport these travel over.
pub const PACKET_TYPE_RELAY_WAN_IDENTITY: &str = "kdeconnect.relay.wan.identity";
pub const PACKET_TYPE_RELAY_DEVICE_STATE: &str = "kdeconnect.relay.device_state";
pub const PACKET_TYPE_RELAY_WALLPAPER: &str = "kdeconnect.relay.wallpaper";
pub const PACKET_TYPE_RELAY_PING: &str = "kdeconnect.relay.ping";
pub const PACKET_TYPE_RELAY_PONG: &str = "kdeconnect.relay.pong";

/// Capabilities that Relay Linux can RECEIVE from KDE Connect peers.
pub fn canonical_incoming_capabilities() -> Vec<String> {
    vec![
        PACKET_TYPE_BATTERY.to_string(),
        PACKET_TYPE_CONNECTIVITY_REPORT.to_string(),
        PACKET_TYPE_CLIPBOARD.to_string(),
        PACKET_TYPE_CLIPBOARD_CONNECT.to_string(),
        PACKET_TYPE_PING.to_string(),
        PACKET_TYPE_NOTIFICATION.to_string(),
        PACKET_TYPE_SMS_MESSAGES.to_string(),
        PACKET_TYPE_TELEPHONY.to_string(),
        // Relay Linux receives the phone's media/command *requests*...
        PACKET_TYPE_MPRIS_REQUEST.to_string(),
        PACKET_TYPE_RUNCOMMAND_REQUEST.to_string(),
        PACKET_TYPE_MOUSEPAD_REQUEST.to_string(),
        PACKET_TYPE_SHARE_REQUEST.to_string(),
        PACKET_TYPE_RELAY_WAN_IDENTITY.to_string(),
        PACKET_TYPE_RELAY_DEVICE_STATE.to_string(),
        PACKET_TYPE_RELAY_PING.to_string(),
        PACKET_TYPE_RELAY_PONG.to_string(),
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
        PACKET_TYPE_SMS_REQUEST.to_string(),
        PACKET_TYPE_SMS_REQUEST_CONVERSATIONS.to_string(),
        PACKET_TYPE_SMS_REQUEST_CONVERSATION.to_string(),
        PACKET_TYPE_TELEPHONY_REQUEST_MUTE.to_string(),
        // ...and sends the resulting player state / command list back.
        PACKET_TYPE_MPRIS.to_string(),
        PACKET_TYPE_RUNCOMMAND.to_string(),
        PACKET_TYPE_SHARE_REQUEST.to_string(),
        PACKET_TYPE_RELAY_WAN_IDENTITY.to_string(),
        PACKET_TYPE_RELAY_DEVICE_STATE.to_string(),
        PACKET_TYPE_RELAY_WALLPAPER.to_string(),
        PACKET_TYPE_RELAY_PING.to_string(),
        PACKET_TYPE_RELAY_PONG.to_string(),
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
        assert!(incoming.contains(&PACKET_TYPE_SMS_MESSAGES.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_TELEPHONY.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_RELAY_WAN_IDENTITY.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_RELAY_DEVICE_STATE.to_string()));

        assert!(outgoing.contains(&PACKET_TYPE_CLIPBOARD.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_CLIPBOARD_CONNECT.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_PING.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_FINDMYPHONE_REQUEST.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_NOTIFICATION_REQUEST.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_SMS_REQUEST.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_SMS_REQUEST_CONVERSATIONS.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_SMS_REQUEST_CONVERSATION.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_TELEPHONY_REQUEST_MUTE.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_RELAY_WAN_IDENTITY.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_RELAY_DEVICE_STATE.to_string()));

        // Relay Linux hosts players and commands: it receives requests and
        // sends state, never the other way round. Getting this backwards makes
        // the phone silently refuse to send us anything.
        assert!(incoming.contains(&PACKET_TYPE_MPRIS_REQUEST.to_string()));
        assert!(incoming.contains(&PACKET_TYPE_RUNCOMMAND_REQUEST.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_MPRIS.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_RUNCOMMAND.to_string()));
        assert!(!incoming.contains(&PACKET_TYPE_MPRIS.to_string()));
        assert!(!incoming.contains(&PACKET_TYPE_RUNCOMMAND.to_string()));
        assert!(!outgoing.contains(&PACKET_TYPE_MPRIS_REQUEST.to_string()));
        assert!(!outgoing.contains(&PACKET_TYPE_RUNCOMMAND_REQUEST.to_string()));

        // Remote input flows one way only: Relay is controlled, never the
        // controller. Advertising it outgoing would invite a phone to expect
        // Relay to drive *it*.
        assert!(incoming.contains(&PACKET_TYPE_MOUSEPAD_REQUEST.to_string()));
        assert!(!outgoing.contains(&PACKET_TYPE_MOUSEPAD_REQUEST.to_string()));

        // Files go both ways, so unlike the control-only features this must be
        // advertised in both directions or one direction silently never starts.
        assert!(incoming.contains(&PACKET_TYPE_SHARE_REQUEST.to_string()));
        assert!(outgoing.contains(&PACKET_TYPE_SHARE_REQUEST.to_string()));

        // Battery is receive only on Linux desktop
        assert!(!outgoing.contains(&PACKET_TYPE_BATTERY.to_string()));
        assert!(!outgoing.contains(&PACKET_TYPE_CONNECTIVITY_REPORT.to_string()));
        // Find phone request is send only on Linux desktop
        assert!(!incoming.contains(&PACKET_TYPE_FINDMYPHONE_REQUEST.to_string()));
    }
}
