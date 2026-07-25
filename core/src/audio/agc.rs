// Software AGC + short-clip padding. Operates on already-captured 16 kHz mono f32 —
// never touches the capture device, mic permission, or the Core ML encoder.

const SAMPLE_RATE: usize = 16_000;

// dBFS thresholds expressed as linear RMS.
const TARGET_RMS: f32 = 0.0708; // -23 dBFS — broadcast speech loudness
const BYPASS_RMS: f32 = 0.0501; // -26 dBFS — at/above this, leave audio untouched
const PEAK_LIMIT: f32 = 0.95;
const MAX_GAIN: f32 = 10.0; // ~+20 dB cap so near-silence isn't blown into noise

/// Minimum trimmed speech length (~300 ms) to treat as a real utterance.
pub const MIN_SPEECH_SAMPLES: usize = SAMPLE_RATE * 300 / 1000;

/// Lifts quiet/murmured audio toward conversational loudness; no-op for audio
/// already at conversational level. Returns the gain applied (for debug logging).
pub fn apply_agc(samples: &mut [f32]) -> f32 {
    let rms = rms(samples);
    if rms >= BYPASS_RMS || rms <= f32::EPSILON {
        return 1.0;
    }
    let mut gain = (TARGET_RMS / rms).min(MAX_GAIN);
    let peak = samples.iter().fold(0.0f32, |m, &s| m.max(s.abs()));
    if peak > 0.0 && peak * gain > PEAK_LIMIT {
        gain = PEAK_LIMIT / peak;
    }
    if gain <= 1.0 {
        return 1.0;
    }
    for s in samples.iter_mut() {
        *s *= gain;
    }
    gain
}

fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum_sq: f32 = samples.iter().map(|s| s * s).sum();
    (sum_sq / samples.len() as f32).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(amp: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| amp * (i as f32 * 0.2).sin()).collect()
    }

    #[test]
    fn boosts_quiet() {
        let mut s = tone(0.01, 16_000); // ~-43 dBFS
        let before = rms(&s);
        let gain = apply_agc(&mut s);
        let after = rms(&s);
        assert!(gain > 1.0, "expected boost, got {gain}");
        assert!(after > before);
        assert!(after > 0.04 && after < 0.10, "after rms {after}");
    }

    #[test]
    fn bypasses_loud() {
        let mut s = tone(0.2, 16_000); // ~-17 dBFS
        let gain = apply_agc(&mut s);
        assert_eq!(gain, 1.0);
    }
}
