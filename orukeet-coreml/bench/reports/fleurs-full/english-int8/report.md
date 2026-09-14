# Full FLEURS English: Orukeet (int8) vs Parakeet (int8)

FLEURS English test split, all 647 clips, matched int8 encoders, FluidAudio Core ML / ANE. This is the
English slice of the full multilingual int8 run. Table in `summary.md`.

| Metric | Parakeet | Orukeet | Delta |
|---|---|---|---|
| WER | 5.59% | 5.23% | -0.36 pp |
| CER | 2.38% | 2.11% | -0.27 pp |

Orukeet lowers English WER and CER. The full 647-clip split gives a cleaner number than the earlier
100-clip sample (report `../../01-english-fp32`), and the direction is unchanged.

Latency: parakeet 78.8 ms, orukeet 92.1 ms median warm per clip (conversion artifact, see the
multilingual report).
