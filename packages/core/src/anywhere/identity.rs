//! Production Relay identity material for Anywhere sessions.
//!
//! The private key is owned by the platform secret store and handed to Rust for
//! the lifetime of an operation, exactly like the LAN server proof signer
//! (`ServerHandle::install_relay_signer`). Anywhere never generates a throwaway
//! identity: the same installation must keep the same RelayId across restarts.

use std::sync::Arc;

use crate::crypto::relay_identity::RelayIdentity;
use crate::relay::RelaySignerInstallError;

/// A loaded production Relay identity, ready for mutual Anywhere proof.
#[derive(Clone)]
pub struct AnywhereIdentity {
    identity: Arc<RelayIdentity>,
    relay_id: String,
}

impl AnywhereIdentity {
    /// Loads the persisted identity from PKCS#8 PEM and verifies it against the
    /// RelayId the caller expects.
    ///
    /// The input buffer is zeroed before returning, on both the success and the
    /// failure path.
    pub fn load(
        private_key_pem: &mut Vec<u8>,
        expected_relay_id: &str,
    ) -> Result<Self, RelaySignerInstallError> {
        let result = Self::load_inner(private_key_pem, expected_relay_id);
        private_key_pem.fill(0);
        private_key_pem.clear();
        result
    }

    fn load_inner(
        private_key_pem: &[u8],
        expected_relay_id: &str,
    ) -> Result<Self, RelaySignerInstallError> {
        let pem = std::str::from_utf8(private_key_pem)
            .map_err(|_| RelaySignerInstallError::InvalidPrivateKey)?;
        let identity = RelayIdentity::from_private_key(pem)
            .map_err(|_| RelaySignerInstallError::InvalidPrivateKey)?;
        let relay_id = identity
            .relay_id()
            .map_err(|_| RelaySignerInstallError::InvalidPrivateKey)?;
        if relay_id != expected_relay_id {
            return Err(RelaySignerInstallError::RelayIdMismatch);
        }
        Ok(Self {
            identity: Arc::new(identity),
            relay_id,
        })
    }

    /// Wraps an already-shared identity (development harness).
    pub fn from_shared(identity: Arc<RelayIdentity>) -> Result<Self, RelaySignerInstallError> {
        let relay_id = identity
            .relay_id()
            .map_err(|_| RelaySignerInstallError::InvalidPrivateKey)?;
        Ok(Self { identity, relay_id })
    }

    /// Test/host-side constructor for an already-loaded identity.
    pub fn from_identity(identity: RelayIdentity) -> Result<Self, RelaySignerInstallError> {
        let relay_id = identity
            .relay_id()
            .map_err(|_| RelaySignerInstallError::InvalidPrivateKey)?;
        Ok(Self {
            identity: Arc::new(identity),
            relay_id,
        })
    }

    pub fn relay_id(&self) -> &str {
        &self.relay_id
    }

    pub(crate) fn inner(&self) -> &RelayIdentity {
        &self.identity
    }
}

impl std::fmt::Debug for AnywhereIdentity {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("AnywhereIdentity")
            .field("relay_id", &self.relay_id)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pem_of(identity: &RelayIdentity) -> Vec<u8> {
        identity.private_key_export().unwrap().as_bytes().to_vec()
    }

    #[test]
    fn same_key_yields_the_same_relay_id_across_reloads() {
        let generated = RelayIdentity::generate();
        let relay_id = generated.relay_id().unwrap();

        let mut first = pem_of(&generated);
        let mut second = pem_of(&generated);
        let reloaded_a = AnywhereIdentity::load(&mut first, &relay_id).unwrap();
        let reloaded_b = AnywhereIdentity::load(&mut second, &relay_id).unwrap();

        assert_eq!(reloaded_a.relay_id(), relay_id);
        assert_eq!(reloaded_b.relay_id(), relay_id);
    }

    #[test]
    fn private_key_buffer_is_zeroed() {
        let generated = RelayIdentity::generate();
        let relay_id = generated.relay_id().unwrap();
        let mut pem = pem_of(&generated);
        AnywhereIdentity::load(&mut pem, &relay_id).unwrap();
        assert!(pem.is_empty());

        let mut invalid = b"not a key".to_vec();
        assert!(AnywhereIdentity::load(&mut invalid, &relay_id).is_err());
        assert!(invalid.is_empty());
    }

    #[test]
    fn mismatched_relay_id_is_rejected() {
        let generated = RelayIdentity::generate();
        let other = RelayIdentity::generate().relay_id().unwrap();
        let mut pem = pem_of(&generated);
        assert_eq!(
            AnywhereIdentity::load(&mut pem, &other).err(),
            Some(RelaySignerInstallError::RelayIdMismatch)
        );
    }

    #[test]
    fn identity_debug_does_not_leak_key_material() {
        let identity = AnywhereIdentity::from_identity(RelayIdentity::generate()).unwrap();
        let rendered = format!("{identity:?}");
        assert!(rendered.contains(identity.relay_id()));
        assert!(!rendered.contains("PRIVATE KEY"));
    }
}
