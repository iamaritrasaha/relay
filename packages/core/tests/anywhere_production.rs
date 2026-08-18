//! Production Anywhere orchestration, exercised through `localsend::anywhere`
//! only. Nothing here links the development RA2B crate.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use localsend::anywhere::AnywhereError;
use localsend::anywhere::{
    AnywhereBatch, AnywhereDecision, AnywhereEvent, AnywhereFileSource, AnywhereFileSpec,
    AnywhereIdentity, AnywhereOutcome, AnywherePathClass, AnywhereReceiveRequest, AnywhereRuntime,
    AnywhereSendRequest, PathPreference, RelayAddressV1, authenticate_address, receive, send_batch,
};
use localsend::crypto::relay_identity::RelayIdentity;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

fn temp_path(prefix: &str) -> PathBuf {
    let unique = format!(
        "{prefix}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    std::env::temp_dir().join(unique)
}

fn identity() -> AnywhereIdentity {
    AnywhereIdentity::from_identity(RelayIdentity::generate()).unwrap()
}

fn file_spec(path: &std::path::Path, size: u64) -> AnywhereFileSpec {
    AnywhereFileSpec {
        id: "file-1".to_owned(),
        name: path.file_name().unwrap().to_string_lossy().into_owned(),
        size,
        file_type: "application/octet-stream".to_owned(),
        sha256: None,
        source: AnywhereFileSource::Path(path.to_path_buf()),
    }
}

/// Collects events and forwards inbound requests so a test can answer them.
struct Recorder {
    events: Arc<Mutex<Vec<String>>>,
    incoming_tx: mpsc::UnboundedSender<(localsend::anywhere::IncomingTransferId, u64)>,
    address_tx: Arc<Mutex<Option<tokio::sync::oneshot::Sender<String>>>>,
}

impl Recorder {
    fn sink(self) -> localsend::anywhere::AnywhereEventSink {
        Arc::new(move |event: AnywhereEvent| {
            self.events
                .lock()
                .unwrap()
                .push(format!("{:?}", std::mem::discriminant(&event)));
            match event {
                AnywhereEvent::EndpointReady { address, .. } => {
                    if let Some(tx) = self.address_tx.lock().unwrap().take() {
                        let _ = tx.send(address);
                    }
                }
                AnywhereEvent::IncomingBatch {
                    transfer_id, files, ..
                } => {
                    let total = files.iter().map(|file| file.size).sum();
                    let _ = self.incoming_tx.send((transfer_id, total));
                }
                _ => {}
            }
        })
    }
}

struct Receiver {
    session: localsend::anywhere::AnywhereSessionId,
    cancel: CancellationToken,
    address: String,
    incoming: mpsc::UnboundedReceiver<(localsend::anywhere::IncomingTransferId, u64)>,
    join: tokio::task::JoinHandle<Result<AnywhereOutcome, AnywhereError>>,
    relay_id: String,
}

async fn start_receiver(runtime: Arc<AnywhereRuntime>) -> Receiver {
    let identity = identity();
    let relay_id = identity.relay_id().to_owned();
    let (session, cancel) = runtime.open_session();
    let (address_tx, address_rx) = tokio::sync::oneshot::channel();
    let (incoming_tx, incoming) = mpsc::unbounded_channel();
    let sink = Recorder {
        events: Arc::new(Mutex::new(Vec::new())),
        incoming_tx,
        address_tx: Arc::new(Mutex::new(Some(address_tx))),
    }
    .sink();

    let join = tokio::spawn(receive(
        runtime.clone(),
        session,
        cancel.clone(),
        AnywhereReceiveRequest {
            identity,
            preference: PathPreference::ForceDirect,
            alias: "Relay".to_owned(),
            expected_remote_relay_id: None,
        },
        sink,
    ));
    let address = tokio::time::timeout(std::time::Duration::from_secs(30), address_rx)
        .await
        .expect("receiver published an address")
        .expect("address channel stayed open");

    Receiver {
        session,
        cancel,
        address,
        incoming,
        join,
        relay_id,
    }
}

fn silent_sink() -> localsend::anywhere::AnywhereEventSink {
    Arc::new(|_event| {})
}

async fn send_to(
    address: &str,
    path: &std::path::Path,
    size: u64,
) -> Result<AnywhereOutcome, AnywhereError> {
    let (_session, cancel) = AnywhereRuntime::new().open_session();
    send_batch(
        localsend::anywhere::AnywhereSessionId::from_u64(1),
        cancel,
        AnywhereSendRequest {
            identity: identity(),
            remote: RelayAddressV1::decode(address).unwrap(),
            preference: PathPreference::ForceDirect,
            alias: "Relay".to_owned(),
            batch: AnywhereBatch {
                files: vec![file_spec(path, size)],
            },
        },
        silent_sink(),
    )
    .await
}

#[tokio::test(flavor = "multi_thread")]
async fn production_api_moves_a_real_file_without_the_development_harness() {
    let runtime = Arc::new(AnywhereRuntime::new());
    let mut receiver = start_receiver(runtime.clone()).await;

    let source = temp_path("relay-anywhere-src");
    let payload = vec![7_u8; 256 * 1024];
    std::fs::write(&source, &payload).unwrap();
    let target = temp_path("relay-anywhere-dst");

    let address = receiver.address.clone();
    let source_for_send = source.clone();
    let sender =
        tokio::spawn(
            async move { send_to(&address, &source_for_send, payload.len() as u64).await },
        );

    let (transfer_id, total) = receiver.incoming.recv().await.expect("inbound request");
    assert_eq!(total, 256 * 1024);
    runtime
        .respond(
            receiver.session,
            transfer_id,
            AnywhereDecision {
                accept: true,
                targets: HashMap::from([("file-1".to_owned(), target.clone())]),
            },
        )
        .unwrap();

    let sent = sender.await.unwrap().expect("send succeeded");
    let received = receiver.join.await.unwrap().expect("receive succeeded");

    assert_eq!(sent.bytes, 256 * 1024);
    assert_eq!(received.bytes, 256 * 1024);
    assert_eq!(received.path, AnywherePathClass::Direct);
    assert_eq!(sent.remote_relay_id, receiver.relay_id);
    assert_eq!(std::fs::read(&target).unwrap(), vec![7_u8; 256 * 1024]);

    runtime.close_session(receiver.session);
    let _ = std::fs::remove_file(&source);
    let _ = std::fs::remove_file(&target);
}

#[tokio::test(flavor = "multi_thread")]
async fn two_inbound_sessions_are_approved_and_declined_independently() {
    let runtime = Arc::new(AnywhereRuntime::new());
    let mut accepted = start_receiver(runtime.clone()).await;
    let mut declined = start_receiver(runtime.clone()).await;
    assert_ne!(accepted.session, declined.session);
    assert_eq!(runtime.open_session_count(), 2);

    let source = temp_path("relay-anywhere-multi-src");
    std::fs::write(&source, vec![3_u8; 4096]).unwrap();
    let target = temp_path("relay-anywhere-multi-dst");

    let accept_address = accepted.address.clone();
    let decline_address = declined.address.clone();
    let source_a = source.clone();
    let source_b = source.clone();
    let sender_a = tokio::spawn(async move { send_to(&accept_address, &source_a, 4096).await });
    let sender_b = tokio::spawn(async move { send_to(&decline_address, &source_b, 4096).await });

    let (accept_id, _) = accepted.incoming.recv().await.expect("first inbound");
    let (decline_id, _) = declined.incoming.recv().await.expect("second inbound");

    // Declining one session must not affect the other's pending approval.
    runtime
        .respond(declined.session, decline_id, AnywhereDecision::decline())
        .unwrap();
    assert!(runtime.is_open(accepted.session));
    assert!(!accepted.cancel.is_cancelled());

    runtime
        .respond(
            accepted.session,
            accept_id,
            AnywhereDecision {
                accept: true,
                targets: HashMap::from([("file-1".to_owned(), target.clone())]),
            },
        )
        .unwrap();

    let accepted_outcome = accepted.join.await.unwrap().expect("accepted transfer ran");
    assert_eq!(accepted_outcome.bytes, 4096);
    assert_eq!(std::fs::read(&target).unwrap().len(), 4096);

    let declined_result = declined.join.await.unwrap();
    assert!(matches!(
        declined_result,
        Err(AnywhereError::AuthorizationDenied)
    ));
    assert!(sender_a.await.unwrap().is_ok());
    assert!(sender_b.await.unwrap().is_err());

    // Closing one handle leaves the other registry entry alone.
    assert!(runtime.close_session(accepted.session));
    assert!(runtime.is_open(declined.session));

    let _ = std::fs::remove_file(&source);
    let _ = std::fs::remove_file(&target);
}

#[tokio::test(flavor = "multi_thread")]
async fn cancelling_one_session_leaves_a_second_receiver_waiting() {
    let runtime = Arc::new(AnywhereRuntime::new());
    let cancelled = start_receiver(runtime.clone()).await;
    let untouched = start_receiver(runtime.clone()).await;

    assert!(runtime.cancel(cancelled.session));
    let result = cancelled.join.await.unwrap();
    assert!(matches!(result, Err(AnywhereError::Cancelled)));

    assert!(!untouched.join.is_finished());
    assert!(!untouched.cancel.is_cancelled());
    runtime.cancel(untouched.session);
    let _ = untouched.join.await;
}

#[tokio::test]
async fn wrong_expected_relay_id_fails_before_any_transfer() {
    let runtime = Arc::new(AnywhereRuntime::new());
    let receiver = start_receiver(runtime.clone()).await;

    let mut address = RelayAddressV1::decode(&receiver.address).unwrap();
    address.claimed_relay_id = AnywhereIdentity::from_identity(RelayIdentity::generate())
        .unwrap()
        .relay_id()
        .to_owned();

    let source = temp_path("relay-anywhere-mismatch");
    std::fs::write(&source, vec![1_u8; 16]).unwrap();

    let (_session, cancel) = runtime.open_session();
    let result = send_batch(
        localsend::anywhere::AnywhereSessionId::from_u64(2),
        cancel,
        AnywhereSendRequest {
            identity: identity(),
            remote: address,
            preference: PathPreference::ForceDirect,
            alias: "Relay".to_owned(),
            batch: AnywhereBatch {
                files: vec![file_spec(&source, 16)],
            },
        },
        silent_sink(),
    )
    .await;

    assert!(matches!(
        result,
        Err(AnywhereError::ExpectedIdentityMismatch { .. }) | Err(AnywhereError::RelayProof)
    ));

    runtime.cancel(receiver.session);
    let _ = receiver.join.await;
    let _ = std::fs::remove_file(&source);
}

#[tokio::test(flavor = "multi_thread")]
async fn pairing_authenticates_the_claimed_relay_id_without_transferring_a_payload() {
    let runtime = Arc::new(AnywhereRuntime::new());
    let receiver = start_receiver(runtime.clone()).await;
    let pairing_runtime = AnywhereRuntime::new();
    let (session, cancel) = pairing_runtime.open_session();

    let outcome = authenticate_address(
        session,
        cancel,
        AnywhereSendRequest {
            identity: identity(),
            remote: RelayAddressV1::decode(&receiver.address).unwrap(),
            preference: PathPreference::ForceDirect,
            alias: "Relay".to_owned(),
            batch: AnywhereBatch { files: vec![] },
        },
        silent_sink(),
    )
    .await
    .expect("pairing proof succeeds");

    assert_eq!(outcome.remote_relay_id, receiver.relay_id);
    assert_eq!(outcome.bytes, 0);
    runtime.cancel(receiver.session);
    let _ = receiver.join.await;
}
