# Models and inference engines

TapTalk ships **no model weights**. Everything is downloaded on explicit user action, from the
publisher, to `~/Library/Application Support/`. Nothing model-shaped is in the app bundle, the DMG
or this repository - see [`../MODEL-LICENSES.md`](../MODEL-LICENSES.md) for why that boundary
matters legally.

## What runs

| Model | Role | Size | Runtime | License |
|---|---|---|---|---|
| **NVIDIA Parakeet TDT 0.6B v3** | Default ASR - English + 24 European | ~490 MB | Core ML / ANE via FluidAudio | CC-BY-4.0 |
| **NVIDIA Nemotron 3.5 ASR Multilingual 0.6B** | ASR - Hindi + 100 languages | ~640 MB | Core ML / ANE via FluidAudio | OpenMDW-1.1 |
| **NVIDIA Parakeet Realtime EOU 120M** | Live typing (optional) | ~440 MB | Core ML / ANE via FluidAudio | NVIDIA Open Model License |
| **Qwen 2.5 1.5B Instruct (GGUF q4_k_m)** | Smart Mode rewrite | 1.06 GB | llama.cpp, pinned release `b10107` | Apache-2.0 |
| OpenAI Whisper (cloud) | Optional, opt-in, off by default | - | OpenAI API | - |

Memory is much lower than disk size suggests, because Core ML weights and the GGUF are
memory-mapped: the app sits at ~164 MB with Parakeet loaded, and `llama-server` at ~279 MB
footprint against a 1.06 GB file.

## Why these, specifically

Every one of these was chosen against a measurement, and several obvious-looking alternatives were
rejected on evidence.

**Parakeet for English/European.** Fast, punctuates, and streams - which is what makes live typing
possible at all.

**Nemotron for everything else.** Parakeet cannot produce Devanagari; it renders Hindi as confident
romanized nonsense rather than failing loudly, which is worse. Nemotron was picked after measuring
alternatives on 418 FLEURS Hindi clips:

| Model | Hindi WER |
|---|---|
| **Nemotron multilingual (shipped)** | **14.5%** |
| IndicWhisper | ~15% |
| Qwen3-ASR 8-bit | 18.6% |
| Apple `DictationTranscriber` | 31.6% |

It also costs no new dependency - it ships inside FluidAudio, which was already used for Parakeet -
and needs no deployment-target change.

**A caveat that matters if you extend this:** Nemotron's vocabulary contains **zero tokens** for
Bengali, Gujarati, Tamil, Telugu, Kannada, Malayalam and Punjabi. Those languages are not slow or
inaccurate, they are *impossible* to emit. Devanagari (196 tokens), Arabic (252), CJK (6,907) and
Kana (217) all work. The language picker is restricted to what the vocabulary can actually produce,
which is why it is shorter than the model's advertised language list.

**Qwen 2.5 1.5B for the rewrite**, kept rather than replaced with something smaller. A 0.6B model
would be roughly 2.5x faster, but the 1.5B *already* fabricates occasionally - it has invented a
time and a closing sentence that were never dictated. Before dropping tiers, measure the
fabrication rate, not just latency.

## What was rejected, and why

Recorded here so it is not re-attempted from first principles.

**Apple Foundation Models** - works, handles Hindi, costs zero disk. But a reused
`LanguageModelSession` accumulates its transcript, so dictation N would see dictation N-1's
content; a fresh session per dictation is required, which is 1121 ms against llama.cpp's 513 ms. It
also threw `guardrailViolation` on ordinary text.

**llama.cpp speculative decoding** (`--spec-type ngram-simple`, `--cache-reuse`) - the plan
expected 2-3x because rewriting mostly copies its input. Measured at temperature 0 with fixed seed
and identical token counts: **no gain, and 3% slower on the copy-heavy case it targeted**. An
earlier benchmark at temperature 0.3 appeared to show a 20% win; that was variable output length,
not speed.

**Larger VAD windows** - 3x faster and *clipped up to 2976 ms of speech* on real audio.

**Rule-based transliteration (ICU)** for Hinglish - deterministic, and produces `kaiphe` for cafe
and `mitinga` for meeting. It destroys exactly the English loanwords that make code-switched text
readable.

## Orukeet, evaluated

Orukeet is Parakeet TDT 0.6B v3 with frozen Gabor kernels replacing half the encoder filters - same
architecture, TDT decoder, and tokenizer (vocabulary byte-identical), the same 25 European languages,
no Hindi. It was converted to the FluidAudio Core ML layout and benchmarked head to head against
Parakeet on FLEURS. Tooling and the four reports live in [`../orukeet-coreml/`](../orukeet-coreml/)
(`bench/reports/`); model artifacts are gitignored.

- English: Orukeet lowers WER by ~0.5 to 0.6 points (5.10% to about 4.5%), holding across float32 and
  int8 encoders.
- Multilingual (6 languages, 60 clips each): roughly tied - Orukeet wins English, Parakeet wins
  German, French, and Russian. Does not reproduce the paper's 23-of-25 win at this sample size.
- Latency runs ~10 to 12 ms slower per clip, a conversion artifact (our int8 encoder is less
  compressed than FluidInference's), not an architecture difference.

License is CC-BY-SA-4.0 (ShareAlike) - a new class here; a shipped Core ML conversion would inherit it.

## Adding or changing a model

1. **Measure first.** WER on real audio for ASR; for a rewrite model, output quality including
   fabrication, not just latency.
2. **Check the vocabulary** if a new script is involved. Advertised language support is not the
   same as tokens existing.
3. **Record the license** in `MODEL-LICENSES.md` and the README attribution list.
4. **Keep weights out of the repo** - including `tokenizer.json` and `config.json`, which count as
   model materials under some of these licenses even though weights are the obvious case.
5. **Mirror the engine actor contract** in [`swift-app.md`](swift-app.md) so the nine wiring points
   stay uniform.

## A note on prompting small models

The rewrite model is 1.5B, and it behaves accordingly. Two findings hold across everything tried:

- **Few-shot beats prose, decisively.** Described in words, transliteration translated to English
  and dropped words; shown five worked pairs, it became stable and correct.
- **It does one job, or none.** Two instructions in one prompt and it satisfies neither. That is
  why the rewrite modes have a precedence order rather than being concatenated.
