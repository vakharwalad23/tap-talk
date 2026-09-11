# English WER: Orukeet (int8) vs Parakeet (int8)

FLEURS `en_us`, 100 clips (same clips as report 01), matched int8 encoders, 2026-09-12.

Config: both encoders int8. Parakeet uses the installed FluidInference int8 encoder (425 MB); Orukeet's
encoder was quantized to int8 (linear, per-channel) by `quantize_encoder.py` from the converted
float32 encoder (568 MB). Decoder, JointDecisionv3, preprocessor, and tokenizer are identical to
report 01. Scored with number normalization (`score.py`).

| Metric | Parakeet | Orukeet | Delta |
|---|---|---|---|
| Corpus WER | 5.10% | 4.55% | -0.55 pp |
| Median clip WER | 3.10% | 0.00% | |
| Median warm ms/clip | 78.6 | 88.7 | |

With precision matched, Orukeet still lowers English WER by 0.55 pp. Quantizing the encoder to int8
cost about 0.09 pp versus the float32 encoder in report 01, so recognition quality holds.

Latency: Orukeet stays about 10 ms slower even at int8. The architecture is identical, so this is not
a model difference. Our int8 encoder is 568 MB against FluidInference's 425 MB, i.e. our conversion is
less compressed. Matching the conversion and quantization recipe would close the gap.

Files: `results.json` (raw), `summary.md` (scored).
