//! Per-device cache for an incoming `kdeconnect.relay.wallpaper` preview.
//!
//! This is decorative state only -- it exists to feed the phone silhouette in
//! the Linux hero, and deliberately stays outside `device-state v1`, the
//! Device Fabric, and the file `Transfer` registry. A bad or missing preview
//! must never affect pairing, connectivity, or reachability, so every
//! operation here is infallible from the caller's point of view: validation
//! failures are logged and dropped, never surfaced as an error the rest of
//! the system has to react to.

use std::path::{Path, PathBuf};

/// Hard ceiling on a received wallpaper preview. Matches the Android sender's
/// own limit; enforced again here because a compromised or buggy peer must
/// not be trusted to have applied it.
pub const MAX_WALLPAPER_RECEIVE_BYTES: u64 = 1024 * 1024;

/// Mime types accepted from a peer. Deliberately small: these are the three
/// formats both platforms already know how to render and validate by magic
/// bytes.
pub fn is_allowed_mime(mime: &str) -> bool {
    matches!(
        mime.to_ascii_lowercase().as_str(),
        "image/jpeg" | "image/jpg" | "image/png" | "image/webp"
    )
}

/// Sniffs the first bytes of a buffer for a JPEG, PNG, or WebP header,
/// independent of the claimed mime type. A peer that lies about the mime type
/// is caught here rather than trusted.
pub fn has_valid_image_header(bytes: &[u8]) -> bool {
    if bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return true; // JPEG
    }
    if bytes.len() >= 4 && bytes[0..4] == [0x89, 0x50, 0x4E, 0x47] {
        return true; // PNG
    }
    if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return true; // WebP
    }
    false
}

/// A declared width/height is trusted only enough to reject absurd values --
/// there is no decoder here to verify it matches the actual pixel data.
pub fn is_plausible_dimension(width: u32, height: u32) -> bool {
    width > 0 && height > 0 && width <= 4096 && height <= 4096
}

fn extension_for_mime(mime: &str) -> &'static str {
    match mime.to_ascii_lowercase().as_str() {
        "image/png" => "png",
        "image/webp" => "webp",
        _ => "jpg",
    }
}

/// A device id turned into a filesystem-safe basename component. Device ids
/// are normally short opaque tokens already, but a hostile peer's *label*
/// must never be trusted for path construction, so this stays defensive.
fn sanitize_device_component(device_id: &str) -> String {
    let cleaned: String = device_id
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    if cleaned.is_empty() {
        "unknown".to_owned()
    } else {
        cleaned
    }
}

/// Per-device store of the last successfully validated wallpaper preview.
///
/// Keyed strictly by authenticated device id: nothing here is derived from a
/// packet's self-reported name, so one peer can never overwrite another's
/// cached preview.
#[derive(Default)]
pub struct WallpaperCache {
    base_dir: std::sync::Mutex<Option<PathBuf>>,
    paths: std::sync::Mutex<std::collections::HashMap<String, PathBuf>>,
}

impl WallpaperCache {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_base_dir(&self, dir: PathBuf) {
        *self.base_dir.lock().unwrap() = Some(dir);
    }

    pub fn path_for(&self, device_id: &str) -> Option<PathBuf> {
        self.paths.lock().unwrap().get(device_id).cloned()
    }

    pub fn clear(&self, device_id: &str) {
        self.paths.lock().unwrap().remove(device_id);
    }

    /// Validates and persists a fully-received preview for `device_id`.
    ///
    /// Returns the final path on success. Every rejection reason is a plain
    /// `Err` string for logging -- callers must not treat any of them as
    /// worth surfacing to the user or the connection state.
    pub async fn store(
        &self,
        device_id: &str,
        mime_type: &str,
        bytes: &[u8],
    ) -> Result<PathBuf, String> {
        if bytes.is_empty() {
            return Err("empty wallpaper payload".into());
        }
        if bytes.len() as u64 > MAX_WALLPAPER_RECEIVE_BYTES {
            return Err(format!("wallpaper payload too large ({} bytes)", bytes.len()));
        }
        if !is_allowed_mime(mime_type) {
            return Err(format!("unsupported wallpaper mime type: {mime_type}"));
        }
        if !has_valid_image_header(bytes) {
            return Err("wallpaper payload is not a valid JPEG/PNG/WebP".into());
        }

        let base_dir = self
            .base_dir
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(|| "no wallpaper cache directory configured".to_owned())?;
        tokio::fs::create_dir_all(&base_dir)
            .await
            .map_err(|error| format!("create wallpaper cache directory: {error}"))?;

        let ext = extension_for_mime(mime_type);
        let filename = format!("wallpaper-{}.{ext}", sanitize_device_component(device_id));
        let destination = base_dir.join(&filename);
        let temp = base_dir.join(format!(".{filename}.tmp"));

        tokio::fs::write(&temp, bytes)
            .await
            .map_err(|error| format!("write wallpaper temp file: {error}"))?;
        // Atomic within the same directory: a reader can never observe a
        // partially-written preview.
        if let Err(error) = tokio::fs::rename(&temp, &destination).await {
            let _ = tokio::fs::remove_file(&temp).await;
            return Err(format!("finalize wallpaper file: {error}"));
        }

        self.paths.lock().unwrap().insert(device_id.to_owned(), destination.clone());
        Ok(destination)
    }
}

