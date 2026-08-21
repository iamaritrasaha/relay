//! Pure Relay transport selection plus its lazy session boundary.
//!
//! This module contains no sockets, Iroh endpoint binding, persistence, trust
//! mutation, or transfer approval. A resolver emits legal descriptions; a
//! session factory lazily turns one description into a fresh connection.

use std::future::Future;
use std::pin::Pin;

use thiserror::Error;

use crate::anywhere::AnywhereError;

use super::device::{AnywhereTransportCandidate, LanTransportCandidate};
use super::{
    AuthenticatedRelaySession, LocalSendPeer, PathDescriptor, RelayDevice, RelayId,
    UnresolvedLanCandidate,
};

/// Product-level transport choices. Direct vs relayed is reported only after
/// an Anywhere connection selects its actual Iroh path.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransportKind {
    Lan,
    Anywhere,
}

/// Actual diagnostic origin of an established session. Never an authorization
/// input and never a resolver candidate.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransportOrigin {
    Local,
    InternetDirect,
    IrohRelay,
}

impl TransportOrigin {
    /// Maps the path selected by an already-open connection. This conversion
    /// is diagnostic only: callers must not use it for authorization.
    pub fn from_path_descriptor(path: &PathDescriptor) -> Self {
        match path {
            PathDescriptor::Lan { .. } => Self::Local,
            PathDescriptor::InternetDirect { .. } => Self::InternetDirect,
            PathDescriptor::Relayed { .. } | PathDescriptor::IrohRelay { .. } => Self::IrohRelay,
        }
    }
}

/// Whether a failure occurred before the expected Relay identity was proven.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ConnectionStage {
    BeforeIdentityVerification,
    AfterIdentityVerification,
}

/// Identity and binding failures that must stop resolution immediately.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum IdentityFailure {
    ExpectedRelayIdMismatch,
    InvalidRelayProof,
    TlsBindingMismatch,
    AuthenticatedIdentitySubstitution,
}

/// Transport-neutral result taxonomy. `detail` is a short sanitized
/// diagnostic supplied by a concrete factory; the typed category is retained.
#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum RelaySendError {
    #[error("transport unavailable: {detail}")]
    TransportUnavailable { detail: String },
    #[error("connection failed at {stage:?}: {detail}")]
    ConnectionFailed {
        stage: ConnectionStage,
        detail: String,
    },
    #[error("Relay identity verification failed: {reason:?}")]
    IdentityVerificationFailed { reason: IdentityFailure },
    #[error("transfer authorization was denied")]
    AuthorizationDenied,
    #[error("transfer failed: {detail}")]
    TransferFailed { detail: String },
    #[error("transfer was cancelled")]
    Cancelled,
    #[error("timed out at {stage:?}")]
    Timeout { stage: ConnectionStage },
}

impl RelaySendError {
    /// Preserves the RA4C0 error category when an Anywhere factory fails
    /// before it has produced an authenticated session. A factory calls this
    /// at its boundary; it must not collapse identity failures into network
    /// retry failures.
    pub fn from_anywhere_before_identity(error: AnywhereError) -> Self {
        match error {
            AnywhereError::Transport { stage, cause } => Self::ConnectionFailed {
                stage: ConnectionStage::BeforeIdentityVerification,
                detail: format!("{}: {cause}", stage.as_str()),
            },
            AnywhereError::Tls { stage, cause } => Self::ConnectionFailed {
                stage: ConnectionStage::BeforeIdentityVerification,
                detail: format!("{}: {cause}", stage.as_str()),
            },
            AnywhereError::RelayProof => Self::IdentityVerificationFailed {
                reason: IdentityFailure::InvalidRelayProof,
            },
            AnywhereError::ExpectedIdentityMismatch { .. } => Self::IdentityVerificationFailed {
                reason: IdentityFailure::ExpectedRelayIdMismatch,
            },
            AnywhereError::AuthorizationDenied => Self::AuthorizationDenied,
            AnywhereError::ProtocolCompletion => Self::TransferFailed {
                detail: "Anywhere completion protocol failed".to_owned(),
            },
            AnywhereError::Cancelled => Self::Cancelled,
            AnywhereError::Timeout { .. } => Self::Timeout {
                stage: ConnectionStage::BeforeIdentityVerification,
            },
        }
    }

