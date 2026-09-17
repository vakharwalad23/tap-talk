# Benchmark method

Head-to-head WER and CER on FLEURS, both models through FluidAudio on Core ML / ANE, the runtime
TapTalk uses. Run it with `make bench`; see [RUNNING.md](RUNNING.md). Results are written to
`reports/` locally (gitignored, not committed).

## Method

- Models: `make models` stages Parakeet from Hugging Face (`FluidInference/parakeet-tdt-0.6b-v3-coreml`)
  and Orukeet from the converted bundles in `out/`, each under `models/<name>/parakeet-tdt-0.6b-v3/`
  with the exact file set `AsrModels.load(from:)` expects. Parakeet is never taken from a local install,
  so the run reproduces anywhere.
- Clips: FLEURS test split via `scripts/bench/fleurs_prep.py`, written as 16 kHz mono wav. `make data`
  downloads all 25 languages; `scripts/bench/probe_fleurs.py` (`make probe`) verifies the codes against
  the paper's per-language counts.
- Inference: the Swift harness (`swift/`) loads one model and transcribes every clip. Each model runs
  once (`scripts/bench/run_passes.sh`): Parakeet is deterministic, so one pass serves both precision
  comparisons. Loading never downloads (`ModelHub.offlineMode`); a staging mistake fails instead of
  falling back.
- Scoring: `scripts/bench/score.py` merges the raw passes and reports per-language WER and CER plus
  pooled and language-macro rows. Text is lowercased, punctuation stripped, and spoken numbers folded
  to digits (English) before scoring, applied equally to both models.

## Caveats

- Encoder precision: reports pair Orukeet float32 or int8 against Parakeet int8. WER is close either
  way; latency is only comparable in the int8 pairing, and even there this earlier int8 conversion of
  Orukeet runs somewhat slower because its int8 encoder is less compressed than FluidInference's. The
  shipped optimized greedy build (Oruk-AI/orukeet#6) closes that gap.
- Orukeet emits one benign Core ML shape-inference warning (`ios17.slice_by_index`) at setup. It does
  not affect output and does not occur for Parakeet.
- Number normalization is English only; other languages get lowercase and punctuation stripping.
