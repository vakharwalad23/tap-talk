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
| own loop, single-step joint | 48.0 ms | preprocessor 1.5, encoder 26.6, decode 20.0 (39 decoder + 46 joint calls) | 196, 127 of 128 identical |
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
