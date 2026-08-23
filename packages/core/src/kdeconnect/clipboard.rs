//! Relay clipboard: loop-safe synchronisation of the *current* clipboard.
//!
//! This is a logical-device feature that sits above the transport layer. It
//! never inspects which route carried a packet, so LAN and Relay WAN behave
//! identically by construction, and there is deliberately no clipboard-specific
//! transport state.
//!
//! # What this is not
//!
//! V1 synchronises the current clipboard only. It is not a clipboard history:
//! nothing here persists content, and the dedupe window below holds *hashes*,
//! never the text itself.
//!
//! # Privacy
//!
//! Clipboard content never reaches a log. Everything logged is derived --
//! device id, direction, byte length, and a short hash prefix -- which is
//! enough to debug a sync problem without exposing what was copied.

use std::collections::VecDeque;

/// Largest clipboard text Relay will send or apply, in bytes of UTF-8.
///
/// 64 KiB comfortably covers text, URLs and multi-page documents while keeping
/// a hostile or accidental paste (a whole file dumped into a selection) from
/// being forwarded. The KDE frame limit of 4 MiB still bounds allocation at the
/// wire level; this is the feature-level policy on top of it.
pub const MAX_CLIPBOARD_BYTES: usize = 64 * 1024;

/// How long a hash stays in the dedupe window.
///
/// Long enough to absorb a round trip on a slow WAN link, short enough that a
/// user who genuinely re-copies the same text a few seconds later still has it
/// propagate.
pub const DEDUPE_WINDOW_MS: i64 = 10_000;

/// Bound on remembered hashes, so a burst of clipboard activity cannot grow
/// this without limit.
const MAX_DEDUPE_ENTRIES: usize = 32;

/// Where a clipboard value came from.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ClipboardOrigin {
    /// Copied by the user on this desktop.
    Local,
    /// Received from a logical device.
    Remote(String),
}

/// Why a clipboard action was refused.
#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum ClipboardRejection {
    #[error("clipboard sync is switched off")]
    Disabled,
    #[error("requesting device is not paired")]
    DeviceNotTrusted,
    #[error("clipboard content exceeds the size bound")]
    TooLarge,
    #[error("clipboard content is empty")]
    Empty,
    /// The value is one Relay just handled -- applying or resending it would
    /// bounce it back where it came from.
    #[error("clipboard content was already handled")]
    Duplicate,
}

/// A non-cryptographic content fingerprint.
///
/// Only ever compared against other fingerprints from this same process, so
/// collision resistance against an adversary is not required; what matters is
/// that identical text always hashes identically. FNV-1a is used rather than
/// `DefaultHasher` because the latter is randomly seeded per process and its
/// value is explicitly not stable, which would make the short prefix printed in
/// logs meaningless across runs.
pub fn content_hash(content: &str) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in content.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// A log-safe fingerprint prefix. Short on purpose: enough to correlate two
/// events, far too little to reconstruct anything.
pub fn hash_prefix(hash: u64) -> String {
    format!("{:04x}", hash >> 48)
}

#[derive(Clone, Debug)]
struct Seen {
    hash: u64,
    at_ms: i64,
}

/// Loop suppression for clipboard synchronisation.
///
/// The failure this exists to prevent: the desktop copies "hello", sends it to
/// the phone, the phone writes its clipboard, its listener observes the change
/// and sends "hello" back, the desktop writes its clipboard, its watcher
/// observes the change... forever.
///
/// The rule is that a value Relay itself just moved -- in either direction --
/// is not moved again. Both directions consult one shared window, so an echo is
/// suppressed no matter which side it comes back from.
#[derive(Debug, Default)]
pub struct ClipboardGuard {
    recent: VecDeque<Seen>,
}

impl ClipboardGuard {
    pub fn new() -> Self {
        Self::default()
    }

    fn prune(&mut self, now_ms: i64) {
        while let Some(front) = self.recent.front() {
            if now_ms.saturating_sub(front.at_ms) > DEDUPE_WINDOW_MS {
                self.recent.pop_front();
            } else {
                break;
            }
        }
        while self.recent.len() > MAX_DEDUPE_ENTRIES {
            self.recent.pop_front();
        }
    }

    fn contains(&self, hash: u64) -> bool {
        self.recent.iter().any(|seen| seen.hash == hash)
    }

    /// Records that Relay moved this content, in either direction.
    pub fn note_handled(&mut self, content: &str, now_ms: i64) {
        let hash = content_hash(content);
        self.prune(now_ms);
        // Refresh rather than duplicate, so repeated traffic for the same value
        // keeps the window alive without filling it.
        if let Some(entry) = self.recent.iter_mut().find(|seen| seen.hash == hash) {
            entry.at_ms = now_ms;
            return;
        }
        self.recent.push_back(Seen { hash, at_ms: now_ms });
        self.prune(now_ms);
    }

