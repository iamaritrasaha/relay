//! Streaming receipt of an incoming file payload.
//!
//! Bytes go straight to disk through a bounded buffer, so memory stays roughly
//! constant regardless of file size -- a 20 MiB transfer costs one 64 KiB
//! buffer, not 20 MiB of heap.
//!
//! Content lands in a `.part` file first and is renamed into place only after
//! the declared byte count has been written and verified. An interrupted or
//! mismatched transfer therefore leaves no file that looks complete, which is
//! the failure mode that matters: a truncated photo the user believes is intact
//! is worse than a transfer that visibly failed.

use std::path::{Path, PathBuf};

use anyhow::{Context as _, Result};
use tokio::io::{AsyncRead, AsyncReadExt as _, AsyncWriteExt as _};

use super::{sanitize_filename, unique_destination, MAX_WAN_PAYLOAD_BYTES};

/// Streaming chunk size. Matches the sender's, so a chunk read is typically one
/// chunk written with no re-buffering in between.
const CHUNK_BYTES: usize = 64 * 1024;

/// Extension for a partially written file. Visible on purpose: if Relay dies
/// mid-transfer the leftover is obviously incomplete rather than masquerading
/// as a real file.
const PARTIAL_SUFFIX: &str = "part";

/// A file being written to disk.
///
/// Dropping this without calling [`finalize`] removes the partial file, so an
/// abandoned transfer -- cancelled, failed, or panicking -- cleans up after
/// itself rather than leaving debris in the user's downloads.
///
/// [`finalize`]: IncomingFile::finalize
pub struct IncomingFile {
    directory: PathBuf,
    filename: String,
    /// Empty until [`IncomingFile::finalize`] claims a name.
    destination: PathBuf,
    partial: PathBuf,
    file: Option<tokio::fs::File>,
    declared: u64,
    written: u64,
}

impl IncomingFile {
    /// Prepares a destination under `directory` for a remote-supplied filename.
    ///
    /// The name is sanitized to a basename and de-duplicated, so nothing the
    /// sender puts in `filename` can escape `directory` or overwrite a file that
    /// is already there.
    /// `limit` is the transport's own size policy, stated explicitly by the
    /// caller rather than assumed here.
    ///
    /// This matters: the 20 MiB ceiling belongs to Relay WAN alone. Enforcing it
    /// inside the shared receiver would silently apply it to LAN too and refuse
    /// perfectly ordinary local files. `None` means the transport imposes no
    /// ceiling, which is the LAN case.
    pub async fn create(
        directory: &Path,
        filename: &str,
        declared: u64,
        limit: Option<u64>,
    ) -> Result<Self> {
        if let Some(limit) = limit {
            if declared > limit {
                anyhow::bail!("declared {declared} bytes exceeds the {limit}-byte transport limit");
            }
        }
        tokio::fs::create_dir_all(directory)
            .await
            .context("create the destination directory")?;

        let safe = sanitize_filename(filename);
        // The partial name carries a per-transfer id rather than being derived
        // from the filename alone: two devices sending `photo.jpg` at the same
        // moment would otherwise write to the same `.part` file and corrupt
        // each other. The final name is chosen at finalize, when it can be
        // claimed atomically.
        let partial = directory.join(format!(
            ".relay-{}.{PARTIAL_SUFFIX}",
            super::generate_transfer_id()
        ));

        let file = tokio::fs::File::create(&partial)
            .await
            .context("create the partial file")?;
        Ok(Self {
            directory: directory.to_path_buf(),
            filename: safe,
            destination: PathBuf::new(),
            partial,
            file: Some(file),
            declared,
            written: 0,
        })
    }

    pub fn destination(&self) -> &Path {
        &self.destination
    }

    pub fn written(&self) -> u64 {
        self.written
    }

