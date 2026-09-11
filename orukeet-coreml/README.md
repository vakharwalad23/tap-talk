# Orukeet to Core ML conversion

Offline build tooling that converts the Orukeet checkpoint into the Core ML bundle FluidAudio
loads onto the Apple Neural Engine. Working area on the `feat/orukeet-coreml-conversion`
branch. Not imported by the app. Generated output (models, venv, vendored converter) does not
belong in the app bundle or repo.

## Model

Orukeet is Parakeet TDT 0.6B v3 with half of the FastConformer encoder's temporal filters
replaced by frozen fitted Gabor kernels. Architecture, TDT decoder, tokenizer, and inference
operators are unchanged, so at the Core ML graph level it is a weights swap. It covers the
same 25 European languages as Parakeet v3 (no Hindi, no Devanagari), so it augments the
Parakeet engine and leaves the Nemotron path untouched.

- Checkpoint: https://huggingface.co/oruk/orukeet  (`orukeet-v0.1.0.nemo`, ~2.5 GB)
- Paper: https://arxiv.org/abs/2609.10054
- Converter (pinned): FluidInference/mobius `models/stt/parakeet-tdt-v3-0.6b/coreml` at
  `4040a39f760290bb1d43a72dc82e5894f27b0f5c`
- Target layout: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml

## License

Orukeet weights are CC-BY-SA-4.0 (ShareAlike), attributing NVIDIA Parakeet TDT 0.6B v3. The
Core ML bundle produced here is an adaptation, so any shipped copy stays CC-BY-SA-4.0 and
carries attribution to Oruk and NVIDIA. This is a new license class relative to the current
models; record it in `MODEL-LICENSES.md` before the app downloads it. Weights, tokenizer, and
config stay out of the app repo. Runtime download only.

## Converter is vendored, not rewritten

The NeMo to Core ML conversion spans several component wrappers and must emit bundles whose
input and output shapes match what FluidAudio already loads. FluidInference maintains that
converter and uses it to publish their Parakeet Core ML repo, so vendoring it at a pinned
commit is what keeps the output loadable. The only original code here is `assemble_bundle.py`.

## Pipeline

- `setup.sh` clones the pinned converter and builds its locked env with `uv sync`. No model
  download. Safe to run before review.
- `run_conversion.sh` is held. It downloads the checkpoint and runs convert, compile, numeric
  validation, and assembly. Do not run until the scripts are reviewed.
- `assemble_bundle.py` maps the compiled `.mlmodelc` into the FluidAudio bundle
  (`Preprocessor` / `Encoder` / `Decoder` / `JointDecision` plus `parakeet_vocab.json`) and
  checks the Orukeet tokenizer against Parakeet v3 before reusing the vocab.

## Layout

```
orukeet-coreml/
  README.md
  setup.sh              vendor converter and build env
  run_conversion.sh     held full pipeline
  assemble_bundle.py    compiled mlmodelc to FluidAudio bundle plus vocab check
  vendor/mobius/        pinned converter (setup.sh)
  models/               downloaded orukeet-v0.1.0.nemo (run_conversion.sh)
  reference/            FluidInference vocab and config for verification
  out/                  mlpackages, compiled mlmodelc, final bundle
```

## Requirements

macOS on Apple Silicon: the `.mlpackage` to `.mlmodelc` compile and ANE validation are macOS
only. Needs `uv` and `xcrun coremlcompiler`. No GPU; the checkpoint loads and traces on CPU.
The converter pins Python 3.10.12, which `uv` fetches.

## Gate

After `setup.sh` finishes, stop and review `run_conversion.sh` and `assemble_bundle.py` before
downloading the model or compiling anything.
