//! Local, per-device continuity permissions.
//!
//! Three questions are kept deliberately separate:
//!
//! 1. *Can we route to this device?* — a stored [`crate::anywhere::RelayAddressV1`].
//! 2. *Is this device who it claims to be?* — a proven
//!    [`crate::relay::AuthenticatedRelaySession`].
//! 3. *Is this device trusted, and did the user enable this capability?* — this
//!    module plus [`crate::relay::TrustDirectory`].
//!
//! Pairing answers (1) and enables (2). It never answers (3). Nothing in this
//! module can be set by a network message; grants come from local user action
//! and are persisted by the app layer.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use super::protocol::ContinuityCapability;

/// How clipboard content moves once the capability is granted.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClipboardMode {
    /// No clipboard content is sent or applied. The default.
    #[default]
    Off,
    /// Incoming content is surfaced for the user to apply; outgoing content is
    /// only sent through an explicit "share clipboard" action.
    Ask,
    /// Content flows in both directions without a prompt.
    Automatic,
}

impl ClipboardMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Ask => "ask",
            Self::Automatic => "automatic",
        }
    }

    /// Whether an automatic (non-user-initiated) send is permitted.
    pub fn allows_automatic_send(self) -> bool {
        matches!(self, Self::Automatic)
    }

    /// Whether incoming content may be written to the local clipboard without
    /// asking.
    pub fn allows_automatic_apply(self) -> bool {
        matches!(self, Self::Automatic)
    }

    pub fn is_enabled(self) -> bool {
        !matches!(self, Self::Off)
    }
}

/// Per-capability user decision. There is no "ask later" state here: an
/// ungranted capability is simply denied, and the UI is what asks.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityGrant {
    #[default]
    Denied,
    Granted,
}

impl CapabilityGrant {
    pub fn is_granted(self) -> bool {
        matches!(self, Self::Granted)
    }
}

/// Continuity permissions for one paired device.
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct DeviceContinuityPermissions {
    #[serde(default)]
    grants: BTreeMap<String, CapabilityGrant>,
    #[serde(default)]
    pub clipboard_mode: ClipboardMode,
}

impl DeviceContinuityPermissions {
    pub fn grant_of(&self, capability: ContinuityCapability) -> CapabilityGrant {
        self.grants
            .get(capability.as_str())
            .copied()
            .unwrap_or_default()
    }

    pub fn set_grant(&mut self, capability: ContinuityCapability, grant: CapabilityGrant) {
        if !capability.is_grantable() {
            return;
        }
        self.grants.insert(capability.as_str().to_owned(), grant);
    }

    pub fn granted_capabilities(&self) -> Vec<ContinuityCapability> {
        ContinuityCapability::GRANTABLE
            .into_iter()
            .filter(|capability| self.is_enabled(*capability))
            .collect()
    }

    /// Whether the capability is usable, folding in the clipboard mode so that
    /// "granted but mode Off" is honestly reported as disabled.
    pub fn is_enabled(&self, capability: ContinuityCapability) -> bool {
        if !self.grant_of(capability).is_granted() {
            return false;
        }
        match capability {
            ContinuityCapability::Clipboard => self.clipboard_mode.is_enabled(),
            _ => true,
        }
    }
}

/// The whole local permission store, keyed by proven RelayId hex.
///
/// Keys are only ever written from a proven session or from local UI. A key is
/// meaningless as a credential: possessing it does not let anyone authenticate.
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct ContinuityPermissions {
    #[serde(default)]
    devices: BTreeMap<String, DeviceContinuityPermissions>,
}

impl ContinuityPermissions {
    pub fn new() -> Self {
        Self::default()
    }

    /// Permissions for a device. A device that has never been configured gets
    /// the all-denied default rather than an inherited or global grant.
    pub fn for_device(&self, relay_id_hex: &str) -> DeviceContinuityPermissions {
        self.devices.get(relay_id_hex).cloned().unwrap_or_default()
    }

    pub fn set_grant(
        &mut self,
        relay_id_hex: &str,
        capability: ContinuityCapability,
        grant: CapabilityGrant,
    ) {
        self.devices
            .entry(relay_id_hex.to_owned())
            .or_default()
            .set_grant(capability, grant);
    }

    pub fn set_clipboard_mode(&mut self, relay_id_hex: &str, mode: ClipboardMode) {
        self.devices
            .entry(relay_id_hex.to_owned())
            .or_default()
            .clipboard_mode = mode;
    }

    pub fn forget_device(&mut self, relay_id_hex: &str) {
        self.devices.remove(relay_id_hex);
    }

    pub fn device_ids(&self) -> Vec<String> {
        self.devices.keys().cloned().collect()
    }

    /// Whether *any* device has continuity enabled.
    ///
    /// The Android layer uses this to decide whether a background connectivity
    /// service should exist at all: a fresh install with continuity untouched
    /// must not run one.
    pub fn any_capability_enabled(&self) -> bool {
        self.devices.values().any(|device| {
            ContinuityCapability::GRANTABLE
                .into_iter()
                .any(|capability| device.is_enabled(capability))
        })
    }
}