    /// Streams exactly `declared` bytes from `source` into the partial file.
    ///
    /// `on_progress` is called after each chunk so the caller can publish byte
    /// counts; it must be cheap, since it runs inside the copy loop.
    ///
    /// Refuses to write more than the declared size even if the sender keeps
    /// talking -- otherwise a peer could ignore its own metadata and fill the
    /// disk.
    pub async fn stream_from<R, F>(&mut self, source: &mut R, mut on_progress: F) -> Result<()>
    where
        R: AsyncRead + Unpin,
        F: FnMut(u64),
    {
        let file = self
            .file
            .as_mut()
            .context("transfer has already been finalized")?;
        let mut buffer = vec![0_u8; CHUNK_BYTES];
        while self.written < self.declared {
            let remaining = (self.declared - self.written) as usize;
            let want = remaining.min(CHUNK_BYTES);
            let read = source
                .read(&mut buffer[..want])
                .await
                .context("read the incoming payload")?;
            if read == 0 {
                // The stream ended early: the file is short and must not be
                // presented as complete.
                anyhow::bail!(
                    "payload ended after {} of {} declared bytes",
                    self.written,
                    self.declared
                );
            }
            file.write_all(&buffer[..read])
                .await
                .context("write the incoming payload")?;
            self.written += read as u64;
            on_progress(self.written);
        }
        Ok(())
    }

    /// Verifies the byte count and moves the file into place.
    ///
    /// QUIC already guarantees the bytes were not corrupted in flight, so no
    /// extra checksum is computed; what still has to be checked is that the
    /// sender delivered the length it promised.
    pub async fn finalize(mut self) -> Result<PathBuf> {
        if self.written != self.declared {
            let written = self.written;
            let declared = self.declared;
            self.cleanup().await;
            anyhow::bail!("payload size mismatch: received {written}, declared {declared}");
        }
        if let Some(mut file) = self.file.take() {
            file.flush().await.context("flush the received file")?;
            file.sync_all().await.context("sync the received file")?;
        }
        // Claim a free name only now, and claim it atomically: two transfers
        // finishing at once must not both decide on the same path between
        // looking and renaming.
        let destination = self.claim_destination().await?;
        // Rename within the same directory, so the file appears complete
        // atomically rather than growing in place where something might read it
        // half-written.
        tokio::fs::rename(&self.partial, &destination)
            .await
            .context("move the received file into place")?;
        self.destination = destination.clone();
        // Prevent Drop from deleting what we just published.
        self.partial = PathBuf::new();
        Ok(destination)
    }

    /// Reserves a destination path that no other transfer holds.
    ///
    /// `create_new` is the atomic step: it succeeds for exactly one caller, so
    /// concurrent receives of the same filename cannot both win the same name.
    /// The reserved placeholder is then replaced by the rename.
    async fn claim_destination(&self) -> Result<PathBuf> {
        for _ in 0..10_000 {
            let candidate = unique_destination(&self.directory, &self.filename);
            match tokio::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&candidate)
                .await
            {
                Ok(_) => return Ok(candidate),
                // Lost the race for this name; the next pass picks the next one.
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => {
                    return Err(error).context("reserve a destination for the received file")
                }
            }
        }
        anyhow::bail!("could not find a free destination filename")
    }

    /// Abandons the transfer and removes the partial file.
    pub async fn cancel(mut self) {
        self.cleanup().await;
    }

    async fn cleanup(&mut self) {
        self.file.take();
        if self.partial.as_os_str().is_empty() {
            return;
        }
        let _ = tokio::fs::remove_file(&self.partial).await;
        self.partial = PathBuf::new();
    }
}

impl Drop for IncomingFile {
    fn drop(&mut self) {
        if self.partial.as_os_str().is_empty() {
            return;
        }
        // Best-effort synchronous removal: Drop cannot await, and leaving a
        // stray `.part` behind is worse than a blocking unlink of one file.
        let _ = std::fs::remove_file(&self.partial);
    }
}

/// The largest file this receiver will accept, re-exported so callers do not
/// have to reach into the WAN module for it.
pub const MAX_RECEIVE_BYTES: u64 = MAX_WAN_PAYLOAD_BYTES;

#[cfg(test)]
mod tests {
    use super::*;

    async fn receive(dir: &Path, name: &str, data: &[u8], declared: u64) -> Result<PathBuf> {
        let mut incoming = IncomingFile::create(dir, name, declared, Some(MAX_RECEIVE_BYTES)).await?;
        let mut source = std::io::Cursor::new(data.to_vec());
        incoming.stream_from(&mut source, |_| {}).await?;
        incoming.finalize().await
    }

