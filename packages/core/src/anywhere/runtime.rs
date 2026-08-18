//! Per-session ownership for Anywhere.
//!
//! There is deliberately no process-wide "current session": every session gets
//! its own identifier, its own cancellation token, and its own set of pending
//! inbound requests. Cancelling, approving, or completing one session cannot
//! affect another.
//!
//! Approving an inbound request is session-scoped consent for that one
//! transfer. It never writes a [`crate::relay::DeviceBinding`] and never
//! becomes persistent trust.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use thiserror::Error;
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

/// Opaque handle to one Anywhere session.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct AnywhereSessionId(u64);

impl AnywhereSessionId {
    pub fn as_u64(self) -> u64 {
        self.0
    }

    pub fn from_u64(raw: u64) -> Self {
        Self(raw)
    }
}

/// Opaque handle to one pending inbound transfer request.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct IncomingTransferId(u64);

impl IncomingTransferId {
    pub fn as_u64(self) -> u64 {
        self.0
    }

    pub fn from_u64(raw: u64) -> Self {
        Self(raw)
    }
}

/// A platform-owned destination selected by the normal receive UI.
///
/// Android SAF documents are represented by an owned descriptor instead of
/// pretending every user-selected destination has a filesystem path.
#[derive(Debug)]
pub enum AnywhereSaveTarget {
    Path(PathBuf),
    #[cfg(target_os = "android")]
    FileDescriptor(std::os::fd::RawFd),
}

/// Session-scoped receiver decision. Save targets come from the existing UI and
/// save-target machinery; nothing here is persisted as trust.
#[derive(Debug)]
pub struct AnywhereDecision {
    pub accept: bool,
    pub targets: HashMap<String, AnywhereSaveTarget>,
}

impl AnywhereDecision {
    pub fn decline() -> Self {
        Self {
            accept: false,
            targets: HashMap::new(),
        }
    }
}

#[derive(Clone, Copy, Debug, Error, Eq, PartialEq)]
pub enum AnywhereRespondError {
    #[error("no such Anywhere session")]
    UnknownSession,
    #[error("no such pending inbound transfer")]
    UnknownRequest,
    #[error("the pending inbound transfer is no longer waiting")]
    RequestGone,
}

struct SessionEntry {
    cancel: CancellationToken,
    pending: HashMap<IncomingTransferId, oneshot::Sender<AnywhereDecision>>,
}

/// Registry of live Anywhere sessions.
///
/// A registry instance may be shared by a bridge layer, but it is a
/// `Map<SessionId, Handle>` — never a single-slot lease.
#[derive(Default)]
pub struct AnywhereRuntime {
    sessions: Mutex<HashMap<AnywhereSessionId, SessionEntry>>,
    next_id: AtomicU64,
}

impl AnywhereRuntime {
    pub fn new() -> Self {
        Self::default()
    }

