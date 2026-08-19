//! Freshness and idempotency for privileged continuity actions.
//!
//! Streaming state (battery, clipboard, notifications) is idempotent by nature.
//! *Action* payloads are not: replaying one would send an SMS twice or answer a
//! call the user already rejected. Every action carries a `request_id` and an
//! `issued_at_ms`; this module bounds both.

use std::collections::VecDeque;

use lru::LruCache;

use super::protocol::MAX_ACTION_SKEW_MS;

/// How many completed action results are remembered per peer session.
const ACTION_HISTORY: usize = 256;
/// How many recently seen envelope ids are remembered per peer session.
const ENVELOPE_HISTORY: usize = 512;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ActionAdmission {
    /// First time this request has been seen; execute it.
    Fresh,
    /// Already executed. The caller replies with the recorded result instead of
    /// executing again.
    Duplicate,
    /// Outside the freshness window in either direction. Never executed.
    Stale,
}

/// Per-session replay guard. One instance belongs to one authenticated peer
/// session and is dropped with it, so ids can never leak between peers.
pub struct ReplayGuard {
    seen_envelopes: LruCache<String, ()>,
    completed_actions: LruCache<String, ()>,
    /// Insertion order, kept only so tests can assert bounded growth.
    order: VecDeque<String>,
}

impl ReplayGuard {
    pub fn new() -> Self {
        Self {
            seen_envelopes: LruCache::new(
                std::num::NonZeroUsize::new(ENVELOPE_HISTORY).expect("non-zero"),
            ),
            completed_actions: LruCache::new(
                std::num::NonZeroUsize::new(ACTION_HISTORY).expect("non-zero"),
            ),
            order: VecDeque::new(),
        }
    }

    /// Records an envelope id. Returns `false` when it was already seen.
    pub fn accept_envelope(&mut self, message_id: &str) -> bool {
        if self.seen_envelopes.contains(message_id) {
            return false;
        }
        self.seen_envelopes.put(message_id.to_owned(), ());
        self.order.push_back(message_id.to_owned());
        while self.order.len() > ENVELOPE_HISTORY {
            self.order.pop_front();
        }
        true
    }

    /// Decides whether a privileged action may run.
    ///
    /// `now_ms` is this device's clock. The window is symmetric so a peer with a
    /// fast clock is not silently trusted to schedule actions into the future.
    pub fn admit_action(
        &mut self,
        request_id: &str,
        issued_at_ms: u64,
        now_ms: u64,
    ) -> ActionAdmission {
        let skew = now_ms.abs_diff(issued_at_ms);
        if skew > MAX_ACTION_SKEW_MS {
            return ActionAdmission::Stale;
        }
        if self.completed_actions.contains(request_id) {
            return ActionAdmission::Duplicate;
        }
        ActionAdmission::Fresh
    }

    /// Marks an action as executed so a retry after reconnect is answered from
    /// history rather than executed again.
    pub fn record_action(&mut self, request_id: &str) {
        self.completed_actions.put(request_id.to_owned(), ());
    }

    pub fn tracked_envelopes(&self) -> usize {
        self.seen_envelopes.len()
    }
}

impl Default for ReplayGuard {
    fn default() -> Self {
        Self::new()
    }
}
