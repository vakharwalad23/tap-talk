<div align="center">

<img src="TapTalk/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" width="120" alt="TapTalk" />

# TapTalk

**Local speech-to-text for macOS. Press a key, speak, paste — your voice never leaves your Mac.**

[![macOS](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-000?logo=apple&logoColor=white)](#requirements)
[![Privacy](https://img.shields.io/badge/privacy-on--device-2ea44f)](#privacy--data-safety)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

TapTalk is a fully local, privacy-first dictation app for macOS. It runs speech-to-text directly on your Mac — no account, no telemetry, and by default no network at all. Hold a hotkey, speak, and your words are transcribed and pasted into whatever app you're using.

Built with SwiftUI and Rust, TapTalk runs inference on the **Apple Neural Engine** through Core ML where possible, and lets you pick the engine that best fits your language, speed, and accuracy needs.

## Why TapTalk?

Most dictation tools stream your audio to a server. TapTalk doesn't. Every byte of audio is processed on your machine. There's no account to create, no subscription, and — unless you explicitly turn on the optional cloud engine — nothing ever leaves your device.

It's also fast and frugal. On Apple Silicon the models run with low latency on the Neural Engine, and TapTalk releases models from memory when idle so it isn't a resource hog sitting in your menu bar.

## Privacy & data safety

Privacy isn't a feature bolted on — it's the default behavior.

- **On-device by default.** Audio is captured, voice-activity-trimmed, and transcribed entirely on your Mac. No analytics, no telemetry, no accounts, no background phone-home.
- **Audio is never persisted.** Recordings are processed in memory and discarded. (The optional Apple Speech engine writes a single short-lived temp file that is deleted immediately after transcription.)
- **No automatic downloads — ever.** No model is fetched until *you* tap **Download**. Selecting an engine whose model isn't installed simply prompts you to download it; it never pulls data silently.
- **You choose what stays on disk.** Models live in `~/Library/Application Support/talk.tap.app/models/`. Each is removable from the **Models** page, and TapTalk cleans up partial/interrupted downloads automatically so nothing is left orphaned.
- **Secrets stay in the Keychain.** If you opt into the cloud engine or a custom LLM endpoint, the API key is stored in the macOS Keychain — never in plaintext, never in a config file.
- **Cloud is strictly opt-in.** TapTalk ships with an optional OpenAI Whisper cloud engine for people who want it. It is off by default and only ever used if you select it *and* provide your own API key. When enabled, audio is sent directly from your Mac to OpenAI — nowhere else.
- **Smart Mode runs locally too.** The optional LLM rewrite uses a local model (Qwen 2.5 1.5B via llama.cpp) by default; a custom endpoint is opt-in.
- **Open source.** Licensed under MIT — the entire pipeline is auditable.

### Permissions TapTalk asks for

| Permission | Why | When |
|---|---|---|
| **Microphone** | To capture the audio you dictate | First recording |
| **Accessibility** | To detect the global push-to-talk hotkey and paste into the focused app | First launch |

That's it. No full-disk access, no network entitlement is required for the on-device engines.

## Transcription engines

TapTalk lets you pick the engine per your needs. All on-device engines run locally; pick one in **Settings → Local model**.

| Engine | Best for | Languages | Download | Runs on |
|---|---|---|---|---|
| **Whisper** (whisper.cpp) | Broadest language coverage, full control | 99 languages | Tiny 75 MB · Small 466 MB · **Large v3 Turbo 1.6 GB** · Large v3 3 GB | GPU/Metal, optional Neural Engine encoder |
| **Parakeet** (NVIDIA TDT 0.6B v3) | Fastest English/European dictation | ~25 European languages (auto) | ~490 MB | Neural Engine |
| **WhisperKit** (Argmax) | Fast multilingual on the Neural Engine | 99 languages (auto-detect) | Turbo ~632 MB · Large v3 ~947 MB | Neural Engine |
| **Apple Speech** (macOS 26+) | Broad on-device coverage, zero download to manage | ~25 system locales incl. CJK, Arabic | System asset (opt-in) | On-device, OS-managed |
| **Cloud (optional)** | When you explicitly want OpenAI | OpenAI Whisper | — | Your OpenAI account (opt-in) |

- **Whisper** is the default. Add the optional Core ML encoder ("Speed up") to run the encoder on the Neural Engine; remove it anytime to reclaim disk.
- **Parakeet** and **WhisperKit** auto-detect the spoken language, so they show an "Auto" indicator instead of a language picker.
- **Apple Speech** only appears on macOS 26+. Its language model downloads on demand when you tap Download — never automatically.

## Features

- **Multiple engines, your choice** — Whisper, Parakeet, WhisperKit, and Apple Speech, all on-device; an optional OpenAI cloud engine for those who want it.
- **90+ languages** — depending on the engine, with automatic language detection on Parakeet/WhisperKit.
- **Neural Engine acceleration** — Core ML inference on Apple Silicon across Parakeet, WhisperKit, and the optional Whisper encoder.
- **Global push-to-talk** — a system-wide hotkey that works from any application.
- **Auto-paste** — transcribed text is inserted into the focused text field.
- **Word dictionary** — custom replacement rules (technical jargon, proper nouns, shorthand) applied as post-processing.
- **Smart Mode** — TapTalk reads the context of where you're typing and rewrites your words to fit. Dropping a message in Slack? Casual. Writing in Notion? Clean prose. Powered by a local LLM by default.
- **Resource-conscious** — switching engines releases the inactive model, and idle models are unloaded to free memory and the Neural Engine.
- **Plain-language model catalog** — clear, non-technical descriptions so you can pick the right model, with downloads that persist across navigation.
- **Fully native** — SwiftUI and Rust. No Electron, no WebView, no web tech.

## Requirements

- macOS 14 or later (the Apple Speech engine requires macOS 26+)
- Apple Silicon (M1, M2, M3, M4, or newer)
- Xcode 26 or later (the build uses the macOS 26 SDK for the Apple Speech engine)
- Rust 1.77 or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

Swift Package dependencies (FluidAudio for Parakeet, WhisperKit) are resolved automatically by Xcode on first build.

## Download

Pre-built DMG is available on the [Releases](https://github.com/vakharwalad23/tap-talk/releases) page.

> **Note:** TapTalk is not yet notarized. If macOS blocks the app on first launch, right-click → Open to bypass it. Notarization is coming in a future release.

## Troubleshooting

**"App is damaged and can't be opened"**

This is Gatekeeper being cautious, not actual corruption. After copying `TapTalk.app` to `/Applications`, remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/TapTalk.app"
```

## Getting Started

```bash
git clone https://github.com/vakharwalad23/tap-talk.git
cd tap-talk
make run
```

This single command compiles the Rust core, generates Swift bindings via UniFFI, builds the Xcode project, and launches the app. No model is bundled — download the one you want from the **Models** page on first use. Models are stored in `~/Library/Application Support/talk.tap.app/models/`.

### Build Targets

| Command | Description |
|---------|-------------|
| `make run` | Full build and launch |
| `make build` | Build without launching |
| `make install` | Build a stable, permission-persistent app into `/Applications` |
| `make rust` | Rebuild Rust core only |
| `make bindings` | Regenerate Swift bindings |
| `make release` | Optimized release build |
| `make clean` | Remove all build artifacts |

## How It Works

TapTalk is split into two layers. The **Rust core** handles audio capture (via cpal), voice activity detection (Silero VAD), software gain for quiet speech, and the whisper.cpp inference engine. The **SwiftUI app** provides the interface, hotkey management, accessibility integration, the additional engines (Parakeet, WhisperKit, Apple Speech), and system services. The two layers communicate through a thin FFI bridge generated by [UniFFI](https://mozilla.github.io/uniffi-rs/).

When you press the hotkey, TapTalk captures audio from your default input device. Silero VAD trims silence. On release, the audio is transcribed by your selected engine, passed through your custom dictionary replacements and optional Smart Mode rewrite, and pasted into the active text field via the accessibility API. The whole round trip happens on your Mac.

## Open-source models & attribution

TapTalk stands on excellent open work. Model weights are downloaded at runtime under their own licenses:

- **OpenAI Whisper** — model under MIT; run via [whisper.cpp](https://github.com/ggerganov/whisper.cpp).
- **NVIDIA Parakeet TDT 0.6B v3** — weights under CC-BY-4.0 (attribution: NVIDIA); run via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0).
- **WhisperKit** by Argmax — framework MIT; Core ML model conversions from `argmaxinc/whisperkit-coreml`.
- **Apple SpeechTranscriber** — Apple's system on-device speech models (macOS 26+).
- **Qwen 2.5 1.5B Instruct** — Smart Mode LLM, Apache-2.0; run via llama.cpp.

## Contributing

Contributions are welcome. Please open an issue to discuss your idea before submitting a pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/your-feature`)
3. Commit your changes using [conventional commits](https://www.conventionalcommits.org/)
4. Open a pull request against `main`

## License

This project is licensed under the [MIT License](LICENSE).
