//! Relay device records and unresolved LAN observations.
//!
//! Discovery data is routing metadata, not identity evidence. In particular,
//! the current LocalSend v2 multicast/register exchange contains no RelayId.
//! A LAN observation therefore remains unresolved until an authenticated
//! session proves its RelayId.

use std::time::SystemTime;

use crate::anywhere::RelayAddressV1;
#[cfg(feature = "discovery")]
use crate::discovery::DiscoveredDevice;
use crate::model::discovery::{DeviceType, ProtocolType};

use super::{
    AuthenticatedRelaySession, ChannelBinding, ClaimedRelayId, PathDescriptor, RelayId, TrustRecord,
};

/// When routing metadata was last observed. It is intentionally advisory.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CandidateFreshness {
    observed_at: SystemTime,
}

impl CandidateFreshness {
    pub fn observed_now() -> Self {
        Self {
            observed_at: SystemTime::now(),
        }
    }

    pub fn observed_at(self) -> SystemTime {
        self.observed_at
    }
}

/// A LocalSend v2 LAN observation that has not established a Relay identity.
///
/// `tls_fingerprint` is the certificate fingerprint observed during HTTPS
/// discovery (or the legacy claimed token for HTTP). It is not a RelayId.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UnresolvedLanCandidate {
    alias: String,
    host: String,
    port: u16,
    protocol: ProtocolType,
    tls_fingerprint: String,
    version: String,
    device_model: Option<String>,
    device_type: Option<DeviceType>,
    download_available: bool,
    freshness: CandidateFreshness,
    claimed_relay_id: Option<ClaimedRelayId>,
    associated_relay_id: Option<RelayId>,
    associated_route: Option<LanRouteIdentity>,
}

impl UnresolvedLanCandidate {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        alias: impl Into<String>,
        host: impl Into<String>,
        port: u16,
        protocol: ProtocolType,
        tls_fingerprint: impl Into<String>,
        version: impl Into<String>,
        device_model: Option<String>,
        device_type: Option<DeviceType>,
        download_available: bool,
        freshness: CandidateFreshness,
    ) -> Self {
        Self {
            alias: alias.into(),
            host: host.into(),
            port,
            protocol,
            tls_fingerprint: tls_fingerprint.into(),
            version: version.into(),
            device_model,
            device_type,
            download_available,
            freshness,
            // Current production LAN discovery has no RelayId field.
            claimed_relay_id: None,
            associated_relay_id: None,
            associated_route: None,
        }
    }

    /// Converts a current LocalSend v2 discovery result without adding fields
    /// that discovery did not provide. The result has no RelayId claim.
    #[cfg(feature = "discovery")]
    pub fn from_discovered_device(
        device: &DiscoveredDevice,
        freshness: CandidateFreshness,
    ) -> Option<Self> {
        let channel = device.http()?;
        Some(Self::new(
            device.alias.clone(),
            channel.host.clone(),
            channel.port,
            channel.protocol,
            device.fingerprint.clone(),
            device.version.clone(),
            device.device_model.clone(),
            device.device_type.clone(),
            device.download,
            freshness,
        ))
    }

    pub fn alias(&self) -> &str {
        &self.alias
    }
    pub fn host(&self) -> &str {
        &self.host
    }
    pub fn port(&self) -> u16 {
        self.port
    }
    pub fn protocol(&self) -> ProtocolType {
        self.protocol
    }
    pub fn tls_fingerprint(&self) -> &str {
        &self.tls_fingerprint
    }
    pub fn version(&self) -> &str {
        &self.version
    }
    pub fn device_model(&self) -> Option<&str> {
        self.device_model.as_deref()
    }
    pub fn device_type(&self) -> Option<&DeviceType> {
        self.device_type.as_ref()
    }
    pub fn download_available(&self) -> bool {
        self.download_available
    }
    pub fn freshness(&self) -> CandidateFreshness {
        self.freshness
    }
    pub fn claimed_relay_id(&self) -> Option<&ClaimedRelayId> {
        self.claimed_relay_id.as_ref()
    }
    pub fn associated_relay_id(&self) -> Option<&RelayId> {
        self.associated_relay_id.as_ref()
    }

    /// Associates this HTTPS observation only using a session that has already
    /// cryptographically proven the remote RelayId on this exact route.
    ///
    /// The route includes host, port, and the discovery certificate fingerprint.
    /// This is routing metadata; it does not create trust.
    pub fn associate_after_authenticated_session(
        &mut self,
        session: &AuthenticatedRelaySession,
    ) -> Result<(), DeviceCandidateError> {
        let route = self.route_identity()?;
        match session.path() {
            PathDescriptor::Lan { host, port }
                if host == route.host() && *port == Some(route.port()) => {}
            _ => return Err(DeviceCandidateError::SessionRouteMismatch),
        }
        if session.tls_binding() != route.tls_binding() {
            return Err(DeviceCandidateError::TlsFingerprintMismatch);
        }
        self.associated_relay_id = Some(session.remote_relay_id().clone());
        self.associated_route = Some(route);
        Ok(())
    }

    fn route_identity(&self) -> Result<LanRouteIdentity, DeviceCandidateError> {
        if self.protocol != ProtocolType::Https {
            return Err(DeviceCandidateError::UnsupportedLanProtocol);
        }
        let Some(tls_binding) = ChannelBinding::from_uppercase_hex(&self.tls_fingerprint) else {
            return Err(DeviceCandidateError::InvalidTlsFingerprint);
        };
        Ok(LanRouteIdentity {
            host: self.host.clone(),
            port: self.port,
            tls_binding,
        })
    }

    fn is_authenticated_for(&self, relay_id: &RelayId) -> bool {
        self.associated_relay_id.as_ref() == Some(relay_id)
            && self.associated_route.as_ref() == self.route_identity().ok().as_ref()
    }

    pub(crate) fn as_lan_candidate(&self) -> LanTransportCandidate {
        LanTransportCandidate {
            host: self.host.clone(),
            port: self.port,
            protocol: self.protocol,
            tls_fingerprint: self.tls_fingerprint.clone(),
            freshness: self.freshness,
            associated_relay_id: self.associated_relay_id.clone(),
            associated_route: self.associated_route.clone(),
        }
    }
}

