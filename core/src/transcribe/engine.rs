use std::path::Path;
use std::sync::Mutex;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

use super::tiers;

pub struct WhisperEngine {
    ctx: Mutex<WhisperContext>,
    tier_id: u8,
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

        let params = WhisperContextParameters::default();
        let ctx = WhisperContext::new_with_params(model_path.to_str().unwrap(), params)
            .map_err(|e| format!("failed to load model: {e}"))?;

        Ok(Self {
            ctx: Mutex::new(ctx),
            tier_id,
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

        Ok(TranscriptionResult {
            text: text.trim().to_string(),
            language: detected_lang,
            duration_ms,
        })
    }
}