    /// Fallback is permitted only for a transport problem before identity
    /// verification. It cannot cross to a weaker requirement.
    fn permits_fallback(&self) -> bool {
        matches!(
            self,
            Self::TransportUnavailable { .. }
                | Self::ConnectionFailed {
                    stage: ConnectionStage::BeforeIdentityVerification,
                    ..
                }
                | Self::Timeout {
                    stage: ConnectionStage::BeforeIdentityVerification
                }
        )
    }
}

/// A route description, without a live socket or mutable connection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum TransportCandidate {
    Lan(LanTransportCandidate),
    Anywhere(AnywhereTransportCandidate),
}

impl TransportCandidate {
    pub fn kind(&self) -> TransportKind {
        match self {
            Self::Lan(_) => TransportKind::Lan,
            Self::Anywhere(_) => TransportKind::Anywhere,
        }
    }

    pub fn lan_host(&self) -> Option<&str> {
        match self {
            Self::Lan(candidate) => Some(&candidate.host),
            Self::Anywhere(_) => None,
        }
    }

    pub fn lan_port(&self) -> Option<u16> {
        match self {
            Self::Lan(candidate) => Some(candidate.port),
            Self::Anywhere(_) => None,
        }
    }
}

/// A logical target deliberately excludes LocalSend compatibility peers.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RelaySendTarget {
    VerifiedDevice(RelayDevice),
    LegacyLan(UnresolvedLanCandidate),
}

impl RelaySendTarget {
    /// LocalSend stays in an explicit compatibility namespace. There is no
    /// conversion from `LocalSendPeer` into this resolver input.
    pub fn requires_explicit_compatibility_action(_: &LocalSendPeer) -> bool {
        true
    }
}

/// Identity strength a connection must satisfy for one logical send.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RelaySecurityRequirement {
    LegacyLanAllowed,
    AuthenticatedRelayDevice(RelayId),
}

/// A candidate selected by the pure policy layer.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransportAttempt {
    pub candidate: TransportCandidate,
    pub requirement: RelaySecurityRequirement,
}

/// Pre-RA3C policy. Verified outbound LAN is legal only if the candidate has
/// previously been associated by an authenticated session, and the factory
/// must still re-prove the expected RelayId when it opens that path.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TransportPolicy {
    pub prefer_local_when_authenticated: bool,
    pub allow_authenticated_lan_initiator: bool,
}

impl Default for TransportPolicy {
    fn default() -> Self {
        Self {
            prefer_local_when_authenticated: true,
            allow_authenticated_lan_initiator: true,
        }
    }
}

/// Pure resolver/policy object.
#[derive(Clone, Copy, Debug, Default)]
pub struct TransportResolver;

impl TransportResolver {
    pub fn resolve(
        &self,
        target: &RelaySendTarget,
        policy: TransportPolicy,
    ) -> Vec<TransportAttempt> {
        match target {
            RelaySendTarget::LegacyLan(candidate) => vec![TransportAttempt {
                candidate: TransportCandidate::Lan(candidate.as_lan_candidate()),
                requirement: RelaySecurityRequirement::LegacyLanAllowed,
            }],
            RelaySendTarget::VerifiedDevice(device) => self.resolve_verified(device, policy),
        }
    }

    fn resolve_verified(
        &self,
        device: &RelayDevice,
        policy: TransportPolicy,
    ) -> Vec<TransportAttempt> {
        let requirement =
            RelaySecurityRequirement::AuthenticatedRelayDevice(device.relay_id().clone());
        let mut local = Vec::new();
        if policy.allow_authenticated_lan_initiator {
            for candidate in device.lan_candidates() {
                if candidate.is_authenticated_for(device.relay_id()) {
                    local.push(TransportAttempt {
                        candidate: TransportCandidate::Lan(candidate.clone()),
                        requirement: requirement.clone(),
                    });
                }
            }
        }
        let anywhere = device
            .anywhere_candidates()
            .iter()
            .filter(|candidate| candidate.expected_relay_id == *device.relay_id())
            .cloned()
            .map(|candidate| TransportAttempt {
                candidate: TransportCandidate::Anywhere(candidate),
                requirement: requirement.clone(),
            });
        if policy.prefer_local_when_authenticated {
            local.into_iter().chain(anywhere).collect()
        } else {
            anywhere.chain(local).collect()
        }
    }
}

