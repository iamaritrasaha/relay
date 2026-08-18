//! Transport-neutral path metadata. Path is never a trust anchor.

/// How a session was reached. Variants are addressing/diagnostic only.
///
/// Concrete Iroh EndpointId fields are deferred so production LAN does not
/// depend on Iroh.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PathDescriptor {
    Lan {
        host: String,
        port: Option<u16>,
    },
    InternetDirect {
        host: String,
        port: Option<u16>,
    },
    /// Future Anywhere fallback path. No Iroh routing material in RA3A.
    Relayed {
        hint: Option<String>,
    },
}

impl PathDescriptor {
    pub fn lan(host: impl Into<String>, port: Option<u16>) -> Self {
        Self::Lan {
            host: host.into(),
            port,
        }
    }
}

/// Binding produced by the existing TLS certificate fingerprint machinery.
/// This is not a RelayId.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ChannelBinding {
    tls_cert_fingerprint: [u8; 32],
}

impl ChannelBinding {
    pub fn tls_cert_sha256(tls_cert_fingerprint: [u8; 32]) -> Self {
        Self {
            tls_cert_fingerprint,
        }
    }

    pub fn from_uppercase_hex(hex: &str) -> Option<Self> {
        super::id::parse_sha256_hex(hex).map(Self::tls_cert_sha256)
    }

    pub fn tls_cert_fingerprint(&self) -> [u8; 32] {
        self.tls_cert_fingerprint
    }

    pub fn tls_cert_fingerprint_hex(&self) -> String {
        super::id::hex_upper(&self.tls_cert_fingerprint)
    }
}