    /// Whether a locally observed clipboard change should be sent out.
    ///
    /// Refuses content Relay itself just applied from a remote device, which is
    /// what breaks the echo at its source.
    pub fn should_send_local(
        &mut self,
        content: &str,
        enabled: bool,
        now_ms: i64,
    ) -> Result<u64, ClipboardRejection> {
        if !enabled {
            return Err(ClipboardRejection::Disabled);
        }
        let checked = validate(content)?;
        self.prune(now_ms);
        if self.contains(checked) {
            return Err(ClipboardRejection::Duplicate);
        }
        Ok(checked)
    }

    /// Whether an incoming clipboard packet should be applied locally.
    ///
    /// `device_trusted` is passed in rather than looked up so this stays a pure
    /// decision function. A duplicate is refused, which is what makes a repeated
    /// or replayed packet idempotent instead of triggering another round trip.
    pub fn should_apply_remote(
        &mut self,
        content: &str,
        enabled: bool,
        device_trusted: bool,
        now_ms: i64,
    ) -> Result<u64, ClipboardRejection> {
        if !device_trusted {
            return Err(ClipboardRejection::DeviceNotTrusted);
        }
        if !enabled {
            return Err(ClipboardRejection::Disabled);
        }
        let checked = validate(content)?;
        self.prune(now_ms);
        if self.contains(checked) {
            return Err(ClipboardRejection::Duplicate);
        }
        Ok(checked)
    }
}

