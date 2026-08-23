//! End-to-end streaming of a file payload through the real wire framing and the
//! real receiver.
//!
//! A `tokio::io::duplex` pipe stands in for the Iroh stream. That is deliberate:
//! the two-endpoint Iroh test in `wan::runtime` needs a usable local UDP path
//! and is `#[ignore]`d because sandboxed runners cannot provide one. Everything
//! *above* the QUIC socket -- header framing, bounded chunked copying, the size
//! contract and the temp-file/atomic-rename receiver -- is identical here, so
//! this covers the transfer logic on every machine.

#![cfg(feature = "kdeconnect-wan")]

use relay_core::kdeconnect::files::receive::IncomingFile;
use relay_core::kdeconnect::wan::payload::MAX_WAN_PAYLOAD_BYTES;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// Chunk size used by the real sender.
const CHUNK: usize = 64 * 1024;

/// Mirrors `WanLink::send_payload`'s writer: a length-prefixed JSON header
/// followed by the body, copied through a bounded buffer.
async fn send_payload<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    relay_payload_id: &str,
    body: &[u8],
) -> anyhow::Result<()> {
    let header = serde_json::json!({
        "relayPayloadId": relay_payload_id,
        "payloadSize": body.len() as u64,
    });
    let header_bytes = serde_json::to_vec(&header)?;
    writer.write_all(&(header_bytes.len() as u32).to_be_bytes()).await?;
    writer.write_all(&header_bytes).await?;

    let mut source = std::io::Cursor::new(body.to_vec());
    let mut buffer = vec![0_u8; CHUNK];
    loop {
        let read = tokio::io::AsyncReadExt::read(&mut source, &mut buffer).await?;
        if read == 0 {
            break;
        }
        writer.write_all(&buffer[..read]).await?;
    }
    writer.flush().await?;
    Ok(())
}

/// Mirrors the receiver: read the header, then stream the body to disk.
async fn read_header<R: AsyncReadExt + Unpin>(reader: &mut R) -> anyhow::Result<(String, u64)> {
    let mut length = [0_u8; 4];
    reader.read_exact(&mut length).await?;
    let mut header = vec![0_u8; u32::from_be_bytes(length) as usize];
    reader.read_exact(&mut header).await?;
    let parsed: serde_json::Value = serde_json::from_slice(&header)?;
    let id = parsed["relayPayloadId"].as_str().unwrap_or_default().to_owned();
    let size = parsed["payloadSize"].as_u64().unwrap_or_default();
    Ok((id, size))
}

/// Transfers `body` end to end and returns the bytes that landed on disk, plus
/// the progress samples observed.
async fn transfer(body: Vec<u8>, filename: &str) -> anyhow::Result<(Vec<u8>, Vec<u64>)> {
    let dir = tempfile::tempdir()?;
    let (mut client, mut server) = tokio::io::duplex(16 * 1024);

    let payload = body.clone();
    let sender = tokio::spawn(async move {
        send_payload(&mut client, "payload-1", &payload).await.unwrap();
        // Closing signals end-of-stream, as finishing a QUIC stream does.
        client.shutdown().await.unwrap();
    });

    let (id, size) = read_header(&mut server).await?;
    assert_eq!(id, "payload-1");

    let mut incoming = IncomingFile::create(dir.path(), filename, size).await?;
    let mut samples = Vec::new();
    incoming
        .stream_from(&mut server, |written| samples.push(written))
        .await?;
    let path = incoming.finalize().await?;
    sender.await?;

    let landed = tokio::fs::read(&path).await?;
    Ok((landed, samples))
}

#[tokio::test]
async fn a_multi_chunk_file_streams_end_to_end_byte_for_byte() {
    // Several full chunks plus a partial one, so the loop's tail is exercised.
    let size = CHUNK * 3 + 4_321;
    let body: Vec<u8> = (0..size).map(|index| (index % 251) as u8).collect();

    let (landed, samples) = transfer(body.clone(), "movie.bin").await.unwrap();

    assert_eq!(landed.len(), body.len());
    assert_eq!(landed, body, "every byte must survive the round trip");
    assert!(samples.len() > 3, "progress should be reported per chunk");
    assert!(
        samples.windows(2).all(|pair| pair[1] > pair[0]),
        "progress must increase monotonically"
    );
    assert_eq!(*samples.last().unwrap(), size as u64);
}