/// Identity of one observed HTTPS LAN route. It is deliberately more specific
/// than a display name or socket address: a certificate change is a new route.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LanRouteIdentity {
    host: String,
    port: u16,
    tls_binding: ChannelBinding,
}

impl LanRouteIdentity {
    pub fn host(&self) -> &str {
        &self.host
    }
    pub fn port(&self) -> u16 {
        self.port
    }
    pub fn tls_binding(&self) -> ChannelBinding {
        self.tls_binding
    }
}

/// One LAN route. It can locate a device but never establishes trust.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LanTransportCandidate {
    pub(crate) host: String,
    pub(crate) port: u16,
    pub(crate) protocol: ProtocolType,
    pub(crate) tls_fingerprint: String,
    pub(crate) freshness: CandidateFreshness,
    pub(crate) associated_relay_id: Option<RelayId>,
    pub(crate) associated_route: Option<LanRouteIdentity>,
}

impl LanTransportCandidate {
    pub fn host(&self) -> &str {
        &self.host
    }
    pub fn port(&self) -> u16 {
        self.port
    }
    pub fn protocol(&self) -> ProtocolType {
        self.protocol
    }
    pub fn tls_fingerprint(&self) -> &str {
        &self.tls_fingerprint
    }
    pub fn freshness(&self) -> CandidateFreshness {
        self.freshness
    }
    pub fn associated_relay_id(&self) -> Option<&RelayId> {
        self.associated_relay_id.as_ref()
    }
    pub fn associated_route(&self) -> Option<&LanRouteIdentity> {
        self.associated_route.as_ref()
    }

    pub(crate) fn is_authenticated_for(&self, relay_id: &RelayId) -> bool {
        self.associated_relay_id.as_ref() == Some(relay_id)
            && self.associated_route.as_ref()
                == Some(&LanRouteIdentity {
                    host: self.host.clone(),
                    port: self.port,
                    tls_binding: match ChannelBinding::from_uppercase_hex(&self.tls_fingerprint) {
                        Some(binding) => binding,
                        None => return false,
                    },
                })
    }
}

/// An Anywhere route paired with the RelayId it must prove.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AnywhereTransportCandidate {
    pub(crate) address: RelayAddressV1,
    pub(crate) expected_relay_id: RelayId,
    pub(crate) freshness: CandidateFreshness,
}

