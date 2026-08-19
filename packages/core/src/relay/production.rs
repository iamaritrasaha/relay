//! Concrete production LAN session factory.
//!
//! The factory creates a new HTTPS client pinned to the discovered certificate
//! fingerprint *before* asking for the Relay proof. The same client is kept in
//! the returned connection context, so every later v2 request remains pinned
//! to the certificate that the proof authenticated.

use crate::http::client::{LsHttpClient, LsHttpClientVersion};
use crate::model::discovery::ProtocolType;

use super::{
    ChannelBinding, ConnectionStage, EstablishedTransportSession, IdentityFailure,
    RelayAuthCoordinator, RelayId, RelaySecurityRequirement, RelaySendError, TransportAttempt,
    TransportCandidate, TransportOrigin, TransportSessionFactory,
};
use super::{PathDescriptor, RelayPeerAuth};

/// Connection context retained by the caller's existing v2 transfer executor.
/// It owns the certificate-pinned HTTP client used for both proof and transfer.
pub struct ProductionLanConnection {
    client: LsHttpClient,
    host: String,
    port: u16,
    protocol: ProtocolType,
    certificate_fingerprint: String,
}

impl ProductionLanConnection {
    pub fn client(&self) -> &LsHttpClient {
        &self.client
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

    pub fn certificate_fingerprint(&self) -> &str {
        &self.certificate_fingerprint
    }
}

/// Concrete factory for the existing LAN v2 client path.
///
/// It intentionally does not authorize a transfer and never writes trust.
pub struct LanRelaySessionFactory {
    local_relay_id: RelayId,
    client_private_key_pem: String,
    client_certificate_pem: String,
    version: LsHttpClientVersion,
}

impl LanRelaySessionFactory {
    pub fn new(
        local_relay_id: RelayId,
        client_private_key_pem: impl Into<String>,
        client_certificate_pem: impl Into<String>,
        version: LsHttpClientVersion,
    ) -> Self {
        Self {
            local_relay_id,
            client_private_key_pem: client_private_key_pem.into(),
            client_certificate_pem: client_certificate_pem.into(),
            version,
        }
    }

    fn pinned_client(&self, fingerprint: &str) -> Result<LsHttpClient, RelaySendError> {
        LsHttpClient::new(
            &self.client_private_key_pem,
            &self.client_certificate_pem,
            self.version,
            Some(fingerprint.to_owned()),
            None,
        )
        .map_err(|error| RelaySendError::ConnectionFailed {
            stage: ConnectionStage::BeforeIdentityVerification,
            detail: format!("could not create pinned LAN client: {error}"),
        })
    }

    async fn open_attempt(
        &self,
        attempt: &TransportAttempt,
    ) -> Result<EstablishedTransportSession<ProductionLanConnection>, RelaySendError> {
        let TransportCandidate::Lan(candidate) = &attempt.candidate else {
            return Err(RelaySendError::TransportUnavailable {
                detail: "LAN factory received a non-LAN candidate".to_owned(),
            });
        };
        let client = self.pinned_client(candidate.tls_fingerprint())?;
        let connection = ProductionLanConnection {
            client,
            host: candidate.host().to_owned(),
            port: candidate.port(),
            protocol: candidate.protocol(),
            certificate_fingerprint: candidate.tls_fingerprint().to_owned(),
        };

        let RelaySecurityRequirement::AuthenticatedRelayDevice(expected) = &attempt.requirement
        else {
            return Ok(EstablishedTransportSession::LegacyLan {
                connection,
                origin: TransportOrigin::Local,
            });
        };

        if candidate.protocol() != ProtocolType::Https {
            return Err(RelaySendError::TransportUnavailable {
                detail: "verified Relay LAN requires HTTPS proof support".to_owned(),
            });
        }
        let auth = connection
            .client()
            .authenticate_relay_server(candidate.protocol(), candidate.host(), candidate.port())
            .await;
        let session = verified_lan_session_from_proof_result(
            &self.local_relay_id,
            expected,
            candidate.host(),
            candidate.port(),
            candidate.tls_fingerprint(),
            auth,
        )?;
        Ok(EstablishedTransportSession::AuthenticatedRelay {
            connection,
            session,
            origin: TransportOrigin::Local,
        })
    }
}

fn verified_lan_session_from_proof_result(
    local_relay_id: &RelayId,
    expected: &RelayId,
    host: &str,
    port: u16,
    candidate_fingerprint: &str,
    auth: RelayPeerAuth,
) -> Result<super::AuthenticatedRelaySession, RelaySendError> {
    let expected_binding = ChannelBinding::from_uppercase_hex(candidate_fingerprint).ok_or(
        RelaySendError::IdentityVerificationFailed {
            reason: IdentityFailure::TlsBindingMismatch,
        },
    )?;
    let (proven, observed_binding) = match auth {
        RelayPeerAuth::Authenticated {
            relay_id,
            tls_fingerprint,
        } => (
            RelayId::from_verified_hex(&relay_id).map_err(|_| {
                RelaySendError::IdentityVerificationFailed {
                    reason: IdentityFailure::InvalidRelayProof,
                }
            })?,
            ChannelBinding::tls_cert_sha256(tls_fingerprint),
        ),
        RelayPeerAuth::TransportUnauthenticated => {
            return Err(RelaySendError::ConnectionFailed {
                stage: ConnectionStage::BeforeIdentityVerification,
                detail: "LAN proof connection did not authenticate TLS".to_owned(),
            });
        }
        RelayPeerAuth::Unsupported
        | RelayPeerAuth::SignerUnavailable
        | RelayPeerAuth::NotAttempted => {
            return Err(RelaySendError::TransportUnavailable {
                detail: "LAN route cannot provide verified Relay proof".to_owned(),
            });
        }
        RelayPeerAuth::Malformed
        | RelayPeerAuth::RoleMismatch
        | RelayPeerAuth::ChallengeMismatch
        | RelayPeerAuth::CryptoInvalid => {
            return Err(RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::InvalidRelayProof,
            });
        }
    };
    if observed_binding != expected_binding {
        return Err(RelaySendError::IdentityVerificationFailed {
            reason: IdentityFailure::TlsBindingMismatch,
        });
    }
    let coordinator = RelayAuthCoordinator::new(local_relay_id.clone());
    coordinator
        .complete_verified_lan_initiator(
            proven,
            observed_binding.tls_cert_fingerprint(),
            expected,
            PathDescriptor::lan(host, Some(port)),
        )
        .map_err(|error| match error {
            super::RelayAuthError::ExpectedIdentityMismatch { .. } => {
                RelaySendError::IdentityVerificationFailed {
                    reason: IdentityFailure::ExpectedRelayIdMismatch,
                }
            }
            super::RelayAuthError::CryptoInvalid
            | super::RelayAuthError::RoleMismatch
            | super::RelayAuthError::ChallengeMismatch => {
                RelaySendError::IdentityVerificationFailed {
                    reason: IdentityFailure::InvalidRelayProof,
                }
            }
        })
}

