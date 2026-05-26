mod audio;
mod llm;
mod models;
mod platform;
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

#[derive(uniffi::Record)]
pub struct RecordingResult {
    pub samples: Vec<f32>,
    pub sample_count: u64,
    pub duration_secs: f32,
}

#[uniffi::export(callback_interface)]
pub trait AudioLevelCallback: Send + Sync {
    fn on_level(&self, rms: f32);
}

#[uniffi::export(callback_interface)]
pub trait AudioChunkCallback: Send + Sync {
    fn on_chunk(&self, samples: Vec<f32>);
}

#[derive(uniffi::Object)]
pub struct Recorder {
    inner: audio::AudioRecorder,
}

impl Default for Recorder {
    fn default() -> Self {
        Self::new()
    }
}

#[uniffi::export]
impl Recorder {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: audio::AudioRecorder::create(),
        }
    }

    /// Registers a sink for live mic RMS level (~30 Hz) to drive the recording pill.
    pub fn set_level_callback(&self, callback: Box<dyn AudioLevelCallback>) {
        self.inner.set_level_callback(Box::new(move |rms| callback.on_level(rms)));
    }

    /// Registers a sink for live mono audio chunks at the device's source sample rate.
    /// Set this before start() to feed a streaming transcriber; clear it after finish/cancel.
    pub fn set_audio_chunk_callback(&self, callback: Box<dyn AudioChunkCallback>) {
        self.inner.set_chunk_callback(Box::new(move |samples| callback.on_chunk(samples)));
    }

    /// Removes any previously-set chunk callback. Zero overhead in the audio thread afterward.
    pub fn clear_audio_chunk_callback(&self) {
        self.inner.clear_chunk_callback();
    }

    /// Source sample rate of the warmed input stream, in Hz. None if warm_up() has not run.
    /// Streaming engines need this to build AVAudioPCMBuffer in the right format.
    pub fn input_sample_rate(&self) -> Option<u32> {
        self.inner.source_sample_rate()
    }

    /// Pre-creates the CoreAudio AudioUnit so the TCC mic dialog happens early.
    pub fn warm_up(&self) -> Result<(), CoreError> {
        self.inner.warm_up().map_err(|msg| CoreError::Audio { msg })
    }

    pub fn start(&self) -> Result<(), CoreError> {
        self.inner.start().map_err(|msg| CoreError::Audio { msg })
    }

    pub fn stop(&self) -> Result<RecordingResult, CoreError> {
        let samples = self.inner.stop().map_err(|msg| CoreError::Audio { msg })?;
        let trimmed = audio::trim_silence(&samples).map_err(|msg| CoreError::Audio { msg })?;

        // Real speech duration (before any padding) for the UI.
        let duration_secs = trimmed.len() as f32 / 16_000.0;

        // Too short to be a real utterance — return empty so the UI shows
        // "Too short — hold longer" instead of a hallucinated transcript.
        if trimmed.len() < audio::MIN_SPEECH_SAMPLES {
            return Ok(RecordingResult { samples: Vec::new(), sample_count: 0, duration_secs: 0.0 });
        }

        // Lift quiet/murmured speech toward conversational loudness — helps every engine.
        // Short-clip noise padding is a whisper.cpp-only hallucination workaround applied in
        // the whisper path; cloud and Parakeet receive the natural (unpadded) clip.
        let mut processed = trimmed;
        let _gain = audio::apply_agc(&mut processed);

        #[cfg(debug_assertions)]
        eprintln!("tt-agc speech_secs={:.2} gain={:.2}x out_len={}", duration_secs, _gain, processed.len());

        let sample_count = processed.len() as u64;
        Ok(RecordingResult {
            samples: processed,
            sample_count,
            duration_secs,
        })
    }
}

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

impl Default for Transcriber {
    fn default() -> Self {
        Self::new()
    }
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

    /// Frees the loaded whisper model and its Core ML encoder to reclaim memory when the
    /// user switches to another engine (Parakeet/cloud).
    pub fn unload(&self) {
        if let Ok(mut guard) = self.engine.lock() {
            *guard = None;
        }
    }

    /// Whether a model is currently loaded — lets the caller reload on demand after an
    /// idle release without tracking state separately.
    pub fn is_loaded(&self) -> bool {
        self.engine.lock().map(|g| g.is_some()).unwrap_or(false)
    }

    pub fn transcribe(&self, samples: Vec<f32>, language: Option<String>) -> Result<TranscriptionResult, CoreError> {
        // whisper.cpp needs at least ~0.1s of audio at 16kHz
        if samples.len() < 1600 {
            return Ok(TranscriptionResult {
                text: String::new(),
                language: "unknown".into(),
                duration_ms: 0,
            });
        }

        let guard = self.engine.lock()
            .map_err(|e| CoreError::Transcription { msg: format!("{e}") })?;

        let engine = guard.as_ref()
            .ok_or_else(|| CoreError::Model { msg: "no model loaded".into() })?;

        // Pad short clips to ~1.5s with low-level noise — whisper.cpp hallucinates on very
        // short utterances. Applied here (whisper-only), not in capture.
        let mut padded = samples;
        audio::pad_short_clip(&mut padded, 1.5);

        let result = engine.transcribe(&padded, language.as_deref())
            .map_err(|msg| CoreError::Transcription { msg })?;

        Ok(TranscriptionResult {
            text: result.text,
            language: result.language,
            duration_ms: result.duration_ms,
        })
    }
}

