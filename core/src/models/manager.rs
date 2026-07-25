use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::llm::catalog::llm_model_by_id;

pub struct ModelManager {
    models_dir: PathBuf,
    active_download: Mutex<Option<String>>,
}

pub struct LlmDownloadProgress {
    pub model_id: String,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub done: bool,
}

impl ModelManager {
    pub fn new(models_dir: &Path) -> Result<Self, String> {
        fs::create_dir_all(models_dir).map_err(|e| format!("cannot create models dir: {e}"))?;
        let manager = Self {
            models_dir: models_dir.to_path_buf(),
            active_download: Mutex::new(None),
        };
        manager.clean_residue();
        Ok(manager)
    }

    // Removes macOS resource-fork junk and orphaned mid-download files left by a run that
    // crashed between streaming and the final rename. Best-effort — failures are non-fatal.
    fn clean_residue(&self) {
        let macosx = self.models_dir.join("__MACOSX");
        if macosx.is_dir() {
            let _ = fs::remove_dir_all(&macosx);
        }
        let ds_store = self.models_dir.join(".DS_Store");
        if ds_store.is_file() {
            let _ = fs::remove_file(&ds_store);
        }

        if let Ok(entries) = fs::read_dir(&self.models_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_file() && path.extension().and_then(|e| e.to_str()) == Some("partial") {
                    let _ = fs::remove_file(&path);
                }
            }
        }
    }

    pub fn models_dir(&self) -> &Path {
        &self.models_dir
    }

    pub fn is_llm_installed(&self, model_id: &str) -> bool {
        let Some(spec) = llm_model_by_id(model_id) else {
            return false;
        };
        self.models_dir.join(spec.filename).exists()
    }

    pub fn llm_model_path(&self, model_id: &str) -> Option<PathBuf> {
        let spec = llm_model_by_id(model_id)?;
        let path = self.models_dir.join(spec.filename);
        path.exists().then_some(path)
    }

    pub fn download_llm(
        &self,
        model_id: &str,
        progress_cb: &dyn Fn(LlmDownloadProgress),
    ) -> Result<(), String> {
        let spec =
            llm_model_by_id(model_id).ok_or_else(|| format!("unknown LLM model: {model_id}"))?;

        self.claim_active(model_id)?;

        let dest = self.models_dir.join(spec.filename);
        let partial = self.models_dir.join(format!("{}.partial", spec.filename));

        let on_progress = |bytes_downloaded: u64, total_bytes: u64| {
            progress_cb(LlmDownloadProgress {
                model_id: model_id.to_string(),
                bytes_downloaded,
                total_bytes,
                done: false,
            });
        };

        let result = stream_to_file(spec.url, &partial, &on_progress)
            .and_then(|_| fs::rename(&partial, &dest).map_err(|e| format!("rename: {e}")));

        if result.is_err() {
            let _ = fs::remove_file(&partial);
        }
        self.release_active();
        result?;

        progress_cb(LlmDownloadProgress {
            model_id: model_id.to_string(),
            bytes_downloaded: 0,
            total_bytes: 0,
            done: true,
        });

        Ok(())
    }

    pub fn delete_llm(&self, model_id: &str) -> Result<(), String> {
        let spec =
            llm_model_by_id(model_id).ok_or_else(|| format!("unknown LLM model: {model_id}"))?;
        let path = self.models_dir.join(spec.filename);
        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("delete: {e}"))?;
        }
        Ok(())
    }

    fn claim_active(&self, model_id: &str) -> Result<(), String> {
        let mut active = self
            .active_download
            .lock()
            .map_err(|e| format!("lock: {e}"))?;
        if active.is_some() {
            return Err("download already in progress".into());
        }
        *active = Some(model_id.to_string());
        Ok(())
    }

    fn release_active(&self) {
        if let Ok(mut active) = self.active_download.lock() {
            *active = None;
        }
    }
}

fn stream_to_file(
    url: &str,
    partial: &Path,
    on_progress: &dyn Fn(u64, u64),
) -> Result<u64, String> {
    let agent = ureq::Agent::new_with_defaults();
    let response = agent
        .get(url)
        .call()
        .map_err(|e| format!("download request failed: {e}"))?;

    let total_bytes = response
        .headers()
        .get("content-length")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(0);

    let mut file = fs::File::create(partial).map_err(|e| format!("create file: {e}"))?;

    let mut reader = response.into_body().into_reader();
    let mut buf = vec![0u8; 64 * 1024];
    let mut downloaded: u64 = 0;

    loop {
        let n = std::io::Read::read(&mut reader, &mut buf).map_err(|e| format!("read: {e}"))?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])
            .map_err(|e| format!("write: {e}"))?;
        downloaded += n as u64;
        on_progress(downloaded, total_bytes);
    }

    file.flush().map_err(|e| format!("flush: {e}"))?;
    drop(file);
    Ok(downloaded)
}
