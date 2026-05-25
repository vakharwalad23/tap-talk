use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::transcribe::TIERS;
use crate::llm::catalog::llm_model_by_id;

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
    DownloadingCoreMl,
    Complete,
}

pub struct LlmDownloadProgress {
    pub model_id: String,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub done: bool,
}

impl ModelManager {
    pub fn new(models_dir: &Path) -> Result<Self, String> {
        fs::create_dir_all(models_dir)
            .map_err(|e| format!("cannot create models dir: {e}"))?;
        let manager = Self {
            models_dir: models_dir.to_path_buf(),
            active_download: Mutex::new(None),
        };
        manager.clean_macos_junk();
        Ok(manager)
    }

    // Removes macOS resource-fork junk (__MACOSX/, .DS_Store) left in the models dir by
    // older builds that extracted it from Core ML zips. Best-effort — failures are non-fatal.
    fn clean_macos_junk(&self) {
        let macosx = self.models_dir.join("__MACOSX");
        if macosx.is_dir() {
            let _ = fs::remove_dir_all(&macosx);
        }
        let ds_store = self.models_dir.join(".DS_Store");
        if ds_store.is_file() {
            let _ = fs::remove_file(&ds_store);
        }

        // Remove leftover *.partial / *.zip.partial downloads from a session that quit or
        // failed mid-download — they are never resumed, so they are pure wasted disk.
        if let Ok(entries) = fs::read_dir(&self.models_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("partial") {
                    let _ = fs::remove_file(&path);
                }
            }
        }
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

    pub fn installed_tiers_missing_coreml(&self) -> Vec<u8> {
        TIERS.iter()
            .filter(|t| {
                self.models_dir.join(t.ggml_filename).exists()
                    && !self.models_dir.join(t.coreml_filename).is_dir()
            })
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

        self.claim_active(tier)?;

        // Only the ggml model is fetched here, so the base install stays small and the
        // model works immediately. The Core ML encoder (~doubles disk) is opt-in via
        // download_coreml_only, surfaced in the UI as a per-tier "Optimize" action.
        let ggml_result = self.download_ggml(tier, t.ggml_filename, progress_cb);

        self.release_active();

        ggml_result?;

        progress_cb(DownloadProgress {
            tier,
            bytes_downloaded: 0,
            total_bytes: 0,
            status: DownloadStatus::Complete,
        });
        Ok(())
    }

    pub fn download_coreml_only(
        &self,
        tier: u8,
        progress_cb: &dyn Fn(DownloadProgress),
    ) -> Result<(), String> {
        let t = TIERS.iter().find(|t| t.id == tier)
            .ok_or_else(|| format!("unknown tier: {tier}"))?;

        if !self.models_dir.join(t.ggml_filename).exists() {
            return Err(format!("ggml model not installed for tier {tier}"));
        }

        self.claim_active(tier)?;
        let result = self.download_coreml_inner(tier, t.coreml_filename, progress_cb);
        self.release_active();

        result?;

        progress_cb(DownloadProgress {
            tier,
            bytes_downloaded: 0,
            total_bytes: 0,
            status: DownloadStatus::Complete,
        });
        Ok(())
    }

    fn claim_active(&self, tier: u8) -> Result<(), String> {
        let mut active = self.active_download.lock()
            .map_err(|e| format!("lock: {e}"))?;
        if active.is_some() {
            return Err("download already in progress".into());
        }
        *active = Some(tier);
        Ok(())
    }

    fn release_active(&self) {
        if let Ok(mut active) = self.active_download.lock() {
            *active = None;
        }
    }