/// Streams a bounded payload of at most `limit` bytes into memory.
///
/// Mirrors the discipline of the file receiver (never trust the declared
/// size alone, never exceed the transport's own ceiling) but returns bytes
/// rather than writing to disk, since a wallpaper preview is capped at 1 MiB
/// and is validated as a whole before anything is persisted.
pub async fn read_bounded<R>(stream: &mut R, declared: u64, limit: u64) -> Result<Vec<u8>, String>
where
    R: tokio::io::AsyncRead + Unpin,
{
    use tokio::io::AsyncReadExt as _;

    if declared > limit {
        return Err(format!("declared {declared} bytes exceeds the {limit}-byte wallpaper limit"));
    }
    let mut buffer = vec![0_u8; declared as usize];
    stream
        .read_exact(&mut buffer)
        .await
        .map_err(|error| format!("read wallpaper payload: {error}"))?;
    Ok(buffer)
}

#[allow(dead_code)]
pub fn wallpaper_path_hint(path: &Path) -> &Path {
    path
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jpeg_bytes() -> Vec<u8> {
        let mut bytes = vec![0xFF, 0xD8, 0xFF, 0xE0];
        bytes.extend_from_slice(&[0_u8; 32]);
        bytes
    }

    #[tokio::test]
    async fn valid_jpeg_is_stored_and_retrievable() {
        let dir = tempfile::tempdir().unwrap();
        let cache = WallpaperCache::new();
        cache.set_base_dir(dir.path().to_path_buf());

        let path = cache.store("device-a", "image/jpeg", &jpeg_bytes()).await.unwrap();
        assert!(path.exists());
        assert_eq!(cache.path_for("device-a"), Some(path));
    }

    #[tokio::test]
    async fn invalid_mime_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let cache = WallpaperCache::new();
        cache.set_base_dir(dir.path().to_path_buf());

        let result = cache.store("device-a", "application/pdf", &jpeg_bytes()).await;
        assert!(result.is_err());
        assert_eq!(cache.path_for("device-a"), None);
    }

    #[tokio::test]
    async fn oversized_payload_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let cache = WallpaperCache::new();
        cache.set_base_dir(dir.path().to_path_buf());

        let big = vec![0xAA_u8; (MAX_WALLPAPER_RECEIVE_BYTES + 1) as usize];
        let result = cache.store("device-a", "image/jpeg", &big).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn malformed_image_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let cache = WallpaperCache::new();
        cache.set_base_dir(dir.path().to_path_buf());

        let result = cache.store("device-a", "image/jpeg", b"not an image, just junk bytes").await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn peer_a_cannot_overwrite_peer_b() {
        let dir = tempfile::tempdir().unwrap();
        let cache = WallpaperCache::new();
        cache.set_base_dir(dir.path().to_path_buf());

        cache.store("device-a", "image/jpeg", &jpeg_bytes()).await.unwrap();
        assert_eq!(cache.path_for("device-b"), None);
        let a_path = cache.path_for("device-a").unwrap();
        assert!(a_path.to_string_lossy().contains("device-a"));
    }

    #[tokio::test]
    async fn bad_replacement_preserves_last_valid_cache() {
        let dir = tempfile::tempdir().unwrap();
        let cache = WallpaperCache::new();
        cache.set_base_dir(dir.path().to_path_buf());

        let good = cache.store("device-a", "image/jpeg", &jpeg_bytes()).await.unwrap();
        let bad = cache.store("device-a", "image/jpeg", b"garbage").await;
        assert!(bad.is_err());
        // The in-memory pointer and the file on disk must still reflect the
        // last *valid* preview, since store() never overwrote it.
        assert_eq!(cache.path_for("device-a"), Some(good.clone()));
        assert!(good.exists());
    }

    #[test]
    fn device_id_is_sanitized_for_the_filesystem() {
        assert_eq!(sanitize_device_component("../../etc/passwd"), "______etc_passwd");
        assert_eq!(sanitize_device_component(""), "unknown");
    }

    #[tokio::test]
    async fn read_bounded_rejects_declared_over_limit() {
        let mut source = std::io::Cursor::new(vec![0_u8; 10]);
        let result = read_bounded(&mut source, 2_000_000, MAX_WALLPAPER_RECEIVE_BYTES).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn read_bounded_reads_exactly_declared_bytes() {
        let mut source = std::io::Cursor::new(vec![7_u8; 100]);
        let bytes = read_bounded(&mut source, 100, MAX_WALLPAPER_RECEIVE_BYTES).await.unwrap();
        assert_eq!(bytes.len(), 100);
        assert!(bytes.iter().all(|b| *b == 7));
    }

    #[tokio::test]
    async fn read_bounded_fails_on_truncated_stream() {
        let mut source = std::io::Cursor::new(vec![7_u8; 10]);
        let result = read_bounded(&mut source, 100, MAX_WALLPAPER_RECEIVE_BYTES).await;
        assert!(result.is_err());
    }
}
