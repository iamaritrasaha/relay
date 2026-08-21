use crate::api::cancel::RsCancellationToken;
use crate::api::stream;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
pub use relay_core::http::client::{ClientError, LsHttpClientVersion};
pub use relay_core::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, PrepareUploadResult, RegisterDto,
    RegisterResponseDto,
};
use relay_core::model::discovery::ProtocolType;
use relay_core::relay::{RelayLanPairingOutcome, RelayPeerAuth};
use relay_core::reqwest;
use relay_core::util::error::ErrorChain;

pub struct RsHttpClient {
    pub(crate) inner: relay_core::http::client::LsHttpClient,
}

/// Creates an HTTP client.
///
/// `expected_fingerprint` pins the peer to the certificate with that SHA-256
/// fingerprint (uppercase hex). It is enforced during the TLS handshake, so a
/// peer that does not present the expected certificate never receives the
/// request. Pass `None` only for discovery, where the peer is not known yet.
#[frb(sync)]
pub fn create_client(
    private_key: String,
    cert: String,
    version: LsHttpClientVersion,
    expected_fingerprint: Option<String>,
    timeout_ms: Option<u32>,
) -> Result<RsHttpClient, RsHttpClientError> {
    let inner = relay_core::http::client::LsHttpClient::new(
        &private_key,
        &cert,
        version,
        expected_fingerprint,
        timeout_ms.map(|ms| std::time::Duration::from_millis(ms as u64)),
    )
    .map_err(RsHttpClientError::from)?;

    Ok(RsHttpClient { inner })
}

impl RsHttpClient {
    /// Authenticates the selected HTTPS peer's Relay proof. Rust owns the
    /// nonce, observed TLS certificate fingerprint, and proof verification.
    pub async fn authenticate_relay_server(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
    ) -> RsRelayPeerAuth {
        self.inner
            .authenticate_relay_server(protocol, ip, port)
            .await
            .into()
    }

    pub async fn register(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: RegisterDto,
    ) -> Result<ResultWithPublicKeyRegisterResponseDto, RsHttpClientError> {
        let response = self
            .inner
            .register(protocol, ip, port, payload)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(ResultWithPublicKeyRegisterResponseDto {
            public_key: response.public_key,
            body: response.body,
        })
    }

    pub async fn prepare_upload(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        payload: PrepareUploadRequestDto,
        public_key: Option<String>,
        pin: Option<String>,
        cancel_token: &RsCancellationToken,
    ) -> Result<PrepareUploadResult, RsHttpClientError> {
        let response = self
            .inner
            .prepare_upload(
                protocol,
                ip,
                port,
                public_key,
                payload,
                pin.as_deref(),
                cancel_token.inner.clone(),
            )
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(response)
    }

    /// Uploads a single file, emitting [RsUploadEvent]s on [sink].
    ///
    /// Failures are emitted as [RsUploadEvent::Failed] instead of being
    /// returned: flutter_rust_bridge discards the returned `Result` of
    /// functions taking a [StreamSink], so a returned error would become an
    /// uncaught async error killing the calling isolate.
    pub async fn upload(
        &self,
        sink: StreamSink<RsUploadEvent>,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        public_key: Option<String>,
        session_id: &str,
        file_id: &str,
        token: &str,
        binary: Option<stream::Dart2RustStreamReceiver>,
        path: Option<String>,
        file_descriptor: Option<i32>,
        content_length: u64,
        cancel_token: &RsCancellationToken,
    ) {
        let result = async {
            let content = resolve_file_content(binary, path, file_descriptor)?;
            let last_emit = std::cell::Cell::new(None::<std::time::Instant>);
            let progress_sink = sink.clone();
            let progress = move |sent| {
                let now = std::time::Instant::now();
                let is_final = sent >= content_length;
                if !is_final {
                    if let Some(last) = last_emit.get() {
                        if now.duration_since(last) < std::time::Duration::from_millis(20) {
                            return;
                        }
                    }
                }
                last_emit.set(Some(now));
                let progress = if content_length == 0 {
                    1.0
                } else {
                    (sent as f64 / content_length as f64).min(1.0)
                };
                let _ = progress_sink.add(RsUploadEvent::Progress { progress });
            };

            self.inner
                .upload(
                    protocol,
                    ip,
                    port,
                    public_key,
                    session_id,
                    file_id,
                    token,
                    content,
                    progress,
                    cancel_token.inner.clone(),
                )
                .await
                .map_err(RsHttpClientError::from)?;

            Ok(())
        }
        .await;

        if let Err(error) = result {
            let _ = sink.add(RsUploadEvent::Failed { error });
        }
    }

    pub async fn cancel(
        &self,
        protocol: ProtocolType,
        ip: &str,
        port: u16,
        session_id: &str,
    ) -> Result<(), RsHttpClientError> {
        self.inner
            .cancel(protocol, ip, port, session_id)
            .await
            .map_err(RsHttpClientError::from)?;

        Ok(())
    }
}

