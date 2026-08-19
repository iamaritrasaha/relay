//! Production bridge for the canonical Relay transfer engine.
//!
//! Flutter supplies UI-selected bounded sources and renders canonical events;
//! it does not implement prepare-upload, accepted-file, upload-loop, or
//! cancellation semantics.

use std::sync::Arc;

use bytes::Bytes;
use tokio::sync::mpsc;

use crate::api::cancel::RsCancellationToken;
use crate::api::http::RsHttpClient;
use crate::api::model::{FileDto, RegisterDto};
use crate::frb_generated::StreamSink;
use relay_core::model::discovery::ProtocolType;
use relay_core::model::transfer::FileContent;
use relay_core::relay::{
    PinnedLanTransferTransport, RelayTransferEngine, RelayTransferEvent, RelayTransferFile,
    RelayTransferRequest, TransportOrigin,
};

/// The only in-memory source accepted by the bridge.  Native large files use
/// a filesystem path or Android descriptor; this guard preserves the
/// application's bounded streaming contract for share-sheet text payloads.
const MAX_INLINE_SOURCE_BYTES: usize = 1024 * 1024;

/// One UI-selected file passed into the canonical engine.
#[derive(Clone, Debug)]
pub struct RsRelayTransferFile {
    pub file: FileDto,
    pub path: Option<String>,
    pub file_descriptor: Option<i32>,
    pub bytes: Option<Vec<u8>>,
}

/// Canonical production event exposed to Flutter.  The event intentionally
/// has no LAN/Anywhere-specific variants.
#[derive(Clone, Debug)]
pub enum RsRelayTransferEvent {
    OutgoingStarted {
        transfer_id: String,
        total_bytes: u64,
        origin: String,
    },
    Accepted {
        transfer_id: String,
        session_id: String,
        accepted_file_ids: Vec<String>,
        total_bytes: u64,
        origin: String,
    },
    Declined {
        transfer_id: String,
        file_id: Option<String>,
        origin: String,
    },
    FileStarted {
        transfer_id: String,
        session_id: String,
        file_id: String,
        file_name: String,
        file_index: u32,
        file_count: u32,
        total_bytes: u64,
        origin: String,
    },
    FileProgress {
        transfer_id: String,
        session_id: String,
        file_id: String,
        bytes: u64,
        total_bytes: u64,
        origin: String,
    },
    OverallProgress {
        transfer_id: String,
        session_id: String,
        bytes: u64,
        total_bytes: u64,
        origin: String,
    },
    Completed {
        transfer_id: String,
        session_id: Option<String>,
        bytes: u64,
        origin: String,
    },
    Failed {
        transfer_id: String,
        category: String,
    },
    Cancelled {
        transfer_id: String,
    },
}

/// Runs one LAN transfer through the canonical engine using the caller-owned
/// certificate-pinned client.  The client is never recreated, so a prior
/// verified Relay proof and the file bytes share the same TLS pin.
#[allow(clippy::too_many_arguments)]
pub async fn relay_transfer_send_lan(
    client: &RsHttpClient,
    protocol: ProtocolType,
    ip: String,
    port: u16,
    transfer_id: String,
    info: RegisterDto,
    files: Vec<RsRelayTransferFile>,
    pin: Option<String>,
    cancel_token: &RsCancellationToken,
    event_sink: StreamSink<RsRelayTransferEvent>,
) {
    let transfer_id_for_failure = transfer_id.clone();
    let result = async {
        let request = RelayTransferRequest {
            transfer_id,
            info: info.into(),
            files: files
                .into_iter()
                .map(relay_transfer_file)
                .collect::<Result<Vec<_>, String>>()?,
            pin,
        };
        let sink = event_sink.clone();
        let events = Arc::new(move |event| {
            let _ = sink.add(map_event(event));
        });
        RelayTransferEngine
            .send(
                &mut PinnedLanTransferTransport::new(&client.inner, protocol, &ip, port),
                request,
                TransportOrigin::Local,
                cancel_token.inner.clone(),
                events,
            )
            .await
            .map(|_| ())
            .map_err(|error| error.to_string())
    }
    .await;

    if let Err(message) = result {
        let _ = event_sink.add(RsRelayTransferEvent::Failed {
            transfer_id: transfer_id_for_failure,
            category: canonical_error_category(&message),
        });
    }
}

