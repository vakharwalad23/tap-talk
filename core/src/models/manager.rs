use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::transcribe::TIERS;

const HF_BASE_URL: &str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";

pub struct ModelManager {
    models_dir: PathBuf,
    active_download: Mutex<Option<u8>>,
}

pub struct DownloadProgress {
    pub tier: u8,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub status: DownloadStatus,
}

pub enum DownloadStatus {
    Downloading,
    Complete,
}

impl ModelManager {
    pub fn new(models_dir: &Path) -> Result<Self, String> {
        fs::create_dir_all(models_dir)
            .map_err(|e| format!("cannot create models dir: {e}"))?;
        Ok(Self {
            models_dir: models_dir.to_path_buf(),
            active_download: Mutex::new(None),
        })
    }

    pub fn models_dir(&self) -> &Path {
        &self.models_dir
    }

    pub fn is_installed(&self, tier: u8) -> bool {
        let Some(t) = TIERS.iter().find(|t| t.id == tier) else { return false };
        self.models_dir.join(t.ggml_filename).exists()
    }

    pub fn installed_tiers(&self) -> Vec<u8> {
        TIERS.iter()
            .filter(|t| self.models_dir.join(t.ggml_filename).exists())
            .map(|t| t.id)
            .collect()
    }

    pub fn download(
        &self,
        tier: u8,
        progress_cb: &dyn Fn(DownloadProgress),
    ) -> Result<(), String> {
        let t = TIERS.iter().find(|t| t.id == tier)
            .ok_or_else(|| format!("unknown tier: {tier}"))?;

        // Prevent concurrent downloads
        {
            let mut active = self.active_download.lock()
                .map_err(|e| format!("lock: {e}"))?;
            if active.is_some() {
                return Err("download already in progress".into());
            }
            *active = Some(tier);
        }

        let result = self.download_file(tier, t.ggml_filename, progress_cb);

        // Clear active download
        if let Ok(mut active) = self.active_download.lock() {
            *active = None;
        }

        result
    }

    fn download_file(
        &self,
        tier: u8,
        filename: &str,
        progress_cb: &dyn Fn(DownloadProgress),
    ) -> Result<(), String> {
        let url = format!("{HF_BASE_URL}/{filename}");
        let dest = self.models_dir.join(filename);
        let partial = self.models_dir.join(format!("{filename}.partial"));

        let agent = ureq::Agent::new_with_defaults();
        let response = agent.get(&url).call()
            .map_err(|e| format!("download request failed: {e}"))?;

        let total_bytes = response.headers().get("content-length")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0);

        let mut file = fs::File::create(&partial)
            .map_err(|e| format!("create file: {e}"))?;

        let mut reader = response.into_body().into_reader();
        let mut buf = vec![0u8; 64 * 1024];
        let mut downloaded: u64 = 0;

        loop {
            let n = std::io::Read::read(&mut reader, &mut buf)
                .map_err(|e| format!("read: {e}"))?;

            if n == 0 { break; }

            file.write_all(&buf[..n])
                .map_err(|e| format!("write: {e}"))?;

            downloaded += n as u64;

            progress_cb(DownloadProgress {
                tier,
                bytes_downloaded: downloaded,
                total_bytes,
                status: DownloadStatus::Downloading,
            });
        }

        file.flush().map_err(|e| format!("flush: {e}"))?;
        drop(file);

        // Rename partial to final; remove stale .partial on failure
        fs::rename(&partial, &dest).map_err(|e| {
            let _ = fs::remove_file(&partial);
            format!("rename: {e}")
        })?;

        progress_cb(DownloadProgress {
            tier,
            bytes_downloaded: downloaded,
            total_bytes,
            status: DownloadStatus::Complete,
        });

        Ok(())
    }

    pub fn delete(&self, tier: u8) -> Result<(), String> {
        let t = TIERS.iter().find(|t| t.id == tier)
            .ok_or_else(|| format!("unknown tier: {tier}"))?;

        let path = self.models_dir.join(t.ggml_filename);
        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("delete: {e}"))?;
        }

        // Also remove Core ML model if present
        let coreml_path = self.models_dir.join(t.coreml_filename);
        if coreml_path.exists() {
            fs::remove_dir_all(&coreml_path).map_err(|e| format!("delete coreml: {e}"))?;
        }

        Ok(())
    }
}
