---
description: Rust coding standards for tap-talk-core
globs: core/**/*.rs
---

# Rust Standards

## Memory & Performance
- Zero-copy where possible. Prefer `&[T]` over `Vec<T>` for read-only data.
- Use `Arc` for shared ownership, never `Rc` (thread safety required).
- Avoid heap allocations in hot paths - preallocate buffers, reuse them.
- Prefer stack allocation for small fixed-size data.
- Use `Box<[T]>` over `Vec<T>` when size is final and won't change.
- Profile before optimizing. Measure with `#[cfg(debug_assertions)]` timing.

## Error Handling
- Return `Result<T, E>` - never `unwrap()` or `expect()` outside tests.
- Define domain-specific error enums with `thiserror`.
- Map external errors at module boundary - callers see project error types only.
- UniFFI-exported functions must return types UniFFI can serialize.

## Structure
- One responsibility per module. Split when a file exceeds ~300 lines.
- Public API at `mod.rs` re-exports only. Implementation in private submodules.
- Group related types: struct + impl + trait impl in same file.
- Keep `unsafe` blocks minimal with a `// SAFETY:` comment explaining invariants.

## Types & Traits
- Prefer newtypes over raw primitives for domain concepts (`SampleRate(u32)` not `u32`).
- Derive `Clone, Debug` on all public types. Add `Send + Sync` bounds on thread-shared types.
- Use `enum` for state machines - exhaustive match, no default arms.
- Implement `Display` for user-facing error messages.

## UniFFI Exports
- Export only high-level operations. Keep FFI surface thin.
- Use UniFFI `enum`, `record`, `interface` - not raw C types.
- Callbacks from Rust to Swift via UniFFI callback interfaces.
- Document every exported function with a single-line `///` doc comment.

## Dependencies
- Audit before adding. Prefer well-maintained crates with <5 transitive deps.
- Pin major versions in `Cargo.toml`.
- No `tokio` unless async is unavoidable - prefer `std::thread` + channels for simplicity.

## Formatting
- `cargo fmt` enforced. `cargo clippy -- -D warnings` must pass.
- Max line length: 100 chars.
