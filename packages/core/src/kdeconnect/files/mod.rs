//! Relay file transfer: KDE-compatible `kdeconnect.share.request` metadata plus
//! the payload transports that carry the bytes.
//!
//! This is a logical-device feature. The control packet and the transfer state
//! machine know nothing about routes; whichever transport the router selects
//! carries the payload, and the same code serves LAN and Relay WAN.
//!
//! # Ownership of a transfer
//!
//! State is keyed by `(device_id, transfer_id)` -- never by filename, transport,
//! LAN address or `EndpointId`. Two devices sending `photo.jpg` at the same
//! moment are two independent transfers, and a route change cannot relabel
//! either of them.
//!
//! # Route policy
//!
//! The transport selected when a payload begins owns that transfer for its whole
//! lifetime. Relay does not migrate bytes mid-stream between LAN and WAN: half a
//! file over one route and half over another has no safe meaning, and the
//! receiver's size check would reject the result anyway. If the owning route
//! dies the transfer fails cleanly and a retry may pick the new route.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES;

pub mod receive;

/// Why a transfer cannot proceed.
#[derive(Clone, Debug, Eq, PartialEq, thiserror::Error)]
pub enum TransferRejection {
    /// The file is larger than Relay WAN will carry. Surfaced to the user as
    /// "Local connection required" -- never as a network error, because nothing
    /// went wrong on the network and retrying remotely cannot help.
    #[error("RequiresLocalConnection: {size} bytes exceeds the {limit}-byte remote limit")]
    RequiresLocalConnection { size: u64, limit: u64 },
    /// Size could not be determined, so the remote limit cannot be enforced up
    /// front. Streaming anyway would mean an unbounded remote transfer.
    #[error("RequiresLocalConnection: file size is unknown")]
    UnknownSize,
    #[error("requesting device is not paired")]
    DeviceNotTrusted,
    #[error("declared payload size is missing or invalid")]
    InvalidMetadata,
}

/// Progress and outcome of one transfer.
///
/// `Sending`/`Receiving` carry byte counters rather than a fraction so the UI
/// can render "8.4 MB / 14.2 MB" without the state machine having to know how a
/// number should be formatted.
#[derive(Clone, Debug, PartialEq)]
pub enum TransferState {
    Preparing,
    Sending { transferred: u64, total: u64 },
    Receiving { transferred: u64, total: u64 },
    Completed { total: u64 },
    Failed { reason: String },
    Cancelled,
    /// Refused before any byte moved because the file is too large for the
    /// current (remote) route.
    RequiresLocalConnection,
}

impl TransferState {
    /// Fraction complete, 0.0 to 1.0.
    ///
    /// A zero-byte file is complete the moment it starts -- reporting 0.0 for
    /// something already finished would leave a progress bar stuck at empty.
    pub fn progress(&self) -> f64 {
        match self {
            TransferState::Preparing => 0.0,
            TransferState::Sending { transferred, total }
            | TransferState::Receiving { transferred, total } => {
                if *total == 0 {
                    1.0
                } else {
                    (*transferred as f64 / *total as f64).clamp(0.0, 1.0)
                }
            }
            TransferState::Completed { .. } => 1.0,
            TransferState::Failed { .. }
            | TransferState::Cancelled
            | TransferState::RequiresLocalConnection => 0.0,
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(
            self,
            TransferState::Completed { .. }
                | TransferState::Failed { .. }
                | TransferState::Cancelled
                | TransferState::RequiresLocalConnection
        )
    }
}

/// Identifies one transfer, for one logical device.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct TransferKey {
    pub device_id: String,
    pub transfer_id: String,
}

impl TransferKey {
    pub fn new(device_id: impl Into<String>, transfer_id: impl Into<String>) -> Self {
        Self {
            device_id: device_id.into(),
            transfer_id: transfer_id.into(),
        }
    }
}

pub fn generate_transfer_id() -> String {
    uuid::Uuid::new_v4().simple().to_string()
}

/// One in-flight or finished transfer.
#[derive(Clone, Debug, PartialEq)]
pub struct Transfer {
    pub key: TransferKey,
    pub filename: String,
    pub total_bytes: u64,
    pub state: TransferState,
}

/// Decides whether a file may be sent over the currently selected route.
///
/// The check happens *before* a transfer starts, which is the whole point: an
/// oversized file must never begin transferring and then be cancelled partway.
///
/// `remote` is whether the selected route is Relay WAN. LAN deliberately has no
/// size policy here -- this must not change LAN behaviour.
pub fn check_sendable(size: Option<u64>, remote: bool) -> Result<u64, TransferRejection> {
    match size {
        Some(size) if !remote => Ok(size),
        Some(size) if size <= MAX_WAN_PAYLOAD_BYTES => Ok(size),
        Some(size) => Err(TransferRejection::RequiresLocalConnection {
            size,
            limit: MAX_WAN_PAYLOAD_BYTES,
        }),
        // Unknown size is only a problem remotely: locally there is no ceiling
        // to enforce, so a stream of unknown length is fine.
        None if !remote => Ok(0),
        None => Err(TransferRejection::UnknownSize),
    }
}

