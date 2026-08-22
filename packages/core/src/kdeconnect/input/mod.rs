//! Remote input: turning KDE `kdeconnect.mousepad.request` packets into pointer
//! and keyboard events on the Linux desktop.
//!
//! The wire format is upstream KDE Connect's, taken from the Android
//! `MousePadPlugin` verbatim -- Relay invents nothing here.
//!
//! Nothing in this module knows about transports. Packets arrive through the
//! shared dispatcher, so a phone on the LAN and a phone on mobile data drive the
//! identical code path; `TransportRouter` sits below the feature and is never
//! consulted from here.
//!
//! The split mirrors the media module: [`InputEvent`] and the packet mapping are
//! pure and unit-tested, while [`portal`] holds the only code that needs a real
//! desktop session.

use std::future::Future;
use std::pin::Pin;

use crate::kdeconnect::packet::MousePadRequestBody;

#[cfg(all(target_os = "linux", feature = "remote-input"))]
pub mod portal;
pub mod queue;

pub use queue::InputQueue;

pub type InputFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Pointer buttons, as Linux evdev codes -- which is what the RemoteDesktop
/// portal expects.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PointerButton {
    Left,
    Right,
    Middle,
}

impl PointerButton {
    pub fn evdev_code(self) -> i32 {
        match self {
            PointerButton::Left => 0x110,
            PointerButton::Right => 0x111,
            PointerButton::Middle => 0x112,
        }
    }
}

/// One input action to perform on the desktop.
///
/// Deliberately coarse: a single packet can expand to several events (a click is
/// a press and a release), and the backend should not have to re-derive that.
#[derive(Clone, Debug, PartialEq)]
pub enum InputEvent {
    /// Relative pointer motion, in pixels.
    PointerMotion { dx: f64, dy: f64 },
    PointerButton { button: PointerButton, pressed: bool },
    /// Scroll, in pixels. Positive `dy` scrolls down, matching the portal.
    Scroll { dx: f64, dy: f64 },
    /// A key identified by X11 keysym, pressed or released.
    Keysym { keysym: i32, pressed: bool },
    /// Literal text to type.
    Text(String),
}

impl InputEvent {
    /// Whether losing this event would be noticed by the user.
    ///
    /// Motion is a stream whose value is cumulative and immediately superseded,
    /// so intermediate samples can be merged under load. Everything else is a
    /// discrete action -- dropping a click or a keystroke is a correctness bug,
    /// not a quality-of-service tradeoff.
    pub fn is_coalescible(&self) -> bool {
        matches!(self, InputEvent::PointerMotion { .. })
    }
}

/// Maximum pointer delta accepted from one packet, in pixels.
///
/// A remote peer should not be able to fling the cursor across every monitor
/// with a single malformed value, and no real touchpad gesture produces this in
/// one sample.
const MAX_POINTER_DELTA: f64 = 500.0;

/// Maximum length of a single text-injection packet.
const MAX_TEXT_LEN: usize = 512;

/// X11 keysyms for KDE Connect's special-key indices.
///
/// The index is the position in the Android `KeyListenerView.SpecialKeysMap`
/// table, which is part of the protocol -- note that 3 is unused and Return is
/// 12, both upstream quirks that must be preserved.
fn special_key_keysym(index: i64) -> Option<i32> {
    let keysym = match index {
        1 => 0xff08,  // BackSpace
        2 => 0xff09,  // Tab
        4 => 0xff51,  // Left
        5 => 0xff52,  // Up
        6 => 0xff53,  // Right
        7 => 0xff54,  // Down
        8 => 0xff55,  // Page_Up
        9 => 0xff56,  // Page_Down
        10 => 0xff50, // Home
        11 => 0xff57, // End
        12 => 0xff0d, // Return
        13 => 0xffff, // Delete
        14 => 0xff1b, // Escape
        15 => 0xff61, // Print
        16 => 0xff14, // Scroll_Lock
        17 => 0xffe3, // Control_L
        18 => 0xffe9, // Alt_L
        19 => 0xffe1, // Shift_L
        20 => 0xffeb, // Super_L
        21..=32 => 0xffbe + (index as i32 - 21), // F1..F12
        _ => return None,
    };
    Some(keysym)
}