impl AnywhereTransportCandidate {
    pub fn address(&self) -> &RelayAddressV1 {
        &self.address
    }
    pub fn expected_relay_id(&self) -> &RelayId {
        &self.expected_relay_id
    }
    pub fn freshness(&self) -> CandidateFreshness {
        self.freshness
    }
}

/// Non-security display metadata for a verified Relay device.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayDeviceMetadata {
    pub display_label: Option<String>,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub trust: TrustRecord,
}

impl Default for RelayDeviceMetadata {
    fn default() -> Self {
        Self {
            display_label: None,
            device_model: None,
            device_type: None,
            trust: TrustRecord::Unknown,
        }
    }
}

/// A verified Relay identity and its known transport descriptions.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelayDevice {
    relay_id: RelayId,
    metadata: RelayDeviceMetadata,
    lan_candidates: Vec<LanTransportCandidate>,
    anywhere_candidates: Vec<AnywhereTransportCandidate>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DeviceCandidateError {
    AddressIdentityMismatch,
    SessionRouteMismatch,
    TlsFingerprintMismatch,
    InvalidTlsFingerprint,
    UnsupportedLanProtocol,
}

impl RelayDevice {
    pub fn new(relay_id: RelayId, metadata: RelayDeviceMetadata) -> Self {
        Self {
            relay_id,
            metadata,
            lan_candidates: Vec::new(),
            anywhere_candidates: Vec::new(),
        }
    }

    pub fn relay_id(&self) -> &RelayId {
        &self.relay_id
    }
    pub fn metadata(&self) -> &RelayDeviceMetadata {
        &self.metadata
    }

    /// Adds a LAN route already associated by an authenticated outbound
    /// session. The association is not trust and is re-verified on use.
    pub fn add_authenticated_lan_candidate(
        &mut self,
        candidate: UnresolvedLanCandidate,
    ) -> Result<(), DeviceCandidateError> {
        if !candidate.is_authenticated_for(&self.relay_id) {
            return Err(DeviceCandidateError::AddressIdentityMismatch);
        }
        self.lan_candidates.push(candidate.as_lan_candidate());
        Ok(())
    }

    /// Adds routing from a Relay address only when its expected identity is
    /// this verified device. Address routing is still not trust evidence.
    pub fn add_anywhere_candidate(
        &mut self,
        address: RelayAddressV1,
        freshness: CandidateFreshness,
    ) -> Result<(), DeviceCandidateError> {
        if address.claimed_relay_id != self.relay_id.as_hex() {
            return Err(DeviceCandidateError::AddressIdentityMismatch);
        }
        self.anywhere_candidates.push(AnywhereTransportCandidate {
            address,
            expected_relay_id: self.relay_id.clone(),
            freshness,
        });
        Ok(())
    }

    pub(crate) fn lan_candidates(&self) -> &[LanTransportCandidate] {
        &self.lan_candidates
    }
    pub(crate) fn anywhere_candidates(&self) -> &[AnywhereTransportCandidate] {
        &self.anywhere_candidates
    }

    fn merge_from(&mut self, mut other: RelayDevice) {
        debug_assert_eq!(self.relay_id, other.relay_id);
        if self.metadata.display_label.is_none() {
            self.metadata.display_label = other.metadata.display_label.take();
        }
        if self.metadata.device_model.is_none() {
            self.metadata.device_model = other.metadata.device_model.take();
        }
        if self.metadata.device_type.is_none() {
            self.metadata.device_type = other.metadata.device_type.take();
        }
        if self.metadata.trust == TrustRecord::Unknown {
            self.metadata.trust = other.metadata.trust;
        }
        self.lan_candidates.append(&mut other.lan_candidates);
        self.anywhere_candidates
            .append(&mut other.anywhere_candidates);
    }
}

/// In-memory grouping of verified records. It is deliberately keyed only by
/// RelayId: names, addresses, fingerprints, and endpoint IDs cannot merge
/// identities.
#[derive(Clone, Debug, Default)]
pub struct RelayDeviceDirectory {
    devices: Vec<RelayDevice>,
}

impl RelayDeviceDirectory {
    pub fn insert_verified(&mut self, device: RelayDevice) {
        match self
            .devices
            .iter_mut()
            .find(|known| known.relay_id == device.relay_id)
        {
            Some(known) => known.merge_from(device),
            None => self.devices.push(device),
        }
    }

    pub fn devices(&self) -> &[RelayDevice] {
        &self.devices
    }
}
