# Orukeet vs Parakeet benchmark

Head-to-head word error rate on FLEURS, both models run through FluidAudio on Core ML / ANE, the
same runtime TapTalk uses. Both models are staged locally in the identical directory layout and
loaded the same way, so the run reproduces on any Apple Silicon Mac.

## Method

- Models: `prep_models.sh` stages both under `models/<name>/parakeet-tdt-0.6b-v3/` with the exact
  file set `AsrModels.load(from:)` expects. Parakeet is copied from the installed FluidAudio cache
  (or downloaded from `FluidInference/parakeet-tdt-0.6b-v3-coreml`); Orukeet is the converted bundle.
- Clips: FLEURS test split, pulled per language by `fleurs_prep.py`, written as 16 kHz mono wav.
- Inference: `ttbench` loads each model through the same local path and transcribes every clip.
  Loading never downloads (`ModelHub.offlineMode`); a staging mistake fails instead of falling back.
- Scoring: `score.py` computes WER, `sum(word edits) / sum(reference words)`, after lowercase,
  punctuation to spaces, and spoken-number to digit normalization (so "twenty nine" is not counted
  wrong against "29"). Reference and hypothesis pass through the same normalizer.
- Latency: median processing time per clip, first clip per model dropped as warm-up.

## Caveats

- Encoder precision differs: Parakeet is int8 (461 MB), the converted Orukeet is float32 (1.1 GB).
  WER is comparable; latency is indicative only until both are matched.
- Orukeet emits one benign Core ML shape-inference warning (`ios17.slice_by_index`) at setup. It
  does not affect output (no empty or broken transcripts). It does not occur for Parakeet.

## Run

```bash
./setup.sh                                   # once: converter env (also enables the prep fallback)
./run_conversion.sh                          # once: produces out/orukeet-tdt-0.6b-v3-coreml
bench/prep_models.sh                          # stage both models locally, identical layout
CONV=vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml
uv run --project "$CONV" python bench/fleurs_prep.py --langs en_us --limit 100 --out bench/fleurs
swift build --package-path bench -c release
bench/.build/release/ttbench \
  --manifest bench/fleurs/manifest.jsonl \
  --parakeet bench/models/parakeet/parakeet-tdt-0.6b-v3 \
  --orukeet  bench/models/orukeet/parakeet-tdt-0.6b-v3 \
  --out bench/results
python3 bench/score.py --results bench/results/results.json
```

`--langs` takes comma separated FLEURS codes (e.g. `en_us,de_de,fr_fr`). `score.py` writes
`summary.md` next to `results.json`.

## Results

FLEURS English (`en_us`), 100 clips, Apple Silicon, 2026-09-12. Scored with number normalization.

| Language | Clips | Parakeet WER | Orukeet WER | Delta (pp) |
|---|---|---|---|---|
| en_us | 100 | 5.10% | 4.46% | -0.64 |
| Overall | 100 | 5.10% | 4.46% | -0.64 |

Median clip WER: parakeet 3.10%, orukeet 0.00%. Median warm processing time per clip: parakeet
77.0 ms, orukeet 88.9 ms (float32 encoder, see caveats).

Orukeet lowers English WER by 0.64 pp, the direction the paper reports. Absolute numbers run higher
than the paper's, which uses NeMo normalization over the full test set; the relative result holds.