const KEYSYM_CTRL: i32 = 0xffe3;
const KEYSYM_ALT: i32 = 0xffe9;
const KEYSYM_SHIFT: i32 = 0xffe1;
const KEYSYM_SUPER: i32 = 0xffeb;

/// Expands one request packet into the events it should produce.
///
/// Returns an empty vector for anything unrecognised or out of range: a packet
/// that cannot be understood must do nothing at all, never something
/// approximate.
pub fn events_for(request: &MousePadRequestBody) -> Vec<InputEvent> {
    let mut events = Vec::new();

    // Modifiers wrap whatever key action the packet carries, so they are pressed
    // first and released in reverse afterwards.
    let modifiers: Vec<i32> = [
        (request.ctrl, KEYSYM_CTRL),
        (request.alt, KEYSYM_ALT),
        (request.shift, KEYSYM_SHIFT),
        (request.super_key, KEYSYM_SUPER),
    ]
    .into_iter()
    .filter_map(|(set, keysym)| set.then_some(keysym))
    .collect();

    let key_action: Vec<InputEvent> = if let Some(index) = request.special_key {
        match special_key_keysym(index) {
            Some(keysym) => vec![
                InputEvent::Keysym { keysym, pressed: true },
                InputEvent::Keysym { keysym, pressed: false },
            ],
            None => {
                tracing::warn!("[Relay Input] ignoring unknown special key index");
                Vec::new()
            }
        }
    } else if let Some(text) = request.key.as_deref() {
        if text.is_empty() || text.len() > MAX_TEXT_LEN {
            tracing::warn!("[Relay Input] ignoring out-of-range text payload");
            Vec::new()
        } else {
            vec![InputEvent::Text(text.to_owned())]
        }
    } else {
        Vec::new()
    };

    if !key_action.is_empty() {
        for keysym in &modifiers {
            events.push(InputEvent::Keysym { keysym: *keysym, pressed: true });
        }
        events.extend(key_action);
        for keysym in modifiers.iter().rev() {
            events.push(InputEvent::Keysym { keysym: *keysym, pressed: false });
        }
        return events;
    }

    if request.scroll {
        // Scroll reuses dx/dy, so it has to be checked before plain motion.
        if let (Some(dx), Some(dy)) = (request.dx, request.dy) {
            if dx.is_finite() && dy.is_finite() {
                events.push(InputEvent::Scroll { dx, dy });
            }
        }
        return events;
    }

    if request.single_click {
        events.push(InputEvent::PointerButton { button: PointerButton::Left, pressed: true });
        events.push(InputEvent::PointerButton { button: PointerButton::Left, pressed: false });
    }
    if request.double_click {
        for _ in 0..2 {
            events.push(InputEvent::PointerButton { button: PointerButton::Left, pressed: true });
            events.push(InputEvent::PointerButton { button: PointerButton::Left, pressed: false });
        }
    }
    if request.right_click {
        events.push(InputEvent::PointerButton { button: PointerButton::Right, pressed: true });
        events.push(InputEvent::PointerButton { button: PointerButton::Right, pressed: false });
    }
    if request.middle_click {
        events.push(InputEvent::PointerButton { button: PointerButton::Middle, pressed: true });
        events.push(InputEvent::PointerButton { button: PointerButton::Middle, pressed: false });
    }
    // Press/release without their partner: this is how a drag is expressed.
    if request.single_hold {
        events.push(InputEvent::PointerButton { button: PointerButton::Left, pressed: true });
    }
    if request.single_release {
        events.push(InputEvent::PointerButton { button: PointerButton::Left, pressed: false });
    }

    if !events.is_empty() {
        return events;
    }

    if let (Some(dx), Some(dy)) = (request.dx, request.dy) {
        // A non-finite or absurd delta is dropped rather than clamped: it can
        // only come from a broken or hostile sender, and guessing at intent
        // would move the user's cursor somewhere they did not ask for.
        if dx.is_finite()
            && dy.is_finite()
            && dx.abs() <= MAX_POINTER_DELTA
            && dy.abs() <= MAX_POINTER_DELTA
            && (dx != 0.0 || dy != 0.0)
        {
            events.push(InputEvent::PointerMotion { dx, dy });
        }
    }

    events
}

