# TapTalk

Local speech-to-text for Mac. Press a key, speak, paste. Nothing leaves your device.

## Features

- 4 Whisper model tiers (Tiny → Large v3) — pick speed vs accuracy
- Multilingual: English + 13 Indian languages (Hindi, Tamil, Telugu, etc.)
- Neural Engine accelerated via Core ML
- Global hotkey — push-to-talk from any app
- Auto-paste into focused text field
- Native macOS app — no Electron, no WebView

## Requirements

- macOS 13+
- Apple Silicon (M1/M2/M3/M4)
- Xcode 15+
- Rust 1.77+
- xcodegen (`brew install xcodegen`)

## Build

```bash
git clone <repo-url>
cd tap-talk
make run
```

This compiles the Rust core, generates Swift bindings, builds the Xcode project, and launches the app.

## Architecture

```
SwiftUI App → UniFFI Bridge → Rust Static Library
                                  ├── whisper-rs (inference)
                                  ├── cpal (audio capture)
                                  └── silero-vad (voice detection)
```

All speech processing runs locally on-device. Models download on first use to `~/Library/Application Support/talk.tap.app/models/`.

## License

TBD
