# Setup

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Xcode command line tools (`swift`, `xcrun coremlcompiler`)
- `uv` (https://docs.astral.sh/uv/) and `git`
- About 12 GB of disk: checkpoint 2.5 GB, exports 2.4 GB, bundles 2.4 GB, environments 4 GB

## One-time steps

```bash
make setup      # vendors the converter source, syncs both uv environments
make nemo       # Orukeet r3 checkpoint into work/, sha256 verified
make shipped    # Nathan's greedy Core ML zip: verified, unpacked, compiled into models/shipped-greedy/
make vendor     # Nathan's PR branch: corpus sealer, scorer, published results; four fixture clips
make corpus     # the two 64-clip FLEURS samples into data/, verified against his manifests
make build      # ttprof, ttreg, ttdecode
```

Each step is resumable and skips work that is already done.

## What gets vendored

| Path | Source | Pinned to |
|---|---|---|
| `vendor/mobius/` | FluidInference/mobius, the converter that produced the shipped graphs | commit 4040a39 |
| `vendor/orukeet/` | Oruk-AI/orukeet PR branch: `export/coreml`, `evaluation/standard_asr`, `evidence/` | commit 852c3e3 |
| `work/orukeet-v0.1.0.nemo` | oruk/orukeet, branch coreml-taptalk-preview-20260915 | sha256 031c8dda... |
| `models/shipped-greedy/` | oruk/orukeet `coreml/orukeet-r3-coreml-greedy.zip` | sha256 beccdc6f... |
| `data/fleurs-a`, `data/fleurs-b` | google/fleurs test split, sealed by Nathan's script | revision 70bb2e84 |

## Environments

Two uv projects, both on Python 3.12. `make` uses them; never call `python3` directly.

| Project | Purpose | Key pins |
|---|---|---|
| `pyproject.toml` | tracing and conversion | torch 2.7.0, coremltools 9.0b1, nemo-toolkit 2.3.1, numpy 1.26.4 |
| `bench/pyproject.toml` | scoring | kaldialign 0.12.0, rapidfuzz 3.14.6, regex 2026.9.3 |

The conversion pins mirror the mobius environment the shipped graphs came from. The scorer pins
mirror Nathan's `requirements-score.txt`.
