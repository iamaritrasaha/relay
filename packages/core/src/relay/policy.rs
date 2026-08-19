//! Pure authorization policy for [`AuthenticatedRelaySession`] only.
//!
//! No sockets, TLS, Iroh, or persistent writes.

use super::id::RelayId;
use super::session::AuthenticatedRelaySession;

/// Future explicit device trust record. Persistence is deferred: existing
/// favorites are TLS-certificate-fingerprint + address, not RelayId bindings,
/// and migrating them would change LAN authorization semantics.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DeviceBinding {
    local_binding_id: String,
    relay_id: RelayId,
    label: String,
    trusted: bool,
    blocked: bool,
}

impl DeviceBinding {
    pub fn new(
        local_binding_id: impl Into<String>,
        relay_id: RelayId,
        label: impl Into<String>,
        trusted: bool,
        blocked: bool,
    ) -> Self {
        Self {
            local_binding_id: local_binding_id.into(),
            relay_id,
            label: label.into(),
            trusted,
            blocked,
        }
    }

    pub fn local_binding_id(&self) -> &str {
        &self.local_binding_id
    }

    pub fn relay_id(&self) -> &RelayId {
        &self.relay_id
    }

    pub fn label(&self) -> &str {
        &self.label
    }

    pub fn trusted(&self) -> bool {
        self.trusted
    }

    pub fn blocked(&self) -> bool {
        self.blocked
    }
}

/// Lookup-only trust directory. Implementations must not be written to by
/// transfer acceptance.
pub trait TrustDirectory {
    fn lookup(&self, relay_id: &RelayId) -> TrustRecord;
}

/// Lets a shared or borrowed directory satisfy the `impl TrustDirectory` bounds
/// used by the authorization entry points. Purely a forwarding impl: it adds no
/// way to construct trust.
impl<T: TrustDirectory + ?Sized> TrustDirectory for &T {
    fn lookup(&self, relay_id: &RelayId) -> TrustRecord {
        (**self).lookup(relay_id)
    }
}

impl<T: TrustDirectory + ?Sized> TrustDirectory for std::sync::Arc<T> {
    fn lookup(&self, relay_id: &RelayId) -> TrustRecord {
        (**self).lookup(relay_id)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum TrustRecord {
    Unknown,
    Trusted,
    Blocked,
}

/// In-memory directory for tests and future explicit pairing. Not persisted.
#[derive(Clone, Debug, Default)]
pub struct MemoryTrustDirectory {
    records: Vec<DeviceBinding>,
}

impl MemoryTrustDirectory {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn insert(&mut self, binding: DeviceBinding) {
        self.records.push(binding);
    }

    /// Accepting a transfer must not create persistent (or even in-memory) trust.
    pub fn record_user_accepted_transfer(&mut self, _session: &AuthenticatedRelaySession) {}

    pub fn bindings(&self) -> &[DeviceBinding] {
        &self.records
    }
}

impl TrustDirectory for MemoryTrustDirectory {
    fn lookup(&self, relay_id: &RelayId) -> TrustRecord {
        match self
            .records
            .iter()
            .find(|binding| binding.relay_id() == relay_id)
        {
            Some(binding) if binding.blocked() => TrustRecord::Blocked,
            Some(binding) if binding.trusted() => TrustRecord::Trusted,
            Some(_) | None => TrustRecord::Unknown,
        }
    }
}

/// Request metadata that is never a trust anchor.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct TransferRequestContext {
    /// Attacker-controlled display name. Advisory only.
    pub claimed_display_name: Option<String>,
    /// Analog of existing "quick save from favorites": auto-accept only if
    /// the proven RelayId is already trusted. Unknown peers are never auto-accepted.
    pub auto_accept_trusted: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransferAuthorization {
    Denied,
    PromptRequired,
    AutoAccept,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AuthorizationAdvisory {
    /// An unknown authenticated peer reused a known device's display name.
    DisplayNameCollision { known_label: String },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthorizationDecision {
    pub outcome: TransferAuthorization,
    pub advisory: Option<AuthorizationAdvisory>,
}

/// Authorize a transfer for a **proven** remote RelayId.
///
/// Display names never upgrade authorization. Accepting a transfer is outside
/// this function and must not write trust.
pub fn authorize(
    session: &AuthenticatedRelaySession,
    trust: &impl TrustDirectory,
    request: &TransferRequestContext,
) -> AuthorizationDecision {
    let record = trust.lookup(session.remote_relay_id());
    let outcome = match record {
        TrustRecord::Blocked => TransferAuthorization::Denied,
        TrustRecord::Trusted if request.auto_accept_trusted => TransferAuthorization::AutoAccept,
        TrustRecord::Trusted | TrustRecord::Unknown => TransferAuthorization::PromptRequired,
    };

    AuthorizationDecision {
        outcome,
        advisory: None,
    }
}

impl MemoryTrustDirectory {
    pub fn display_name_collision_with(&self, claimed_display_name: &str) -> Option<String> {
        self.records.iter().find_map(|binding| {
            if binding.trusted() && binding.label() == claimed_display_name {
                Some(binding.label().to_owned())
            } else {
                None
            }
        })
    }
}

/// Completes `authorize` advisory using in-memory labels when available.
pub fn authorize_with_memory_directory(
    session: &AuthenticatedRelaySession,
    trust: &MemoryTrustDirectory,
    request: &TransferRequestContext,
) -> AuthorizationDecision {
    let mut decision = authorize(session, trust, request);
    if matches!(
        trust.lookup(session.remote_relay_id()),
        TrustRecord::Unknown
    ) {
        if let Some(claimed) = request.claimed_display_name.as_deref() {
            if let Some(known_label) = trust.display_name_collision_with(claimed) {
                decision.advisory =
                    Some(AuthorizationAdvisory::DisplayNameCollision { known_label });
            }
        }
    }
    decision
}
