# Orukeet Core ML lab

Builds Orukeet Core ML variants from the r3 `.nemo` and measures them against the greedy bundle
TapTalk ships (Oruk-AI/orukeet#6): latency per component with `ttprof`, word error rate on Nathan
Roll's sealed 128-clip FLEURS regression corpus with `ttreg` and his own scorer. Research behind it:
[docs/CORE-ML-OPTIMIZATION.md](docs/CORE-ML-OPTIMIZATION.md) and [docs/STREAMING.md](docs/STREAMING.md).

Two variants are in scope:

1. int8 per-channel symmetric encoder with the greedy (top-K-free) joint, to recover the accuracy
   the inherited 6-bit palette costs without changing latency.
2. A joint graph that scores K encoder frames per call, to cut the per-frame Core ML dispatches that
   make up about a quarter of the recognition step.

Everything Python runs through `uv` in this folder's own environments: `pyproject.toml` (conversion,
pins mirror the mobius converter) and `bench/pyproject.toml` (Nathan's scorer pins). Nothing
model-shaped is committed; `vendor/`, `work/`, `out/`, `data/` and raw results are gitignored.

## Layout

```
Makefile              every entry point (make help)
pyproject.toml        conversion environment (torch, coremltools, nemo-toolkit)
convert/
  vendor_mobius.sh    FluidInference converter source at the pinned commit
  fetch_nemo.sh       r3 checkpoint download and sha256 check
  fetch_shipped.sh    published greedy (or baseline) bundle, verified and compiled into models/
  export.sh           .nemo to FP16 Core ML components (mobius convert-parakeet.py, unchanged)
  quantize_encoder.py int8 per-channel encoder, symmetric or asymmetric
  prune_joint.py      greedy joint: drop the top-K outputs
  assemble_bundle.py  compile into TapTalk's bundle layout
  export_batched_joint.py   K-frame joint with blank logit and logsumexp outputs
  audit_batched_joint.py    parity audit against the shipped single-step joint
bench/
  pyproject.toml      scorer environment
  vendor.sh           Nathan's PR branch: corpus sealer, scorer, published evidence; fixture clips
  corpus.sh           seal both 64-clip corpora, verify hashes against his manifests
  verify_corpus.py
  score.py            per-language errors and WER for every run, next to his numbers
swift/
  Sources/ttprof      per-component and per-clip latency of any compiled bundle
  Sources/ttreg       transcribe a sealed corpus with any compiled bundle
docs/                 research write-ups
```

## Quickstart

```bash
make setup                 # vendor converter source, sync both uv environments
make nemo                  # 2.5 GB checkpoint into work/, verified
make shipped               # Nathan's published greedy bundle, verified and compiled into models/
make vendor corpus         # Nathan's tooling and the two sealed 64-clip corpora
make export                # FP16 components into out/export/
make int8 int8-asym bundles   # encoders and compiled bundles into out/bundles/
make reg-all score         # transcribe every bundle on both corpora, score against his results
make profile DIR=out/bundles/orukeet-int8sym-greedy AUDIO=data/fixtures/jfk.wav
make joint-batched K=8 && make audit K=8
```

`make profile` with no arguments profiles the shipped bundle in `models/shipped-greedy/`. Nothing
here reads a TapTalk install; the reference comes from the pinned Hugging Face release.

## Results

Filled in as runs complete. Reference points from Oruk-AI/orukeet#6 on the same 128 clips:
Parakeet Core ML 217 errors / 2539 words (8.55 percent), Orukeet greedy 194 / 2538 (7.64 percent),
Orukeet NeMo FP32 185 / 2538 (7.29 percent).
