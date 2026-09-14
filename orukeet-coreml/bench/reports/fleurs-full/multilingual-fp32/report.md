# Full FLEURS multilingual: Orukeet (float32) vs Parakeet (int8)

All 25 FLEURS languages, 20,146 clips, FluidAudio Core ML / ANE. Orukeet uses its float32 encoder,
Parakeet its int8 encoder. Full per-language WER and CER with pooled and language-macro rows are in
`summary.md`.

| Metric | Parakeet | Orukeet | Delta |
|---|---|---|---|
| Pooled WER | 13.98% | 11.81% | -2.17 pp (-15.5% rel) |
| Pooled CER | 4.35% | 3.96% | -0.39 pp |
| Language macro WER | 14.08% | 11.94% | -2.14 pp |

The result is effectively identical to the int8 run (report multilingual-int8): pooled WER 11.81%
float32 versus 11.80% int8. Quantizing the Orukeet encoder to int8 does not move the multilingual
result. Orukeet wins WER on the same 23 of 25 languages, losing French and German.

Latency: parakeet 84.2 ms, orukeet 99.1 ms median warm per clip. Encoder precision differs here
(Orukeet float32 vs Parakeet int8), so latency is indicative only; report multilingual-int8 matches
precision.
