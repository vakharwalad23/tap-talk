# TapTalk

Local speech-to-text for macOS. Native SwiftUI + Rust. No cloud, no web tech.

## Stack

- **UI:** SwiftUI (macOS 14+, Apple Silicon)
- **Core:** Rust static library (`core/`) - audio capture, VAD, model downloads
- **Bridge:** UniFFI proc macros -> auto-generated Swift bindings
- **Build:** `make run` (cargo -> uniffi-bindgen -> xcodegen -> xcodebuild)

## Build Commands

```bash
make run          # full build + launch
make build        # build without launching
make rust         # rebuild Rust only
make bindings     # regenerate Swift bindings
make clean        # remove all build artifacts
```

## Project Layout

- `core/` - Rust static library (all compute-heavy work)
- `TapTalk/` - SwiftUI app source
- `TapTalk/Generated/` - UniFFI-generated bindings (rebuild with `make bindings`)
- `project.yml` - xcodegen spec (generates `.xcodeproj`)
- `scripts/` - build helper scripts
- `website/` - marketing site, a separate TanStack Start project (see `.claude/rules/website.md`)

## Documentation

- `docs/architecture.md` - layer split and the dictation path end to end
- `docs/rust-core.md` - audio path, FFI surface, VAD constants that must not be tuned blindly
- `docs/swift-app.md` - services, engine actor contract, prompt-clause precedence
- `docs/models.md` - model choices with their measurements, and rejected alternatives with reasons
- `MODEL-LICENSES.md` - model terms; keep weights *and* tokenizer/config files out of the repo

Read `docs/models.md` before proposing a model or inference change - several obvious optimizations
are recorded there as measured dead ends.

## Rules

Coding standards live in `.claude/rules/`:
- `rust.md` - Rust style, memory, error handling, UniFFI exports
- `swift.md` - SwiftUI patterns, performance, architecture
- `commits.md` - Conventional commits (feat/fix/refactor), no co-authored-by
- `comments.md` - Minimal comments, no decorative, no first-person
- `architecture.md` - Modular, pluggable, configurable design
- `performance.md` - Key-up-to-paste latency budget, ANE/MLX selection, warm paths
- `resources.md` - Memory, lifecycle, and concurrency audit required after every change
- `website.md` - Marketing site only: TanStack Start, strict TypeScript, Biome, Cloudflare deploy

## Key Constraints

- No web tech in the app (no React, Electron, WebView, npm, pnpm) - `website/` is the one exception
- No Python anywhere
- ASCII only in code, comments, docs, and UI strings: no em or en dashes, smart quotes, arrows, or
  ellipsis characters. Devanagari in Hindi examples and demo data is the one exception.
- No `unwrap()` in Rust outside tests
- No force-unwrap in Swift outside previews
- No bundled models - download at runtime to Application Support
- Apple Silicon only for v1