fn relay_transfer_file(file: RsRelayTransferFile) -> Result<RelayTransferFile, String> {
    let content = match (file.path, file.file_descriptor, file.bytes) {
        (Some(path), None, None) => FileContent::Path(path.into()),
        (None, Some(descriptor), None) => {
            #[cfg(target_os = "android")]
            {
                FileContent::Fd(descriptor)
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = descriptor;
                return Err(
                    "Android file descriptors are not available on this platform".to_owned(),
                );
            }
        }
        (None, None, Some(bytes)) if bytes.len() <= MAX_INLINE_SOURCE_BYTES => {
            if bytes.len() as u64 != file.file.size {
                return Err("inline source size does not match transfer metadata".to_owned());
            }
            let (sender, receiver) = mpsc::channel(1);
            sender
                .try_send(Bytes::from(bytes))
                .map_err(|_| "could not stage inline transfer source".to_owned())?;
            FileContent::Stream(receiver)
        }
        (None, None, Some(_)) => {
            return Err("large files must use a streaming path or Android descriptor".to_owned());
        }
        _ => return Err("exactly one transfer source must be provided".to_owned()),
    };
    Ok(RelayTransferFile {
        dto: file.file,
        content,
    })
}

fn map_event(event: RelayTransferEvent) -> RsRelayTransferEvent {
    match event {
        RelayTransferEvent::OutgoingStarted {
            transfer_id,
            total_bytes,
            origin,
        } => RsRelayTransferEvent::OutgoingStarted {
            transfer_id,
            total_bytes,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::Accepted {
            transfer_id,
            session_id,
            accepted_files,
            total_bytes,
            origin,
        } => RsRelayTransferEvent::Accepted {
            transfer_id,
            session_id,
            accepted_file_ids: accepted_files,
            total_bytes,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::Declined {
            transfer_id,
            file_id,
            origin,
        } => RsRelayTransferEvent::Declined {
            transfer_id,
            file_id,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::FileStarted {
            transfer_id,
            session_id,
            file_id,
            file_name,
            file_index,
            file_count,
            total_bytes,
            origin,
        } => RsRelayTransferEvent::FileStarted {
            transfer_id,
            session_id,
            file_id,
            file_name,
            file_index: file_index as u32,
            file_count: file_count as u32,
            total_bytes,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::FileProgress {
            transfer_id,
            session_id,
            file_id,
            bytes,
            total_bytes,
            origin,
        } => RsRelayTransferEvent::FileProgress {
            transfer_id,
            session_id,
            file_id,
            bytes,
            total_bytes,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::OverallProgress {
            transfer_id,
            session_id,
            bytes,
            total_bytes,
            origin,
        } => RsRelayTransferEvent::OverallProgress {
            transfer_id,
            session_id,
            bytes,
            total_bytes,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::Completed {
            transfer_id,
            session_id,
            bytes,
            origin,
        } => RsRelayTransferEvent::Completed {
            transfer_id,
            session_id,
            bytes,
            origin: origin_label(origin).to_owned(),
        },
        RelayTransferEvent::Failed { transfer_id, .. } => RsRelayTransferEvent::Failed {
            transfer_id,
            category: "transfer_failed".to_owned(),
        },
        RelayTransferEvent::Cancelled { transfer_id, .. } => {
            RsRelayTransferEvent::Cancelled { transfer_id }
        }
    }
}

fn origin_label(origin: TransportOrigin) -> &'static str {
    match origin {
        TransportOrigin::Local => "local",
        TransportOrigin::InternetDirect => "direct",
        TransportOrigin::IrohRelay => "relayed",
    }
}

fn canonical_error_category(message: &str) -> String {
    if message.contains("cancelled") {
        "cancelled".to_owned()
    } else if message.contains("denied") {
        "declined".to_owned()
    } else if message.contains("PIN") {
        "pin_required".to_owned()
    } else {
        "transfer_failed".to_owned()
    }
}
