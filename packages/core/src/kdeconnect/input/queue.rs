//! Bounded, coalescing delivery of input events to the backend.
//!
//! Pointer motion arrives at touch-sample rates and can outpace the compositor,
//! especially over WAN where a stall produces a burst on recovery. An unbounded
//! queue would turn that into growing memory and a cursor replaying minutes-old
//! movement; dropping indiscriminately would lose clicks.
//!
//! So the queue distinguishes the two: consecutive pointer motion is merged into
//! a single cumulative delta (the user only cares where the cursor ends up),
//! while clicks, scrolls and key events are never dropped or reordered.

use std::collections::VecDeque;
use std::sync::Arc;

use tokio::sync::{mpsc, Mutex};

use super::{InputEvent, RemoteInputBackend};

/// Hard cap on queued *discrete* actions.
///
/// Reached only if the backend has effectively stopped, in which case the
/// session is already broken and preserving more history helps nobody.
const MAX_QUEUED_EVENTS: usize = 256;

/// A per-device input queue.
pub struct InputQueue {
    tx: mpsc::Sender<Vec<InputEvent>>,
}

impl InputQueue {
    /// Starts a queue feeding `backend`.
    pub fn start(backend: Arc<dyn RemoteInputBackend>) -> Self {
        let (tx, mut rx) = mpsc::channel::<Vec<InputEvent>>(64);
        tokio::spawn(async move {
            let pending: Arc<Mutex<VecDeque<InputEvent>>> = Arc::new(Mutex::new(VecDeque::new()));
            while let Some(batch) = rx.recv().await {
                {
                    let mut queue = pending.lock().await;
                    for event in batch {
                        push_coalescing(&mut queue, event);
                    }
                }
                // Drain everything currently queued in one go so a click's press
                // and release are never split across dispatches.
                let drained: Vec<InputEvent> = {
                    let mut queue = pending.lock().await;
                    queue.drain(..).collect()
                };
                if drained.is_empty() {
                    continue;
                }
                if let Err(error) = backend.dispatch(&drained).await {
                    // A failed backend must not take Relay down with it; the
                    // session is marked unusable and later packets are refused
                    // by the gate rather than retried forever.
                    tracing::warn!("[Relay Input] dispatch failed: {error}");
                }
            }
        });
        Self { tx }
    }

    /// Offers a batch. Never blocks the caller: if the queue is full the batch
    /// is dropped, which is the same tradeoff as a saturated input device.
    pub async fn submit(&self, events: Vec<InputEvent>) {
        if self.tx.try_send(events).is_err() {
            tracing::debug!("[Relay Input] queue saturated, dropping a batch");
        }
    }
}

/// Appends `event`, merging it into the previous one when both are motion.
///
/// Merging is only correct because motion is relative and cumulative: two
/// consecutive deltas are exactly equivalent to their sum. Nothing else is
/// merged, so a click can never be absorbed into a movement.
pub(crate) fn push_coalescing(queue: &mut VecDeque<InputEvent>, event: InputEvent) {
    if let InputEvent::PointerMotion { dx, dy } = event {
        if let Some(InputEvent::PointerMotion { dx: prev_dx, dy: prev_dy }) = queue.back_mut() {
            *prev_dx += dx;
            *prev_dy += dy;
            return;
        }
        queue.push_back(InputEvent::PointerMotion { dx, dy });
        return;
    }
    if queue.len() >= MAX_QUEUED_EVENTS {
        // Shed the oldest coalescible sample rather than a discrete action.
        if let Some(index) = queue.iter().position(InputEvent::is_coalescible) {
            queue.remove(index);
        } else {
            queue.pop_front();
        }
    }
    queue.push_back(event);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kdeconnect::input::PointerButton;

    fn motion(dx: f64, dy: f64) -> InputEvent {
        InputEvent::PointerMotion { dx, dy }
    }

    fn click(pressed: bool) -> InputEvent {
        InputEvent::PointerButton { button: PointerButton::Left, pressed }
    }

    #[test]
    fn consecutive_motion_is_merged_into_one_cumulative_delta() {
        let mut queue = VecDeque::new();
        push_coalescing(&mut queue, motion(1.0, 2.0));
        push_coalescing(&mut queue, motion(3.0, -1.0));
        push_coalescing(&mut queue, motion(0.5, 0.5));

        assert_eq!(queue.len(), 1, "motion should collapse");
        assert_eq!(queue[0], motion(4.5, 1.5), "and the sum must be preserved exactly");
    }

    #[test]
    fn a_click_separates_motion_runs_and_is_never_merged() {
        let mut queue = VecDeque::new();
        push_coalescing(&mut queue, motion(1.0, 0.0));
        push_coalescing(&mut queue, click(true));
        push_coalescing(&mut queue, click(false));
        push_coalescing(&mut queue, motion(2.0, 0.0));

        assert_eq!(
            queue.iter().cloned().collect::<Vec<_>>(),
            vec![motion(1.0, 0.0), click(true), click(false), motion(2.0, 0.0)],
            "clicks must keep their order and their pairing"
        );
    }

    #[test]
    fn discrete_events_are_never_dropped_while_a_coalescible_one_can_be_shed() {
        let mut queue = VecDeque::new();
        // One motion sample followed by a full cap of discrete actions.
        push_coalescing(&mut queue, motion(1.0, 1.0));
        for _ in 0..MAX_QUEUED_EVENTS {
            push_coalescing(&mut queue, InputEvent::Keysym { keysym: 0xff0d, pressed: true });
        }

        assert!(
            !queue.iter().any(InputEvent::is_coalescible),
            "the motion sample should have been shed first"
        );
        assert_eq!(
            queue.iter().filter(|event| !event.is_coalescible()).count(),
            MAX_QUEUED_EVENTS,
            "every discrete action must survive"
        );
    }

    #[test]
    fn the_queue_never_grows_past_its_cap() {
        let mut queue = VecDeque::new();
        for index in 0..(MAX_QUEUED_EVENTS * 4) {
            push_coalescing(&mut queue, InputEvent::Keysym { keysym: index as i32, pressed: true });
        }
        assert!(queue.len() <= MAX_QUEUED_EVENTS, "bounded, got {}", queue.len());
    }

    #[test]
    fn scroll_is_not_merged_because_steps_are_discrete_to_the_user() {
        let mut queue = VecDeque::new();
        push_coalescing(&mut queue, InputEvent::Scroll { dx: 0.0, dy: 10.0 });
        push_coalescing(&mut queue, InputEvent::Scroll { dx: 0.0, dy: 10.0 });
        assert_eq!(queue.len(), 2);
    }
}
