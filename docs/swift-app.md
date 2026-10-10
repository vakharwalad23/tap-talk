# The Swift app

SwiftUI and AppKit, no third-party UI. Everything that talks to Apple frameworks lives here:
audio, recognition, the rewrite, the hotkey, the paste, the interface.

```
TapTalk/
  Audio/      TapTalkAudio package: capture, 16 kHz conversion, Silero VAD, trim, gain
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
before crossing into it - never read `settings` from inside the task.

## Audio

`TapTalk/Audio` is a local Swift package (`TapTalkAudio`) with its own tests (`make test`).

- `MicrophoneCapture` - `AVAudioEngine` input into an `AVAudioSinkNode`. The sink block runs on
  Core Audio's real-time thread and only downmixes into `SampleRing`: no locks, no allocation, no
  reference counting. The engine is paused, never torn down, between dictations; a device change
  marks the graph for rebuild on the next start. The rebuild wires the input node with its hardware
  format (`inputFormat`): after a device change its output format still describes the old device,
  and connecting with that raises an Objective-C exception (#22). Graph wiring runs inside
  `tt_catch_exception`, so any such exception becomes an error instead of quitting the app.
- `MicrophoneSelection` - the "Use the built-in microphone" setting. Each graph build points the input
  node at the chosen Core Audio device (`kAudioOutputUnitProperty_CurrentDevice`): the built-in
  microphone when preferred and present, else the system default. Changing it marks the graph for
  rebuild, so it applies on the next key press; Bluetooth headphones then stay in their high-quality
  mode because nothing records from their microphone.
- `RecordingPipeline` (actor) drains the ring every 32 ms: RMS for the pill, `AVAudioConverter`
  to 16 kHz, Silero on each complete 512-sample window, or the live sink for EOU instead.
- `DictationRecorder.stop` pauses the engine and finishes only the last ~32 ms. Measured on an M3
  Pro with 17 to 21 s clips: 0.7 to 1.2 ms, against 53 to 66 ms for the Rust stage it replaced
  (ONNX Silero at ~2.5 ms per second of audio plus a full-clip resample, and ~100 ms more on the
  first dictation of a process).

**512 is not a tuning knob.** Silero v5 and v6 need exactly 512 samples at 16 kHz. Larger windows
were measured 3x faster and clipped up to 2976 ms of opening speech on 34 of 59 real clips while
returning plausible probabilities. The threshold is 0.35, below Silero's 0.5, to catch murmured
dictation; six windows (~190 ms) of padding are kept either side. Do not change any of these
without re-running that comparison on real speech.

Silero (`silero-vad-unified-v6.0.0`, the 32 ms Core ML conversion) downloads at launch from a
pinned Hugging Face revision with SHA-256 checks, into `models/silero-vad/`. Until it is present,
recordings are transcribed untrimmed.

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

`OrukeetEngine` - Oruk r3, the default English and European engine (a more accurate Parakeet
fine-tune), auto-detect only, batch only. It wraps the vendored `OrukeetCoreML` package and is the
one engine that downloads a `.mlpackage` bundle and compiles it to `.mlmodelc` on the device once
(OS-stamped, recompiled after a macOS upgrade), so its installer has a distinct compiling phase.
`ParakeetEngine` - English and 24 European languages, auto-detect only; kept as the base for the
optional live-typing add-on.
`NemotronEngine` - Hindi and 100+ languages, with an explicit language prompt.
`EouStreamingEngine` - the live-typing model, conforming to `StreamingTranscriber`.

Adding an engine means touching nine places: the `LocalEngine` enum and its exhaustive switches,
`ActiveEngine`, `EnginePlan`, `resolveEnginePlan`, both halves of `applyEnginePlan`,
`releaseEngines`, `sweepDownloadResidue`, the transcribe dispatch, and a catalog card. The
exhaustive switches will not compile until all of them are updated, which is intentional.

`NemotronEngine.unload()` calls `cleanup()` before dropping the reference. Dropping an actor
reference alone does not free Core ML models held inside it.

`OrukeetMigration` (with `AppNavigation`) runs once at launch and is resolved from a single
persisted `orukeetMigrationState`. New installs default to Orukeet. An existing Parakeet user
without the EOU add-on gets a one-time, dismissible upgrade banner on the Record page that
downloads and compiles Orukeet, then switches to it. Parakeet is never removed, and a live-typing
(EOU) user is never switched off it.

## The rewrite

`AppContextService` builds the instruction; `LLMService` sends it; `LlamaServerManager` runs the
local `llama-server` subprocess.

**Instruction clauses do not stack.** The 1.5B model reliably does *one* job and none when given
two. Measured 3/3 across every combination tried: adding a cleanup clause beside the
destination clause made the destination clause be ignored entirely. So there is a precedence
order - romanization outranks match-the-app, which outranks polish and restructure - rather than
concatenation. Read the comments in `AppContextService.systemPrompt` before adding a clause.

Prompts are assembled in a **fixed order** with all variable content last, so the stable prefix is
as long as possible for server-side caching.

`LlamaServerManager` pins an exact llama.cpp release and records it beside the binary, so changing
the pin re-provisions rather than silently keeping whatever "latest" was on the day of install.

## Input and output

- `HotkeyService` - one `CGEvent` tap, two independently registered modifier hotkeys. Only
  `.flagsChanged` is observed, so hotkeys must be modifiers. A health check re-enables a tap macOS
  has silently disabled.
- `PasteService` - pasteboard write marked `transient`/`concealed` so clipboard managers skip the
  entry, then Cmd-V, then restore.
- `LiveInserter` - live typing. Prefers an Accessibility range-replace, falls back to pasteboard,
  and permanently disables the AX path after a first failure rather than retrying per keystroke.
- `AppContextService` - reads the frontmost app and its window title for rewrite context. The
  Accessibility read carries a 250 ms timeout because an AX request to a hung app otherwise blocks
  forever, on the paste path.

Browsers are detected by asking Launch Services which apps handle `https`, never a hardcoded list -
a list already missed a browser installed on the development machine.

## Conventions

- `@Published` + `didSet` writing to `UserDefaults` for every setting; Keychain for secrets.
- Actors for engines, `@MainActor` for UI state. No `@unchecked Sendable`, except the three audio
  types that share raw memory or `AVAudioEngine` with the real-time thread (`SampleRing`, its
  `Writer`, `MicrophoneCapture`); each names its invariant in a comment.
- No force-unwrapping outside previews.
- Warnings are treated as errors in review even though the build does not enforce it - the Swift 6
  concurrency warnings in particular have twice indicated real races.

## Working on it

```bash
make run      # rust -> bindings -> xcodegen -> xcodebuild -> launch
make kill     # stop a running instance first; two instances fight over the event tap
make test     # Rust tests and the TapTalkAudio package tests
```

`make test` runs the Rust tests and the `TapTalkAudio` package tests. The rest of the app has no
test target: its logic is prompt composition and enum dispatch, where exhaustive `switch` breakage
at compile time is a stronger check than a test would be. `make build` failing is the signal.
