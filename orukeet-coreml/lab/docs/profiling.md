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

Runs the four Core ML models directly, without FluidAudio: pad to 15 s, preprocessor, encoder,
then greedy TDT decoding with NeMo semantics (argmax token and duration per frame, blank advances by
its duration, a non-blank updates the decoder). Reports preprocessor, encoder and decode time
separately, plus decoder and joint call counts. Picks the single-step joint from the bundle, or a
K-frame batched joint given with `JOINT`.

The declared audio length is rounded up to a whole 80 ms frame, as FluidAudio does; without that
the mel features differ slightly and about 10 percent of transcripts change.

## What the numbers mean

- Encoder time is fixed per clip: every clip is padded to the 15 s window.
- Decoder and joint run on the CPU whatever compute units are requested; Core ML keeps graphs this
  small off the Neural Engine.
- `AsrManager.transcribe` minus `ttdecode` on the same bundle is FluidAudio's own overhead.