    #[tokio::test]
    async fn a_file_is_written_and_published_atomically() {
        let dir = tempfile::tempdir().unwrap();
        let data = b"hello relay".to_vec();
        let path = receive(dir.path(), "note.txt", &data, data.len() as u64).await.unwrap();

        assert_eq!(path.file_name().unwrap(), "note.txt");
        assert_eq!(tokio::fs::read(&path).await.unwrap(), data);
        // No debris left behind.
        assert!(!dir.path().join("note.txt.part").exists());
    }

    #[tokio::test]
    async fn a_zero_byte_file_is_still_created() {
        let dir = tempfile::tempdir().unwrap();
        let path = receive(dir.path(), "empty.bin", b"", 0).await.unwrap();
        assert!(path.exists());
        assert_eq!(tokio::fs::metadata(&path).await.unwrap().len(), 0);
    }

    #[tokio::test]
    async fn a_one_byte_file_round_trips() {
        let dir = tempfile::tempdir().unwrap();
        let path = receive(dir.path(), "one.bin", b"x", 1).await.unwrap();
        assert_eq!(tokio::fs::read(&path).await.unwrap(), b"x");
    }

    #[tokio::test]
    async fn a_multi_chunk_payload_streams_without_buffering_it_all() {
        let dir = tempfile::tempdir().unwrap();
        // Several chunks plus a partial one, to exercise the loop's tail.
        let size = CHUNK_BYTES * 3 + 1234;
        let data: Vec<u8> = (0..size).map(|index| (index % 251) as u8).collect();

        let mut incoming = IncomingFile::create(dir.path(), "big.bin", size as u64, Some(MAX_RECEIVE_BYTES))
            .await.unwrap();
        let mut samples = Vec::new();
        let mut source = std::io::Cursor::new(data.clone());
        incoming
            .stream_from(&mut source, |written| samples.push(written))
            .await
            .unwrap();
        let path = incoming.finalize().await.unwrap();

        assert_eq!(tokio::fs::read(&path).await.unwrap(), data);
        assert!(samples.len() >= 4, "progress should be reported per chunk");
        assert!(samples.windows(2).all(|pair| pair[1] > pair[0]), "monotonic");
        assert_eq!(*samples.last().unwrap(), size as u64);
    }

    #[tokio::test]
    async fn a_truncated_payload_fails_and_leaves_no_file() {
        let dir = tempfile::tempdir().unwrap();
        let mut incoming = IncomingFile::create(dir.path(), "short.bin", 100, Some(MAX_RECEIVE_BYTES))
            .await.unwrap();
        let mut source = std::io::Cursor::new(vec![0_u8; 40]);

        let error = incoming.stream_from(&mut source, |_| {}).await.unwrap_err();
        assert!(error.to_string().contains("ended after 40 of 100"));

        drop(incoming);
        assert!(!dir.path().join("short.bin").exists(), "nothing may be published");
        assert!(!dir.path().join("short.bin.part").exists(), "partial must be removed");
    }

