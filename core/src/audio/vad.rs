use voice_activity_detector::VoiceActivityDetector;

const SAMPLE_RATE: i64 = 16_000;
const CHUNK_SIZE: usize = 512;
const SPEECH_THRESHOLD: f32 = 0.5;
const PAD_CHUNKS: usize = 4;

/// Samples per VAD chunk at 16 kHz (~32 ms).
pub const VAD_CHUNK_SIZE: usize = CHUNK_SIZE;

/// A persistent Silero detector for streaming, fed one 512-sample chunk at a time
/// in order (the model is recurrent, so call order matters).
pub struct SileroVad {
    inner: VoiceActivityDetector,
    threshold: f32,
}

impl SileroVad {
    pub fn new(threshold: f32) -> Result<Self, String> {
        let inner = VoiceActivityDetector::builder()
            .sample_rate(SAMPLE_RATE)
            .chunk_size(CHUNK_SIZE)
            .build()
            .map_err(|e| format!("vad init: {e}"))?;
        Ok(Self { inner, threshold })
    }

    pub fn is_speech(&mut self, chunk: &[f32]) -> bool {
        self.inner.predict(chunk.iter().copied()) >= self.threshold
    }
}

/// Remove leading and trailing silence from 16kHz mono samples
pub fn trim_silence(samples: &[f32]) -> Result<Vec<f32>, String> {
    if samples.len() < CHUNK_SIZE {
        return Ok(samples.to_vec());
    }

    let mut vad = VoiceActivityDetector::builder()
        .sample_rate(SAMPLE_RATE)
        .chunk_size(CHUNK_SIZE)
        .build()
        .map_err(|e| format!("vad init: {e}"))?;

    let chunks: Vec<&[f32]> = samples.chunks(CHUNK_SIZE)
        .filter(|c| c.len() == CHUNK_SIZE)
        .collect();

    if chunks.is_empty() {
        return Ok(samples.to_vec());
    }

    let speech_flags: Vec<bool> = chunks.iter()
        .map(|chunk| vad.predict(chunk.iter().copied()) >= SPEECH_THRESHOLD)
        .collect();

    let first_speech = match speech_flags.iter().position(|&s| s) {
        Some(pos) => pos,
        None => return Ok(Vec::new()),
    };

    let last_speech = speech_flags.iter().rposition(|&s| s).unwrap_or(first_speech);

    let start = first_speech.saturating_sub(PAD_CHUNKS);
    let end = (last_speech + PAD_CHUNKS + 1).min(chunks.len());

    let start_sample = start * CHUNK_SIZE;
    let end_sample = (end * CHUNK_SIZE).min(samples.len());

    Ok(samples[start_sample..end_sample].to_vec())
}
