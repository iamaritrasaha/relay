#![cfg(feature = "full")]

use bytes::Bytes;
use relay_core::crypto::relay_identity::RelayIdentity;
use relay_core::crypto::relay_identity_proof::{create_relay_identity_proof, RelayProofRole};
use relay_core::http::client::AnywhereHttpClient;
use relay_core::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use relay_core::http::server::common::save::FileUploadTarget;
use relay_core::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use relay_core::http::server::{start_with_port, ConnectionOrigin, ServerConfigV2};
use relay_core::http::state::ClientInfo as ServerInfo;
use relay_core::model::discovery::ProtocolType;
use relay_core::model::transfer::{FileContent, FileDto};
use relay_core::relay::{AuthenticatedRelaySession, PathDescriptor, RelayAuthCoordinator};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::io;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::{mpsc, oneshot};
use tokio_util::sync::CancellationToken;

/// Records the first application bytes consumed by the Anywhere HTTP server
/// without altering the caller-owned stream semantics.
struct CaptureFirstRead<S> {
    inner: S,
    captured: Arc<std::sync::Mutex<Vec<u8>>>,
}

impl<S: AsyncRead + Unpin> AsyncRead for CaptureFirstRead<S> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let result = Pin::new(&mut self.inner).poll_read(cx, buf);
        if let Poll::Ready(Ok(())) = &result {
            let bytes = buf.filled();
            if !bytes.is_empty() {
                let mut captured = self.captured.lock().unwrap();
                if captured.is_empty() {
                    captured.extend_from_slice(bytes);
                }
            }
        }
        result
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for CaptureFirstRead<S> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

fn session() -> AuthenticatedRelaySession {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof =
        create_relay_identity_proof(&remote, RelayProofRole::Client, [0x21; 32], [0x22; 32])
            .unwrap();
    RelayAuthCoordinator::new(relay_core::relay::RelayId::from_local_identity(&local).unwrap())
        .complete_anywhere_responder(
            &proof,
            [0x22; 32],
            None,
            PathDescriptor::IrohRelay {
                hint: Some("test".into()),
            },
        )
        .unwrap()
}

async fn server(
    events: mpsc::Sender<ServerEventV2>,
) -> (relay_core::http::server::ServerHandle, oneshot::Sender<()>) {
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = start_with_port(
        0,
        None,
        ServerInfo {
            alias: "Anywhere receiver".into(),
            version: "2.2".into(),
            device_model: None,
            device_type: None,
            token: "test".into(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            verify_checksums: true,
            event_tx: events,
        }),
        None,
        stop_rx,
    )
    .await
    .unwrap();
    (handle, stop_tx)
}

fn payload(file: &FileDto) -> PrepareUploadRequestDtoV2 {
    PrepareUploadRequestDtoV2 {
        info: RegisterDtoV2 {
            alias: "Android".into(),
            version: "2.2".into(),
            device_model: None,
            device_type: None,
            fingerprint: "claimed-token".into(),
            port: 0,
            protocol: ProtocolType::Https,
            download: false,
        },
        files: HashMap::from([(file.id.clone(), file.clone())]),
    }
}

