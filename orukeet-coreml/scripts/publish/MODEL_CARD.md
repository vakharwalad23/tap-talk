---
license: cc-by-sa-4.0
base_model: nvidia/parakeet-tdt-0.6b-v3
library_name: fluid-audio
tags:
  - asr
  - speech-to-text
  - coreml
  - parakeet
  - orukeet
  - apple-neural-engine
language:
  - bg
  - hr
  - cs
  - da
  - nl
  - en
  - et
  - fi
  - fr
  - de
  - el
  - hu
  - it
  - lv
  - lt
  - mt
  - pl
  - pt
  - ro
  - ru
  - sk
  - sl
  - es
  - sv
  - uk
---

# Orukeet Core ML (FluidAudio)

Core ML conversion of Orukeet (oruk/orukeet) for the FluidAudio Swift SDK, running on the Apple
Neural Engine. Orukeet is a fine-tune of NVIDIA Parakeet TDT 0.6B v3 with frozen Gabor kernels
(arXiv 2609.10054).

Two bundles are provided, differing only in encoder precision:

- `float32/` - higher precision, larger.
- `int8/` - smaller and faster, quantized. Recognition quality is within about 0.01 WER of float32.

Each is a directory that FluidAudio loads directly onto the Neural Engine.

## File layout

Each bundle contains:

- `Preprocessor.mlmodelc`
- `Encoder.mlmodelc`
- `Decoder.mlmodelc`
- `JointDecisionv3.mlmodelc`
- `config.json`
- `parakeet_vocab.json`
- `parakeet_v3_vocab.json`

## How to use

Download one bundle directory and load it with `AsrModels.load(from:version:)` using `.v3`, then
transcribe 16 kHz mono `[Float]` samples with an `AsrManager`:

```swift
import FluidAudio

let dir = URL(fileURLWithPath: "/path/to/int8")
let models = try await AsrModels.load(from: dir, version: .v3)

let asr = AsrManager(config: .default)
try await asr.loadModels(models)

var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
let result = try await asr.transcribe(samples, decoderState: &state)
print(result.text)
```

## Benchmarks

Orukeet lowers pooled FLEURS word error rate relative to NVIDIA Parakeet TDT 0.6B v3 across the 25
FLEURS European languages, with the largest gains on higher-error languages. Exact numbers are in the
benchmark suite that produced this conversion; none are reproduced here to avoid drift.

## Attribution

- Orukeet (oruk/orukeet) by the Oruk team, arXiv 2609.10054, licensed CC-BY-SA-4.0.
- Base model: NVIDIA Parakeet TDT 0.6B v3 (nvidia/parakeet-tdt-0.6b-v3), licensed CC-BY-4.0.

This repository is a Core ML adaptation of Orukeet produced for FluidAudio.

## License

Licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC-BY-SA-4.0). Because
Orukeet is a ShareAlike work, this conversion is an adaptation and carries the same license.

Any redistribution or further adaptation must:

- remain under CC-BY-SA-4.0 (or a later compatible BY-SA version), and
- retain attribution to the Oruk team (Orukeet) and to NVIDIA Parakeet TDT 0.6B v3.

Full license text is in LICENSE, and at
https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt
