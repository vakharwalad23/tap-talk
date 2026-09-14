# Orukeet vs Parakeet benchmark

Head-to-head WER and CER on FLEURS, both models run through FluidAudio on Core ML / ANE, the same
runtime TapTalk uses. Both models are staged locally in the identical directory layout and loaded the
same way, so the run reproduces on any Apple Silicon Mac.

## Method

- Models: `prep_models.sh` stages Parakeet and Orukeet (float32) under
  `models/<name>/parakeet-tdt-0.6b-v3/`; `build_orukeet_int8.sh` adds an int8-encoder Orukeet. Each
  directory has the exact file set `AsrModels.load(from:)` expects. Parakeet is copied from the
  installed FluidAudio cache (or downloaded).
- Clips: FLEURS test split via `fleurs_prep.py`, written as 16 kHz mono wav. `--limit 0` takes every
  clip. `probe_fleurs.py` verifies the 25 language codes against the paper's per-language counts.
- Inference: `ttbench` loads one model and transcribes every clip. Each model runs once
  (`run_full_bench.sh`): Parakeet is deterministic, so one pass serves both precision comparisons.
  Loading never downloads (`ModelHub.offlineMode`); a staging mistake fails instead of falling back.
- Scoring: `score.py` merges the raw passes and reports per-language WER and CER plus pooled and
  language-macro rows. Text is lowercased, punctuation stripped, and spoken numbers folded to digits
  (English) before scoring, applied equally to both models. `make_full_reports.sh` writes the four
  reports.
- Latency: median processing time per clip, first clip per model dropped as warm-up.

## Caveats

- Encoder precision: reports pair Orukeet float32 or int8 against Parakeet int8. WER is comparable
  either way (precision moves pooled WER by ~0.01 pp); latency is only comparable in the int8 pairing,
  and even there Orukeet runs ~14 ms slower because our int8 encoder is less compressed than
  FluidInference's.
- Orukeet emits one benign Core ML shape-inference warning (`ios17.slice_by_index`) at setup. It does
  not affect output. It does not occur for Parakeet.
- Number normalization is English only; other languages get lowercase and punctuation stripping.

## Run (full FLEURS, 25 languages)

```bash
./setup.sh && ./run_conversion.sh
bench/prep_models.sh && bench/build_orukeet_int8.sh
CONV=vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml
LANGS=bg_bg,hr_hr,cs_cz,da_dk,nl_nl,en_us,et_ee,fi_fi,fr_fr,de_de,el_gr,hu_hu,it_it,lv_lv,lt_lt,mt_mt,pl_pl,pt_br,ro_ro,ru_ru,sk_sk,sl_si,es_419,sv_se,uk_ua
uv run --project "$CONV" python bench/probe_fleurs.py         # verify codes vs paper counts
uv run --project "$CONV" python bench/fleurs_prep.py --langs "$LANGS" --limit 0 --out bench/fleurs-full
swift build --package-path bench -c release
bench/run_full_bench.sh && bench/make_full_reports.sh
```

For a quick single-language check, prep with `--langs en_us --limit 100`, run `ttbench` directly with
`--model-dir` and `--label` per model, then `score.py --results <files>`.

## Results

See [`reports/README.md`](reports/README.md). Full FLEURS (25 languages, 20,146 clips) is in
[`reports/fleurs-full/`](reports/fleurs-full/README.md); the 01-04 folders are superseded quick
samples.