    fn download_ggml(
        &self,
        tier: u8,
        filename: &str,
        progress_cb: &dyn Fn(DownloadProgress),
    ) -> Result<(), String> {
        let url = format!("{HF_BASE_URL}/{filename}");
        let dest = self.models_dir.join(filename);
        let partial = self.models_dir.join(format!("{filename}.partial"));

        let on_progress = |bytes_downloaded: u64, total_bytes: u64| {
            progress_cb(DownloadProgress {
                tier,
                bytes_downloaded,
                total_bytes,
                status: DownloadStatus::Downloading,
            });
        };

        if let Err(e) = stream_to_file(&url, &partial, &on_progress) {
            let _ = fs::remove_file(&partial);
            return Err(e);
        }

        fs::rename(&partial, &dest).map_err(|e| {
            let _ = fs::remove_file(&partial);
            format!("rename: {e}")
        })?;

        Ok(())
    }

    fn download_coreml_inner(
        &self,
        tier: u8,
        coreml_name: &str,
        progress_cb: &dyn Fn(DownloadProgress),
    ) -> Result<(), String> {
        let url = format!("{HF_BASE_URL}/{coreml_name}.zip");
        let zip_partial = self.models_dir.join(format!("{coreml_name}.zip.partial"));
        let zip_path = self.models_dir.join(format!("{coreml_name}.zip"));
        let bundle_dir = self.models_dir.join(coreml_name);

        let on_progress = |bytes_downloaded: u64, total_bytes: u64| {
            progress_cb(DownloadProgress {
                tier,
                bytes_downloaded,
                total_bytes,
                status: DownloadStatus::DownloadingCoreMl,
            });
        };

        let stream_result = stream_to_file(&url, &zip_partial, &on_progress);
        if let Err(e) = stream_result {
            let _ = fs::remove_file(&zip_partial);
            return Err(e);
        }

        fs::rename(&zip_partial, &zip_path).map_err(|e| {
            let _ = fs::remove_file(&zip_partial);
            format!("rename zip: {e}")
        })?;

        let extract_result = extract_zip(&zip_path, &self.models_dir);
        let _ = fs::remove_file(&zip_path);

        if let Err(e) = extract_result {
            let _ = fs::remove_dir_all(&bundle_dir);
            return Err(e);
        }

        if !bundle_dir.is_dir() {
            return Err(format!("extracted archive missing {coreml_name}/"));
        }

        Ok(())
    }

    pub fn is_llm_installed(&self, model_id: &str) -> bool {
        let Some(spec) = llm_model_by_id(model_id) else { return false };
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
        let spec = llm_model_by_id(model_id)
            .ok_or_else(|| format!("unknown LLM model: {model_id}"))?;

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

        stream_to_file(spec.url, &partial, &on_progress)?;

        fs::rename(&partial, &dest).map_err(|e| {
            let _ = fs::remove_file(&partial);
            format!("rename: {e}")
        })?;

        progress_cb(LlmDownloadProgress {
            model_id: model_id.to_string(),
            bytes_downloaded: 0,
            total_bytes: 0,
            done: true,
        });

        Ok(())
    }

    pub fn delete_llm(&self, model_id: &str) -> Result<(), String> {
        let spec = llm_model_by_id(model_id)
            .ok_or_else(|| format!("unknown LLM model: {model_id}"))?;
        let path = self.models_dir.join(spec.filename);
        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("delete: {e}"))?;
        }
        Ok(())
    }

    pub fn delete(&self, tier: u8) -> Result<(), String> {
        let t = TIERS.iter().find(|t| t.id == tier)
            .ok_or_else(|| format!("unknown tier: {tier}"))?;

        let path = self.models_dir.join(t.ggml_filename);
        if path.exists() {
            fs::remove_file(&path).map_err(|e| format!("delete: {e}"))?;
        }

        let coreml_path = self.models_dir.join(t.coreml_filename);
        if coreml_path.exists() {
            fs::remove_dir_all(&coreml_path).map_err(|e| format!("delete coreml: {e}"))?;
        }

        Ok(())
    }

    /// Removes ONLY the Core ML encoder bundle, reclaiming disk while keeping the
    /// ggml model fully usable (encoder falls back to GPU). The `.bin` is never touched.
    pub fn delete_coreml(&self, tier: u8) -> Result<(), String> {
        let t = TIERS.iter().find(|t| t.id == tier)
            .ok_or_else(|| format!("unknown tier: {tier}"))?;

        let coreml_path = self.models_dir.join(t.coreml_filename);

        // Safety: only ever remove a `.mlmodelc` directory. Never a file (the `.bin`
        // is a file), and never if the name isn't the expected Core ML bundle.
        if !t.coreml_filename.ends_with(".mlmodelc") {
            return Err("unexpected coreml filename".into());
        }
        if coreml_path.is_dir() {
            fs::remove_dir_all(&coreml_path).map_err(|e| format!("delete coreml: {e}"))?;
        }

        Ok(())
    }
}