/// A fresh opened connection, plus the security result and actual path origin.
/// The opaque `connection` is owned by the concrete LAN or Anywhere adapter.
pub enum EstablishedTransportSession<S> {
    AuthenticatedRelay {
        connection: S,
        session: AuthenticatedRelaySession,
        origin: TransportOrigin,
    },
    LegacyLan {
        connection: S,
        origin: TransportOrigin,
    },
}

impl<S> EstablishedTransportSession<S> {
    pub fn origin(&self) -> TransportOrigin {
        match self {
            Self::AuthenticatedRelay { origin, .. } | Self::LegacyLan { origin, .. } => *origin,
        }
    }

    fn satisfies(&self, requirement: &RelaySecurityRequirement) -> Result<(), RelaySendError> {
        match (requirement, self) {
            (RelaySecurityRequirement::LegacyLanAllowed, _) => Ok(()),
            (
                RelaySecurityRequirement::AuthenticatedRelayDevice(expected),
                Self::AuthenticatedRelay { session, .. },
            ) if session.remote_relay_id() == expected => Ok(()),
            (
                RelaySecurityRequirement::AuthenticatedRelayDevice(_),
                Self::AuthenticatedRelay { .. },
            ) => Err(RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::ExpectedRelayIdMismatch,
            }),
            (RelaySecurityRequirement::AuthenticatedRelayDevice(_), Self::LegacyLan { .. }) => {
                Err(RelaySendError::IdentityVerificationFailed {
                    reason: IdentityFailure::AuthenticatedIdentitySubstitution,
                })
            }
        }
    }
}

pub type SessionFuture<'a, S> = Pin<
    Box<dyn Future<Output = Result<EstablishedTransportSession<S>, RelaySendError>> + Send + 'a>,
>;
pub type TransferFuture<'a> = Pin<Box<dyn Future<Output = Result<(), RelaySendError>> + Send + 'a>>;

/// Opens one attempt lazily. Implementations are the only place that may
/// invoke the existing LAN client path or RA4C0 Anywhere runtime.
pub trait TransportSessionFactory {
    type Connection;

    fn open<'a>(&'a self, attempt: &'a TransportAttempt) -> SessionFuture<'a, Self::Connection>;
}

/// Delegates bytes and receiver approval to the existing transfer code. A
/// different `EstablishedTransportSession` is passed for every fallback, so
/// approval is never reused between connections.
pub trait RelayTransferExecutor<S, Payload> {
    fn send<'a>(
        &'a self,
        session: &'a mut EstablishedTransportSession<S>,
        payload: Payload,
    ) -> TransferFuture<'a>;
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelaySendOutcome {
    pub origin: TransportOrigin,
    pub attempted_transports: Vec<TransportKind>,
}

/// Core callable send boundary. It is UI- and FRB-independent by design.
#[derive(Clone, Copy, Debug, Default)]
pub struct RelaySendService {
    resolver: TransportResolver,
    policy: TransportPolicy,
}

impl RelaySendService {
    pub fn new(policy: TransportPolicy) -> Self {
        Self {
            resolver: TransportResolver,
            policy,
        }
    }

    pub async fn send<S, P, F, E>(
        &self,
        target: &RelaySendTarget,
        payload: P,
        factory: &F,
        executor: &E,
    ) -> Result<RelaySendOutcome, RelaySendError>
    where
        F: TransportSessionFactory<Connection = S>,
        E: RelayTransferExecutor<S, P>,
    {
        let attempts = self.resolver.resolve(target, self.policy);
        if attempts.is_empty() {
            return Err(RelaySendError::TransportUnavailable {
                detail: "no candidate can satisfy the target identity requirement".to_owned(),
            });
        }
        let mut attempted_transports = Vec::with_capacity(attempts.len());
        let mut last_retryable = None;
        let mut payload = Some(payload);
        for attempt in attempts {
            attempted_transports.push(attempt.candidate.kind());
            let mut session = match factory.open(&attempt).await {
                Ok(session) => session,
                Err(error) if error.permits_fallback() => {
                    last_retryable = Some(error);
                    continue;
                }
                Err(error) => return Err(error),
            };
            session.satisfies(&attempt.requirement)?;
            let origin = session.origin();
            // Content is taken only after the connection has satisfied the
            // expected Relay identity. Retryable pre-auth failures can still
            // try an equally secure route; a transfer is never replayed after
            // the canonical executor has begun.
            let payload = payload.take().expect("a transfer payload is consumed once");
            match executor.send(&mut session, payload).await {
                Ok(()) => {
                    return Ok(RelaySendOutcome {
                        origin,
                        attempted_transports,
                    });
                }
                Err(error) => return Err(error),
            }
        }
        Err(
            last_retryable.unwrap_or(RelaySendError::TransportUnavailable {
                detail: "no transport attempt could be opened".to_owned(),
            }),
        )
    }
}

