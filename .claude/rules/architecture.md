---
description: Modular architecture and code organization rules
globs: "**/*.{rs,swift}"
---

# Architecture Standards

## Modularity
- Every module has a single responsibility. Name reflects purpose.
- Modules communicate through well-defined interfaces (traits in Rust, protocols in Swift).
- No circular dependencies between modules.
- New functionality = new module. Extend existing only if same responsibility.

## Pluggability
- Core interfaces defined as traits/protocols - implementations are swappable.
- Configuration via structs, not hardcoded values. Inject at initialization.
- Audio backend, inference engine, VAD - all behind trait boundaries.
- Storage paths, URLs, thresholds - configurable, never magic constants.

## Dependency Direction
```
SwiftUI Views -> Services -> Rust Core (via UniFFI)
                              v
                     audio / transcribe / models
```
- Views depend on services. Services depend on core. Core depends on nothing app-specific.
- Rust core is a standalone library - usable without Swift layer.
- No upward dependencies. Lower layers never import higher ones.

## File Organization
- One type per file when type exceeds ~50 lines.
- Group by feature, not by kind (not `models/`, `views/`, `controllers/`).
- Keep related code close - helper functions in same file as caller.
- Max file length: ~400 lines. Split if larger.

## Configuration
- All magic numbers extracted to constants or config structs.
- Default values defined once, at module boundary.
- Runtime config loaded from disk, with sensible fallback defaults.
- Environment-specific values (paths, URLs) injected, not embedded.
