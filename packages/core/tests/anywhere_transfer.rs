#![cfg(feature = "full")]

use bytes::Bytes;
use localsend::crypto::relay_identity::RelayIdentity;
use localsend::crypto::relay_identity_proof::{create_relay_identity_proof, RelayProofRole};
use localsend::http::client::AnywhereHttpClient;
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, RegisterDtoV2};
use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use localsend::http::server::{start_with_port, ConnectionOrigin, ServerConfigV2};
use localsend::http::state::ClientInfo as ServerInfo;
use localsend::model::discovery::ProtocolType;
use localsend::model::transfer::{FileContent, FileDto};
use localsend::relay::{AuthenticatedRelaySession, PathDescriptor, RelayAuthCoordinator};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use tokio::sync::{mpsc, oneshot};
use tokio_util::sync::CancellationToken;

fn session() -> AuthenticatedRelaySession {
    let local = RelayIdentity::generate();
    let remote = RelayIdentity::generate();
    let proof =
        create_relay_identity_proof(&remote, RelayProofRole::Client, [0x21; 32], [0x22; 32])
            .unwrap();
    RelayAuthCoordinator::new(localsend::relay::RelayId::from_local_identity(&local).unwrap())
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
) -> (localsend::http::server::ServerHandle, oneshot::Sender<()>) {
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
    let auth = session();
    server
        .serve_authenticated_stream(server_stream, auth.clone(), ConnectionOrigin::IrohRelay)
        .await
        .unwrap();
    let client = AnywhereHttpClient::handshake(client_stream, auth)
        .await
        .unwrap();

    let data = Bytes::from_static(b"relay anywhere file body");
    let content_length = data.len() as u64;
    let hash = localsend::crypto::hash::sha256_hex(&data);
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
        Err(localsend::http::client::ClientError::StatusCode(_))
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
    let expected = localsend::relay::RelayId::from_local_identity(&remote).unwrap();
    let session =
        RelayAuthCoordinator::new(localsend::relay::RelayId::from_local_identity(&local).unwrap())
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

fn temp_path(prefix: &str) -> PathBuf {
    std::env::temp_dir().join(format!("{prefix}-{}", uuid::Uuid::new_v4()))
}
