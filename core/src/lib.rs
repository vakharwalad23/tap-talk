mod audio;
mod llm;
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
        self.inner
            .set_level_callback(Box::new(move |rms| callback.on_level(rms)));
    }

    /// Registers a sink for live mono audio chunks at the device's source sample rate.
    /// Set this before start() to feed a streaming transcriber; clear it after finish/cancel.
    pub fn set_audio_chunk_callback(&self, callback: Box<dyn AudioChunkCallback>) {
        self.inner
            .set_chunk_callback(Box::new(move |samples| callback.on_chunk(samples)));
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
            return Ok(RecordingResult {
                samples: Vec::new(),
                sample_count: 0,
                duration_secs: 0.0,
            });
        }

        // Lift quiet/murmured speech toward conversational loudness — helps every engine.
        let mut processed = trimmed;
        let _gain = audio::apply_agc(&mut processed);

        #[cfg(debug_assertions)]
        eprintln!(
            "tt-agc speech_secs={:.2} gain={:.2}x out_len={}",
            duration_secs,
            _gain,
            processed.len()
        );

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

/// Validate an OpenAI API key by calling the models endpoint.
#[uniffi::export]
pub fn test_cloud_connection(api_key: String) -> Result<String, CoreError> {
    transcribe::test_cloud_connection(&api_key).map_err(|msg| CoreError::Transcription { msg })
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

    pub fn is_llm_installed(&self, model_id: String) -> bool {
        self.inner.is_llm_installed(&model_id)
    }

    pub fn llm_model_path(&self, model_id: String) -> Option<String> {
        self.inner
            .llm_model_path(&model_id)
            .map(|p| p.to_string_lossy().to_string())
    }

    pub fn download_llm(
        &self,
        model_id: String,
        callback: Box<dyn LlmDownloadProgressCallback>,
    ) -> Result<(), CoreError> {
        self.inner
            .download_llm(&model_id, &|progress| {
                callback.on_progress(LlmDownloadProgressInfo {
                    model_id: progress.model_id.clone(),
                    bytes_downloaded: progress.bytes_downloaded,
                    total_bytes: progress.total_bytes,
                    done: progress.done,
                });
            })
            .map_err(|msg| CoreError::Model { msg })
    }

    pub fn delete_llm(&self, model_id: String) -> Result<(), CoreError> {
        self.inner
            .delete_llm(&model_id)
            .map_err(|msg| CoreError::Model { msg })
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
