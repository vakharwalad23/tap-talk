---
description: Code commenting standards across all languages
globs: "**/*.{rs,swift}"
---

# Commenting Standards

## Principles
- Code explains what. Comments explain why.
- No decorative comments (banners, section dividers, ASCII art).
- No first-person language ("I", "we", "our"). Write impersonal.
- Single-line comments only. No multi-line comment blocks.

## When to Comment
- Non-obvious logic: algorithms, bitwise ops, complex conditionals.
- Workarounds: link to issue or explain the constraint.
- Performance choices: why this approach over the simpler one.
- Safety invariants: `// SAFETY:` for unsafe Rust, pre/post conditions.
- Public API: single-line `///` doc comment on every exported function.

## When NOT to Comment
- Obvious code: `let count = items.count` needs no comment.
- Restating the code: `// increment counter` above `counter += 1`.
- TODO/FIXME without context — include what and when.
- Changelog-style: "added in v0.2" — that belongs in git history.

## No Planning Artifacts
Source reads as a finished product. It carries no trace of how the work was scheduled.

- No phase, step, stage, or milestone numbers. Not `// Phase 2: remove whisper`.
- No references to plan documents, roadmaps, or working notes.
- No `TODO` pointing at future scheduled work. Deferred work belongs in the working notes, not the source.
- Identifiers, file names, and type names describe behavior, never sequence.

## Style
```rust
// Resample to 16kHz — whisper.cpp requires fixed sample rate
let resampled = resample(&buffer, source_rate, 16000);
```

```swift
// CGEvent tap requires accessibility permission granted at runtime
let tap = CGEvent.tapCreate(...)
```

Bad:
```rust
// We need to resample the audio buffer here because
// the whisper model expects 16kHz input and we might
// get a different sample rate from the microphone
```
