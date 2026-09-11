# Orukeet vs Parakeet benchmarks

Head-to-head WER on FLEURS through FluidAudio (Core ML / ANE), the runtime TapTalk uses. Method,
build, and run steps are in [`../BENCHMARKS.md`](../BENCHMARKS.md). Each report keeps its own
`results.json` (raw hypotheses and timings) and `summary.md` (scored). WER uses number normalization,
see [`../score.py`](../score.py).

| Report | Set | Precision | Overall Orukeet vs Parakeet |
|---|---|---|---|
| [01-english-fp32](01-english-fp32/report.md) | FLEURS en_us, 100 | Orukeet float32, Parakeet int8 | -0.64 pp (Orukeet better) |
| [02-english-int8](02-english-int8/report.md) | FLEURS en_us, 100 | both int8 | -0.55 pp (Orukeet better) |
| [03-multilingual-fp32](03-multilingual-fp32/report.md) | FLEURS 6 languages, 360 | Orukeet float32, Parakeet int8 | +0.24 pp (roughly tied) |
| [04-multilingual-int8](04-multilingual-int8/report.md) | FLEURS 6 languages, 360 | both int8 | +0.16 pp (roughly tied) |

## Takeaways

- English: Orukeet lowers WER by about 0.5 to 0.6 pp, and precision (float32 vs int8) barely moves it.
- Multilingual: mixed and close on this small sample (Orukeet wins English, Parakeet wins German,
  French, Russian), roughly tied overall either precision. Orukeet does not reproduce the paper's win
  on 23 of 25 languages here. Confirming that needs the full FLEURS test split, matched decoding, and
  per-language normalization.
- Precision barely affects WER: quantizing the Orukeet encoder to int8 moves English by ~0.09 pp and
  the multilingual overall by ~0.08 pp.
- Latency: Orukeet runs about 10 to 12 ms slower per clip. The architecture is identical to Parakeet,
  so this is a conversion artifact: our int8 encoder is 568 MB against FluidInference's 425 MB. A
  matched conversion and quantization recipe would close the gap.
