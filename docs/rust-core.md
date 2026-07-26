# The Rust core

`core/` builds a static library (`libtap_talk_core.a`) linked into the app. It owns the audio path
and model downloads, and nothing else. Roughly 1,000 lines.

```
core/src/
  lib.rs              the entire FFI surface — no other file has uniffi attributes
  audio/capture.rs    cpal stream, downmix, resample
  audio/vad.rs        Silero silence trimming
  audio/agc.rs        gain for quiet speech
  models/manager.rs   GGUF download, partial-file hygiene
  llm/catalog.rs      which LLM models exist
  transcribe/cloud.rs optional OpenAI path
```

## The FFI surface

Every `#[uniffi::export]` lives in `lib.rs`. That is deliberate: the exported API is reviewable in
one file, and the modules underneath stay plain Rust with no binding concerns.

Bindings are **generated at build time** into `TapTalk/Generated/` and are **not committed**. So
deleting a Rust export surfaces as a Swift compile error on the next `make build` — the compiler is
the completeness check.

Exported:

| Item | Purpose |
|---|---|
| `Recorder` | `warm_up`, `start`, `stop`, level and chunk callbacks |
| `ModelManager` | LLM download, path lookup, delete |
| `RecordingResult` | samples, count, real speech duration |
| `TranscriptionResult` | text, language, duration |
| `transcribe_cloud`, `test_cloud_connection` | the optional OpenAI path |
| `AudioLevelCallback`, `AudioChunkCallback`, `LlmDownloadProgressCallback` | Rust → Swift callbacks |

`CoreError` is the only error type crossing the boundary. Internals use `String` errors and map at
the `lib.rs` edge, so callers never see a foreign error type.

## The audio path

### Capture (`audio/capture.rs`)

The stream is created once and **paused**, never destroyed, between recordings. Rebuilding it makes
macOS re-validate the microphone permission each time, which is both slow and visible to the user.
`warm_up()` exists so that creation — and the TCC prompt — happens at launch rather than inside the
hotkey callback.

Inside the callback, which runs on CoreAudio's real-time thread:

- Downmix to mono **once**. Mono input is passed through with no copy at all.
- `try_lock` on the buffer, never `lock` — blocking a real-time thread is not acceptable, and
  dropping a callback is preferable to stalling one.
- Append to a buffer pre-reserved for 30 s so the allocator is never called here.
- Emit RMS every ~30 Hz, not every callback.

`stop()` swaps the buffer out with `mem::replace` for a freshly reserved one, so the next recording
does not grow-and-realloc on the audio thread.

### Silence trimming (`audio/vad.rs`)

Silero VAD via ONNX Runtime, 512-sample windows, threshold 0.35 — deliberately below Silero's
default 0.5 to catch murmured dictation. Six chunks (~190 ms) of padding are kept either side so
soft word onsets survive.

**512 is not a tuning knob.** Silero v5 requires exactly 512 samples at 16 kHz. Larger windows were
measured at 3× faster and *clipped up to 2976 ms of opening speech on 34 of 59 real clips*, while
returning perfectly plausible probabilities. The crate accepts them without complaint. Do not
change it without re-running that comparison on real speech.

Cost is linear at ~2.4 ms per second of audio, and the first call of a process pays ~64 ms of ONNX
Runtime initialisation.

### Gain (`audio/agc.rs`)

Lifts quiet speech toward −23 dBFS, bypasses anything already at conversational level, caps at
+20 dB, and limits peaks. Two linear passes, effectively free.

## Model downloads (`models/manager.rs`)

Only the LLM GGUF goes through here — ASR models are downloaded by FluidAudio on the Swift side.

- Streams to `<name>.partial`, then `fs::rename` to the final path, so a crashed download never
  leaves a file that looks complete.
- `clean_residue()` at construction sweeps orphaned `.partial` files and macOS resource-fork junk.
- `claim_active` serialises downloads; a second concurrent request is rejected rather than
  interleaved.
- **No resume.** A failed transfer restarts at byte zero. See the deferred notes for why that is
  not a small fix.

## Conventions

- `Result<T, String>` internally, mapped to `CoreError` at the boundary. No `unwrap` outside tests.
- `unsafe` only for the `Send`/`Sync` assertion on the cpal stream, with a `// SAFETY:` comment
  naming the invariant.
- `cargo fmt` and `cargo clippy -- -D warnings` must both pass. Clippy is load-bearing — it is what
  catches code left orphaned by a removal.

## Working on it

```bash
cd core
cargo build --release
cargo test
cargo clippy --release -- -D warnings
```

Note `make build` compiles Rust in **release** regardless of the Xcode configuration, so
`#[cfg(debug_assertions)]` blocks in the core never execute in a normal app build.
