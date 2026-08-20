//! Stable local KDE Connect identity: deviceId, display name, and TLS material.
//!
//! This identity is independent of RelayId / LocalSend fingerprints. The
//! certificate common name is the KDE Connect deviceId, as current upstream
//! implementations require.

use crate::kdeconnect::packet::{
    filter_device_name, is_valid_device_id, IdentityBody, PROTOCOL_VERSION,
};
use anyhow::{Context, Result};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use std::sync::Once;
use time::{Duration, OffsetDateTime};
use uuid::Uuid;
use x509_parser::prelude::FromDer;

const DEVICE_TYPE_DESKTOP: &str = "desktop";
const CERT_O: &str = "KDE";
const CERT_OU: &str = "KDE Connect";

static INSTALL_PROVIDER: Once = Once::new();

pub fn install_crypto_provider() {
    INSTALL_PROVIDER.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

#[derive(Clone, Debug)]
pub struct LocalIdentity {
    pub device_id: String,
    pub device_name: String,
    pub device_type: String,
    pub certificate_pem: String,
    pub private_key_pem: String,
}

impl LocalIdentity {
    pub fn generate(device_name: &str) -> Result<Self> {
        install_crypto_provider();
        let device_id = Uuid::new_v4().simple().to_string();
        generate_with_id(device_id, device_name)
    }

    pub fn from_persisted(
        device_id: String,
        device_name: String,
        certificate_pem: String,
        private_key_pem: String,
    ) -> Result<Self> {
        install_crypto_provider();
        if !is_valid_device_id(&device_id) {
            anyhow::bail!("persisted KDE Connect deviceId is not valid");
        }
        CertificateDer::from_pem_slice(certificate_pem.as_bytes())
            .context("persisted KDE Connect certificate")?;
        PrivateKeyDer::from_pem_slice(private_key_pem.as_bytes())
            .context("persisted KDE Connect private key")?;
        let cn = certificate_common_name_from_pem(&certificate_pem)?;
        if cn != device_id {
            anyhow::bail!("persisted certificate CN does not match deviceId");
        }
        Ok(Self {
            device_id,
            device_name: filter_device_name(&device_name),
            device_type: DEVICE_TYPE_DESKTOP.into(),
            certificate_pem,
            private_key_pem,
        })
    }

    pub fn identity_packet(&self, tcp_port: Option<u16>) -> IdentityBody {
        IdentityBody {
            device_id: self.device_id.clone(),
            device_name: self.device_name.clone(),
            device_type: self.device_type.clone(),
            protocol_version: PROTOCOL_VERSION,
            incoming_capabilities: crate::kdeconnect::canonical_incoming_capabilities(),
            outgoing_capabilities: crate::kdeconnect::canonical_outgoing_capabilities(),
            tcp_port,
            target_device_id: None,
            target_protocol_version: None,
        }
    }

    pub fn certificate_der(&self) -> Result<CertificateDer<'static>> {
        CertificateDer::from_pem_slice(self.certificate_pem.as_bytes())
            .context("parse local KDE Connect certificate")
    }

    pub fn private_key_der(&self) -> Result<PrivateKeyDer<'static>> {
        PrivateKeyDer::from_pem_slice(self.private_key_pem.as_bytes())
            .context("parse local KDE Connect private key")
    }
}

fn generate_with_id(device_id: String, device_name: &str) -> Result<LocalIdentity> {
    let key_pair = rcgen::KeyPair::generate_for(&rcgen::PKCS_ECDSA_P256_SHA256)
        .context("generate KDE Connect TLS key")?;
    let mut params = rcgen::CertificateParams::default();
    params.distinguished_name.push(
        rcgen::DnType::OrganizationName,
        rcgen::DnValue::Utf8String(CERT_O.into()),
    );
    params.distinguished_name.push(
        rcgen::DnType::OrganizationalUnitName,
        rcgen::DnValue::Utf8String(CERT_OU.into()),
    );
    params.distinguished_name.push(
        rcgen::DnType::CommonName,
        rcgen::DnValue::Utf8String(device_id.clone()),
    );
    let not_before = OffsetDateTime::now_utc() - Duration::days(1);
    let not_after = OffsetDateTime::now_utc() + Duration::days(3650);
    params.not_before = not_before;
    params.not_after = not_after;

    let cert = params
        .self_signed(&key_pair)
        .context("self-sign KDE Connect certificate")?;
    let certificate_pem = cert.pem();
    let private_key_pem = key_pair.serialize_pem();

    Ok(LocalIdentity {
        device_id,
        device_name: filter_device_name(device_name),
        device_type: DEVICE_TYPE_DESKTOP.into(),
        certificate_pem,
        private_key_pem,
    })
}

pub fn certificate_common_name_from_pem(pem: &str) -> Result<String> {
    let der = CertificateDer::from_pem_slice(pem.as_bytes())
        .context("parse KDE Connect certificate PEM")?;
    certificate_common_name(&der)
}

pub fn certificate_common_name(der: &[u8]) -> Result<String> {
    let (_, parsed) =
        x509_parser::certificate::X509Certificate::from_der(der).context("parse X.509 cert DER")?;
    let cn = parsed
        .subject()
        .iter_common_name()
        .next()
        .and_then(|n| n.as_str().ok())
        .ok_or_else(|| anyhow::anyhow!("certificate has no common name"))?;
    Ok(cn.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_device_id_is_stable_shape() {
        let first = LocalIdentity::generate("Relay").unwrap();
        assert!(is_valid_device_id(&first.device_id));
        assert_eq!(first.device_id.len(), 32);
        let restored = LocalIdentity::from_persisted(
            first.device_id.clone(),
            first.device_name.clone(),
            first.certificate_pem.clone(),
            first.private_key_pem.clone(),
        )
        .unwrap();
        assert_eq!(restored.device_id, first.device_id);
        assert_eq!(restored.certificate_pem, first.certificate_pem);
    }

    #[test]
    fn regenerated_identity_is_a_new_device_id() {
        let a = LocalIdentity::generate("Relay").unwrap();
        let b = LocalIdentity::generate("Relay").unwrap();
        assert_ne!(a.device_id, b.device_id);
    }

    #[test]
    fn capability_advertisement_derives_from_canonical_registry() {
        let id = LocalIdentity::generate("Relay").unwrap();
        let pkt = id.identity_packet(Some(1716));
        assert_eq!(
            pkt.incoming_capabilities,
            crate::kdeconnect::canonical_incoming_capabilities()
        );
        assert_eq!(
            pkt.outgoing_capabilities,
            crate::kdeconnect::canonical_outgoing_capabilities()
        );
    }
}