/// Shared content checks. Empty is refused because writing an empty clipboard
/// destroys whatever the user had, for no benefit.
fn validate(content: &str) -> Result<u64, ClipboardRejection> {
    if content.is_empty() {
        return Err(ClipboardRejection::Empty);
    }
    if content.len() > MAX_CLIPBOARD_BYTES {
        return Err(ClipboardRejection::TooLarge);
    }
    Ok(content_hash(content))
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: i64 = 1_700_000_000_000;

    #[test]
    fn identical_text_always_hashes_identically_and_differs_from_other_text() {
        assert_eq!(content_hash("hello"), content_hash("hello"));
        assert_ne!(content_hash("hello"), content_hash("hello "));
        assert_ne!(content_hash("hello"), content_hash("Hello"));
        // Unicode and multiline are just bytes to the hash.
        assert_eq!(content_hash("héllo\nwörld"), content_hash("héllo\nwörld"));
        assert_ne!(content_hash("héllo"), content_hash("hello"));
    }

    #[test]
    fn a_local_copy_propagates_once_and_then_is_deduped() {
        let mut guard = ClipboardGuard::new();
        let hash = guard.should_send_local("hello", true, T0).unwrap();
        guard.note_handled("hello", T0);

        assert_eq!(
            guard.should_send_local("hello", true, T0 + 100).unwrap_err(),
            ClipboardRejection::Duplicate,
            "the same value must not be sent twice inside the window"
        );
        assert_eq!(hash, content_hash("hello"));
    }

    #[test]
    fn applying_a_remote_value_stops_it_bouncing_back() {
        // The exact loop this design exists to prevent.
        let mut guard = ClipboardGuard::new();
        guard.should_apply_remote("hello", true, true, T0).unwrap();
        guard.note_handled("hello", T0);

        // The local clipboard watcher now observes the write Relay just made.
        assert_eq!(
            guard.should_send_local("hello", true, T0 + 5).unwrap_err(),
            ClipboardRejection::Duplicate,
            "a remote write must never be echoed back to its sender"
        );
    }

    #[test]
    fn a_duplicate_incoming_packet_is_idempotent() {
        let mut guard = ClipboardGuard::new();
        guard.should_apply_remote("hello", true, true, T0).unwrap();
        guard.note_handled("hello", T0);

        assert_eq!(
            guard.should_apply_remote("hello", true, true, T0 + 50).unwrap_err(),
            ClipboardRejection::Duplicate,
            "a retransmitted packet must not write the clipboard again"
        );
    }

    #[test]
    fn a_reconnect_replaying_the_same_value_does_not_loop() {
        // A connect packet re-sends the peer's current clipboard on every
        // reconnect; without dedupe that is an endless replay.
        let mut guard = ClipboardGuard::new();
        for round in 0..5 {
            let at = T0 + round * 100;
            let outcome = guard.should_apply_remote("hello", true, true, at);
            if round == 0 {
                assert!(outcome.is_ok());
                guard.note_handled("hello", at);
            } else {
                assert_eq!(outcome.unwrap_err(), ClipboardRejection::Duplicate);
            }
        }
    }

    #[test]
    fn the_same_value_propagates_again_once_the_window_has_passed() {
        // A user who deliberately re-copies the same text later must not be
        // silently ignored forever.
        let mut guard = ClipboardGuard::new();
        guard.note_handled("hello", T0);
        assert!(guard.should_send_local("hello", true, T0 + DEDUPE_WINDOW_MS + 1).is_ok());
    }

    #[test]
    fn a_different_value_is_never_blocked_by_a_previous_one() {
        let mut guard = ClipboardGuard::new();
        guard.note_handled("hello", T0);
        assert!(guard.should_send_local("world", true, T0 + 1).is_ok());
    }

    #[test]
    fn disabling_sync_blocks_both_directions() {
        let mut guard = ClipboardGuard::new();
        assert_eq!(
            guard.should_send_local("hello", false, T0).unwrap_err(),
            ClipboardRejection::Disabled
        );
        assert_eq!(
            guard.should_apply_remote("hello", false, true, T0).unwrap_err(),
            ClipboardRejection::Disabled,
            "a disabled clipboard must not be overwritten from outside either"
        );
    }

    #[test]
    fn an_untrusted_device_is_refused_before_anything_else_is_considered() {
        let mut guard = ClipboardGuard::new();
        // Refused even for otherwise perfectly valid content.
        assert_eq!(
            guard.should_apply_remote("hello", true, false, T0).unwrap_err(),
            ClipboardRejection::DeviceNotTrusted
        );
    }

    #[test]
    fn oversized_content_is_refused_in_both_directions() {
        let mut guard = ClipboardGuard::new();
        let huge = "x".repeat(MAX_CLIPBOARD_BYTES + 1);
        assert_eq!(
            guard.should_send_local(&huge, true, T0).unwrap_err(),
            ClipboardRejection::TooLarge
        );
        assert_eq!(
            guard.should_apply_remote(&huge, true, true, T0).unwrap_err(),
            ClipboardRejection::TooLarge,
            "an oversized packet must leave the local clipboard untouched"
        );
        // Exactly at the bound is still accepted.
        let exact = "x".repeat(MAX_CLIPBOARD_BYTES);
        assert!(guard.should_apply_remote(&exact, true, true, T0).is_ok());
    }

    #[test]
    fn empty_content_is_refused_so_a_clipboard_is_never_wiped() {
        let mut guard = ClipboardGuard::new();
        assert_eq!(guard.should_send_local("", true, T0).unwrap_err(), ClipboardRejection::Empty);
        assert_eq!(
            guard.should_apply_remote("", true, true, T0).unwrap_err(),
            ClipboardRejection::Empty
        );
    }

    #[test]
    fn unicode_and_multiline_content_round_trips() {
        let mut guard = ClipboardGuard::new();
        let text = "line one\nline two\tTabbed\n日本語 — émoji 🎉\nhttps://example.com/a?b=c";
        assert!(guard.should_apply_remote(text, true, true, T0).is_ok());
        guard.note_handled(text, T0);
        assert_eq!(
            guard.should_send_local(text, true, T0 + 1).unwrap_err(),
            ClipboardRejection::Duplicate
        );
    }

    #[test]
    fn a_multi_device_round_trip_settles_instead_of_looping() {
        // Desktop copies; phone A and phone B both echo it back. Neither echo
        // may be re-sent, or the fan-out becomes a storm.
        let mut guard = ClipboardGuard::new();
        guard.should_send_local("shared", true, T0).unwrap();
        guard.note_handled("shared", T0);

        for (index, device) in ["phone-a", "phone-b", "tablet"].iter().enumerate() {
            let at = T0 + 10 * (index as i64 + 1);
            assert_eq!(
                guard.should_apply_remote("shared", true, true, at).unwrap_err(),
                ClipboardRejection::Duplicate,
                "{device} echoed the desktop's own value back"
            );
        }
    }

    #[test]
    fn the_dedupe_window_stays_bounded_under_sustained_activity() {
        let mut guard = ClipboardGuard::new();
        for index in 0..(MAX_DEDUPE_ENTRIES * 10) {
            guard.note_handled(&format!("value-{index}"), T0 + index as i64);
        }
        assert!(
            guard.recent.len() <= MAX_DEDUPE_ENTRIES,
            "window grew to {}",
            guard.recent.len()
        );
    }

    #[test]
    fn repeating_one_value_refreshes_rather_than_filling_the_window() {
        let mut guard = ClipboardGuard::new();
        for index in 0..100 {
            guard.note_handled("same", T0 + index);
        }
        assert_eq!(guard.recent.len(), 1);
        // ...and the refresh keeps it suppressed relative to the latest write.
        assert_eq!(
            guard.should_send_local("same", true, T0 + 100).unwrap_err(),
            ClipboardRejection::Duplicate
        );
    }

    #[test]
    fn a_hash_prefix_is_short_and_stable_across_runs() {
        let prefix = hash_prefix(content_hash("hello"));
        assert_eq!(prefix.len(), 4);
        assert_eq!(prefix, hash_prefix(content_hash("hello")));
        assert_ne!(prefix, hash_prefix(content_hash("world")));
    }
}
