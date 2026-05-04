# TapTalk

Local speech-to-text for macOS. Native SwiftUI + Rust. No cloud, no web tech.

## Stack

- **UI:** SwiftUI (macOS 13+, Apple Silicon)
- **Core:** Rust static library (`core/`) — audio capture, VAD, whisper inference
- **Bridge:** UniFFI proc macros → auto-generated Swift bindings
- **Build:** `make run` (cargo → uniffi-bindgen → xcodegen → xcodebuild)

## Build Commands

```bash
make run          # full build + launch
make build        # build without launching
make rust         # rebuild Rust only
make bindings     # regenerate Swift bindings
make clean        # remove all build artifacts
```

## Project Layout

- `core/` — Rust static library (all compute-heavy work)
- `TapTalk/` — SwiftUI app source
- `TapTalk/Generated/` — UniFFI-generated bindings (rebuild with `make bindings`)
- `project.yml` — xcodegen spec (generates `.xcodeproj`)
- `scripts/` — build helper scripts

## Rules

Coding standards live in `.claude/rules/`:
- `rust.md` — Rust style, memory, error handling, UniFFI exports
- `swift.md` — SwiftUI patterns, performance, architecture
- `commits.md` — Conventional commits (feat/fix/refactor), no co-authored-by
- `comments.md` — Minimal comments, no decorative, no first-person
- `architecture.md` — Modular, pluggable, configurable design

## Key Constraints

- No web tech (no React, Electron, WebView, npm, pnpm)
- No Python anywhere
- No `unwrap()` in Rust outside tests
- No force-unwrap in Swift outside previews
- No bundled models — download at runtime to Application Support
- Apple Silicon only for v1
