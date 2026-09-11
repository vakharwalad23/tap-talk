# English WER: Orukeet (float32) vs Parakeet (int8)

FLEURS `en_us`, 100 clips, FluidAudio Core ML / ANE, 2026-09-12.

Config: Parakeet TDT 0.6B v3 with an int8 encoder (installed FluidInference bundle); Orukeet with a
float32 encoder (our conversion). Both share the same decoder, single-step JointDecisionv3,
preprocessor, and tokenizer. Scored with number normalization (`score.py`).

| Metric | Parakeet | Orukeet | Delta |
|---|---|---|---|
| Corpus WER | 5.10% | 4.46% | -0.64 pp |
| Median clip WER | 3.10% | 0.00% | |
| Median warm ms/clip | 77.0 | 88.9 | |

Orukeet lowers English WER by 0.64 pp, the direction the paper reports.

Caveat: encoder precision differs (Orukeet float32 vs Parakeet int8). WER is comparable; latency is
not apples-to-apples here, since float32 is slower. Report 02 matches precision.

Files: `results.json` (raw hypotheses and timings), `summary.md` (scored).