#[tokio::test]
async fn anywhere_uses_existing_v2_prepare_and_streaming_save_on_a_non_tcp_stream() {
    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (server, stop_tx) = server(event_tx).await;
    let (client_stream, server_stream) = tokio::io::duplex(64 * 1024);
    let first_application_bytes = Arc::new(std::sync::Mutex::new(Vec::new()));
    let auth = session();
    server
        .serve_authenticated_stream(
            CaptureFirstRead {
                inner: server_stream,
                captured: first_application_bytes.clone(),
            },
            auth.clone(),
            ConnectionOrigin::IrohRelay,
        )
        .await
        .unwrap();
    let client = AnywhereHttpClient::handshake(client_stream, auth)
        .await
        .unwrap();

    let data = Bytes::from_static(b"relay anywhere file body");
    let content_length = data.len() as u64;
    let hash = relay_core::crypto::hash::sha256_hex(&data);
    let file = FileDto {
        id: "one".into(),
        file_name: "one.txt".into(),
        size: data.len() as u64,
        file_type: "text".into(),
        sha256: Some(hash),
        preview: None,
        metadata: None,
    };

    let prepare = {
        let mut client = client;
        let payload = payload(&file);
        tokio::spawn(async move {
            client
                .prepare_upload(payload, None, CancellationToken::new())
                .await
                .map(|result| (client, result))
        })
    };
    let event = event_rx.recv().await.expect("prepare event");
    assert_eq!(
        first_application_bytes.lock().unwrap().first().copied(),
        Some(b'P'),
        "the RA4 client must start normal HTTP POST; the legacy proof decoder must not consume it"
    );
    let (decision_tx, file_id) = match event {
        ServerEventV2::PrepareUpload {
            session_id: _,
            ip,
            authenticated_relay_id,
            files,
            decision_tx,
            ..
        } => {
            assert!(ip.is_none(), "relay must not fabricate a PeerIp");
            assert!(authenticated_relay_id.is_some());
            assert_eq!(files["one"].file_name, "one.txt");
            (decision_tx, "one".to_owned())
        }
        other => panic!("unexpected event: {other:?}"),
    };
    decision_tx
        .send(PrepareUploadDecisionV2::Accept(HashSet::from([
            file_id.clone()
        ])))
        .unwrap();
    let (mut client, prepared) = prepare.await.unwrap().unwrap();
    let prepared = prepared.response.unwrap();
    let token = prepared.files[&file_id].clone();

    let path = temp_path("anywhere-transfer");
    let (target_tx, target_rx) = oneshot::channel();
    let (source_tx, source_rx) = mpsc::channel(2);
    source_tx.send(data.clone()).await.unwrap();
    drop(source_tx);
    let upload = tokio::spawn(async move {
        client
            .upload(
                &prepared.session_id,
                &file_id,
                &token,
                FileContent::Stream(source_rx),
                content_length,
                |_| {},
                CancellationToken::new(),
            )
            .await
    });
    let upload_event = event_rx.recv().await.expect("file upload event");
    match upload_event {
        ServerEventV2::FileUpload {
            target_tx: responder,
            ..
        } => {
            responder
                .send(FileUploadTarget::Path {
                    path: path.clone(),
                    result_tx: target_tx,
                    progress_tx: None,
                })
                .unwrap();
        }
        other => panic!("unexpected event: {other:?}"),
    }
    upload.await.unwrap().unwrap();
    assert_eq!(target_rx.await.unwrap(), Ok(()));
    assert_eq!(tokio::fs::read(&path).await.unwrap(), data);
    let _ = tokio::fs::remove_file(&path).await;

    let _ = stop_tx.send(());
    server.wait_stopped().await;
}

#[tokio::test]
async fn anywhere_decline_returns_before_body_and_keeps_route_surface_restricted() {
    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (server, stop_tx) = server(event_tx).await;
    let (client_stream, server_stream) = tokio::io::duplex(16 * 1024);
    let auth = session();
    server
        .serve_authenticated_stream(
            server_stream,
            auth.clone(),
            ConnectionOrigin::InternetDirect,
        )
        .await
        .unwrap();
    let mut client = AnywhereHttpClient::handshake(client_stream, auth)
        .await
        .unwrap();
    let file = FileDto {
        id: "one".into(),
        file_name: "one.bin".into(),
        size: 4,
        file_type: "file".into(),
        sha256: None,
        preview: None,
        metadata: None,
    };
    let request = tokio::spawn(async move {
        client
            .prepare_upload(payload(&file), None, CancellationToken::new())
            .await
    });
    let event = event_rx.recv().await.unwrap();
    if let ServerEventV2::PrepareUpload { decision_tx, .. } = event {
        decision_tx.send(PrepareUploadDecisionV2::Decline).unwrap();
    } else {
        panic!("expected prepare upload");
    }
    let result = request.await.unwrap();
    assert!(matches!(
        result,
        Err(relay_core::http::client::ClientError::StatusCode(_))
    ));
    let _ = stop_tx.send(());
    server.wait_stopped().await;
}

#[tokio::test]
async fn anywhere_http_cannot_start_with_a_non_mutual_lan_session() {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof =
        create_relay_identity_proof(&remote, RelayProofRole::Server, [0x31; 32], [0x32; 32])
            .unwrap();
    let expected = relay_core::relay::RelayId::from_local_identity(&remote).unwrap();
    let session =
        RelayAuthCoordinator::new(relay_core::relay::RelayId::from_local_identity(&local).unwrap())
            .complete_lan_initiator(
                &proof,
                [0x32; 32],
                None,
                PathDescriptor::lan("192.0.2.1", Some(443)),
            )
            .unwrap();
    assert!(!session.mutual());
    let (client_stream, _server_stream) = tokio::io::duplex(1024);
    let result = AnywhereHttpClient::handshake(client_stream, session).await;
    assert!(result.is_err());
    assert_eq!(expected.as_hex().len(), 64);
}

/// Exercises the real Anywhere Hyper request-body path with a source whose
/// bounded channel fills at 128 KiB (16 x 8 KiB). This mirrors a SAF provider
/// that yields small reads and guards against producer/consumer deadlocks.
#[tokio::test]
async fn anywhere_streams_small_source_chunks_past_the_128_kib_channel_window() {
    for size in [256 * 1024, 1024 * 1024, 16 * 1024 * 1024, 64 * 1024 * 1024] {
        let timeout = if size >= 64 * 1024 * 1024 {
            Duration::from_secs(60)
        } else {
            Duration::from_secs(20)
        };
        tokio::time::timeout(timeout, transfer_generated_chunks(size))
            .await
            .unwrap_or_else(|_| panic!("Anywhere transfer timed out at {size} bytes"));
    }
}

async fn transfer_generated_chunks(size: usize) {
    const CHUNK_SIZE: usize = 8 * 1024;
    let expected_sha256 = repeated_chunk_sha256(size, CHUNK_SIZE, 0x5a);

    let (event_tx, mut event_rx) = mpsc::channel(8);
    let (server, stop_tx) = server(event_tx).await;
    let (client_stream, server_stream) = tokio::io::duplex(64 * 1024);
    let auth = session();
    server
        .serve_authenticated_stream(server_stream, auth.clone(), ConnectionOrigin::IrohRelay)
        .await
        .unwrap();
    let client = AnywhereHttpClient::handshake(client_stream, auth)
        .await
        .unwrap();
    let file = FileDto {
        id: "streamed".into(),
        file_name: "streamed.bin".into(),
        size: size as u64,
        file_type: "file".into(),
        sha256: Some(expected_sha256.clone()),
        preview: None,
        metadata: None,
    };

    let prepare = tokio::spawn(async move {
        let mut client = client;
        let result = client
            .prepare_upload(payload(&file), None, CancellationToken::new())
            .await;
        (client, result)
    });
    let decision_tx = match event_rx.recv().await.expect("prepare event") {
        ServerEventV2::PrepareUpload { decision_tx, .. } => decision_tx,
        other => panic!("unexpected event: {other:?}"),
    };
    decision_tx
        .send(PrepareUploadDecisionV2::Accept(HashSet::from([
            "streamed".to_owned()
        ])))
        .unwrap();
    let (mut client, prepared) = prepare.await.unwrap();
    let prepared = prepared.unwrap().response.unwrap();
    let token = prepared.files["streamed"].clone();

    // The producer cannot get more than sixteen chunks ahead of Hyper. If the
    // request body stops being polled, it will stop exactly around 128 KiB.
    let (source_tx, source_rx) = mpsc::channel(16);
    let source_bytes = Arc::new(AtomicU64::new(0));
    let source_counter = source_bytes.clone();
    let producer = tokio::spawn(async move {
        let mut remaining = size;
        while remaining > 0 {
            let chunk_len = remaining.min(CHUNK_SIZE);
            source_tx
                .send(Bytes::from(vec![0x5a; chunk_len]))
                .await
                .unwrap();
            source_counter.fetch_add(chunk_len as u64, Ordering::Relaxed);
            remaining -= chunk_len;
        }
    });
    let body_bytes = Arc::new(AtomicU64::new(0));
    let body_counter = body_bytes.clone();
    let upload = tokio::spawn(async move {
        client
            .upload(
                &prepared.session_id,
                "streamed",
                &token,
                FileContent::Stream(source_rx),
                size as u64,
                move |bytes| body_counter.store(bytes, Ordering::Relaxed),
                CancellationToken::new(),
            )
            .await
    });
    let path = temp_path("anywhere-small-chunks");
    let (target_tx, target_rx) = oneshot::channel();
    match event_rx.recv().await.expect("file upload event") {
        ServerEventV2::FileUpload {
            target_tx: responder,
            ..
        } => responder
            .send(FileUploadTarget::Path {
                path: path.clone(),
                result_tx: target_tx,
                progress_tx: None,
            })
            .unwrap(),
        other => panic!("unexpected event: {other:?}"),
    }
    producer.await.unwrap();
    upload.await.unwrap().unwrap();
    assert_eq!(
        source_bytes.load(Ordering::Relaxed),
        size as u64,
        "source bytes"
    );
    assert_eq!(
        body_bytes.load(Ordering::Relaxed),
        size as u64,
        "Hyper body bytes"
    );
    assert_eq!(target_rx.await.unwrap(), Ok(()));
    assert_eq!(
        tokio::fs::metadata(&path).await.unwrap().len(),
        size as u64,
        "saved bytes"
    );
    assert_eq!(
        relay_core::crypto::hash::sha256_file_content(
            FileContent::Path(path.clone()),
            &CancellationToken::new(),
            |_| {}
        )
        .await
        .unwrap(),
        expected_sha256,
        "saved SHA-256"
    );
    let _ = tokio::fs::remove_file(&path).await;
    let _ = stop_tx.send(());
    server.wait_stopped().await;
}

/// Calculates the expected digest without allocating the generated payload.
fn repeated_chunk_sha256(size: usize, chunk_size: usize, byte: u8) -> String {
    let chunk = vec![byte; chunk_size];
    let mut remaining = size;
    let mut hasher = Sha256::new();
    while remaining > 0 {
        let length = remaining.min(chunk.len());
        hasher.update(&chunk[..length]);
        remaining -= length;
    }
    hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn temp_path(prefix: &str) -> PathBuf {
    std::env::temp_dir().join(format!("{prefix}-{}", uuid::Uuid::new_v4()))
}
