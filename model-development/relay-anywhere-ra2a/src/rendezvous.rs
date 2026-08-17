use std::{collections::HashMap, sync::Arc, time::Duration};

use iroh::EndpointAddr;
use rand::RngCore;
use tokio::{sync::Mutex, time::Instant};

pub const CAPABILITY_BYTES: usize = 32;

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct Capability([u8; CAPABILITY_BYTES]);

impl Capability {
    pub fn generate() -> Self {
        let mut value = [0_u8; CAPABILITY_BYTES];
        rand::rng().fill_bytes(&mut value);
        Self(value)
    }

    pub fn encoded(&self) -> String {
        hex::encode(self.0)
    }
}

#[derive(Clone, Debug)]
struct Entry {
    endpoint: EndpointAddr,
    expires_at: Instant,
    claimed: bool,
}

#[derive(Clone, Debug, Default)]
pub struct TemporaryRendezvous {
    entries: Arc<Mutex<HashMap<Capability, Entry>>>,
}

impl TemporaryRendezvous {
    pub async fn publish(&self, endpoint: EndpointAddr, ttl: Duration) -> Capability {
        let capability = Capability::generate();
        self.entries.lock().await.insert(
            capability.clone(),
            Entry {
                endpoint,
                expires_at: Instant::now() + ttl,
                claimed: false,
            },
        );
        capability
    }

    pub async fn lookup(&self, capability: &Capability) -> Option<EndpointAddr> {
        let mut entries = self.entries.lock().await;
        let entry = entries.get(capability)?;
        if entry.expires_at <= Instant::now() {
            entries.remove(capability);
            return None;
        }
        Some(entry.endpoint.clone())
    }

    pub async fn take(&self, capability: &Capability) -> Option<EndpointAddr> {
        let mut entries = self.entries.lock().await;
        let entry = entries.remove(capability)?;
        (entry.expires_at > Instant::now()).then_some(entry.endpoint)
    }

    /// Single-use discovery for a proof session. Claiming prevents replay while retaining the
    /// entry until the session's explicit cleanup path deletes it.
    pub async fn claim(&self, capability: &Capability) -> Option<EndpointAddr> {
        let mut entries = self.entries.lock().await;
        let entry = entries.get_mut(capability)?;
        if entry.expires_at <= Instant::now() {
            entries.remove(capability);
            return None;
        }
        if entry.claimed {
            return None;
        }
        entry.claimed = true;
        Some(entry.endpoint.clone())
    }

    pub async fn delete(&self, capability: &Capability) -> bool {
        self.entries.lock().await.remove(capability).is_some()
    }

    pub async fn len(&self) -> usize {
        self.entries.lock().await.len()
    }

    pub async fn is_empty(&self) -> bool {
        self.entries.lock().await.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use iroh::{EndpointAddr, SecretKey};

    use super::{CAPABILITY_BYTES, Capability, TemporaryRendezvous};

    fn endpoint() -> EndpointAddr {
        EndpointAddr::new(SecretKey::generate().public())
    }

    #[tokio::test]
    async fn rendezvous_capability_has_unguessable_shape_and_supports_lookup() {
        let rendezvous = TemporaryRendezvous::default();
        let capability = rendezvous.publish(endpoint(), Duration::from_secs(1)).await;
        let other = Capability::generate();

        assert_eq!(capability.encoded().len(), CAPABILITY_BYTES * 2);
        assert_ne!(capability, other);
        assert!(rendezvous.lookup(&capability).await.is_some());
        assert!(rendezvous.lookup(&other).await.is_none());
    }

    #[tokio::test(start_paused = true)]
    async fn rendezvous_ttl_expiry_removes_stale_entry() {
        let rendezvous = TemporaryRendezvous::default();
        let capability = rendezvous.publish(endpoint(), Duration::from_secs(5)).await;

        tokio::time::advance(Duration::from_secs(6)).await;

        assert!(rendezvous.lookup(&capability).await.is_none());
        assert_eq!(rendezvous.len().await, 0);
    }

    #[tokio::test]
    async fn rendezvous_explicit_deletion_and_take_are_single_use() {
        let rendezvous = TemporaryRendezvous::default();
        let deleted = rendezvous.publish(endpoint(), Duration::from_secs(1)).await;
        assert!(rendezvous.delete(&deleted).await);
        assert!(rendezvous.lookup(&deleted).await.is_none());

        let taken = rendezvous.publish(endpoint(), Duration::from_secs(1)).await;
        assert!(rendezvous.take(&taken).await.is_some());
        assert!(rendezvous.take(&taken).await.is_none());
    }

    #[tokio::test(start_paused = true)]
    async fn stale_or_claimed_capability_cannot_be_replayed() {
        let rendezvous = TemporaryRendezvous::default();
        let stale = rendezvous.publish(endpoint(), Duration::from_secs(5)).await;
        tokio::time::advance(Duration::from_secs(6)).await;
        assert!(rendezvous.claim(&stale).await.is_none());

        let fresh = rendezvous.publish(endpoint(), Duration::from_secs(5)).await;
        assert!(rendezvous.claim(&fresh).await.is_some());
        assert!(rendezvous.claim(&fresh).await.is_none());
        assert!(rendezvous.delete(&fresh).await);
        assert!(rendezvous.is_empty().await);
    }
}