/// Why remote input is not currently available.
#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum RemoteInputRejection {
    #[error("requesting device is not paired")]
    DeviceNotTrusted,
    #[error("remote input is switched off for this desktop")]
    Disabled,
    #[error("no authorised remote-input session")]
    NoSession,
}

/// Injects input into the desktop session.
///
/// Abstracted so packet handling can be tested against a recording double, and
/// so a platform with no supported input path simply has no implementation
/// rather than needing special-casing further up.
pub trait RemoteInputBackend: Send + Sync {
    /// Whether an authorised session is currently established.
    fn is_ready(&self) -> bool;

    /// Delivers a batch of events. Batching matters: a click is two events that
    /// must not be separated by an unrelated packet from another device.
    fn dispatch<'a>(&'a self, events: &'a [InputEvent]) -> InputFuture<'a, anyhow::Result<()>>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Map, Value};

    fn request(pairs: &[(&str, Value)]) -> MousePadRequestBody {
        let mut body = Map::new();
        for (key, value) in pairs {
            body.insert((*key).to_owned(), value.clone());
        }
        crate::kdeconnect::packet::NetworkPacket::new("kdeconnect.mousepad.request", body)
            .as_mousepad_request()
            .expect("valid request")
    }

    #[test]
    fn relative_motion_is_passed_through() {
        let events = events_for(&request(&[("dx", 12.5.into()), ("dy", (-3.0).into())]));
        assert_eq!(events, vec![InputEvent::PointerMotion { dx: 12.5, dy: -3.0 }]);
    }

    #[test]
    fn an_absurd_or_non_finite_delta_moves_nothing() {
        for (dx, dy) in [(10_000.0_f64, 0.0_f64), (0.0, -9_999.0), (f64::NAN, 1.0), (1.0, f64::INFINITY)] {
            let events = events_for(&request(&[("dx", dx.into()), ("dy", dy.into())]));
            assert!(events.is_empty(), "({dx}, {dy}) should have been refused");
        }
    }

    #[test]
    fn a_zero_delta_produces_no_event() {
        assert!(events_for(&request(&[("dx", 0.0.into()), ("dy", 0.0.into())])).is_empty());
    }

    #[test]
    fn each_click_expands_to_a_press_and_a_release() {
        for (field, button) in [
            ("singleclick", PointerButton::Left),
            ("rightclick", PointerButton::Right),
            ("middleclick", PointerButton::Middle),
        ] {
            let events = events_for(&request(&[(field, true.into())]));
            assert_eq!(
                events,
                vec![
                    InputEvent::PointerButton { button, pressed: true },
                    InputEvent::PointerButton { button, pressed: false },
                ],
                "{field}"
            );
        }
    }

    #[test]
    fn a_double_click_is_two_full_click_cycles() {
        let events = events_for(&request(&[("doubleclick", true.into())]));
        assert_eq!(events.len(), 4);
        assert!(events.iter().all(|event| matches!(
            event,
            InputEvent::PointerButton { button: PointerButton::Left, .. }
        )));
    }

    #[test]
    fn hold_and_release_stay_unpaired_so_a_drag_works() {
        assert_eq!(
            events_for(&request(&[("singlehold", true.into())])),
            vec![InputEvent::PointerButton { button: PointerButton::Left, pressed: true }]
        );
        assert_eq!(
            events_for(&request(&[("singlerelease", true.into())])),
            vec![InputEvent::PointerButton { button: PointerButton::Left, pressed: false }]
        );
    }

    #[test]
    fn scroll_is_distinguished_from_motion_by_its_flag() {
        let events = events_for(&request(&[
            ("scroll", true.into()),
            ("dx", 0.0.into()),
            ("dy", 120.0.into()),
        ]));
        assert_eq!(events, vec![InputEvent::Scroll { dx: 0.0, dy: 120.0 }]);
    }

    #[test]
    fn text_is_injected_verbatim() {
        assert_eq!(
            events_for(&request(&[("key", "hello".into())])),
            vec![InputEvent::Text("hello".into())]
        );
        assert!(events_for(&request(&[("key", "".into())])).is_empty());
    }

    #[test]
    fn an_oversized_text_payload_is_refused_while_parsing() {
        // Bounded at the parse boundary rather than here, so an oversized
        // payload never reaches the event layer at all.
        let mut body = Map::new();
        body.insert("key".into(), "x".repeat(MAX_TEXT_LEN + 1).into());
        let packet =
            crate::kdeconnect::packet::NetworkPacket::new("kdeconnect.mousepad.request", body);
        assert!(packet.as_mousepad_request().is_err());
    }

    #[test]
    fn every_special_key_index_upstream_defines_maps_to_a_keysym() {
        // 3 is deliberately unused upstream; Return is 12 instead.
        for index in (1..=2).chain(4..=32) {
            let events = events_for(&request(&[("specialKey", index.into())]));
            assert_eq!(events.len(), 2, "index {index} should press and release");
        }
        assert!(events_for(&request(&[("specialKey", 3.into())])).is_empty());
        assert_eq!(special_key_keysym(12), Some(0xff0d), "Return is index 12");
        assert_eq!(special_key_keysym(21), Some(0xffbe), "F1");
        assert_eq!(special_key_keysym(32), Some(0xffc9), "F12");
    }

    #[test]
    fn an_unknown_special_key_index_does_nothing() {
        for index in [0_i64, 33, 999, -1] {
            assert!(events_for(&request(&[("specialKey", index.into())])).is_empty(), "{index}");
        }
    }

    #[test]
    fn modifiers_wrap_the_key_and_are_released_in_reverse() {
        let events = events_for(&request(&[
            ("ctrl", true.into()),
            ("shift", true.into()),
            ("key", "c".into()),
        ]));
        assert_eq!(
            events,
            vec![
                InputEvent::Keysym { keysym: KEYSYM_CTRL, pressed: true },
                InputEvent::Keysym { keysym: KEYSYM_SHIFT, pressed: true },
                InputEvent::Text("c".into()),
                InputEvent::Keysym { keysym: KEYSYM_SHIFT, pressed: false },
                InputEvent::Keysym { keysym: KEYSYM_CTRL, pressed: false },
            ]
        );
    }

    #[test]
    fn a_modifier_with_no_key_action_presses_nothing() {
        // Otherwise a stray packet could leave Ctrl latched down.
        assert!(events_for(&request(&[("ctrl", true.into())])).is_empty());
    }

    #[test]
    fn an_empty_packet_produces_no_events() {
        assert!(events_for(&request(&[("dx", 0.0.into())])).is_empty());
    }

    #[test]
    fn only_pointer_motion_is_coalescible() {
        assert!(InputEvent::PointerMotion { dx: 1.0, dy: 1.0 }.is_coalescible());
        assert!(!InputEvent::PointerButton { button: PointerButton::Left, pressed: true }.is_coalescible());
        assert!(!InputEvent::Scroll { dx: 0.0, dy: 1.0 }.is_coalescible());
        assert!(!InputEvent::Keysym { keysym: 0xff0d, pressed: true }.is_coalescible());
        assert!(!InputEvent::Text("a".into()).is_coalescible());
    }

    #[test]
    fn pointer_buttons_use_linux_evdev_codes() {
        assert_eq!(PointerButton::Left.evdev_code(), 0x110);
        assert_eq!(PointerButton::Right.evdev_code(), 0x111);
        assert_eq!(PointerButton::Middle.evdev_code(), 0x112);
    }
}
