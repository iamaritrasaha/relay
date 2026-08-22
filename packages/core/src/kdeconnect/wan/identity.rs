//! Persistent Relay WAN identity: a stable Iroh secret key, independent of the
//! KDE Connect TLS identity ([`crate::kdeconnect::LocalIdentity`]) and of the
//! Relay Anywhere routing key ([`crate::anywhere::AnywhereRoutingKey`]).
//!
//! This key is generated once and persisted by the host platform; it must
//! never be regenerated on every launch, since its public half (the Iroh
//! `EndpointId`) is the cryptographic WAN identity bound to KDE device ids in
//! the [`super::binding::WanBindingRegistry`].

use iroh::{EndpointId, SecretKey};

/// Opaque persisted Relay WAN routing credential. `Debug` never reveals key
/// material or the derived `EndpointId`.
#[derive(Clone)]
pub struct WanIdentity(SecretKey);

impl std::fmt::Debug for WanIdentity {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("WanIdentity(<redacted>)")
    }
}

impl WanIdentity {
    pub const LENGTH: usize = 32;

    pub fn generate() -> Self {
        Self(SecretKey::generate())
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, WanIdentityError> {
        let bytes: [u8; Self::LENGTH] = bytes
            .try_into()
            .map_err(|_| WanIdentityError::InvalidLength)?;
        Ok(Self(SecretKey::from_bytes(&bytes)))
    }

    /// Opaque key bytes for the platform secret store to persist. Callers must
    /// not log, expose, or derive any other identity from them.
    pub fn secret_bytes(&self) -> [u8; Self::LENGTH] {
        self.0.to_bytes()
    }

    pub fn endpoint_id(&self) -> EndpointId {
        self.0.public()
    }

    pub(crate) fn secret_key(&self) -> SecretKey {
        self.0.clone()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum WanIdentityError {
    #[error("invalid Relay WAN identity key length")]
    InvalidLength,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persisted_identity_reloads_to_the_same_endpoint_id() {
        let original = WanIdentity::generate();
        let restored = WanIdentity::from_bytes(&original.secret_bytes()).unwrap();

        assert_eq!(original.endpoint_id(), restored.endpoint_id());
    }

    #[test]
    fn invalid_key_material_is_rejected() {
        assert_eq!(
            WanIdentity::from_bytes(&[0_u8; 31]).unwrap_err(),
            WanIdentityError::InvalidLength
        );
    }

    #[test]
    fn two_generated_identities_are_never_the_same_endpoint() {
        let a = WanIdentity::generate();
        let b = WanIdentity::generate();
        assert_ne!(a.endpoint_id(), b.endpoint_id());
    }
}