fn stream_to_file(
    url: &str,
    partial: &Path,
    on_progress: &dyn Fn(u64, u64),
) -> Result<u64, String> {
    let agent = ureq::Agent::new_with_defaults();
    let response = agent.get(url).call()
        .map_err(|e| format!("download request failed: {e}"))?;

    let total_bytes = response.headers().get("content-length")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(0);

    let mut file = fs::File::create(partial)
        .map_err(|e| format!("create file: {e}"))?;

    let mut reader = response.into_body().into_reader();
    let mut buf = vec![0u8; 64 * 1024];
    let mut downloaded: u64 = 0;

    loop {
        let n = std::io::Read::read(&mut reader, &mut buf)
            .map_err(|e| format!("read: {e}"))?;
        if n == 0 { break; }
        file.write_all(&buf[..n]).map_err(|e| format!("write: {e}"))?;
        downloaded += n as u64;
        on_progress(downloaded, total_bytes);
    }

    file.flush().map_err(|e| format!("flush: {e}"))?;
    drop(file);
    Ok(downloaded)
}

fn extract_zip(zip_path: &Path, dest_root: &Path) -> Result<(), String> {
    let file = fs::File::open(zip_path).map_err(|e| format!("open zip: {e}"))?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| format!("read zip: {e}"))?;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(|e| format!("zip entry {i}: {e}"))?;
        let Some(rel_path) = entry.enclosed_name() else {
            return Err(format!("zip entry {} has unsafe path", entry.name()));
        };

        // macOS-created zips carry a __MACOSX/ resource-fork tree and .DS_Store files —
        // junk that must never land in the models dir.
        if is_macos_junk(&rel_path) {
            continue;
        }

        let out_path = dest_root.join(&rel_path);

        if entry.is_dir() {
            fs::create_dir_all(&out_path).map_err(|e| format!("mkdir: {e}"))?;
            continue;
        }

        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir parent: {e}"))?;
        }
        let mut out_file = fs::File::create(&out_path)
            .map_err(|e| format!("create {}: {e}", out_path.display()))?;
        std::io::copy(&mut entry, &mut out_file)
            .map_err(|e| format!("write {}: {e}", out_path.display()))?;
    }
    Ok(())
}

fn is_macos_junk(path: &Path) -> bool {
    path.components().any(|c| c.as_os_str() == "__MACOSX")
        || path.file_name().is_some_and(|n| n == ".DS_Store")
}

#[cfg(test)]
mod tests {
    use super::is_macos_junk;
    use std::path::Path;

    #[test]
    fn flags_macos_junk_only() {
        assert!(is_macos_junk(Path::new("__MACOSX/foo-encoder.mlmodelc/weights")));
        assert!(is_macos_junk(Path::new("foo-encoder.mlmodelc/.DS_Store")));
        assert!(!is_macos_junk(Path::new("ggml-large-v3-turbo-encoder.mlmodelc/weights/weight.bin")));
        assert!(!is_macos_junk(Path::new("ggml-large-v3-turbo-encoder.mlmodelc/model.mil")));
    }
}
