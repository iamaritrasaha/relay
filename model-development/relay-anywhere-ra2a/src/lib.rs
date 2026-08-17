//! Isolated Linux-only proof of the Relay Anywhere RA1 path architecture.

mod harness;
mod inner_tls;
mod rendezvous;

pub use harness::{ProofReport, run_manual_proof};
pub use rendezvous::{Capability, TemporaryRendezvous};
