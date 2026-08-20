//! KDE Connect pairing state machine (protocol version 8).
//!
//! Pairing is bilateral: a `pair: true` packet with a timestamp is a request,
//! an answering `pair: true` while we are `Requested` completes pairing, and
//! `pair: false` rejects or unpairs. Certificates are never updated here.

use crate::kdeconnect::packet::{PairBody, PROTOCOL_VERSION};
use std::time::{SystemTime, UNIX_EPOCH};

pub const PAIRING_TIMEOUT_SECS: u64 = 30;
pub const ALLOWED_TIMESTAMP_SKEW_SECS: i64 = 1800;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PairState {
    NotPaired,
    Requested,
    RequestedByPeer,
    Paired,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PairingFailReason {
    MissingTimestamp,
    ClocksOutOfSync,
    CanceledByPeer,
    TimedOut,
    AlreadyPaired,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PairingEffect {
    None,
    IncomingRequest { timestamp: i64 },
    Completed,
    Failed(PairingFailReason),
    Unpaired,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PairingSession {
    pub state: PairState,
    pub timestamp: Option<i64>,
}

impl PairingSession {
    pub fn new(paired: bool) -> Self {
        Self {
            state: if paired {
                PairState::Paired
            } else {
                PairState::NotPaired
            },
            timestamp: None,
        }
    }

    pub fn on_packet(
        &mut self,
        packet: &PairBody,
        now_unix: i64,
        protocol_version: i64,
    ) -> PairingEffect {
        if packet.pair {
            match self.state {
                PairState::Requested => {
                    self.state = PairState::Paired;
                    PairingEffect::Completed
                }
                PairState::RequestedByPeer => PairingEffect::None,
                PairState::Paired => {
                    self.state = PairState::NotPaired;
                    self.timestamp = None;
                    PairingEffect::Unpaired
                }
                PairState::NotPaired => {
                    if protocol_version >= PROTOCOL_VERSION {
                        let Some(timestamp) = packet.timestamp else {
                            self.state = PairState::NotPaired;
                            return PairingEffect::Failed(PairingFailReason::MissingTimestamp);
                        };
                        if (timestamp - now_unix).abs() > ALLOWED_TIMESTAMP_SKEW_SECS {
                            self.state = PairState::NotPaired;
                            return PairingEffect::Failed(PairingFailReason::ClocksOutOfSync);
                        }
                        self.timestamp = Some(timestamp);
                    }
                    self.state = PairState::RequestedByPeer;
                    PairingEffect::IncomingRequest {
                        timestamp: self.timestamp.unwrap_or(now_unix),
                    }
                }
            }
        } else {
            match self.state {
                PairState::NotPaired => PairingEffect::None,
                PairState::Requested | PairState::RequestedByPeer => {
                    self.state = PairState::NotPaired;
                    self.timestamp = None;
                    PairingEffect::Failed(PairingFailReason::CanceledByPeer)
                }
                PairState::Paired => {
                    self.state = PairState::NotPaired;
                    self.timestamp = None;
                    PairingEffect::Unpaired
                }
            }
        }
    }

    pub fn begin_request(&mut self, now_unix: i64) -> Result<PairBody, PairingFailReason> {
        if self.state == PairState::Paired {
            return Err(PairingFailReason::AlreadyPaired);
        }
        if self.state == PairState::RequestedByPeer {
            return Ok(PairBody {
                pair: true,
                timestamp: None,
            });
        }
        self.state = PairState::Requested;
        self.timestamp = Some(now_unix);
        Ok(PairBody {
            pair: true,
            timestamp: Some(now_unix),
        })
    }

    pub fn accept(&mut self) {
        self.state = PairState::Paired;
    }

    pub fn local_cancel(&mut self) {
        self.state = PairState::NotPaired;
        self.timestamp = None;
    }

    pub fn timeout(&mut self) -> PairingEffect {
        if matches!(
            self.state,
            PairState::Requested | PairState::RequestedByPeer
        ) {
            self.state = PairState::NotPaired;
            self.timestamp = None;
            PairingEffect::Failed(PairingFailReason::TimedOut)
        } else {
            PairingEffect::None
        }
    }
}

pub fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use x509_parser::prelude::FromDer;

pub fn compute_verification_key(
    my_public_key: &[u8],
    peer_public_key: &[u8],
    timestamp: i64,
) -> String {
    let mut hasher = Sha256::new();
    if my_public_key < peer_public_key {
        hasher.update(my_public_key);
        hasher.update(peer_public_key);
    } else {
        hasher.update(peer_public_key);
        hasher.update(my_public_key);
    }
    hasher.update(timestamp.to_string().as_bytes());
    let hash = hasher.finalize();
    format!(
        "{:02X}{:02X}{:02X}{:02X}",
        hash[0], hash[1], hash[2], hash[3]
    )
}

pub fn extract_public_key_der(cert_der: &[u8]) -> Result<Vec<u8>> {
    let (_, cert) =
        x509_parser::certificate::X509Certificate::from_der(cert_der).context("parse x509 cert")?;
    Ok(cert.tbs_certificate.subject_pki.raw.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn outgoing_initial_request_contains_pair_true_and_seconds_timestamp() {
        let mut session = PairingSession::new(false);
        let now = now_unix();
        assert!(
            now > 1_700_000_000 && now < 2_500_000_000,
            "timestamp must be seconds-scale, not milliseconds"
        );
        let body = session.begin_request(now).unwrap();
        assert!(body.pair);
        assert_eq!(body.timestamp, Some(now));
        assert_eq!(session.state, PairState::Requested);
        assert_eq!(session.timestamp, Some(now));

        let packet = PairBody::request(body.timestamp.unwrap());
        let serialized = packet.serialize();
        let parsed = crate::kdeconnect::NetworkPacket::parse(&serialized)
            .unwrap()
            .as_pair()
            .unwrap();
        assert!(parsed.pair);
        assert_eq!(parsed.timestamp, Some(now));
    }

    #[test]
    fn acceptance_contains_pair_true_and_preserves_timestamp() {
        let mut session = PairingSession::new(false);
        let req_ts = 1_700_000_000;
        let effect = session.on_packet(
            &PairBody {
                pair: true,
                timestamp: Some(req_ts),
            },
            req_ts,
            PROTOCOL_VERSION,
        );
        assert!(matches!(effect, PairingEffect::IncomingRequest { .. }));
        assert_eq!(session.state, PairState::RequestedByPeer);
        assert_eq!(session.timestamp, Some(req_ts));

        session.accept();
        assert_eq!(session.state, PairState::Paired);
        assert_eq!(session.timestamp, Some(req_ts));

        let accept_pkt = PairBody::accept();
        assert_eq!(accept_pkt.packet_type, crate::kdeconnect::PACKET_TYPE_PAIR);
        let parsed = crate::kdeconnect::NetworkPacket::parse(&accept_pkt.serialize())
            .unwrap()
            .as_pair()
            .unwrap();
        assert!(parsed.pair);
        assert_eq!(parsed.timestamp, None);
    }

    #[test]
    fn rejection_and_unpair_contain_pair_false() {
        let mut session = PairingSession::new(false);
        session.on_packet(
            &PairBody {
                pair: true,
                timestamp: Some(1_700_000_000),
            },
            1_700_000_000,
            PROTOCOL_VERSION,
        );
        session.local_cancel();
        assert_eq!(session.state, PairState::NotPaired);
        assert_eq!(session.timestamp, None);

        let unpair_pkt = PairBody::unpair();
        let parsed = crate::kdeconnect::NetworkPacket::parse(&unpair_pkt.serialize())
            .unwrap()
            .as_pair()
            .unwrap();
        assert!(!parsed.pair);
        assert_eq!(parsed.timestamp, None);
    }

    #[test]
    fn missing_timestamp_on_incoming_v8_is_rejected() {
        let mut session = PairingSession::new(false);
        let effect = session.on_packet(
            &PairBody {
                pair: true,
                timestamp: None,
            },
            1_700_000_000,
            PROTOCOL_VERSION,
        );
        assert_eq!(
            effect,
            PairingEffect::Failed(PairingFailReason::MissingTimestamp)
        );
        assert_eq!(session.state, PairState::NotPaired);
    }

    #[test]
    fn stale_or_skewed_timestamp_is_rejected_according_to_upstream_tolerance() {
        let mut session = PairingSession::new(false);
        let now = 1_700_000_000;
        // Skew > 1800s (e.g. 1801s)
        let effect_too_old = session.on_packet(
            &PairBody {
                pair: true,
                timestamp: Some(now - ALLOWED_TIMESTAMP_SKEW_SECS - 1),
            },
            now,
            PROTOCOL_VERSION,
        );
        assert_eq!(
            effect_too_old,
            PairingEffect::Failed(PairingFailReason::ClocksOutOfSync)
        );
        assert_eq!(session.state, PairState::NotPaired);

        // Skew in future > 1800s
        let effect_too_future = session.on_packet(
            &PairBody {
                pair: true,
                timestamp: Some(now + ALLOWED_TIMESTAMP_SKEW_SECS + 1),
            },
            now,
            PROTOCOL_VERSION,
        );
        assert_eq!(
            effect_too_future,
            PairingEffect::Failed(PairingFailReason::ClocksOutOfSync)
        );
        assert_eq!(session.state, PairState::NotPaired);

        // Skew within 1800s is accepted
        let effect_valid = session.on_packet(
            &PairBody {
                pair: true,
                timestamp: Some(now - ALLOWED_TIMESTAMP_SKEW_SECS),
            },
            now,
            PROTOCOL_VERSION,
        );
        assert!(matches!(
            effect_valid,
            PairingEffect::IncomingRequest { .. }
        ));
        assert_eq!(session.state, PairState::RequestedByPeer);
    }

    #[test]
    fn unpair_clears_paired_state() {
        let mut session = PairingSession::new(true);
        let effect = session.on_packet(
            &PairBody {
                pair: false,
                timestamp: None,
            },
            0,
            PROTOCOL_VERSION,
        );
        assert_eq!(effect, PairingEffect::Unpaired);
        assert_eq!(session.state, PairState::NotPaired);
    }

    #[test]
    fn outgoing_accept_from_peer_completes() {
        let mut session = PairingSession::new(false);
        session.begin_request(1_700_000_000).unwrap();
        let effect = session.on_packet(
            &PairBody {
                pair: true,
                timestamp: None,
            },
            1_700_000_001,
            PROTOCOL_VERSION,
        );
        assert_eq!(effect, PairingEffect::Completed);
        assert_eq!(session.state, PairState::Paired);
    }

    #[test]
    fn verification_key_is_deterministic_8_hex_chars() {
        let key_a = b"public_key_a_sample_bytes_12345678";
        let key_b = b"public_key_b_sample_bytes_87654321";
        let ts = 1_700_000_000;

        let code1 = compute_verification_key(key_a, key_b, ts);
        let code2 = compute_verification_key(key_b, key_a, ts);
        assert_eq!(code1.len(), 8);
        assert_eq!(code1, code2);
        assert!(code1
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_lowercase()));

        let code_diff_ts = compute_verification_key(key_a, key_b, ts + 1);
        assert_ne!(code1, code_diff_ts);
    }
}
