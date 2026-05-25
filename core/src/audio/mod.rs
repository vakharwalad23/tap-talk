mod agc;
mod capture;
mod vad;

pub use agc::{apply_agc, pad_short_clip, MIN_SPEECH_SAMPLES};
pub use capture::AudioRecorder;
pub use vad::trim_silence;