#[cfg(test)]
mod tests {
    use std::collections::VecDeque;
    use std::sync::Mutex;

    use crate::anywhere::{iroh_endpoint_bind_count, RelayAddressV1, TlsStage, TransportStage};
    use crate::crypto::relay_identity::RelayIdentity;
    use crate::model::discovery::ProtocolType;
    use crate::relay::{
        authorize, MemoryTrustDirectory, PathDescriptor, RelayAuthCoordinator,
        RelayDeviceDirectory, RelayDeviceMetadata, TransferAuthorization, TransferRequestContext,
    };
    use iroh::{SecretKey, TransportAddr};

    use super::*;

    fn relay_id() -> RelayId {
        RelayId::from_local_identity(&RelayIdentity::generate()).unwrap()
    }
    fn freshness() -> super::super::device::CandidateFreshness {
        super::super::device::CandidateFreshness::observed_now()
    }
    fn test_tls_fingerprint() -> String {
        "03".repeat(32)
    }
    fn lan_with_fingerprint(name: &str, fingerprint: String) -> UnresolvedLanCandidate {
        UnresolvedLanCandidate::new(
            name,
            "192.0.2.8",
            53317,
            ProtocolType::Https,
            fingerprint,
            "2.2",
            None,
            None,
            false,
            freshness(),
        )
    }
    fn lan(name: &str) -> UnresolvedLanCandidate {
        lan_with_fingerprint(name, test_tls_fingerprint())
    }
    fn address(id: &RelayId) -> RelayAddressV1 {
        RelayAddressV1::new(
            id.as_hex(),
            iroh::EndpointAddr::from_parts(
                SecretKey::generate().public(),
                [TransportAddr::Ip("127.0.0.1:4242".parse().unwrap())],
            ),
        )
        .unwrap()
    }
    fn device_with_anywhere(id: RelayId) -> RelayDevice {
        let mut device = RelayDevice::new(id, RelayDeviceMetadata::default());
        device
            .add_anywhere_candidate(address(device.relay_id()), freshness())
            .unwrap();
        device
    }
    fn session_for_remote(
        remote_identity: RelayIdentity,
        origin: TransportOrigin,
    ) -> (RelayId, EstablishedTransportSession<usize>) {
        let local = RelayIdentity::generate();
        let coordinator = RelayAuthCoordinator::new(RelayId::from_local_identity(&local).unwrap());
        let remote = RelayId::from_local_identity(&remote_identity).unwrap();
        let session = coordinator
            .complete_lan_initiator(
                &crate::crypto::relay_identity_proof::create_relay_identity_proof(
                    &remote_identity,
                    crate::crypto::relay_identity_proof::RelayProofRole::Server,
                    [7; 32],
                    [3; 32],
                )
                .unwrap(),
                [3; 32],
                Some(&remote),
                PathDescriptor::lan("192.0.2.8", Some(53317)),
            )
            .unwrap();
        (
            remote,
            EstablishedTransportSession::AuthenticatedRelay {
                connection: 1,
                session,
                origin,
            },
        )
    }

