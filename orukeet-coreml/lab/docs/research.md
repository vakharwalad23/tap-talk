# Research trail

How the experiments were chosen. Each line: the question, where the answer came from, the verdict.

## Sources read

- Oruk-AI/orukeet#6: conversion scripts, numerical validation, latency and WER evidence, the sealed
  FLEURS corpora and per-model hypotheses.
- FluidAudio 0.15.5 source (the version TapTalk pins) and release notes through 0.15.8: model
  loading, the TDT decode loop, the sliding-window and cache-aware streaming managers, the int8
  `Encoder_v2` issue, the local bundle loader Nathan contributed.
- FluidInference/mobius: how the shipped graphs were traced, quantized and measured.
- NVIDIA NeMo: transducer decoding strategies, n-gram fusion, phrase boosting, cache-aware
  streaming; the Parakeet, Nemotron and parakeet-unified model cards.
- Apple: coremltools compression and stateful-model guides, Core ML runtime APIs.

## Latency ideas

| Idea | Verdict |
|---|---|
| Remove the FluidAudio zero-fill | Measured 20 ms per transcription; fix upstream or use the own loop |
| Batch K encoder frames per joint call | Built and measured slower; TDT already skips blanks |
| Move the encoder to the GPU | 2.8x slower on M3 Pro, faster on M5-class parts; per chip only |
| Lower encoder precision for speed | No effect on the Neural Engine, compute-bound; int4 was slower and worse in FluidInference's sweep |
| Fuse decoder and joint into one graph | Built and measured 5 ms slower: the loop already skips the decoder on blank steps, the fused graph cannot; closed |
| Shorter encoder windows for short dictations | Built 5 s and 10 s exports; 8 ms saved under 5 s, 5 ms under 10 s, accuracy unchanged; one encoder with several traced shapes is the open question |
| `MLOptimizationHints`, `MLState`, W8A8 | FluidAudio measured the hints as a regression; state is tiny here; W8A8 is contested on the Neural Engine |

## Accuracy ideas

| Idea | Verdict |
|---|---|
| int8 per-channel encoder instead of the 6-bit palette | Measured 185 vs 194 errors, same latency; full FLEURS is the remaining gate |
| Nathan's FP16 precision profile | Underpowered on 64 clips; worth scoring on full FLEURS |
| Beam search | Every published TDT result shows near-zero gain without a language model; dropped |
| N-gram fusion, phrase boosting, blank penalty | Real gains in the literature; need the blank logit and top-K or full logits, which the batched joint export carries |
| Calibration-based palettization | Fallback if the 143 MB of int8 is unacceptable |

## Streaming

Orukeet has no streaming variant; the 0.6B TDT class degrades badly on short windows without
streaming training. Two tracks: keep the live-typing model and run Orukeet per utterance as the
finalizer (TapTalk only), and a multi-context fine-tune for a native streaming Orukeet (with the
model author; encoder-only change, tens to low hundreds of GPU-hours at a few thousand hours of
audio). A short-window measurement of the shipped model on the corpus is the next data point.