/// Validate an OpenAI API key by calling the models endpoint.
#[uniffi::export]
pub fn test_cloud_connection(api_key: String) -> Result<String, CoreError> {
    transcribe::test_cloud_connection(&api_key)
        .map_err(|msg| CoreError::Transcription { msg })
}

/// Transcribe audio via OpenAI Whisper API. Blocks until response arrives.
#[uniffi::export]
pub fn transcribe_cloud(
    samples: Vec<f32>,
    language: Option<String>,
    model: String,
    api_key: String,
) -> Result<TranscriptionResult, CoreError> {
    if samples.len() < 1600 {
        return Ok(TranscriptionResult {
            text: String::new(),
            language: "unknown".into(),
            duration_ms: 0,
        });
    }

    transcribe::transcribe_cloud(&samples, language.as_deref(), &model, &api_key)
        .map(|r| TranscriptionResult {
            text: r.text,
            language: r.language,
            duration_ms: r.duration_ms,
        })
        .map_err(|msg| CoreError::Transcription { msg })
}

#[derive(uniffi::Enum)]
pub enum DownloadPhase {
    Ggml,
    CoreMl,
    Complete,
}

#[derive(uniffi::Record)]
pub struct DownloadProgressInfo {
    pub tier: u8,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub done: bool,
    pub phase: DownloadPhase,
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
    pub fn new(models_dir: String) -> Result<Self, CoreError> {
        Ok(Self {
            inner: models::ModelManager::new(std::path::Path::new(&models_dir))
                .map_err(|msg| CoreError::Model { msg })?,
        })
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

    pub fn installed_tiers_missing_coreml(&self) -> Vec<u8> {
        self.inner.installed_tiers_missing_coreml()
    }

    pub fn download(&self, tier: u8, callback: Box<dyn DownloadProgressCallback>) -> Result<(), CoreError> {
        self.inner.download(tier, &|progress| {
            callback.on_progress(map_progress(&progress));
        }).map_err(|msg| CoreError::Model { msg })
    }

    pub fn download_coreml_only(&self, tier: u8, callback: Box<dyn DownloadProgressCallback>) -> Result<(), CoreError> {
        self.inner.download_coreml_only(tier, &|progress| {
            callback.on_progress(map_progress(&progress));
        }).map_err(|msg| CoreError::Model { msg })
    }

    pub fn delete(&self, tier: u8) -> Result<(), CoreError> {
        self.inner.delete(tier).map_err(|msg| CoreError::Model { msg })
    }

    /// Removes only the Core ML encoder optimization for a tier; keeps the ggml model.
    pub fn delete_coreml(&self, tier: u8) -> Result<(), CoreError> {
        self.inner.delete_coreml(tier).map_err(|msg| CoreError::Model { msg })
    }

    pub fn is_llm_installed(&self, model_id: String) -> bool {
        self.inner.is_llm_installed(&model_id)
    }

    pub fn llm_model_path(&self, model_id: String) -> Option<String> {
        self.inner.llm_model_path(&model_id)
            .map(|p| p.to_string_lossy().to_string())
    }

    pub fn download_llm(&self, model_id: String, callback: Box<dyn LlmDownloadProgressCallback>) -> Result<(), CoreError> {
        self.inner.download_llm(&model_id, &|progress| {
            callback.on_progress(LlmDownloadProgressInfo {
                model_id: progress.model_id.clone(),
                bytes_downloaded: progress.bytes_downloaded,
                total_bytes: progress.total_bytes,
                done: progress.done,
            });
        }).map_err(|msg| CoreError::Model { msg })
    }

    pub fn delete_llm(&self, model_id: String) -> Result<(), CoreError> {
        self.inner.delete_llm(&model_id).map_err(|msg| CoreError::Model { msg })
    }
}

fn map_progress(progress: &models::manager::DownloadProgress) -> DownloadProgressInfo {
    let (done, phase) = match progress.status {
        models::manager::DownloadStatus::Downloading => (false, DownloadPhase::Ggml),
        models::manager::DownloadStatus::DownloadingCoreMl => (false, DownloadPhase::CoreMl),
        models::manager::DownloadStatus::Complete => (true, DownloadPhase::Complete),
    };
    DownloadProgressInfo {
        tier: progress.tier,
        bytes_downloaded: progress.bytes_downloaded,
        total_bytes: progress.total_bytes,
        done,
        phase,
    }
}

#[derive(uniffi::Record)]
pub struct LlmDownloadProgressInfo {
    pub model_id: String,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub done: bool,
}

#[uniffi::export(callback_interface)]
pub trait LlmDownloadProgressCallback: Send + Sync {
    fn on_progress(&self, progress: LlmDownloadProgressInfo);
}

