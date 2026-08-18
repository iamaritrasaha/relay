//! Production-shaped mutual inner TLS for isolated Anywhere development proofs.
//!
//! Uses the same certificate validation machinery as LAN HTTP/TLS:
//! [`PinnedServerCertVerifier`] on the client and [`CustomClientCertVerifier`] on
//! the server. Peer identity remains authoritative only after
//! [`RelayIdentityProofV1`] verification.

use std::sync::Arc;

use anyhow::{Context as _, Result};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use tokio_rustls::{TlsAcceptor, TlsConnector};

use crate::crypto::cert::{fingerprint_digest_from_cert_der, generate_self_signed, SelfSignedCert};
use crate::http::client::PinnedServerCertVerifier;
use crate::http::server::common::CustomClientCertVerifier;

/// Independent inner-TLS identity for one RA2B peer.
///
/// Each peer owns a fresh RSA-2048 self-signed certificate generated with the
/// same helper used for production LAN TLS.
#[derive(Clone)]
pub struct InnerTlsPeer {
    pub certificate_pem: String,
    pub private_key_pem: String,
    pub cert_fingerprint: [u8; 32],
    connector: TlsConnector,
    acceptor: TlsAcceptor,
}

impl InnerTlsPeer {
    pub fn generate() -> Result<Self> {
        Self::from_self_signed(generate_self_signed()?)
    }

    fn from_self_signed(cert: SelfSignedCert) -> Result<Self> {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let cert_der = CertificateDer::from_pem_slice(cert.certificate_pem.as_bytes())
            .context("parse generated inner TLS certificate")?;
        let key_der = PrivateKeyDer::from_pem_slice(cert.private_key_pem.as_bytes())
            .context("parse generated inner TLS private key")?;
        let cert_fingerprint = fingerprint_digest_from_cert_der(cert_der.as_ref());

        let client_config = rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(
                PinnedServerCertVerifier::try_new(&cert.certificate_pem, None)
                    .context("build production-shaped inner TLS client verifier")?,
            ))
            .with_client_auth_cert(vec![cert_der.clone()], key_der.clone_key())
            .context("configure inner TLS client certificate")?;
        let server_config = rustls::ServerConfig::builder()
            .with_client_cert_verifier(Arc::new(
                CustomClientCertVerifier::try_new(&cert.certificate_pem, true)
                    .context("build production-shaped inner TLS server verifier")?,
            ))
            .with_single_cert(vec![cert_der], key_der)
            .context("configure inner TLS server certificate")?;

        Ok(Self {
            certificate_pem: cert.certificate_pem,
            private_key_pem: cert.private_key_pem,
            cert_fingerprint,
            connector: TlsConnector::from(Arc::new(client_config)),
            acceptor: TlsAcceptor::from(Arc::new(server_config)),
        })
    }

    pub fn connector(&self) -> &TlsConnector {
        &self.connector
    }

    pub fn acceptor(&self) -> &TlsAcceptor {
        &self.acceptor
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_distinct_production_shaped_identities() {
        let a = InnerTlsPeer::generate().unwrap();
        let b = InnerTlsPeer::generate().unwrap();
        assert_ne!(a.cert_fingerprint, b.cert_fingerprint);
        assert!(!a.certificate_pem.is_empty());
        assert!(!b.certificate_pem.is_empty());
    }
}
