use std::path::Path;
use std::sync::Mutex;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

use super::tiers;
use crate::platform::{self, ChipFamily, ChipInfo};

pub struct WhisperEngine {
    ctx: Mutex<WhisperContext>,
    tier_id: u8,
    chip: ChipInfo,
}

pub struct TranscriptionResult {
    pub text: String,
    pub language: String,
    pub duration_ms: u64,
}

impl WhisperEngine {
    pub fn load(tier_id: u8, models_dir: &Path) -> Result<Self, String> {
        let tier = tiers::tier_by_id(tier_id)
            .ok_or_else(|| format!("unknown tier: {tier_id}"))?;

        let model_path = models_dir.join(tier.ggml_filename);
        if !model_path.exists() {
            return Err(format!("model not found: {}", model_path.display()));
        }

        let path_str = model_path.to_str()
            .ok_or_else(|| "model path contains non-UTF-8 characters".to_string())?;

        let chip = platform::detect();
        let mut params = WhisperContextParameters::default();
        // M1 GPU is known to be flaky with flash-attention on some attention shapes.
        // Enable only on M2+ where it's stable and yields ~20% encoder speedup.
        if matches!(chip.family, ChipFamily::M2 | ChipFamily::M3 | ChipFamily::M4 | ChipFamily::M5) {
            params.flash_attn(true);
        }

        let ctx = WhisperContext::new_with_params(path_str, params)
            .map_err(|e| format!("failed to load model: {e}"))?;

        Ok(Self {
            ctx: Mutex::new(ctx),
            tier_id,
            chip,
        })
    }

    pub fn tier_id(&self) -> u8 {
        self.tier_id
    }

    pub fn transcribe(
        &self,
        samples: &[f32],
        language: Option<&str>,
    ) -> Result<TranscriptionResult, String> {
        let start = std::time::Instant::now();

        let ctx = self.ctx.lock().map_err(|e| format!("lock: {e}"))?;
        let mut state = ctx.create_state().map_err(|e| format!("state: {e}"))?;

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_single_segment(false);
        params.set_n_threads(self.chip.performance_cores.max(2) as i32);

        // Encoder cost scales with audio_ctx tokens. ~50 tokens per second of audio.
        // Default 1500 over-processes short utterances; cap trims it without affecting long clips.
        let secs = (samples.len() as f32 / 16_000.0).ceil() as i32;
        let audio_ctx = ((secs * 50) + 64).clamp(256, 1500);
        params.set_audio_ctx(audio_ctx);

        match language {
            Some(lang) => params.set_language(Some(lang)),
            None => params.set_language(None),
        }

        state.full(params, samples)
            .map_err(|e| format!("transcription failed: {e}"))?;

        let n_segments = state.full_n_segments()
            .map_err(|e| format!("segments: {e}"))?;

        let mut text = String::new();
        for i in 0..n_segments {
            if let Ok(segment) = state.full_get_segment_text(i) {
                text.push_str(&segment);
            }
        }

        let detected_lang = state.full_lang_id_from_state()
            .ok()
            .and_then(|id| whisper_rs::get_lang_str(id).map(|s| s.to_string()))
            .unwrap_or_else(|| "unknown".to_string());

        let duration_ms = start.elapsed().as_millis() as u64;

        #[cfg(debug_assertions)]
        eprintln!(
            "tt-perf total={}ms cores={} family={:?} audio_ctx={} secs={}",
            duration_ms,
            self.chip.performance_cores,
            self.chip.family,
            audio_ctx,
            secs,
        );

        Ok(TranscriptionResult {
            text: text.trim().to_string(),
            language: detected_lang,
            duration_ms,
        })
    }
}
