mod audio;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("{msg}")]
    Audio { msg: String },
}

#[uniffi::export]
pub fn ping() -> String {
    "pong from Rust".to_string()
}

#[uniffi::export]
pub fn system_info() -> String {
    format!("tap-talk-core v{}, aarch64-apple-darwin", env!("CARGO_PKG_VERSION"))
}

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
