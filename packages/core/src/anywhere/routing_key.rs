//! Private Iroh routing credential for a Relay Anywhere listener.
//!
//! This deliberately has no relationship to `RelayId`: it is only the stable
//! Iroh EndpointId credential required to make a manually shared address
//! usable after an application restart. Platform code persists the opaque
//! 32-byte value in its existing secret-store mechanism.

use iroh::{PublicKey, SecretKey};

/// Opaque private routing credential. Its `Debug` implementation intentionally
/// does not reveal either the key material or its EndpointId.
#[derive(Clone)]
pub struct AnywhereRoutingKey(SecretKey);

impl std::fmt::Debug for AnywhereRoutingKey {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("AnywhereRoutingKey(<redacted>)")
    }
}

impl AnywhereRoutingKey {
    pub const LENGTH: usize = 32;

    pub fn generate() -> Self {
        Self(SecretKey::generate())
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, RoutingKeyError> {
        let bytes: [u8; Self::LENGTH] = bytes
            .try_into()
            .map_err(|_| RoutingKeyError::InvalidLength)?;
        Ok(Self(SecretKey::from_bytes(&bytes)))
    }

    /// Returns opaque key bytes solely so a platform secret store can persist
    /// them. Callers must not log, expose, or derive Relay identity from them.
    pub fn secret_bytes(&self) -> [u8; Self::LENGTH] {
        self.0.to_bytes()
    }

    pub fn endpoint_id(&self) -> PublicKey {
        self.0.public()
    }

    pub(crate) fn secret_key(&self) -> SecretKey {
        self.0.clone()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum RoutingKeyError {
    #[error("invalid Anywhere routing key length")]
    InvalidLength,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persisted_key_reloads_to_the_same_endpoint_id() {
        let original = AnywhereRoutingKey::generate();
        let restored = AnywhereRoutingKey::from_bytes(&original.secret_bytes()).unwrap();

        assert_eq!(original.endpoint_id(), restored.endpoint_id());
    }

    #[test]
    fn invalid_key_material_cannot_be_interpreted_as_a_key() {
        assert_eq!(
            AnywhereRoutingKey::from_bytes(&[0_u8; 31]).unwrap_err(),
            RoutingKeyError::InvalidLength
        );
    }

    #[test]
    fn replacement_key_rotates_only_the_routing_endpoint() {
        let original = AnywhereRoutingKey::generate();
        let replacement = AnywhereRoutingKey::generate();

        assert_ne!(original.endpoint_id(), replacement.endpoint_id());
    }
}
