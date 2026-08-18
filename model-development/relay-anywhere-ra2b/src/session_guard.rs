use std::sync::{Mutex, OnceLock};

use anyhow::{Result, bail};

use crate::session::Ra2bCancellation;

struct ActiveSession {
    cancel: Ra2bCancellation,
}

fn active_slot() -> &'static Mutex<Option<ActiveSession>> {
    static SLOT: OnceLock<Mutex<Option<ActiveSession>>> = OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(None))
}

/// Process-wide RA2B lease: only one proof session may run at a time.
pub struct ActiveSessionGuard {
    cancel: Ra2bCancellation,
}

impl ActiveSessionGuard {
    pub fn acquire() -> Result<Self> {
        let mut slot = active_slot()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if slot.is_some() {
            bail!("RA2B session already active");
        }
        let cancel = Ra2bCancellation::new();
        *slot = Some(ActiveSession {
            cancel: cancel.clone(),
        });
        Ok(Self { cancel })
    }

    pub fn cancellation(&self) -> &Ra2bCancellation {
        &self.cancel
    }
}

impl Drop for ActiveSessionGuard {
    fn drop(&mut self) {
        self.cancel.cancel();
        let mut slot = active_slot()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        *slot = None;
    }
}

pub fn cancel_active_session() {
    if let Some(session) = active_slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .as_ref()
    {
        session.cancel.cancel();
    }
}

pub fn session_is_active() -> bool {
    active_slot()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_SERIAL: Mutex<()> = Mutex::new(());

    #[test]
    fn session_single_active_invariant() {
        let _serial = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        while session_is_active() {
            cancel_active_session();
        }
        let first = ActiveSessionGuard::acquire().unwrap();
        let second = ActiveSessionGuard::acquire();
        assert!(second.is_err());
        assert!(session_is_active());
        drop(first);
        assert!(!session_is_active());
        let third = ActiveSessionGuard::acquire().unwrap();
        drop(third);
        assert!(!session_is_active());
    }

    #[test]
    fn cancel_cleanup_sets_flag() {
        let _serial = TEST_SERIAL.lock().unwrap_or_else(|p| p.into_inner());
        while session_is_active() {
            cancel_active_session();
        }
        let guard = ActiveSessionGuard::acquire().unwrap();
        assert!(!guard.cancellation().is_cancelled());
        cancel_active_session();
        assert!(guard.cancellation().is_cancelled());
        drop(guard);
        assert!(!session_is_active());
    }
}
