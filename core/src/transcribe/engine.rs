use std::path::Path;
use std::sync::Mutex;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

use super::tiers;
use crate::platform::{self, ChipInfo};

pub struct WhisperEngine {
    ctx: Mutex<WhisperContext>,
    tier_id: u8,
    chip: ChipInfo,
    // Whether the Core ML encoder bundle is present (whisper.cpp auto-loads it). It has a
    // fixed audio context, so audio_ctx tuning is only applied on the pure-Metal path.
    coreml_present: bool,
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

        // whisper.cpp auto-loads a sibling `<name>-encoder.mlmodelc` if present.
        let coreml_present = models_dir.join(tier.coreml_filename).is_dir();

        let chip = platform::detect();
        let mut params = WhisperContextParameters::default();
        // M1 GPU is flaky with flash-attention on some attention shapes; M2 and newer
        // are stable and gain ~20% encoder speedup.
        if chip.family.supports_flash_attn() {
            params.flash_attn(true);
        }

        let ctx = WhisperContext::new_with_params(path_str, params)
            .map_err(|e| format!("failed to load model: {e}"))?;

        Ok(Self {
            ctx: Mutex::new(ctx),
            tier_id,
            chip,
            coreml_present,
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

        // audio_ctx trims the encoder to the clip length (~50 tokens/sec) for faster
        // short-clip encoding — but ONLY on the Metal path. The Core ML encoder is
        // compiled for a fixed 1500-token context; a custom value feeds it the wrong
        // shape and yields garbage, so it's left at the default when Core ML is present.
        if !self.coreml_present {
            let secs = (samples.len() as f32 / 16_000.0).ceil() as i32;
            let audio_ctx = ((secs * 50) + 64).clamp(256, 1500);
            params.set_audio_ctx(audio_ctx);
        }

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
            "tt-perf total={}ms cores={} family={:?} samples={}",
            duration_ms,
            self.chip.performance_cores,
            self.chip.family,
            samples.len(),
        );

        Ok(TranscriptionResult {
            text: text.trim().to_string(),
            language: detected_lang,
            duration_ms,
        })
    }
}
