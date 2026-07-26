# The Swift app

SwiftUI and AppKit, no third-party UI. Everything that talks to Apple frameworks lives here:
recognition, the rewrite, the hotkey, the paste, the interface.

```
TapTalk/
  Services/   system interaction and orchestration
  Pages/      full screens (Record, Settings, Intelligence, Privacy, About)
  Views/      reusable components and the floating pill
  Models/     plain data types
  Theme/      colours and key labels
```

The rule from `.claude/rules/swift.md`: **views call services, services call the core, views never
touch system APIs directly.**

## AppController

The single orchestrator, and the first file to read. It owns the engines, the recording state
machine, hotkey registration and the transcribe task.

Two mechanisms in it are load-bearing:

**Generation guards.** Engine loads are async and can be superseded. Every load bumps
`engineLoadGeneration`, and every continuation re-checks `isCurrentGeneration(gen)` before
committing a result. Switching engines twice quickly must not let the first load win. New async
paths that can be superseded should reuse this, not invent a variant.

**Serialised engine tasks.** Loads and unloads chain through a single `engineTask` so an unload
from a superseded plan cannot run after the next load has finished.

The transcribe path is a detached task. Settings are snapshotted **by value** on the main actor
before crossing into it — never read `settings` from inside the task.

## Recognition engines

Both wrap FluidAudio and share the same actor shape, which is the contract every consumer expects:

```swift
actor SomeEngine {
    nonisolated static func isInstalled() -> Bool
    nonisolated static func download(progress:) async throws
    nonisolated static func sweepOrphans()
    nonisolated static func delete() throws
    func ensureLoaded() async throws   // never downloads; throws if absent
    func unload() async
    func transcribe(...) async throws -> Output
}
```

`ParakeetEngine` — English and 24 European languages, auto-detect only.
`NemotronEngine` — Hindi and 100+ languages, with an explicit language prompt.
`EouStreamingEngine` — the live-typing model, conforming to `StreamingTranscriber`.

Adding an engine means touching nine places: the `LocalEngine` enum and its exhaustive switches,
`ActiveEngine`, `EnginePlan`, `resolveEnginePlan`, both halves of `applyEnginePlan`,
`releaseEngines`, `sweepDownloadResidue`, the transcribe dispatch, and a catalog card. The
exhaustive switches will not compile until all of them are updated, which is intentional.

`NemotronEngine.unload()` calls `cleanup()` before dropping the reference. Dropping an actor
reference alone does not free Core ML models held inside it.

## The rewrite

`AppContextService` builds the instruction; `LLMService` sends it; `LlamaServerManager` runs the
local `llama-server` subprocess.

**Instruction clauses do not stack.** The 1.5B model reliably does *one* job and none when given
two. Measured 3/3 across every combination tried: adding a cleanup clause beside the
destination clause made the destination clause be ignored entirely. So there is a precedence
order — romanization outranks match-the-app, which outranks polish and restructure — rather than
concatenation. Read the comments in `AppContextService.systemPrompt` before adding a clause.

Prompts are assembled in a **fixed order** with all variable content last, so the stable prefix is
as long as possible for server-side caching.

`LlamaServerManager` pins an exact llama.cpp release and records it beside the binary, so changing
the pin re-provisions rather than silently keeping whatever "latest" was on the day of install.

## Input and output

- `HotkeyService` — one `CGEvent` tap, two independently registered modifier hotkeys. Only
  `.flagsChanged` is observed, so hotkeys must be modifiers. A health check re-enables a tap macOS
  has silently disabled.
- `PasteService` — pasteboard write marked `transient`/`concealed` so clipboard managers skip the
  entry, then Cmd-V, then restore.
- `LiveInserter` — live typing. Prefers an Accessibility range-replace, falls back to pasteboard,
  and permanently disables the AX path after a first failure rather than retrying per keystroke.
- `AppContextService` — reads the frontmost app and its window title for rewrite context. The
  Accessibility read carries a 250 ms timeout because an AX request to a hung app otherwise blocks
  forever, on the paste path.

Browsers are detected by asking Launch Services which apps handle `https`, never a hardcoded list —
a list already missed a browser installed on the development machine.

## Conventions

- `@Published` + `didSet` writing to `UserDefaults` for every setting; Keychain for secrets.
- Actors for engines, `@MainActor` for UI state. No `@unchecked Sendable`.
- No force-unwrapping outside previews.
- Warnings are treated as errors in review even though the build does not enforce it — the Swift 6
  concurrency warnings in particular have twice indicated real races.

## Working on it

```bash
make run      # rust → bindings → xcodegen → xcodebuild → launch
make kill     # stop a running instance first; two instances fight over the event tap
```

There is no test target. The added logic is prompt composition and enum dispatch, where exhaustive
`switch` breakage at compile time is a stronger check than a test would be. `make build` failing is
the signal.
