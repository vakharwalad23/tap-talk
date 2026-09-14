# Full FLEURS English: Orukeet (float32) vs Parakeet (int8)

FLEURS English test split, all 647 clips, FluidAudio Core ML / ANE. Orukeet uses its float32 encoder,
Parakeet its int8 encoder. English slice of the full multilingual float32 run. Table in `summary.md`.

| Metric | Parakeet | Orukeet | Delta |
|---|---|---|---|
| WER | 5.59% | 5.21% | -0.38 pp |
| CER | 2.38% | 2.09% | -0.29 pp |

Orukeet lowers English WER and CER. Precision barely moves it: 5.21% float32 versus 5.23% int8
(report english-int8).

Caveat: encoder precision differs (Orukeet float32 vs Parakeet int8), so latency is not comparable
here. Latency: parakeet 78.8 ms, orukeet 92.5 ms median warm per clip.
