# Full FLEURS multilingual: Orukeet (int8) vs Parakeet (int8)

All 25 FLEURS languages, 20,146 clips, matched int8 encoders, FluidAudio Core ML / ANE. Full
per-language WER and CER with pooled and language-macro rows are in `summary.md`.

| Metric | Parakeet | Orukeet | Delta |
|---|---|---|---|
| Pooled WER | 13.98% | 11.80% | -2.17 pp (-15.6% rel) |
| Pooled CER | 4.35% | 3.94% | -0.41 pp |
| Language macro WER | 14.08% | 11.93% | -2.15 pp |

Orukeet wins WER on 23 of 25 languages, losing only French (+0.76) and German (+0.49). Largest gains:
Latvian -8.03, Maltese -7.32, Lithuanian -5.98, Estonian -4.09. CER improves pooled but is mixed per
language (Orukeet wins 14 of 25); it regresses on some low-error languages (German +1.39, French +0.89)
where Orukeet favors different but valid spacing or spelling that the normalizer does not fold.

This matches the paper's reported 23-of-25 win count. Absolute WERs are higher than the paper's because
of lighter, English-only number normalization and Core ML int8 decoding versus the paper's NeMo
pipeline; the relative reduction (15.6%) exceeds the paper's 10.6%.

Latency: parakeet 84.2 ms, orukeet 98.5 ms median warm per clip. Same architecture, so the gap is a
conversion artifact (our int8 encoder is less compressed than FluidInference's), not a model
difference.