/// Reduces a remote-supplied filename to a safe basename.
///
/// Remote file *paths* are never trusted. Anything that could escape the
/// destination directory -- separators, `..`, drive letters, NUL -- is stripped
/// or replaced, and a name that reduces to nothing gets a neutral fallback
/// rather than being used as-is.
pub fn sanitize_filename(raw: &str) -> String {
    // Take the last component under either separator, so `../../etc/passwd` and
    // `C:\Windows\system32\x` both reduce to their final element.
    let basename = raw
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or("")
        .trim()
        .to_string();

    let cleaned: String = basename
        .chars()
        .filter(|c| !c.is_control() && *c != '\0')
        .collect();

    // `.` and `..` survive the basename step but are still directory
    // references, and a leading dot would silently hide the file.
    let cleaned = cleaned.trim_start_matches('.').trim().to_string();

    if cleaned.is_empty() {
        return "relay-file".to_string();
    }
    // Bound the length so a pathological name cannot break the filesystem.
    if cleaned.len() > 200 {
        let mut truncated: String = cleaned.chars().take(200).collect();
        truncated.push_str(".part");
        return truncated;
    }
    cleaned
}

/// Picks a destination that does not overwrite an existing file.
///
/// Collisions are resolved by suffixing, the way a browser download does:
/// silently replacing a file the user already had would be data loss caused by
/// a remote device.
pub fn unique_destination(directory: &Path, filename: &str) -> PathBuf {
    let candidate = directory.join(filename);
    if !candidate.exists() {
        return candidate;
    }
    let path = Path::new(filename);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("relay-file");
    let extension = path.extension().and_then(|value| value.to_str());
    for index in 1..10_000 {
        let name = match extension {
            Some(extension) => format!("{stem} ({index}).{extension}"),
            None => format!("{stem} ({index})"),
        };
        let candidate = directory.join(name);
        if !candidate.exists() {
            return candidate;
        }
    }
    directory.join(format!("{stem}-{}", generate_transfer_id()))
}

/// Tracks every transfer, scoped to its logical device.
#[derive(Debug, Default)]
pub struct TransferRegistry {
    transfers: HashMap<TransferKey, Transfer>,
    /// How much progress must move before a new update is worth emitting.
    progress_step: u64,
    last_reported: HashMap<TransferKey, u64>,
}

impl TransferRegistry {
    pub fn new() -> Self {
        Self {
            // Roughly 1% of the remote ceiling: frequent enough to look smooth,
            // sparse enough that a fast local transfer does not flood the UI
            // with thousands of rebuilds.
            progress_step: 256 * 1024,
            ..Default::default()
        }
    }

    pub fn insert(&mut self, transfer: Transfer) {
        self.last_reported.insert(transfer.key.clone(), 0);
        self.transfers.insert(transfer.key.clone(), transfer);
    }

    pub fn get(&self, key: &TransferKey) -> Option<&Transfer> {
        self.transfers.get(key)
    }

    /// Transfers belonging to one logical device, and only that device.
    pub fn for_device(&self, device_id: &str) -> Vec<&Transfer> {
        self.transfers
            .values()
            .filter(|transfer| transfer.key.device_id == device_id)
            .collect()
    }

    /// Records progress. Returns true when the change is worth publishing,
    /// which throttles UI churn without ever suppressing a terminal state.
    pub fn advance(&mut self, key: &TransferKey, transferred: u64, receiving: bool) -> bool {
        let Some(transfer) = self.transfers.get_mut(key) else {
            return false;
        };
        if transfer.state.is_terminal() {
            return false;
        }
        // Never let a counter go backwards: progress that jitters is worse than
        // progress that is coarse.
        let previous = match &transfer.state {
            TransferState::Sending { transferred, .. }
            | TransferState::Receiving { transferred, .. } => *transferred,
            _ => 0,
        };
        let transferred = transferred.max(previous).min(transfer.total_bytes);
        transfer.state = if receiving {
            TransferState::Receiving {
                transferred,
                total: transfer.total_bytes,
            }
        } else {
            TransferState::Sending {
                transferred,
                total: transfer.total_bytes,
            }
        };

        let last = self.last_reported.get(key).copied().unwrap_or(0);
        let complete = transferred >= transfer.total_bytes;
        if complete || transferred.saturating_sub(last) >= self.progress_step {
            self.last_reported.insert(key.clone(), transferred);
            return true;
        }
        false
    }

