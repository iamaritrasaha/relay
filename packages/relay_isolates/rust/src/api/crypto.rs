use crate::api::cancel::RsCancellationToken;
use crate::frb_generated::StreamSink;

pub fn verify_cert(cert: String, public_key: String) -> anyhow::Result<()> {
    relay_core::crypto::cert::verify_cert_from_pem(cert, Some(&public_key))
}

pub fn generate_key_pair() -> anyhow::Result<KeyPair> {
    let signing_key = relay_core::crypto::token::generate_key();
    let private_key = relay_core::crypto::token::export_private_key(&signing_key)?;
    let public_key = relay_core::crypto::token::export_public_key(&signing_key)?;

    Ok(KeyPair {
        private_key: private_key.to_string(),
        public_key,
    })
}

pub struct KeyPair {
    pub private_key: String,
    pub public_key: String,
}

/// Relay identity material produced and validated exclusively by Rust.
///
/// `private_key` contains the canonical PKCS#8 PEM bytes and must be passed
/// directly to the platform secure store by a later coordinator.
pub struct RelayIdentityMaterial {
    pub private_key: Vec<u8>,
    pub public_key: String,
    pub relay_id: String,
}

/// Generates a new Relay Ed25519 identity and returns its canonical exports.
pub fn generate_relay_identity() -> anyhow::Result<RelayIdentityMaterial> {
    relay_identity_material(relay_core::crypto::relay_identity::RelayIdentity::generate())
}

/// Restores a Relay Ed25519 identity from canonical PKCS#8 PEM bytes.
///
/// Invalid input is rejected without generating a replacement identity.
pub fn restore_relay_identity(private_key: Vec<u8>) -> anyhow::Result<RelayIdentityMaterial> {
    if private_key.is_empty() {
        anyhow::bail!("Relay identity private key is empty");
    }

    let private_key = std::str::from_utf8(&private_key)
        .map_err(|_| anyhow::anyhow!("Relay identity private key is not valid UTF-8"))?;
    let identity = relay_core::crypto::relay_identity::RelayIdentity::from_private_key(private_key)
        .map_err(|_| anyhow::anyhow!("Relay identity private key is not valid PKCS#8 PEM"))?;
    relay_identity_material(identity)
}

fn relay_identity_material(
    identity: relay_core::crypto::relay_identity::RelayIdentity,
) -> anyhow::Result<RelayIdentityMaterial> {
    let private_key = identity.private_key_export()?.as_bytes().to_vec();
    Ok(RelayIdentityMaterial {
        private_key,
        public_key: identity.public_key_export()?,
        relay_id: identity.relay_id()?,
    })
}

#[cfg(test)]
mod relay_identity_tests {
    use super::*;

    #[test]
    fn generate_returns_valid_relay_identity_material() {
        let material = generate_relay_identity().unwrap();

        assert!(!material.private_key.is_empty());
        assert!(relay_core::crypto::relay_identity::parse_public_key(&material.public_key).is_ok());
        assert_eq!(material.relay_id.len(), 64);
        assert!(
            material
                .relay_id
                .chars()
                .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_lowercase())
        );
    }

    #[test]
    fn restore_generated_private_key_preserves_public_key_and_relay_id() {
        let generated = generate_relay_identity().unwrap();
        let restored = restore_relay_identity(generated.private_key).unwrap();

        assert_eq!(restored.public_key, generated.public_key);
        assert_eq!(restored.relay_id, generated.relay_id);
    }

    #[test]
    fn restore_rejects_invalid_utf8() {
        assert!(restore_relay_identity(vec![0xff]).is_err());
    }

    #[test]
    fn restore_rejects_invalid_pkcs8_pem() {
        assert!(restore_relay_identity(b"not a PKCS#8 PEM key".to_vec()).is_err());
    }

    #[test]
    fn restore_rejects_empty_private_key() {
        assert!(restore_relay_identity(Vec::new()).is_err());
    }

    #[test]
    fn generated_identities_are_distinct() {
        let first = generate_relay_identity().unwrap();
        let second = generate_relay_identity().unwrap();

        assert_ne!(first.public_key, second.public_key);
        assert_ne!(first.relay_id, second.relay_id);
    }
}

