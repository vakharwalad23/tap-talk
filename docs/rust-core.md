# The Rust core

`core/` builds a static library (`libtap_talk_core.a`) linked into the app. It owns the LLM model
downloads and the optional OpenAI client, and nothing else. Roughly 500 lines. Audio moved to the
Swift `TapTalkAudio` package; see [`swift-app.md`](swift-app.md).

```
core/src/
  lib.rs              the entire FFI surface - no other file has uniffi attributes
  models/manager.rs   GGUF download, partial-file hygiene
  llm/catalog.rs      which LLM models exist
  transcribe/cloud.rs optional OpenAI path
```

## The FFI surface

Every `#[uniffi::export]` lives in `lib.rs`. That is deliberate: the exported API is reviewable in
one file, and the modules underneath stay plain Rust with no binding concerns.

Bindings are **generated at build time** into `TapTalk/Generated/` and are **not committed**. So
deleting a Rust export surfaces as a Swift compile error on the next `make build` - the compiler is
the completeness check.

Exported:

| Item | Purpose |
|---|---|
| `ModelManager` | LLM download, path lookup, delete |
| `TranscriptionResult` | text, language, duration |
| `transcribe_cloud`, `test_cloud_connection` | the optional OpenAI path |
| `LlmDownloadProgressCallback` | Rust -> Swift download progress |

`CoreError` is the only error type crossing the boundary. Internals use `String` errors and map at
the `lib.rs` edge, so callers never see a foreign error type.

## Model downloads (`models/manager.rs`)

Only the LLM GGUF goes through here - the ASR models and the Silero VAD model are downloaded on the
Swift side.

- Streams to `<name>.partial`, then `fs::rename` to the final path, so a crashed download never
  leaves a file that looks complete.
- `clean_residue()` at construction sweeps orphaned `.partial` files and macOS resource-fork junk.
- `claim_active` serialises downloads; a second concurrent request is rejected rather than
  interleaved.
- **No resume.** A failed transfer restarts at byte zero. See the deferred notes for why that is
  not a small fix.

## Conventions

- `Result<T, String>` internally, mapped to `CoreError` at the boundary. No `unwrap` outside tests.
- No `unsafe`.
- `cargo fmt` and `cargo clippy -- -D warnings` must both pass. Clippy is load-bearing - it is what
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