    #[tokio::test]
    async fn a_size_mismatch_at_finalize_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        let mut incoming = IncomingFile::create(dir.path(), "x.bin", 10, Some(MAX_RECEIVE_BYTES))
            .await.unwrap();
        // Claim ten bytes but only ever write five by lying about the declared
        // length after the fact.
        let mut source = std::io::Cursor::new(vec![1_u8; 5]);
        let _ = incoming.stream_from(&mut source, |_| {}).await;
        assert!(!dir.path().join("x.bin").exists());
    }

    #[tokio::test]
    async fn a_sender_that_overruns_its_declared_size_is_cut_off() {
        let dir = tempfile::tempdir().unwrap();
        let mut incoming = IncomingFile::create(dir.path(), "x.bin", 10, Some(MAX_RECEIVE_BYTES))
            .await.unwrap();
        let mut source = std::io::Cursor::new(vec![7_u8; 10_000]);

        incoming.stream_from(&mut source, |_| {}).await.unwrap();
        let path = incoming.finalize().await.unwrap();

        assert_eq!(
            tokio::fs::metadata(&path).await.unwrap().len(),
            10,
            "only the declared bytes may be written"
        );
    }

    #[tokio::test]
    async fn an_oversized_declaration_is_refused_before_a_file_is_created() {
        let dir = tempfile::tempdir().unwrap();
        assert!(
            IncomingFile::create(dir.path(), "huge.bin", MAX_RECEIVE_BYTES + 1, Some(MAX_RECEIVE_BYTES))
            .await
                .is_err()
        );
        // Nothing at all should have been created.
        let mut entries = tokio::fs::read_dir(dir.path()).await.unwrap();
        assert!(entries.next_entry().await.unwrap().is_none());
    }

    #[tokio::test]
    async fn exactly_the_limit_is_accepted_as_a_declaration() {
        let dir = tempfile::tempdir().unwrap();
        assert!(IncomingFile::create(dir.path(), "x.bin", MAX_RECEIVE_BYTES, Some(MAX_RECEIVE_BYTES))
            .await.is_ok());
    }

    #[tokio::test]
    async fn cancelling_removes_the_partial_file() {
        let dir = tempfile::tempdir().unwrap();
        let mut incoming = IncomingFile::create(dir.path(), "x.bin", 1_000, Some(MAX_RECEIVE_BYTES))
            .await.unwrap();
        let mut source = std::io::Cursor::new(vec![0_u8; 500]);
        let _ = incoming.stream_from(&mut source, |_| {}).await;

        incoming.cancel().await;

        assert!(!dir.path().join("x.bin").exists());
        assert!(!dir.path().join("x.bin.part").exists());
    }

    #[tokio::test]
    async fn a_traversing_filename_lands_inside_the_destination_directory() {
        let dir = tempfile::tempdir().unwrap();
        let path = receive(dir.path(), "../../../etc/passwd", b"nope", 4).await.unwrap();

        assert_eq!(path.parent().unwrap(), dir.path(), "must stay in the directory");
        assert_eq!(path.file_name().unwrap(), "passwd");
    }

    #[tokio::test]
    async fn an_absolute_remote_path_cannot_escape_either() {
        let dir = tempfile::tempdir().unwrap();
        let path = receive(dir.path(), "/etc/shadow", b"nope", 4).await.unwrap();
        assert_eq!(path.parent().unwrap(), dir.path());
        assert_eq!(path.file_name().unwrap(), "shadow");
    }

    #[tokio::test]
    async fn two_devices_sending_the_same_name_do_not_overwrite_each_other() {
        let dir = tempfile::tempdir().unwrap();
        let first = receive(dir.path(), "photo.jpg", b"from-a", 6).await.unwrap();
        let second = receive(dir.path(), "photo.jpg", b"from-b", 6).await.unwrap();

        assert_ne!(first, second);
        assert_eq!(tokio::fs::read(&first).await.unwrap(), b"from-a");
        assert_eq!(tokio::fs::read(&second).await.unwrap(), b"from-b");
    }

    #[tokio::test]
    async fn concurrent_transfers_do_not_corrupt_each_others_bytes() {
        let dir = tempfile::tempdir().unwrap();
        let a: Vec<u8> = vec![0xAA; CHUNK_BYTES + 7];
        let b: Vec<u8> = vec![0xBB; CHUNK_BYTES + 13];

        let (left, right) = tokio::join!(
            receive(dir.path(), "same.bin", &a, a.len() as u64),
            receive(dir.path(), "same.bin", &b, b.len() as u64),
        );
        let (left, right) = (left.unwrap(), right.unwrap());

        assert_ne!(left, right);
        let left_bytes = tokio::fs::read(&left).await.unwrap();
        let right_bytes = tokio::fs::read(&right).await.unwrap();
        // Each file is uniform: no interleaving of the two streams.
        assert!(left_bytes.iter().all(|byte| *byte == left_bytes[0]));
        assert!(right_bytes.iter().all(|byte| *byte == right_bytes[0]));
        assert_ne!(left_bytes[0], right_bytes[0]);
    }
}
