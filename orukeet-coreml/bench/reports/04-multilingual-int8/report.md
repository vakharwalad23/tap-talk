# Multilingual WER: Orukeet (int8) vs Parakeet (int8)

FLEURS, 6 European languages, 60 clips each (360 total), matched int8 encoders, 2026-09-12.

Config: both encoders int8, same 360 clips as report 03 (multilingual fp32); the Orukeet int8 encoder
is the one built in report 02. Scored with number normalization, which is English only; other
languages get lowercase and punctuation stripping, applied equally to both.

| Language | Clips | Parakeet WER | Orukeet WER | Delta (pp) |
|---|---|---|---|---|
| de_de | 60 | 7.69% | 8.62% | +0.93 |
| en_us | 60 | 5.29% | 5.21% | -0.07 |
| es_419 | 60 | 5.45% | 5.17% | -0.27 |
| fr_fr | 60 | 4.82% | 5.12% | +0.30 |
| it_it | 60 | 2.14% | 2.07% | -0.07 |
| ru_ru | 60 | 5.21% | 5.40% | +0.19 |
| Overall | 360 | 5.05% | 5.21% | +0.16 |

Median clip WER: parakeet 0.00%, orukeet 0.00%. Median warm ms/clip: parakeet 82.7, orukeet 94.5.

Mixed and close: Orukeet wins on English, Spanish, and Italian; Parakeet wins on German, French, and
Russian; roughly tied overall at +0.16 pp for Orukeet. This does not reproduce the paper's reported
win on 23 of 25 languages. Likely causes, in order: small sample (60 clips per language, high
variance), our int8 Core ML conversion versus the paper's full-precision NeMo decode, and an
English-only number normalizer. A definitive multilingual comparison needs the full FLEURS test
split, matched decoding, and per-language normalization.

Files: `results.json` (raw), `summary.md` (scored).
