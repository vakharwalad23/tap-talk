# Findings

What the measurements established, one item each.

- **The palette costs accuracy, not the conversion.** Nathan's numerical validation attributes 95
  percent of the encoder's deviation from FP32 to the inherited 6-bit per-tensor palette. Replacing
  it with int8 per-channel symmetric weights moves the corpus from 194 to 185 errors, equal to the
  NeMo FP32 reference, for +143 MB.
- **Weight format does not change encoder latency.** 6-bit palette, int8 and FP16 all run the 15 s
  window in 26.5 to 27.0 ms on the Neural Engine. The encoder is compute-bound; the palette buys
  download size only.
- **The June int8 bundle was slow because of its preprocessor.** The mobius preprocessor export
  takes a variable-length input and costs 11 ms per clip against 1.4 ms for the fixed-shape one.
  Lab bundles reuse the shipped preprocessor, which has no learned weights.
- **FluidAudio spends 20 ms per transcription zero-filling a buffer.** `MLArrayCache.returnArray`
  clears the 240000-sample input one `NSNumber` at a time after each transcription, on the path
  that returns the text. `memset` takes 0.006 ms. Present in 0.15.5 and still on main.
- **The own decode loop reproduces FluidAudio exactly and saves the overhead.** Same four models,
  no FluidAudio, FluidAudio's decode semantics ported (cached predictor output, same-frame and
  forced-advance rules, boundary flush, recovery ladder): 48.7 ms against 72 ms on the 11 s clip,
  128 of 128 transcripts identical. The declared audio length must be rounded up to a whole 80 ms
  frame, and the end-of-window flush is what the plain NeMo loop was missing.
- **Batching the joint does not pay for TDT.** Durations already skip blank frames; the joint runs
  about once per emitted token, and a batched call costs 3.6x more. Closed.
- **Encoder placement depends on the chip.** GPU is 2.8x slower than the Neural Engine on M3 Pro;
  FluidAudio and Nathan measured GPU faster on M5-class parts. Keep the Neural Engine as default,
  choose per chip only by measurement.
- **The first load builds the Neural Engine program.** 15.6 s on first load of a compiled bundle,
  0.1 s afterwards, again after a macOS upgrade. The `.mlpackage` compile TapTalk already does is
  not this step.
- **The GPU pays at load time too.** Loading the encoder on the GPU takes 1.9 s (shader build)
  against 0.2 s on the Neural Engine with a cached program, on top of running 2.8x slower here.
- **Shorter windows save 5 to 8 ms, not 17.** The encoder has about 17 ms of fixed cost per call
  and about 0.06 ms per frame: 63 frames cost 19 ms, 126 cost 22 ms, 188 cost 27 ms. A 5 s window
  saves 8 ms on a 4 s clip, a 10 s window 5 ms on 6 to 9 s clips, with no accuracy change on the
  corpus.
- **Fusing decoder and joint loses in a caching loop.** The loop runs the decoder only on
  emissions (39 per 11 s clip) and the joint on every step (51); the fused graph recomputes the
  LSTM on all 51 steps and costs 5 ms more. Transcripts identical.
- **A blank penalty does not help here.** With the top-K joint, penalty 0 reproduces greedy exactly;
  0.5 ties at 194 errors and 1.0 to 3.0 add 5 to 14 errors, all insertions. The model does not
  under-emit on this corpus.
- **Per-token cost is what remains in the decode loop.** About 0.23 ms per Core ML call, 85 calls
  per 11 s clip. Fusing decoder and joint halves the calls (FluidInference measured 1.11x); a
  native loop removes dispatch but stays memory-bound. A few milliseconds either way.