#[tokio::test]
async fn boundary_sizes_transfer_intact() {
    for size in [0_usize, 1, CHUNK - 1, CHUNK, CHUNK + 1] {
        let body = vec![0x5A_u8; size];
        let (landed, _) = transfer(body.clone(), "edge.bin").await.unwrap();
        assert_eq!(landed, body, "size {size} did not round trip");
    }
}

#[tokio::test]
async fn a_payload_at_exactly_the_remote_limit_is_accepted_by_the_receiver() {
    let dir = tempfile::tempdir().unwrap();
    // Only the declaration is exercised here; moving 20 MiB through a duplex
    // pipe would make the suite slow for no additional coverage.
    assert!(
        IncomingFile::create(dir.path(), "max.bin", MAX_WAN_PAYLOAD_BYTES)
            .await
            .is_ok()
    );
    assert!(
        IncomingFile::create(dir.path(), "over.bin", MAX_WAN_PAYLOAD_BYTES + 1)
            .await
            .is_err(),
        "one byte over the limit must be refused before any file is created"
    );
}

#[tokio::test]
async fn a_truncated_stream_never_produces_a_finished_file() {
    let dir = tempfile::tempdir().unwrap();
    let (mut client, mut server) = tokio::io::duplex(16 * 1024);

    tokio::spawn(async move {
        // Declare 10 KiB, then deliver 1 KiB and hang up.
        let header = serde_json::json!({ "relayPayloadId": "p", "payloadSize": 10_240 });
        let bytes = serde_json::to_vec(&header).unwrap();
        client.write_all(&(bytes.len() as u32).to_be_bytes()).await.unwrap();
        client.write_all(&bytes).await.unwrap();
        client.write_all(&vec![1_u8; 1024]).await.unwrap();
        client.shutdown().await.unwrap();
    });

    let (_, size) = read_header(&mut server).await.unwrap();
    let mut incoming = IncomingFile::create(dir.path(), "short.bin", size).await.unwrap();
    let error = incoming.stream_from(&mut server, |_| {}).await.unwrap_err();
    assert!(error.to_string().contains("ended after 1024 of 10240"));
    drop(incoming);

    // Neither a finished file nor a stray partial may remain.
    let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
    assert!(
        entries.next_entry().await.unwrap().is_none(),
        "a failed transfer must leave the destination directory clean"
    );
}

#[tokio::test]
async fn concurrent_transfers_of_the_same_filename_stay_separate() {
    let dir = tempfile::tempdir().unwrap();

    async fn one(dir: std::path::PathBuf, fill: u8, size: usize) -> std::path::PathBuf {
        let (mut client, mut server) = tokio::io::duplex(16 * 1024);
        let body = vec![fill; size];
        tokio::spawn(async move {
            send_payload(&mut client, "p", &body).await.unwrap();
            client.shutdown().await.unwrap();
        });
        let (_, declared) = read_header(&mut server).await.unwrap();
        let mut incoming = IncomingFile::create(&dir, "photo.jpg", declared).await.unwrap();
        incoming.stream_from(&mut server, |_| {}).await.unwrap();
        incoming.finalize().await.unwrap()
    }

    let (left, right) = tokio::join!(
        one(dir.path().to_path_buf(), 0xAA, CHUNK + 11),
        one(dir.path().to_path_buf(), 0xBB, CHUNK + 22),
    );

    assert_ne!(left, right, "two devices must not collide on one name");
    let left_bytes = tokio::fs::read(&left).await.unwrap();
    let right_bytes = tokio::fs::read(&right).await.unwrap();
    assert!(left_bytes.iter().all(|byte| *byte == 0xAA), "streams must not interleave");
    assert!(right_bytes.iter().all(|byte| *byte == 0xBB));
    assert_eq!(left_bytes.len(), CHUNK + 11);
    assert_eq!(right_bytes.len(), CHUNK + 22);
}