/// Generates a new device identity: an RSA-2048 key pair and a self-signed
/// certificate whose SHA-256 fingerprint identifies the device.
pub fn generate_security_context() -> anyhow::Result<SecurityContext> {
    let cert = relay_core::crypto::cert::generate_self_signed()?;

    Ok(SecurityContext {
        private_key: cert.private_key_pem,
        public_key: cert.public_key_pem,
        certificate: cert.certificate_pem,
        certificate_hash: cert.fingerprint,
    })
}

pub struct SecurityContext {
    pub private_key: String,
    pub public_key: String,
    pub certificate: String,
    pub certificate_hash: String,
}

/// An event emitted while a file is being hashed by [hash_file].
#[derive(Clone)]
pub enum RsHashFileEvent {
    /// Cumulative number of bytes hashed so far.
    /// Throttled, so not every hashed chunk is reported.
    Progress { bytes: u64 },

    /// Hashing has finished; [hash] is the checksum, encoded as lowercase hex.
    /// Always the last event of the stream.
    Done { hash: String },
}

/// Computes the SHA-256 checksum of a file, reported as the final
/// [RsHashFileEvent::Done] event of the returned stream.
///
/// The file is read chunk by chunk, so it is never fully loaded into memory.
/// Cancelling [cancel_token] aborts the read, so hashing a large file does not
/// have to be waited out.
///
/// Failures (including cancellation) are emitted as errors on the stream:
/// flutter_rust_bridge discards the returned `Result` of functions taking a
/// [StreamSink], so a returned error would become an uncaught async error
/// killing the calling isolate.
///
/// Exactly one content source must be provided:
/// a [path] to a regular file, a [file_descriptor] (Android only), or [bytes]
/// for a file that only lives in memory.
pub async fn hash_file(
    sink: StreamSink<RsHashFileEvent>,
    path: Option<String>,
    file_descriptor: Option<i32>,
    bytes: Option<Vec<u8>>,
    cancel_token: &RsCancellationToken,
) {
    let result = async {
        let content = match (path, file_descriptor, bytes) {
            (Some(path), None, None) => relay_core::model::transfer::FileContent::Path(path.into()),
            (None, Some(file_descriptor), None) => {
                #[cfg(target_os = "android")]
                {
                    relay_core::model::transfer::FileContent::Fd(file_descriptor)
                }
                #[cfg(not(target_os = "android"))]
                {
                    let _ = file_descriptor;
                    anyhow::bail!("File descriptors are only supported on Android");
                }
            }
            (None, None, Some(bytes)) => {
                let hash = relay_core::crypto::hash::sha256_hex(&bytes);
                let _ = sink.add(RsHashFileEvent::Done { hash });
                return Ok(());
            }
            _ => anyhow::bail!("Exactly one content source must be provided"),
        };

        // Progress events with throttling
        let last_emit = std::cell::Cell::new(None::<std::time::Instant>);
        let progress = {
            let sink = sink.clone();
            move |hashed| {
                let now = std::time::Instant::now();
                if let Some(last) = last_emit.get() {
                    if now.duration_since(last) < std::time::Duration::from_millis(20) {
                        return;
                    }
                }
                last_emit.set(Some(now));
                let _ = sink.add(RsHashFileEvent::Progress { bytes: hashed });
            }
        };

        let hash =
            relay_core::crypto::hash::sha256_file_content(content, &cancel_token.inner, progress)
                .await?;
        let _ = sink.add(RsHashFileEvent::Done { hash });
        Ok(())
    }
    .await;

    if let Err(err) = result {
        let _ = sink.add_error(err);
    }
}