impl TransportSessionFactory for LanRelaySessionFactory {
    type Connection = ProductionLanConnection;

    fn open<'a>(
        &'a self,
        attempt: &'a TransportAttempt,
    ) -> super::transport::SessionFuture<'a, Self::Connection> {
        Box::pin(self.open_attempt(attempt))
    }
}

#[cfg(test)]
mod tests {
    use crate::crypto::relay_identity::RelayIdentity;

    use super::*;

    fn relay_id() -> RelayId {
        RelayId::from_local_identity(&RelayIdentity::generate()).unwrap()
    }

    fn valid_auth(relay_id: &RelayId, fingerprint: [u8; 32]) -> RelayPeerAuth {
        RelayPeerAuth::Authenticated {
            relay_id: relay_id.as_hex(),
            tls_fingerprint: fingerprint,
        }
    }

    fn fingerprint_hex(fingerprint: [u8; 32]) -> String {
        fingerprint
            .iter()
            .map(|byte| format!("{byte:02X}"))
            .collect()
    }

    #[test]
    fn valid_verified_lan_proof_creates_an_authenticated_session() {
        let local = relay_id();
        let remote = relay_id();
        let fingerprint = [0x22; 32];
        let session = verified_lan_session_from_proof_result(
            &local,
            &remote,
            "192.0.2.8",
            53317,
            &fingerprint_hex(fingerprint),
            valid_auth(&remote, fingerprint),
        )
        .unwrap();

        assert_eq!(session.remote_relay_id(), &remote);
        assert!(!session.mutual());
        assert_eq!(
            session.path(),
            &PathDescriptor::lan("192.0.2.8", Some(53317))
        );
    }

    #[test]
    fn mismatch_or_malformed_proof_never_yields_a_transfer_session() {
        let local = relay_id();
        let expected = relay_id();
        let other = relay_id();
        let fingerprint = [0x22; 32];
        let mismatch = verified_lan_session_from_proof_result(
            &local,
            &expected,
            "192.0.2.8",
            53317,
            &fingerprint_hex(fingerprint),
            valid_auth(&other, fingerprint),
        );
        assert_eq!(
            mismatch,
            Err(RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::ExpectedRelayIdMismatch,
            })
        );
        let malformed = verified_lan_session_from_proof_result(
            &local,
            &expected,
            "192.0.2.8",
            53317,
            &fingerprint_hex(fingerprint),
            RelayPeerAuth::Malformed,
        );
        assert_eq!(
            malformed,
            Err(RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::InvalidRelayProof,
            })
        );
    }

    #[test]
    fn certificate_substitution_after_proof_is_rejected_before_transfer() {
        let local = relay_id();
        let remote = relay_id();
        let proof_certificate = [0x22; 32];
        let substituted_certificate = [0x23; 32];
        let result = verified_lan_session_from_proof_result(
            &local,
            &remote,
            "192.0.2.8",
            53317,
            &fingerprint_hex(proof_certificate),
            valid_auth(&remote, substituted_certificate),
        );

        assert_eq!(
            result,
            Err(RelaySendError::IdentityVerificationFailed {
                reason: IdentityFailure::TlsBindingMismatch,
            })
        );
    }
}