    struct Factory {
        results: Mutex<VecDeque<Result<EstablishedTransportSession<usize>, RelaySendError>>>,
        opens: Mutex<Vec<TransportKind>>,
    }
    impl TransportSessionFactory for Factory {
        type Connection = usize;
        fn open<'a>(&'a self, attempt: &'a TransportAttempt) -> SessionFuture<'a, usize> {
            self.opens.lock().unwrap().push(attempt.candidate.kind());
            let result = self.results.lock().unwrap().pop_front().unwrap();
            Box::pin(async move { result })
        }
    }
    struct Executor {
        calls: Mutex<Vec<TransportOrigin>>,
        result: Mutex<Result<(), RelaySendError>>,
    }
    impl RelayTransferExecutor<usize, ()> for Executor {
        fn send<'a>(
            &'a self,
            session: &'a mut EstablishedTransportSession<usize>,
            _: (),
        ) -> TransferFuture<'a> {
            self.calls.lock().unwrap().push(session.origin());
            let result = self.result.lock().unwrap().clone();
            Box::pin(async move { result })
        }
    }
    fn service() -> RelaySendService {
        RelaySendService::new(TransportPolicy::default())
    }
    fn executor() -> Executor {
        Executor {
            calls: Mutex::new(Vec::new()),
            result: Mutex::new(Ok(())),
        }
    }

    #[test]
    fn lan_only_resolution_does_not_initialize_iroh() {
        let before = iroh_endpoint_bind_count();
        let attempts = TransportResolver.resolve(
            &RelaySendTarget::LegacyLan(lan("nearby")),
            TransportPolicy::default(),
        );
        assert_eq!(attempts.len(), 1);
        assert_eq!(attempts[0].candidate.kind(), TransportKind::Lan);
        assert_eq!(iroh_endpoint_bind_count(), before);
    }

    #[test]
    fn anywhere_only_verified_device_resolves_to_anywhere() {
        let device = device_with_anywhere(relay_id());
        let attempts = TransportResolver.resolve(
            &RelaySendTarget::VerifiedDevice(device),
            TransportPolicy::default(),
        );
        assert_eq!(
            attempts
                .iter()
                .map(|attempt| attempt.candidate.kind())
                .collect::<Vec<_>>(),
            vec![TransportKind::Anywhere]
        );
    }

    #[test]
    fn verified_device_does_not_downgrade_to_unassociated_lan() {
        let id = relay_id();
        let mut device = device_with_anywhere(id);
        let unassociated = lan("nearby");
        assert!(device
            .add_authenticated_lan_candidate(unassociated)
            .is_err());
        let attempts = TransportResolver.resolve(
            &RelaySendTarget::VerifiedDevice(device),
            TransportPolicy::default(),
        );
        assert_eq!(attempts[0].candidate.kind(), TransportKind::Anywhere);
    }

    #[test]
    fn directory_merges_only_same_verified_relay_id() {
        let id = relay_id();
        let mut directory = RelayDeviceDirectory::default();
        directory.insert_verified(RelayDevice::new(
            id.clone(),
            RelayDeviceMetadata {
                display_label: Some("same".into()),
                ..Default::default()
            },
        ));
        directory.insert_verified(RelayDevice::new(id, RelayDeviceMetadata::default()));
        directory.insert_verified(RelayDevice::new(
            relay_id(),
            RelayDeviceMetadata {
                display_label: Some("same".into()),
                ..Default::default()
            },
        ));
        assert_eq!(directory.devices().len(), 2);
    }

    #[test]
    fn unresolved_lan_candidate_is_not_a_relay_device() {
        let candidate = lan("nearby");
        assert!(candidate.associated_relay_id().is_none());
        assert!(candidate.claimed_relay_id().is_none());
    }

    #[test]
    fn discovery_conversion_keeps_only_actual_v2_identity_data() {
        let discovered = crate::discovery::DiscoveredDevice {
            alias: "nearby".into(),
            version: "2.2".into(),
            device_model: Some("phone".into()),
            device_type: None,
            fingerprint: "F".repeat(64),
            channel: crate::discovery::DeviceChannel::Http(crate::discovery::HttpChannel {
                host: "192.0.2.9".into(),
                port: 53317,
                protocol: ProtocolType::Https,
            }),
            download: true,
        };
        let candidate =
            UnresolvedLanCandidate::from_discovered_device(&discovered, freshness()).unwrap();
        assert_eq!(candidate.alias(), "nearby");
        assert_eq!(candidate.host(), "192.0.2.9");
        assert_eq!(candidate.port(), 53317);
        assert_eq!(candidate.tls_fingerprint(), "F".repeat(64));
        assert!(candidate.associated_relay_id().is_none());
        assert!(candidate.claimed_relay_id().is_none());
    }

    #[test]
    fn localsend_is_never_a_relay_resolver_target() {
        let peer = LocalSendPeer::from_claimed_device_fingerprint("local-send");
        assert!(RelaySendTarget::requires_explicit_compatibility_action(
            &peer
        ));
    }

    #[test]
    fn path_origin_is_not_an_authorization_input() {
        let id = relay_id();
        let requirement = RelaySecurityRequirement::AuthenticatedRelayDevice(id.clone());
        assert_ne!(TransportOrigin::InternetDirect, TransportOrigin::IrohRelay);
        assert_eq!(
            requirement,
            RelaySecurityRequirement::AuthenticatedRelayDevice(id)
        );
        assert_eq!(
            TransportOrigin::from_path_descriptor(&PathDescriptor::InternetDirect {
                host: String::new(),
                port: None
            }),
            TransportOrigin::InternetDirect
        );
        assert_eq!(
            TransportOrigin::from_path_descriptor(&PathDescriptor::IrohRelay { hint: None }),
            TransportOrigin::IrohRelay
        );
    }

    #[test]
    fn resolver_never_mutates_trust_metadata() {
        let id = relay_id();
        let device = device_with_anywhere(id);
        assert_eq!(device.metadata().trust, crate::relay::TrustRecord::Unknown);
        let _ = TransportResolver.resolve(
            &RelaySendTarget::VerifiedDevice(device.clone()),
            TransportPolicy::default(),
        );
        assert_eq!(device.metadata().trust, crate::relay::TrustRecord::Unknown);
    }

    #[test]
    fn relay_device_trust_snapshot_cannot_bypass_production_authorization() {
        let remote_identity = RelayIdentity::generate();
        let (remote_id, established) =
            session_for_remote(remote_identity, TransportOrigin::InternetDirect);
        let device = RelayDevice::new(
            remote_id,
            RelayDeviceMetadata {
                trust: crate::relay::TrustRecord::Trusted,
                ..Default::default()
            },
        );
        let EstablishedTransportSession::AuthenticatedRelay { session, .. } = established else {
            unreachable!();
        };

        assert_eq!(device.metadata().trust, crate::relay::TrustRecord::Trusted);
        assert_eq!(
            authorize(
                &session,
                &MemoryTrustDirectory::new(),
                &TransferRequestContext {
                    auto_accept_trusted: true,
                    ..Default::default()
                },
            )
            .outcome,
            TransferAuthorization::PromptRequired
        );
    }

    #[test]
    fn authenticated_lan_association_is_bound_to_exact_https_route_and_certificate() {
        let remote_identity = RelayIdentity::generate();
        let (id, established) = session_for_remote(remote_identity, TransportOrigin::Local);
        let EstablishedTransportSession::AuthenticatedRelay { session, .. } = established else {
            unreachable!();
        };
        let mut candidate = lan("nearby");
        candidate
            .associate_after_authenticated_session(&session)
            .unwrap();

        let mut device = device_with_anywhere(id);
        device.add_authenticated_lan_candidate(candidate).unwrap();
        assert_eq!(
            TransportResolver
                .resolve(
                    &RelaySendTarget::VerifiedDevice(device),
                    TransportPolicy::default(),
                )
                .first()
                .unwrap()
                .candidate
                .kind(),
            TransportKind::Lan
        );
    }

    #[test]
    fn changed_certificate_invalidates_same_alias_ip_and_port_association() {
        let remote_identity = RelayIdentity::generate();
        let (id, established) = session_for_remote(remote_identity, TransportOrigin::Local);
        let EstablishedTransportSession::AuthenticatedRelay { session, .. } = established else {
            unreachable!();
        };
        let mut authenticated = lan("nearby");
        authenticated
            .associate_after_authenticated_session(&session)
            .unwrap();
        let mut device = device_with_anywhere(id);
        device
            .add_authenticated_lan_candidate(authenticated)
            .unwrap();

        let replacement = lan_with_fingerprint("nearby", "04".repeat(32));
        assert!(replacement.associated_relay_id().is_none());
        assert_eq!(
            device.add_authenticated_lan_candidate(replacement),
            Err(crate::relay::DeviceCandidateError::AddressIdentityMismatch)
        );
        assert_eq!(
            TransportResolver
                .resolve(
                    &RelaySendTarget::VerifiedDevice(device),
                    TransportPolicy::default(),
                )
                .iter()
                .map(|attempt| attempt.candidate.kind())
                .collect::<Vec<_>>(),
            vec![TransportKind::Lan, TransportKind::Anywhere]
        );
    }

    #[test]
    fn same_display_name_on_a_different_route_never_merges_identity() {
        let mut directory = RelayDeviceDirectory::default();
        directory.insert_verified(RelayDevice::new(
            relay_id(),
            RelayDeviceMetadata {
                display_label: Some("nearby".into()),
                ..Default::default()
            },
        ));
        directory.insert_verified(RelayDevice::new(
            relay_id(),
            RelayDeviceMetadata {
                display_label: Some("nearby".into()),
                ..Default::default()
            },
        ));
        assert_eq!(directory.devices().len(), 2);
    }

    #[test]
    fn transport_error_policy_is_explicit() {
        assert!(RelaySendError::ConnectionFailed {
            stage: ConnectionStage::BeforeIdentityVerification,
            detail: "refused".into()
        }
        .permits_fallback());
        assert!(RelaySendError::Timeout {
            stage: ConnectionStage::BeforeIdentityVerification
        }
        .permits_fallback());
        assert!(!RelaySendError::ConnectionFailed {
            stage: ConnectionStage::AfterIdentityVerification,
            detail: "reset".into()
        }
        .permits_fallback());
        assert!(!RelaySendError::Cancelled.permits_fallback());
        assert!(!RelaySendError::IdentityVerificationFailed {
            reason: IdentityFailure::InvalidRelayProof
        }
        .permits_fallback());
    }

    #[test]
    fn ra4c0_anywhere_errors_keep_retry_and_identity_meaning() {
        assert!(
            RelaySendError::from_anywhere_before_identity(AnywhereError::transport(
                TransportStage::Connect,
                "refused",
            ))
            .permits_fallback()
        );
        assert!(matches!(
            RelaySendError::from_anywhere_before_identity(AnywhereError::tls(
                TlsStage::ClientHandshake,
                "unavailable",
            )),
            RelaySendError::ConnectionFailed {
                stage: ConnectionStage::BeforeIdentityVerification,
                ..
            }
        ));
        assert_eq!(
            RelaySendError::from_anywhere_before_identity(AnywhereError::RelayProof),
            RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::InvalidRelayProof
            }
        );
    }

    #[tokio::test]
    async fn lan_transport_failure_before_auth_falls_back_to_anywhere() {
        let remote_identity = RelayIdentity::generate();
        let (id, session) = session_for_remote(remote_identity, TransportOrigin::InternetDirect);
        let mut device = device_with_anywhere(id);
        let mut associated = lan("nearby");
        if let EstablishedTransportSession::AuthenticatedRelay { session, .. } = &session {
            associated
                .associate_after_authenticated_session(session)
                .unwrap();
        }
        device.add_authenticated_lan_candidate(associated).unwrap();
        let factory = Factory {
            results: Mutex::new(VecDeque::from([
                Err(RelaySendError::ConnectionFailed {
                    stage: ConnectionStage::BeforeIdentityVerification,
                    detail: "refused".into(),
                }),
                Ok(session),
            ])),
            opens: Mutex::new(Vec::new()),
        };
        let executor = executor();
        let outcome = service()
            .send(
                &RelaySendTarget::VerifiedDevice(device),
                (),
                &factory,
                &executor,
            )
            .await
            .unwrap();
        assert_eq!(outcome.origin, TransportOrigin::InternetDirect);
        assert_eq!(
            *factory.opens.lock().unwrap(),
            vec![TransportKind::Lan, TransportKind::Anywhere]
        );
        assert_eq!(
            *executor.calls.lock().unwrap(),
            vec![TransportOrigin::InternetDirect]
        );
    }

    #[tokio::test]
    async fn anywhere_transport_failure_before_identity_tries_an_equally_secure_candidate() {
        let remote_identity = RelayIdentity::generate();
        let (id, session) = session_for_remote(remote_identity, TransportOrigin::IrohRelay);
        let mut device = device_with_anywhere(id);
        device
            .add_anywhere_candidate(address(device.relay_id()), freshness())
            .unwrap();
        let factory = Factory {
            results: Mutex::new(VecDeque::from([
                Err(RelaySendError::Timeout {
                    stage: ConnectionStage::BeforeIdentityVerification,
                }),
                Ok(session),
            ])),
            opens: Mutex::new(Vec::new()),
        };
        let executor = executor();
        let outcome = service()
            .send(
                &RelaySendTarget::VerifiedDevice(device),
                (),
                &factory,
                &executor,
            )
            .await
            .unwrap();
        assert_eq!(
            outcome.attempted_transports,
            vec![TransportKind::Anywhere, TransportKind::Anywhere]
        );
        assert_eq!(outcome.origin, TransportOrigin::IrohRelay);
    }

    #[tokio::test]
    async fn expected_relay_id_mismatch_is_terminal_and_never_downgrades() {
        let expected = relay_id();
        let mut device = device_with_anywhere(expected);
        device
            .add_anywhere_candidate(address(device.relay_id()), freshness())
            .unwrap();
        let (_, wrong_session) =
            session_for_remote(RelayIdentity::generate(), TransportOrigin::InternetDirect);
        let factory = Factory {
            results: Mutex::new(VecDeque::from([Ok(wrong_session)])),
            opens: Mutex::new(Vec::new()),
        };
        let executor = executor();
        let error = service()
            .send(
                &RelaySendTarget::VerifiedDevice(device),
                (),
                &factory,
                &executor,
            )
            .await
            .unwrap_err();
        assert_eq!(
            error,
            RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::ExpectedRelayIdMismatch
            }
        );
        assert_eq!(factory.opens.lock().unwrap().len(), 1);
        assert!(executor.calls.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn invalid_proof_and_cancellation_are_terminal() {
        for error in [
            RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::InvalidRelayProof,
            },
            RelaySendError::Cancelled,
        ] {
            let id = relay_id();
            let mut device = device_with_anywhere(id);
            device
                .add_anywhere_candidate(address(device.relay_id()), freshness())
                .unwrap();
            let factory = Factory {
                results: Mutex::new(VecDeque::from([Err(error.clone())])),
                opens: Mutex::new(Vec::new()),
            };
            let executor = executor();
            assert_eq!(
                service()
                    .send(
                        &RelaySendTarget::VerifiedDevice(device),
                        (),
                        &factory,
                        &executor
                    )
                    .await
                    .unwrap_err(),
                error
            );
            assert_eq!(factory.opens.lock().unwrap().len(), 1);
            assert!(executor.calls.lock().unwrap().is_empty());
        }
    }

    #[tokio::test]
    async fn verified_target_rejects_legacy_session_without_any_fallback() {
        let id = relay_id();
        let mut device = device_with_anywhere(id);
        device
            .add_anywhere_candidate(address(device.relay_id()), freshness())
            .unwrap();
        let factory = Factory {
            results: Mutex::new(VecDeque::from([Ok(
                EstablishedTransportSession::LegacyLan {
                    connection: 1,
                    origin: TransportOrigin::Local,
                },
            )])),
            opens: Mutex::new(Vec::new()),
        };
        let executor = executor();
        let error = service()
            .send(
                &RelaySendTarget::VerifiedDevice(device),
                (),
                &factory,
                &executor,
            )
            .await
            .unwrap_err();
        assert_eq!(
            error,
            RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::AuthenticatedIdentitySubstitution
            }
        );
        assert_eq!(factory.opens.lock().unwrap().len(), 1);
        assert!(executor.calls.lock().unwrap().is_empty());
    }

    #[test]
    fn direct_and_relayed_anywhere_have_the_same_identity_requirement() {
        let remote = RelayIdentity::generate();
        let (id, direct) = session_for_remote(remote, TransportOrigin::InternetDirect);
        let relay = match direct {
            EstablishedTransportSession::AuthenticatedRelay {
                connection,
                session,
                ..
            } => EstablishedTransportSession::AuthenticatedRelay {
                connection,
                session,
                origin: TransportOrigin::IrohRelay,
            },
            EstablishedTransportSession::LegacyLan { .. } => unreachable!(),
        };
        let requirement = RelaySecurityRequirement::AuthenticatedRelayDevice(id);
        assert!(relay.satisfies(&requirement).is_ok());
    }
}
