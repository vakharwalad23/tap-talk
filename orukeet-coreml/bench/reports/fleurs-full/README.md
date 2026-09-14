# Full FLEURS benchmark: Orukeet vs Parakeet

The complete FLEURS test set the Orukeet paper reports on: all 25 languages, 20,146 clips (per-language
counts match the paper exactly), run through FluidAudio on Core ML / ANE. WER and CER, scored with
number normalization (`../../score.py`). Each model is transcribed once; Parakeet is deterministic, so
one pass serves both precision comparisons.

| Report | Set | Precision | Pooled WER (Parakeet / Orukeet) |
|---|---|---|---|
| [multilingual-int8](multilingual-int8/report.md) | 25 languages, 20146 | both int8 | 13.98% / 11.80% (-2.17 pp) |
| [multilingual-fp32](multilingual-fp32/report.md) | 25 languages, 20146 | Orukeet float32 | 13.98% / 11.81% (-2.17 pp) |
| [english-int8](english-int8/report.md) | en_us, 647 | both int8 | 5.59% / 5.23% (-0.36 pp) |
| [english-fp32](english-fp32/report.md) | en_us, 647 | Orukeet float32 | 5.59% / 5.21% (-0.38 pp) |

Each report's `summary.md` has the full per-language WER and CER table with pooled and language-macro rows.

## Headline

Orukeet lowers pooled WER from 13.98% to 11.80% (int8), a 2.17 point drop and a 15.6% relative
reduction. It wins WER on 23 of 25 languages, losing only French (+0.76) and German (+0.49). The
largest gains are on higher-error languages: Latvian -8.03, Maltese -7.32, Lithuanian -5.98,
Estonian -4.09. CER also improves pooled (4.35% to 3.94%), though per-language CER is more mixed
(Orukeet wins 14 of 25).

Precision barely matters: pooled WER is 11.80% int8 versus 11.81% float32.

## Does this reproduce the paper?

Yes, in direction and breadth. The paper reports Orukeet winning 23 of 25 languages and pooled WER
falling 11.01% to 9.85% (10.6% relative). We measure the same 23 of 25 win count and a larger relative
reduction (15.6%). Absolute WERs run higher than the paper's because our scoring is lighter and English
only for number normalization, and we decode a Core ML int8 conversion rather than the paper's
full-precision NeMo pipeline. The relative result holds regardless.

This corrects the earlier small-sample runs (`../01-english-fp32` through `../04-multilingual-int8`),
which used 60 clips across 6 low-error European languages and looked roughly tied. That sample missed
the higher-error languages where Orukeet gains the most.

## Latency

Orukeet runs about 14 ms slower per clip (84 vs 98 ms, int8). The architecture is identical to
Parakeet, so this is a conversion artifact: our int8 encoder is less compressed than FluidInference's.
A matched conversion and quantization recipe would close the gap. WER, not latency, is the comparable
axis here.

## Reproduce

```bash
./setup.sh && ./run_conversion.sh          # once: Orukeet Core ML bundle
bench/prep_models.sh && bench/build_orukeet_int8.sh
CONV=vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml
LANGS=bg_bg,hr_hr,cs_cz,da_dk,nl_nl,en_us,et_ee,fi_fi,fr_fr,de_de,el_gr,hu_hu,it_it,lv_lv,lt_lt,mt_mt,pl_pl,pt_br,ro_ro,ru_ru,sk_sk,sl_si,es_419,sv_se,uk_ua
uv run --project "$CONV" python bench/fleurs_prep.py --langs "$LANGS" --limit 0 --out bench/fleurs-full
swift build --package-path bench -c release
bench/run_full_bench.sh && bench/make_full_reports.sh
```

Raw per-clip results are written to `_raw/` (gitignored, regenerable).
