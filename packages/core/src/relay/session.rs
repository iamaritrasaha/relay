//! Production session types: proven initiator sessions vs legacy inbound LAN.

use super::id::{ClaimedRelayId, RelayId};
use super::path::{ChannelBinding, PathDescriptor};

/// Local role in an authenticated Relay session.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionRole {
    Initiator,
    Responder,
}

/// A session whose `remote_relay_id` is cryptographically proven from this
/// endpoint's perspective.
///
/// Fields are private. The only constructor is
/// [`super::coordinator::RelayAuthCoordinator`] after a successful proof.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AuthenticatedRelaySession {
    remote_relay_id: RelayId,
    local_relay_id: RelayId,
    local_role: SessionRole,
    mutual: bool,
    tls_binding: ChannelBinding,
    path: PathDescriptor,
}

impl AuthenticatedRelaySession {
    pub(crate) fn from_coordinator(
        remote_relay_id: RelayId,
        local_relay_id: RelayId,
        local_role: SessionRole,
        mutual: bool,
        tls_binding: ChannelBinding,
        path: PathDescriptor,
    ) -> Self {
        Self {
            remote_relay_id,
            local_relay_id,
            local_role,
            mutual,
            tls_binding,
            path,
        }
    }

    pub fn remote_relay_id(&self) -> &RelayId {
        &self.remote_relay_id
    }

    pub fn local_relay_id(&self) -> &RelayId {
        &self.local_relay_id
    }

    pub fn local_role(&self) -> SessionRole {
        self.local_role
    }

    /// Whether the remote also authenticated our Relay identity.
    /// Capability metadata only; it does not decide whether `remote_relay_id`
    /// is proven (the type existing already means it is).
    pub fn mutual(&self) -> bool {
        self.mutual
    }

    pub fn tls_binding(&self) -> ChannelBinding {
        self.tls_binding
    }

    pub fn path(&self) -> &PathDescriptor {
        &self.path
    }
}

/// Existing production LAN inbound session: the remote client's RelayId is
/// **not** proven (no Client-role Relay proof).
///
/// This type is the explicit unsafe/legacy boundary. It must not be passed to
/// authenticated trust policy. Scheduled for deletion in RA3C.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LegacyLanInboundSession {
    claimed_relay_id: Option<ClaimedRelayId>,
    claimed_device_fingerprint: String,
    claimed_alias: String,
    tls_binding: Option<ChannelBinding>,
    path: PathDescriptor,
}

impl LegacyLanInboundSession {
    /// Production LAN prepare-upload / register inbound view.
    ///
    /// Current protocol does not carry a RelayId, so `claimed_relay_id` is
    /// `None`. The JSON `fingerprint` is a claimed device token (historically
    /// a TLS cert fingerprint), not a proven [`RelayId`].
    pub fn from_production_lan(
        claimed_device_fingerprint: impl Into<String>,
        claimed_alias: impl Into<String>,
        observed_cert_fingerprint_hex: Option<&str>,
        path: PathDescriptor,
    ) -> Self {
        Self {
            claimed_relay_id: None,
            claimed_device_fingerprint: claimed_device_fingerprint.into(),
            claimed_alias: claimed_alias.into(),
            tls_binding: observed_cert_fingerprint_hex.and_then(ChannelBinding::from_uppercase_hex),
            path,
        }
    }

    pub fn claimed_relay_id(&self) -> Option<&ClaimedRelayId> {
        self.claimed_relay_id.as_ref()
    }

    pub fn claimed_device_fingerprint(&self) -> &str {
        &self.claimed_device_fingerprint
    }

    pub fn claimed_alias(&self) -> &str {
        &self.claimed_alias
    }

    pub fn tls_binding(&self) -> Option<ChannelBinding> {
        self.tls_binding
    }

    pub fn path(&self) -> &PathDescriptor {
        &self.path
    }

    /// Observed mTLS client-cert fingerprint hex, matching existing events.
    pub fn observed_cert_fingerprint_hex(&self) -> Option<String> {
        self.tls_binding
            .map(|binding| binding.tls_cert_fingerprint_hex())
    }
}

/// A LocalSend-compatible peer. It has no RelayId and cannot enter Relay
/// authenticated trust state.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalSendPeer {
    claimed_device_fingerprint: String,
}

impl LocalSendPeer {
    pub fn from_claimed_device_fingerprint(claimed_device_fingerprint: impl Into<String>) -> Self {
        Self {
            claimed_device_fingerprint: claimed_device_fingerprint.into(),
        }
    }

    pub fn claimed_device_fingerprint(&self) -> &str {
        &self.claimed_device_fingerprint
    }
}
