mod llm;
mod models;
mod transcribe;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("{msg}")]
    Model { msg: String },
    #[error("{msg}")]
    Transcription { msg: String },
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
