# Multilingual WER: Orukeet (float32) vs Parakeet (int8)

FLEURS, 6 European languages, 60 clips each (360 total), 2026-09-12.

Config: Parakeet with an int8 encoder (installed FluidInference); Orukeet with a float32 encoder (our
conversion). Same decoder, JointDecisionv3, preprocessor, and tokenizer. Same 360 clips as report 04.
Scored with number normalization, which is English only; other languages get lowercase and
punctuation stripping, applied equally to both.

| Language | Clips | Parakeet WER | Orukeet WER | Delta (pp) |
|---|---|---|---|---|
| de_de | 60 | 7.69% | 8.77% | +1.09 |
| en_us | 60 | 5.29% | 5.07% | -0.22 |
| es_419 | 60 | 5.45% | 5.51% | +0.07 |
| fr_fr | 60 | 4.82% | 5.06% | +0.24 |
| it_it | 60 | 2.14% | 2.14% | +0.00 |
| ru_ru | 60 | 5.21% | 5.59% | +0.39 |
| Overall | 360 | 5.05% | 5.29% | +0.24 |

Median clip WER: parakeet 0.00%, orukeet 0.00%. Median warm ms/clip: parakeet 83.2, orukeet 96.1.

Mixed and close, matching report 04 (int8): Orukeet wins on English and ties Italian; Parakeet wins
German, French, Spanish, and Russian; roughly tied overall at +0.24 pp for Orukeet. Precision barely
moves it (float32 5.29% vs int8 5.21% overall). It does not reproduce the paper's win on 23 of 25
languages; same caveats as report 04, namely 60 clips per language, our Core ML conversion versus the
paper's NeMo decode, and an English-only number normalizer.

Caveat: encoder precision differs (Orukeet float32 vs Parakeet int8). WER is comparable; latency is
not apples-to-apples here. Report 04 matches precision.

Files: `results.json` (raw), `summary.md` (scored).
