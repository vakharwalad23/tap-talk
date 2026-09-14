# Orukeet vs Parakeet benchmarks

Head-to-head WER (and CER) on FLEURS through FluidAudio (Core ML / ANE), the runtime TapTalk uses.
Method, build, and run steps are in [`../BENCHMARKS.md`](../BENCHMARKS.md). WER uses number
normalization, see [`../score.py`](../score.py).

## Full FLEURS (definitive)

The complete test set the Orukeet paper reports on: 25 languages, 20,146 clips, WER and CER. See
[`fleurs-full/`](fleurs-full/README.md).

- Pooled WER: Parakeet 13.98% vs Orukeet 11.80% (int8), a 15.6% relative reduction.
- Orukeet wins WER on 23 of 25 languages, matching the paper. Largest gains on higher-error languages
  (Latvian, Maltese, Lithuanian, Estonian).
- Precision (float32 vs int8) is negligible; latency is ~14 ms slower for Orukeet, a conversion artifact.

## Quick samples (superseded)

Runs 01 through 04 below used 60 to 100 clips over a few low-error European languages as a smoke test.
They looked roughly tied, because that small sample missed the higher-error languages where Orukeet
gains the most. Kept for history; the full FLEURS run above is the real result.

| Report | Set | Precision | Overall Orukeet vs Parakeet |
|---|---|---|---|
| [01-english-fp32](01-english-fp32/report.md) | en_us, 100 | Orukeet float32 | -0.64 pp |
| [02-english-int8](02-english-int8/report.md) | en_us, 100 | both int8 | -0.55 pp |
| [03-multilingual-fp32](03-multilingual-fp32/report.md) | 6 languages, 360 | Orukeet float32 | +0.24 pp |
| [04-multilingual-int8](04-multilingual-int8/report.md) | 6 languages, 360 | both int8 | +0.16 pp |
