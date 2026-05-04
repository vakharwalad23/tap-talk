mod audio;
mod models;
mod transcribe;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("{msg}")]
    Audio { msg: String },
    #[error("{msg}")]
    Model { msg: String },
    #[error("{msg}")]
    Transcription { msg: String },
}

#[uniffi::export]
pub fn ping() -> String {
    "pong from Rust".to_string()
}

#[uniffi::export]
pub fn system_info() -> String {
    format!("tap-talk-core v{}, aarch64-apple-darwin", env!("CARGO_PKG_VERSION"))
}

// --- Audio Recording ---

#[derive(uniffi::Record)]
pub struct RecordingResult {
    pub samples: Vec<f32>,
    pub sample_count: u64,
    pub duration_secs: f32,
}

#[derive(uniffi::Object)]
pub struct Recorder {
    inner: audio::AudioRecorder,
}

#[uniffi::export]
impl Recorder {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: audio::AudioRecorder::create(),
        }
    }

    pub fn is_recording(&self) -> bool {
        self.inner.is_recording()
    }

    pub fn start(&self) -> Result<(), CoreError> {
        self.inner.start().map_err(|msg| CoreError::Audio { msg })
    }

    pub fn stop(&self) -> Result<RecordingResult, CoreError> {
        let samples = self.inner.stop().map_err(|msg| CoreError::Audio { msg })?;
        let trimmed = audio::trim_silence(&samples).map_err(|msg| CoreError::Audio { msg })?;
        let sample_count = trimmed.len() as u64;
        let duration_secs = sample_count as f32 / 16_000.0;

        Ok(RecordingResult {
            samples: trimmed,
            sample_count,
            duration_secs,
        })
    }
}

// --- Transcription ---

#[derive(uniffi::Record)]
pub struct TranscriptionResult {
    pub text: String,
    pub language: String,
    pub duration_ms: u64,
}

#[derive(uniffi::Record)]
pub struct ModelTierInfo {
    pub id: u8,
    pub name: String,
    pub ggml_filename: String,
    pub disk_size_mb: u32,
}

#[uniffi::export]
pub fn available_tiers() -> Vec<ModelTierInfo> {
    transcribe::TIERS.iter().map(|t| ModelTierInfo {
        id: t.id,
        name: t.name.to_string(),
        ggml_filename: t.ggml_filename.to_string(),
        disk_size_mb: t.disk_size_mb,
    }).collect()
}

#[derive(uniffi::Object)]
pub struct Transcriber {
    engine: std::sync::Mutex<Option<transcribe::WhisperEngine>>,
}

#[uniffi::export]
impl Transcriber {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            engine: std::sync::Mutex::new(None),
        }
    }

    pub fn load_model(&self, tier: u8, models_dir: String) -> Result<(), CoreError> {
        let engine = transcribe::WhisperEngine::load(tier, std::path::Path::new(&models_dir))
            .map_err(|msg| CoreError::Model { msg })?;

        let mut guard = self.engine.lock().map_err(|e| CoreError::Model { msg: format!("{e}") })?;
        *guard = Some(engine);
        Ok(())
    }

    pub fn current_tier(&self) -> Option<u8> {
        self.engine.lock().ok()?.as_ref().map(|e| e.tier_id())
    }

    pub fn transcribe(&self, samples: Vec<f32>, language: Option<String>) -> Result<TranscriptionResult, CoreError> {
        let guard = self.engine.lock()
            .map_err(|e| CoreError::Transcription { msg: format!("{e}") })?;

        let engine = guard.as_ref()
            .ok_or_else(|| CoreError::Model { msg: "no model loaded".into() })?;

        let result = engine.transcribe(&samples, language.as_deref())
            .map_err(|msg| CoreError::Transcription { msg })?;

        Ok(TranscriptionResult {
            text: result.text,
            language: result.language,
            duration_ms: result.duration_ms,
        })
    }
}

// --- Model Manager ---

#[derive(uniffi::Record)]
pub struct DownloadProgressInfo {
    pub tier: u8,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub done: bool,
}

#[uniffi::export(callback_interface)]
pub trait DownloadProgressCallback: Send + Sync {
    fn on_progress(&self, progress: DownloadProgressInfo);
}

#[derive(uniffi::Object)]
pub struct ModelManager {
    inner: models::ModelManager,
}

#[uniffi::export]
impl ModelManager {
    #[uniffi::constructor]
    pub fn new(models_dir: String) -> Self {
        Self {
            inner: models::ModelManager::new(std::path::Path::new(&models_dir)),
        }
    }

    pub fn models_dir(&self) -> String {
        self.inner.models_dir().to_string_lossy().to_string()
    }

    pub fn is_installed(&self, tier: u8) -> bool {
        self.inner.is_installed(tier)
    }

    pub fn installed_tiers(&self) -> Vec<u8> {
        self.inner.installed_tiers()
    }

    pub fn download(&self, tier: u8, callback: Box<dyn DownloadProgressCallback>) -> Result<(), CoreError> {
        self.inner.download(tier, &|progress| {
            callback.on_progress(DownloadProgressInfo {
                tier: progress.tier,
                bytes_downloaded: progress.bytes_downloaded,
                total_bytes: progress.total_bytes,
                done: matches!(progress.status, models::manager::DownloadStatus::Complete),
            });
        }).map_err(|msg| CoreError::Model { msg })
    }

    pub fn delete(&self, tier: u8) -> Result<(), CoreError> {
        self.inner.delete(tier).map_err(|msg| CoreError::Model { msg })
    }
}