fn resolve_file_content(
    binary: Option<stream::Dart2RustStreamReceiver>,
    path: Option<String>,
    file_descriptor: Option<i32>,
) -> Result<relay_core::model::transfer::FileContent, RsHttpClientError> {
    match (binary, path, file_descriptor) {
        (Some(binary), None, None) => Ok(relay_core::model::transfer::FileContent::Stream(
            binary.receiver,
        )),
        (None, Some(path), None) => Ok(relay_core::model::transfer::FileContent::Path(path.into())),
        (None, None, Some(file_descriptor)) => {
            #[cfg(target_os = "android")]
            {
                Ok(relay_core::model::transfer::FileContent::Fd(
                    file_descriptor,
                ))
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = file_descriptor;
                Err(RsHttpClientError::Other(
                    "File descriptors are only supported on Android".into(),
                ))
            }
        }
        _ => Err(RsHttpClientError::Other(
            "Exactly one upload content source must be provided".into(),
        )),
    }
}

/// Progress of a mutual Relay LAN pairing attempt.
///
/// Flutter never sees a private key, a nonce, or proof bytes: it sees the
/// verification code to display and the terminal result. Only
/// [RsRelayLanPairingEvent::Paired] may be persisted, and the RelayId it
/// carries is the **proven** one.
pub enum RsRelayLanPairingEvent {
    /// Both identities are proven and the remote user is being asked. Show this
    /// code so both people can confirm they are looking at the same pairing.
    VerificationCode {
        code: String,
        remote_relay_id: String,
    },
    /// The remote user accepted. This is the only outcome that establishes a
    /// relationship, and it still grants no capability.
    Paired {
        remote_relay_id: String,
        remote_alias: String,
        verification_code: String,
    },
    /// The remote user rejected. Nothing may be stored.
    Declined,
    /// The peer does not support Relay pairing.
    Unsupported,
    /// The peer is already showing a pairing prompt for another device.
    Busy,
    /// An identity proof was missing, wrong, or not the identity we demanded.
    AuthenticationFailed,
    /// The exchange did not complete. Nothing about identity may be inferred.
    TransportFailed,
}

impl From<RelayLanPairingOutcome> for RsRelayLanPairingEvent {
    fn from(value: RelayLanPairingOutcome) -> Self {
        match value {
            RelayLanPairingOutcome::Paired {
                remote_relay_id,
                remote_alias,
                verification_code,
            } => Self::Paired {
                remote_relay_id,
                remote_alias,
                verification_code,
            },
            RelayLanPairingOutcome::Declined => Self::Declined,
            RelayLanPairingOutcome::Unsupported => Self::Unsupported,
            RelayLanPairingOutcome::Busy => Self::Busy,
            RelayLanPairingOutcome::AuthenticationFailed => Self::AuthenticationFailed,
            RelayLanPairingOutcome::TransportFailed => Self::TransportFailed,
        }
    }
}

/// Runs the mutual Relay LAN pairing handshake against a discovered device.
///
/// `certificate_fingerprint` pins *which socket* is spoken to. It is not an
/// identity: the peer still has to produce a Server-role proof over that exact
/// certificate, and this device still has to produce a Client-role proof over
/// its own, before the remote user is asked anything.
///
/// `expected_relay_id`, when given, is the identity the user targeted. A peer
/// that proves a different one is a hard failure rather than a new device.
#[allow(clippy::too_many_arguments)]
pub async fn relay_lan_pair(
    sink: StreamSink<RsRelayLanPairingEvent>,
    private_key_pem: Vec<u8>,
    relay_id: String,
    client_private_key: String,
    client_certificate: String,
    version: LsHttpClientVersion,
    protocol: ProtocolType,
    ip: String,
    port: u16,
    certificate_fingerprint: String,
    alias: String,
    expected_relay_id: Option<String>,
) {
    let identity = match load_pairing_identity(&private_key_pem, &relay_id) {
        Ok(identity) => identity,
        Err(event) => {
            let _ = sink.add(event);
            return;
        }
    };
    let expected = match expected_relay_id
        .as_deref()
        .map(relay_core::relay::RelayId::from_expected_canonical_hex)
        .transpose()
    {
        Ok(expected) => expected,
        Err(_) => {
            let _ = sink.add(RsRelayLanPairingEvent::AuthenticationFailed);
            return;
        }
    };

    let (event_tx, mut event_rx) = tokio::sync::mpsc::channel(8);
    // The sender is owned by the pairing future so it is dropped exactly when
    // the handshake ends, which is what closes the forwarding loop below.
    let pairing = async move {
        let event_tx = event_tx;
        relay_core::http::client::pair_relay_lan_device(
            &client_private_key,
            &client_certificate,
            version,
            protocol,
            &ip,
            port,
            &certificate_fingerprint,
            &identity,
            &alias,
            expected.as_ref(),
            &event_tx,
        )
        .await;
    };

    let forward = async {
        while let Some(event) = event_rx.recv().await {
            let mapped = match event {
                relay_core::http::client::relay::RelayLanPairingEvent::VerificationCode {
                    code,
                    remote_relay_id,
                } => RsRelayLanPairingEvent::VerificationCode {
                    code,
                    remote_relay_id,
                },
                relay_core::http::client::relay::RelayLanPairingEvent::Outcome(outcome) => {
                    outcome.into()
                }
            };
            if sink.add(mapped).is_err() {
                break;
            }
        }
    };

    tokio::join!(pairing, forward);
}