    fn next(&self) -> u64 {
        self.next_id.fetch_add(1, Ordering::SeqCst) + 1
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<AnywhereSessionId, SessionEntry>> {
        self.sessions
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Opens a session. Any number of sessions may be open at once.
    pub fn open_session(&self) -> (AnywhereSessionId, CancellationToken) {
        let id = AnywhereSessionId(self.next());
        let cancel = CancellationToken::new();
        self.lock().insert(
            id,
            SessionEntry {
                cancel: cancel.clone(),
                pending: HashMap::new(),
            },
        );
        (id, cancel)
    }

    /// Registers a pending inbound request against one session and returns the
    /// receiver that session must await.
    pub fn register_incoming(
        &self,
        session: AnywhereSessionId,
    ) -> Option<(IncomingTransferId, oneshot::Receiver<AnywhereDecision>)> {
        let id = IncomingTransferId(self.next());
        let (tx, rx) = oneshot::channel();
        let mut sessions = self.lock();
        let entry = sessions.get_mut(&session)?;
        entry.pending.insert(id, tx);
        Some((id, rx))
    }

    /// Answers exactly one pending request. Other requests, in this session or
    /// any other, are untouched.
    pub fn respond(
        &self,
        session: AnywhereSessionId,
        request: IncomingTransferId,
        decision: AnywhereDecision,
    ) -> Result<(), AnywhereRespondError> {
        let sender = {
            let mut sessions = self.lock();
            let entry = sessions
                .get_mut(&session)
                .ok_or(AnywhereRespondError::UnknownSession)?;
            entry
                .pending
                .remove(&request)
                .ok_or(AnywhereRespondError::UnknownRequest)?
        };
        sender
            .send(decision)
            .map_err(|_| AnywhereRespondError::RequestGone)
    }

    /// Cancels one session. Returns whether a live session was found.
    pub fn cancel(&self, session: AnywhereSessionId) -> bool {
        let sessions = self.lock();
        match sessions.get(&session) {
            Some(entry) => {
                entry.cancel.cancel();
                true
            }
            None => false,
        }
    }

    /// Removes one session's handle, dropping any request still pending on it.
    pub fn close_session(&self, session: AnywhereSessionId) -> bool {
        self.lock().remove(&session).is_some()
    }

    /// The session's own cancellation token, if it is still open.
    pub fn cancellation(&self, session: AnywhereSessionId) -> Option<CancellationToken> {
        self.lock().get(&session).map(|entry| entry.cancel.clone())
    }

    pub fn is_open(&self, session: AnywhereSessionId) -> bool {
        self.lock().contains_key(&session)
    }

    pub fn open_session_count(&self) -> usize {
        self.lock().len()
    }

    pub fn pending_request_count(&self, session: AnywhereSessionId) -> usize {
        self.lock()
            .get(&session)
            .map_or(0, |entry| entry.pending.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn accept() -> AnywhereDecision {
        AnywhereDecision {
            accept: true,
            targets: HashMap::new(),
        }
    }

    #[test]
    fn two_independent_sessions_can_be_open_at_once() {
        let runtime = AnywhereRuntime::new();
        let (first, _) = runtime.open_session();
        let (second, _) = runtime.open_session();
        assert_ne!(first, second);
        assert_eq!(runtime.open_session_count(), 2);
        assert!(runtime.is_open(first) && runtime.is_open(second));
    }

    #[tokio::test]
    async fn two_inbound_requests_stay_pending_independently() {
        let runtime = AnywhereRuntime::new();
        let (session, _) = runtime.open_session();
        let (first, first_rx) = runtime.register_incoming(session).unwrap();
        let (second, second_rx) = runtime.register_incoming(session).unwrap();
        assert_ne!(first, second);
        assert_eq!(runtime.pending_request_count(session), 2);
        drop((first_rx, second_rx));
    }

    #[tokio::test]
    async fn accepting_one_request_does_not_answer_the_other() {
        let runtime = AnywhereRuntime::new();
        let (session, _) = runtime.open_session();
        let (first, mut first_rx) = runtime.register_incoming(session).unwrap();
        let (_second, mut second_rx) = runtime.register_incoming(session).unwrap();

        runtime.respond(session, first, accept()).unwrap();

        assert!(first_rx.try_recv().unwrap().accept);
        assert_eq!(
            second_rx.try_recv().err(),
            Some(oneshot::error::TryRecvError::Empty)
        );
        assert_eq!(runtime.pending_request_count(session), 1);
    }

    #[tokio::test]
    async fn declining_one_request_does_not_cancel_the_session_or_the_other() {
        let runtime = AnywhereRuntime::new();
        let (session, cancel) = runtime.open_session();
        let (_first, mut first_rx) = runtime.register_incoming(session).unwrap();
        let (second, mut second_rx) = runtime.register_incoming(session).unwrap();

        runtime
            .respond(session, second, AnywhereDecision::decline())
            .unwrap();

        assert!(!second_rx.try_recv().unwrap().accept);
        assert_eq!(
            first_rx.try_recv().err(),
            Some(oneshot::error::TryRecvError::Empty)
        );
        assert!(!cancel.is_cancelled());
    }

    #[test]
    fn cancelling_one_session_leaves_the_other_running() {
        let runtime = AnywhereRuntime::new();
        let (first, first_cancel) = runtime.open_session();
        let (second, second_cancel) = runtime.open_session();

        assert!(runtime.cancel(first));

        assert!(first_cancel.is_cancelled());
        assert!(!second_cancel.is_cancelled());
        assert!(runtime.is_open(second));
    }

    #[test]
    fn completion_removes_only_its_own_handle() {
        let runtime = AnywhereRuntime::new();
        let (first, _first_cancel) = runtime.open_session();
        let (second, second_cancel) = runtime.open_session();

        assert!(runtime.close_session(first));

        assert!(!runtime.is_open(first));
        assert!(runtime.is_open(second));
        assert!(!second_cancel.is_cancelled());
        assert_eq!(runtime.open_session_count(), 1);
        assert!(!runtime.close_session(first));
    }

    #[test]
    fn responding_to_an_unknown_session_or_request_is_an_error() {
        let runtime = AnywhereRuntime::new();
        let (session, _) = runtime.open_session();
        assert_eq!(
            runtime.respond(AnywhereSessionId(999), IncomingTransferId(1), accept()),
            Err(AnywhereRespondError::UnknownSession)
        );
        assert_eq!(
            runtime.respond(session, IncomingTransferId(999), accept()),
            Err(AnywhereRespondError::UnknownRequest)
        );
    }
}
