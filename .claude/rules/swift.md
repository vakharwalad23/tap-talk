---
description: Swift and SwiftUI coding standards for TapTalk app
globs: TapTalk/**/*.swift
---

# Swift Standards

## SwiftUI Patterns
- Use `@Observable` (macOS 14+) or `@ObservableObject` for shared state.
- Keep views small — extract subviews when body exceeds ~40 lines.
- Use `@State` for local view state, `@Environment` for dependency injection.
- Prefer `task {}` over `onAppear` for async work.
- Use `NavigationStack` not deprecated `NavigationView`.

## Performance
- Minimize view redraws — use `EquatableView` or split state granularly.
- Heavy work off main thread — `Task.detached` or dedicated `DispatchQueue`.
- Lazy load views with `LazyVStack`/`LazyHStack` for lists.
- Cache computed values — avoid recomputation in `body`.
- Use `nonisolated` on methods that don't need MainActor.

## Architecture
- Services layer handles system interactions (hotkey, paste, audio, config).
- Views only call services — no direct system API usage in view code.
- Use Swift concurrency (`async/await`) over GCD where possible.
- Protocol-driven design for testability — services behind protocols.

## Types
- Use `struct` by default. `class` only when reference semantics required.
- Prefer `enum` with associated values over raw strings/ints for state.
- Use `Codable` for serialization — manual coding keys only when names differ.
- Mark types `Sendable` when crossing concurrency boundaries.

## Error Handling
- Use typed errors with `enum AppError: LocalizedError`.
- Provide `errorDescription` for user-facing messages.
- Never force-unwrap optionals outside previews.
- Use `guard let` for early returns, `if let` for branching.

## Naming
- Follow Swift API Design Guidelines strictly.
- Methods read as English: `downloadModel(tier:)` not `download(t:)`.
- Boolean properties: `isRecording`, `hasPermission`, `canTranscribe`.
- Callbacks: `onComplete`, `onProgress`, `onError`.

## App Size
- No third-party UI libraries — SwiftUI + AppKit only.
- SF Symbols for icons — no bundled image assets unless unavoidable.
- Strip debug symbols in release builds.