    /// Moves a transfer to a terminal state. Always publishable.
    pub fn finish(&mut self, key: &TransferKey, state: TransferState) -> Option<&Transfer> {
        let transfer = self.transfers.get_mut(key)?;
        transfer.state = state;
        Some(transfer)
    }

    pub fn remove(&mut self, key: &TransferKey) -> Option<Transfer> {
        self.last_reported.remove(key);
        self.transfers.remove(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIMIT: u64 = MAX_WAN_PAYLOAD_BYTES;

    #[test]
    fn the_remote_limit_is_exactly_twenty_mebibytes() {
        assert_eq!(LIMIT, 20 * 1024 * 1024);
        assert_eq!(LIMIT, 20_971_520);
    }

    #[test]
    fn the_remote_size_boundary_is_enforced_before_a_transfer_starts() {
        assert!(check_sendable(Some(0), true).is_ok());
        assert!(check_sendable(Some(1), true).is_ok());
        assert!(check_sendable(Some(LIMIT - 1), true).is_ok());
        assert!(check_sendable(Some(LIMIT), true).is_ok(), "exactly at the limit is allowed");

        let error = check_sendable(Some(LIMIT + 1), true).unwrap_err();
        assert_eq!(
            error,
            TransferRejection::RequiresLocalConnection { size: LIMIT + 1, limit: LIMIT },
            "one byte over must be refused up front, not cancelled mid-transfer"
        );
    }

    #[test]
    fn a_local_route_has_no_size_ceiling() {
        // The remote policy must not change LAN behaviour.
        assert!(check_sendable(Some(LIMIT + 1), false).is_ok());
        assert!(check_sendable(Some(u64::MAX), false).is_ok());
    }

    #[test]
    fn an_unknown_size_is_refused_remotely_but_allowed_locally() {
        // Streaming an unknown length remotely would be an unbounded transfer.
        assert_eq!(check_sendable(None, true).unwrap_err(), TransferRejection::UnknownSize);
        assert!(check_sendable(None, false).is_ok());
    }

    #[test]
    fn path_traversal_is_reduced_to_a_safe_basename() {
        for (raw, expected) in [
            ("../../etc/passwd", "passwd"),
            ("/etc/shadow", "shadow"),
            ("C:\\Windows\\system32\\evil.dll", "evil.dll"),
            ("..\\..\\secret.txt", "secret.txt"),
            ("photo.jpg", "photo.jpg"),
            ("subdir/photo.jpg", "photo.jpg"),
        ] {
            assert_eq!(sanitize_filename(raw), expected, "{raw}");
        }
    }

    #[test]
    fn names_that_reduce_to_nothing_get_a_neutral_fallback() {
        for raw in ["", "   ", "..", ".", "/", "\\", "///", "..."] {
            let safe = sanitize_filename(raw);
            assert_eq!(safe, "relay-file", "{raw:?} produced {safe:?}");
        }
    }

    #[test]
    fn a_sanitized_name_can_never_contain_a_separator_or_control_character() {
        for raw in ["a/b", "a\\b", "a\0b", "a\nb", "..\\/..\\x"] {
            let safe = sanitize_filename(raw);
            assert!(!safe.contains('/'), "{raw:?} -> {safe:?}");
            assert!(!safe.contains('\\'), "{raw:?} -> {safe:?}");
            assert!(!safe.chars().any(char::is_control), "{raw:?} -> {safe:?}");
        }
    }

    #[test]
    fn an_absurdly_long_name_is_bounded() {
        let safe = sanitize_filename(&"x".repeat(5000));
        assert!(safe.len() <= 210, "got {} chars", safe.len());
    }

    #[test]
    fn a_leading_dot_cannot_be_used_to_hide_a_received_file() {
        assert_eq!(sanitize_filename(".bashrc"), "bashrc");
    }

    #[test]
    fn a_colliding_destination_is_suffixed_rather_than_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        let first = unique_destination(dir.path(), "photo.jpg");
        assert_eq!(first.file_name().unwrap(), "photo.jpg");
        std::fs::write(&first, b"one").unwrap();

        let second = unique_destination(dir.path(), "photo.jpg");
        assert_eq!(second.file_name().unwrap(), "photo (1).jpg");
        std::fs::write(&second, b"two").unwrap();

        let third = unique_destination(dir.path(), "photo.jpg");
        assert_eq!(third.file_name().unwrap(), "photo (2).jpg");
        // The original is untouched.
        assert_eq!(std::fs::read(&first).unwrap(), b"one");
    }

    #[test]
    fn a_collision_on_a_name_without_an_extension_still_resolves() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("README"), b"x").unwrap();
        let next = unique_destination(dir.path(), "README");
        assert_eq!(next.file_name().unwrap(), "README (1)");
    }

    fn transfer(device: &str, id: &str, total: u64) -> Transfer {
        Transfer {
            key: TransferKey::new(device, id),
            filename: "photo.jpg".into(),
            total_bytes: total,
            state: TransferState::Preparing,
        }
    }

    #[test]
    fn two_devices_sending_the_same_filename_are_independent_transfers() {
        let mut registry = TransferRegistry::new();
        registry.insert(transfer("device-a", "t1", 100));
        registry.insert(transfer("device-b", "t2", 200));

        registry.advance(&TransferKey::new("device-a", "t1"), 50, true);

        assert_eq!(
            registry.get(&TransferKey::new("device-a", "t1")).unwrap().state,
            TransferState::Receiving { transferred: 50, total: 100 }
        );
        assert_eq!(
            registry.get(&TransferKey::new("device-b", "t2")).unwrap().state,
            TransferState::Preparing,
            "the other device's transfer must be untouched"
        );
        assert_eq!(registry.for_device("device-a").len(), 1);
        assert_eq!(registry.for_device("device-b").len(), 1);
    }

    #[test]
    fn the_same_transfer_id_under_two_devices_does_not_collide() {
        let mut registry = TransferRegistry::new();
        registry.insert(transfer("device-a", "same-id", 10));
        registry.insert(transfer("device-b", "same-id", 20));
        assert_eq!(registry.get(&TransferKey::new("device-a", "same-id")).unwrap().total_bytes, 10);
        assert_eq!(registry.get(&TransferKey::new("device-b", "same-id")).unwrap().total_bytes, 20);
    }

    #[test]
    fn progress_never_moves_backwards() {
        let mut registry = TransferRegistry::new();
        let key = TransferKey::new("device-a", "t1");
        registry.insert(transfer("device-a", "t1", 1_000_000));

        registry.advance(&key, 800_000, false);
        registry.advance(&key, 100_000, false); // a late, stale sample
        match &registry.get(&key).unwrap().state {
            TransferState::Sending { transferred, .. } => assert_eq!(*transferred, 800_000),
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn progress_is_clamped_to_the_declared_total() {
        let mut registry = TransferRegistry::new();
        let key = TransferKey::new("device-a", "t1");
        registry.insert(transfer("device-a", "t1", 100));
        registry.advance(&key, 500, true);
        assert_eq!(registry.get(&key).unwrap().state.progress(), 1.0);
    }

    #[test]
    fn progress_updates_are_throttled_but_completion_always_reports() {
        let mut registry = TransferRegistry::new();
        let key = TransferKey::new("device-a", "t1");
        registry.insert(transfer("device-a", "t1", 10_000_000));

        // A trickle of tiny updates should not each produce an event.
        let mut published = 0;
        for chunk in 1..=20 {
            if registry.advance(&key, chunk * 1024, false) {
                published += 1;
            }
        }
        assert_eq!(published, 0, "small deltas must be coalesced");

        assert!(registry.advance(&key, 300 * 1024, false), "a large delta publishes");
        assert!(
            registry.advance(&key, 10_000_000, false),
            "reaching the total always publishes"
        );
    }

    #[test]
    fn a_terminal_transfer_ignores_further_progress() {
        let mut registry = TransferRegistry::new();
        let key = TransferKey::new("device-a", "t1");
        registry.insert(transfer("device-a", "t1", 100));
        registry.finish(&key, TransferState::Cancelled);

        assert!(!registry.advance(&key, 50, true));
        assert_eq!(registry.get(&key).unwrap().state, TransferState::Cancelled);
    }

    #[test]
    fn progress_of_each_state_reads_sensibly() {
        assert_eq!(TransferState::Preparing.progress(), 0.0);
        assert_eq!(TransferState::Completed { total: 10 }.progress(), 1.0);
        assert_eq!(TransferState::Cancelled.progress(), 0.0);
        assert_eq!(TransferState::RequiresLocalConnection.progress(), 0.0);
        // A zero-byte file is finished as soon as it begins.
        assert_eq!(
            TransferState::Receiving { transferred: 0, total: 0 }.progress(),
            1.0
        );
        assert_eq!(
            TransferState::Sending { transferred: 5, total: 10 }.progress(),
            0.5
        );
    }

    #[test]
    fn only_terminal_states_report_as_terminal() {
        assert!(!TransferState::Preparing.is_terminal());
        assert!(!TransferState::Sending { transferred: 1, total: 2 }.is_terminal());
        assert!(TransferState::Completed { total: 2 }.is_terminal());
        assert!(TransferState::Failed { reason: "x".into() }.is_terminal());
        assert!(TransferState::Cancelled.is_terminal());
        assert!(TransferState::RequiresLocalConnection.is_terminal());
    }
}