/// Loads the local Relay identity for pairing and checks it against the
/// RelayId the caller believes it holds, so a mismatched key never signs.
fn load_pairing_identity(
    private_key_pem: &[u8],
    relay_id: &str,
) -> Result<relay_core::crypto::relay_identity::RelayIdentity, RsRelayLanPairingEvent> {
    let pem = std::str::from_utf8(private_key_pem)
        .map_err(|_| RsRelayLanPairingEvent::AuthenticationFailed)?;
    let identity = relay_core::crypto::relay_identity::RelayIdentity::from_private_key(pem)
        .map_err(|_| RsRelayLanPairingEvent::AuthenticationFailed)?;
    let own = identity
        .relay_id()
        .map_err(|_| RsRelayLanPairingEvent::AuthenticationFailed)?;
    if own != relay_id {
        return Err(RsRelayLanPairingEvent::AuthenticationFailed);
    }
    Ok(identity)
}

/// An event emitted while a file is being uploaded by [RsHttpClient::upload].
#[derive(Clone)]
pub enum RsUploadEvent {
    /// The upload progress as a fraction (0.0 to 1.0). Throttled.
    Progress { progress: f64 },

    /// The upload failed. Always the last event of the stream.
    Failed { error: RsHttpClientError },
}

#[derive(Clone)]
pub enum RsHttpClientError {
    StatusCode {
        status: u16,
        message: Option<String>,
    },
    Reqwest(String),
    Json(String),
    Io(String),
    Other(String),
}

/// Relay proof authentication result for the app send path. The TLS
/// fingerprint remains in Rust; only the public RelayId is returned on
/// successful authentication.
#[derive(Clone)]
pub enum RsRelayPeerAuth {
    NotAttempted,
    Unsupported,
    TransportUnauthenticated,
    SignerUnavailable,
    Malformed,
    RoleMismatch,
    ChallengeMismatch,
    CryptoInvalid,
    Authenticated { relay_id: String },
}

impl From<RelayPeerAuth> for RsRelayPeerAuth {
    fn from(value: RelayPeerAuth) -> Self {
        match value {
            RelayPeerAuth::NotAttempted => Self::NotAttempted,
            RelayPeerAuth::Unsupported => Self::Unsupported,
            RelayPeerAuth::TransportUnauthenticated => Self::TransportUnauthenticated,
            RelayPeerAuth::SignerUnavailable => Self::SignerUnavailable,
            RelayPeerAuth::Malformed => Self::Malformed,
            RelayPeerAuth::RoleMismatch => Self::RoleMismatch,
            RelayPeerAuth::ChallengeMismatch => Self::ChallengeMismatch,
            RelayPeerAuth::CryptoInvalid => Self::CryptoInvalid,
            RelayPeerAuth::Authenticated { relay_id, .. } => Self::Authenticated { relay_id },
        }
    }
}

impl From<ClientError> for RsHttpClientError {
    fn from(e: ClientError) -> Self {
        match e {
            ClientError::StatusCode(e) => RsHttpClientError::StatusCode {
                status: e.status,
                message: e.message,
            },
            ClientError::Reqwest(e) => RsHttpClientError::Reqwest(ErrorChain(&e).to_string()),
            ClientError::Json(e) => RsHttpClientError::Json(e.to_string()),
            ClientError::Io(e) => RsHttpClientError::Io(e.to_string()),
            ClientError::Other(e) => RsHttpClientError::Other(e.to_string()),
            ClientError::Cancelled => RsHttpClientError::Other("Upload cancelled".to_string()),
        }
    }
}

#[frb(mirror(LsHttpClientVersion))]
pub enum _LsHttpClientVersion {
    V2,
    V3,
}

#[frb(mirror(PrepareUploadResult))]
pub struct _PrepareUploadResult {
    pub status_code: u16,
    pub response: Option<PrepareUploadResponseDto>,
}

pub struct ResultWithPublicKeyRegisterResponseDto {
    pub public_key: Option<String>,
    pub body: RegisterResponseDto,
}
