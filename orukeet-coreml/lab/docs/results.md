# Results

Measured 2026-09-20 on an Apple M3 Pro, macOS 26.6.2, FluidAudio 0.15.5. Corpus and scorer as in
[bench.md](bench.md). Raw scores: `reports/score.md`.

## Accuracy, 128 clips

| Bundle | Errors / words | WER |
|---|---|---|
| shipped greedy (6-bit palette, Nathan) | 194 / 2538 | 7.64 |
| int8 symmetric per-channel, greedy joint | 185 / 2535 | 7.30 |
| int8 asymmetric, greedy joint | 190 / 2535 | 7.50 |
| FP16, greedy joint | 191 / 2535 | 7.53 |
| Nathan, NeMo FP32 reference | 185 / 2538 | 7.29 |
| Nathan, Parakeet Core ML | 217 / 2539 | 8.55 |

Word counts differ by a few words through the scorer's compound handling. Differences under about
5 words are ties on this corpus.

## Latency, shipped and lab bundles through FluidAudio

| Bundle | Encoder p50 | Per clip, corpus median |
|---|---|---|
| shipped greedy | 26.5 ms | 78 ms |
| int8 symmetric | 27.0 ms | 78 ms |
| int8 asymmetric | 26.6 ms | 80 ms |
| FP16 | 26.6 ms | 78 ms |

Encoder time is the same for all four weight formats.

## Decode loop, shipped bundle, JFK 11 s clip

| Path | Total | Breakdown | Errors on 128 clips |
|---|---|---|---|
| FluidAudio `transcribe` | 73 to 77 ms | encoder 26.7, zero-fill 20.5, decode 20, preprocessor 1.5, other 5 | 194 |
| own loop, NeMo semantics, single-step joint | 48.0 ms | preprocessor 1.5, encoder 26.6, decode 20.0 (39 decoder + 46 joint calls) | 196, 127 of 128 identical |
| own loop, FluidAudio semantics, single-step joint | 48.7 ms | preprocessor 1.5, encoder 26.6, decode 20.6 (39 decoder + 51 joint calls) | 194, 128 of 128 identical |
| own loop, batched joint K=8 | 64.3 ms | decode 36.0 (40 joint calls at 0.61 ms) | 197 |
| own loop, batched joint K=16 | 76.5 ms | decode 48.1 (39 joint calls at 0.93 ms) | |

## Component costs, shipped bundle

| Component | Units | p50 |
|---|---|---|
| Preprocessor | CPU | 1.4 ms |
| Encoder | Neural Engine | 26.3 ms |
| Encoder | GPU | 73.2 ms |
| Decoder step | CPU | 0.12 ms |
| Joint step | CPU | 0.17 ms |
| First model load (Neural Engine program build) | | 15.6 s |
| Warm model load | | 0.1 s |

## FluidAudio with the zero-fill fix, JFK 11 s clip

`AsrManager.transcribe` through the lab profiler, FluidAudio main against the fix branch (the
upstream pull request), median of 20 warm runs, two interleaved pairs:

| FluidAudio | Wall time |
|---|---|
| main (87a39dfe) | 71.1 ms |
| main + bulk `MLMultiArray` reset and copy | 48.3 ms |

The fixed FluidAudio matches the own loop; the remaining difference to the models' compute is the
decode loop itself.

## Shorter encoder windows, own loop

| Clip | Window | Preprocessor | Encoder | Decode | Total |
|---|---|---|---|---|---|
| 4.32 s | 15 s | 1.5 | 26.6 | 12.9 | 40.9 |
| 4.32 s | 5 s | 0.6 | 19.1 | 13.2 | 32.9 |
| 5.76 s | 15 s | 1.5 | 26.6 | 16.4 | 44.5 |
| 5.76 s | 10 s | 1.0 | 21.7 | 17.2 | 40.0 |
| 9.36 s | 15 s | 1.5 | 26.6 | 26.4 | 54.6 |
| 9.36 s | 10 s | 1.0 | 21.8 | 26.6 | 49.6 |

Accuracy on the 128 clips with the 5 s and 10 s windows (2 and 55 clips used them): 192 errors
against 191 for the same FP16 weights at 15 s, 4 transcripts differ.

## Fused decoder+joint, own loop, JFK 11 s clip

| Decoder side | Decode time | Calls | Errors on 128 clips |
|---|---|---|---|
| separate Decoder + JointDecisionv3 | 20.5 ms | 51 joint + 39 decoder | 194, 128 of 128 identical |
| fused fp16 | 25.5 ms | 51 fused | 194, 128 of 128 identical |

## Encoder placement and first load, shipped bundle

| Measurement | Value |
|---|---|
| Encoder, Neural Engine, median of 10 | 27.6 ms |
| Encoder, GPU, median of 10 | 73.3 ms |
| Encoder load, Neural Engine, program cached | 0.2 s |
| Encoder load, GPU | 1.9 s |
| First load after a fresh compile, Neural Engine | 14.8 s |
| Second load in the same process | 0.09 s |
