# Running the suite

Everything is driven by the `Makefile` at the folder root. Run `make help` for the target list.

## Requirements

- Apple Silicon Mac (arm64). `make preflight` checks this and fails early otherwise.
- `uv` (https://docs.astral.sh/uv/) for the Python converter environment.
- Xcode with command line tools (`swift`, `xcrun coremlcompiler`).
- `git`.

`make preflight` verifies all of the above. Every script also runs its own checks before doing work.

## One-time conversion

```bash
make setup       # vendor the pinned FluidInference converter and build its uv env
make convert     # download the Orukeet .nemo, convert to a float32 Core ML bundle in out/
make quantize    # quantize the encoder to int8, producing the int8 bundle in out/
```

Outputs:

- `out/orukeet-tdt-0.6b-v3-coreml` (float32 encoder)
- `out/orukeet-tdt-0.6b-v3-coreml-int8` (int8 encoder)

## Benchmark

```bash
make data        # download FLEURS: all 25 languages, all clips (about 11 GB). LANGS/LIMIT override.
make bench       # build the harness, stage models, run all passes, score reports
```

`make bench` stages Parakeet from Hugging Face (not from any local install) and Orukeet from the
converted bundles, then transcribes every clip once per model and scores WER and CER into
`reports/fleurs-full/`. A full run is a few hours of Neural Engine inference.

Quick smoke test (English, 100 clips, separate output):

```bash
make bench-quick
```

Override the languages or clip count:

```bash
make data LANGS=en_us,de_de,fr_fr LIMIT=200
```

Verify the FLEURS language codes against the paper's per-language counts:

```bash
make probe
```

## Publish the bundles

```bash
make publish REPO=yourname/orukeet-coreml           # dry run, prints the plan
make publish REPO=yourname/orukeet-coreml PUSH=1    # actually upload (needs huggingface-cli login)
```

The bundles are uploaded under `float32/` and `int8/` with the CC-BY-SA-4.0 LICENSE, NOTICE, and model
card. See [`../scripts/publish/`](../scripts/publish/).

## Clean up

```bash
make clean       # remove build output and staged models
make distclean   # also remove the converter env, downloads, and raw results
```
