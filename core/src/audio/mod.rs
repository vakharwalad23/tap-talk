mod capture;
mod vad;

pub use capture::AudioRecorder;
pub use vad::{trim_silence, SileroVad, VAD_CHUNK_SIZE};
