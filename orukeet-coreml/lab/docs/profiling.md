# Profiling

Two tools, both in `swift/`. Medians of warm runs; the first load of a bundle builds the Neural
Engine program and takes about 15 s, so run twice when a bundle is new.

## ttprof: components and end to end through FluidAudio

```bash
make profile                                          # shipped bundle, encoder on the Neural Engine
make profile DIR=out/bundles/orukeet-int8sym-greedy   # any bundle
make profile UNITS=gpu                                # encoder on the GPU
make profile AUDIO=data/fixtures/jfk.wav              # add end-to-end timing of a 16 kHz mono clip
```

Prints each model's inputs and outputs, then per-call medians: preprocessor, encoder, one decoder
step, one joint step (synthetic inputs). With `AUDIO`, it also times `AsrManager.transcribe`, the
exact path TapTalk uses. Extra options on the binary: `--extra <model.mlmodelc>` times any other
single-call model; `--ideal` runs preprocessor, encoder and one joint call per frame by hand;
`--reset-bench` times FluidAudio's per-transcription buffer zero-fill.

## ttdecode: the own decode loop

```bash
make decode AUDIO=data/fixtures/jfk.wav                                   # shipped bundle, single-step joint
make decode AUDIO=data/fixtures/jfk.wav JOINT=out/joint/JointDecisionBatchedK8.mlmodelc
make decode-reg LABEL=own-shipped-k1                                      # both corpora, then make score
```

Runs the Core ML models directly, without FluidAudio, with FluidAudio's single-window decode
semantics: frame-aligned declared length, a cached predictor output across blank frames, the
same-frame and forced-advance rules, the end-of-window flush over the boundary frames, and the
empty-decode recovery ladder. On the 128 sealed clips the transcripts are identical to
`AsrManager.transcribe`. Reports preprocessor, encoder and decode time separately, decoder and
joint call counts, and the mean token confidence.

Options on the binary: `--window <dir>` (repeatable) adds a Preprocessor + Encoder pair with a
shorter fixed window; the smallest window that fits the clip is used. `--fused <model.mlmodelc>`
replaces Decoder + joint with a fused decoder+joint graph. `--joint <batched.mlmodelc>` runs a
K-frame batched joint through the older NeMo-style loop, kept for the batched-joint measurement.

## What the numbers mean

- Encoder time is fixed per clip: every clip is padded to the 15 s window.
- Decoder and joint run on the CPU whatever compute units are requested; Core ML keeps graphs this
  small off the Neural Engine.
- `AsrManager.transcribe` minus `ttdecode` on the same bundle is FluidAudio's own overhead.
