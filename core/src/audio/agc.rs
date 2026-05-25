// Software AGC + short-clip padding. Operates on already-captured 16 kHz mono f32 —
// never touches the capture device, mic permission, or the Core ML encoder.

const SAMPLE_RATE: usize = 16_000;

// dBFS thresholds expressed as linear RMS.
const TARGET_RMS: f32 = 0.0708; // -23 dBFS — Whisper's training loudness
const BYPASS_RMS: f32 = 0.0501; // -26 dBFS — at/above this, leave audio untouched
const PEAK_LIMIT: f32 = 0.95;
const MAX_GAIN: f32 = 10.0; // ~+20 dB cap so near-silence isn't blown into noise

const NOISE_AMP: f32 = 0.00316; // ~-50 dBFS synthetic pad

/// Minimum trimmed speech length (~300 ms) to treat as a real utterance.
pub const MIN_SPEECH_SAMPLES: usize = SAMPLE_RATE * 300 / 1000;

/// Lifts quiet/murmured audio toward Whisper's training loudness; no-op for audio
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

/// Pads a short clip up to `min_secs` with low-level synthetic noise (not zeros),
/// which Whisper tolerates far better than hard silence on short utterances.
pub fn pad_short_clip(samples: &mut Vec<f32>, min_secs: f32) {
    let min_len = (min_secs * SAMPLE_RATE as f32) as usize;
    if samples.len() >= min_len {
        return;
    }
    let needed = min_len - samples.len();
    samples.reserve(needed);
    let mut rng: u32 = 0x9E37_79B9;
    for _ in 0..needed {
        // xorshift32 — deterministic, no dep
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        let n = (rng as f32 / u32::MAX as f32) * 2.0 - 1.0;
        samples.push(n * NOISE_AMP);
    }
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

    #[test]
    fn pads_with_noise_not_zeros() {
        let mut s = tone(0.05, 8_000); // 0.5s
        pad_short_clip(&mut s, 1.5);
        assert_eq!(s.len(), 24_000);
        let tail = &s[10_000..];
        assert!(tail.iter().any(|&x| x != 0.0));
        let tail_rms = rms(tail);
        assert!(tail_rms > 0.0 && tail_rms < 0.01, "tail rms {tail_rms}");
    }
}
