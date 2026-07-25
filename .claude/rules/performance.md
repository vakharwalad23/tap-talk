---
description: Latency budget and on-device acceleration rules
globs: "**/*.{rs,swift}"
---

# Performance Standards

## The metric
- Key-up to pasted text is the number that matters. Everything else is a proxy.
- Every change to the capture, inference, post-processing, or paste path records a before/after measurement. Median of 10 runs on a fixed clip.
- Model load, warm-up, and first-token cost count. "Excluding cold start" hides the exact latency users complain about.
- A change that regresses key-up-to-paste does not land, regardless of what else it fixes.

## Measure, then optimize
- Profile before optimizing. Record the profile alongside the change.
- No speculative optimization without a number attached.
- Attribute wins per change, not per batch. Three flags landed together prove nothing individually.

## On-device acceleration
- Core ML/ANE and MLX are both candidates for any on-device model. Pick by measurement on the target chip.
- Measure on the oldest and newest Apple Silicon available, not only the development machine.
- Never assume a runtime is faster because of its reputation or its host language. Inference speed comes from the accelerator, not the FFI layer.

## Warm paths
- Prewarm on the earliest signal, not on first use. Key-down, not key-up.
- Prewarming must never delay the work it precedes. Off the main actor, non-blocking.
- Keep loaded models and warm caches resident when the memory cost is justified, and record that cost.

## Hot paths
- Preallocate and reuse buffers on the audio path. No new allocation inside a real-time callback.
- Downmix, resample, and copy at most once per buffer.
- Heavy work off the main thread. Inference, file I/O, and network never run on the main actor.
