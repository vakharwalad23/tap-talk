# Warm

One tool in `swift/`: `ttwarm`. Picks the faster encoder placement per machine, and measures the
one-time Neural Engine program build cost on a freshly compiled model.

## make warm: placement pick

```bash
make warm                                          # shipped bundle, 10 runs per placement
make warm DIR=out/bundles/orukeet-int8sym-greedy   # any bundle
make warm RUNS=30
```

Loads `Encoder.mlmodelc` from `DIR` twice, once on the Neural Engine (`cpuAndNeuralEngine`) and
once on the GPU (`cpuAndGPU`), and times `RUNS` predictions on each against a zero-filled input
built from the model's own declared input shapes, so it works on any bundle's encoder, not only
this lab's. Prints load times and per-placement median and p95 to stderr, then prints exactly one
JSON object to stdout:

```json
{"encoder_units":"ane","ane_ms":26.4,"gpu_ms":73.1,"ane_load_ms":110,"gpu_load_ms":95,"runs":10}
```

That JSON is what an app installer would persist: read `encoder_units` once, per machine, and
configure the encoder's compute units from it from then on, instead of probing placement on every
launch.

## make warm-first: first-load cost

```bash
make warm-first                                    # shipped Encoder.mlpackage
make warm-first PKG=models/shipped-greedy-packages/Decoder.mlpackage
```

Compiles `PKG` with `coremlcompiler` into a fresh temporary directory, loads the result on the
Neural Engine and runs one prediction (the first load in this process), then loads and predicts
again in a second model instance (warm), and prints both totals.

## What the numbers mean

- The Neural Engine builds and caches its program the first time a model's exact compute graph is
  loaded. That build is the slow number from `warm-first`; later loads of the same content are
  fast, on the order of a hundred times faster.
- The cache is keyed by model content, not by file path or process: a model recompiled from the
  same source can still land in a warm cache. This tool does not know, and does not claim to know,
  where that cache is stored on disk.
- Placement is chip-dependent: the Neural Engine can win on one chip and lose on another, so
  `make warm` is meant to run on the machine it configures, not to be trusted across machines.
- An installer should pick placement once per machine with logic like `make warm` and persist the
  result, then warm the Neural Engine program once, right after compiling a model, instead of
  paying the first-load cost during the user's first dictation.

## Measured, M3 Pro, macOS 26.6

| Measurement | Value |
|---|---|
| Encoder on the Neural Engine, median of 10 | 27.6 ms |
| Encoder on the GPU, median of 10 | 73.3 ms |
| Encoder load, Neural Engine (program cached) | 0.2 s |
| Encoder load, GPU (shader build) | 1.9 s |
| First load after a fresh compile, Neural Engine, plus one prediction | 14.8 s |
| Second load in the same process, plus one prediction | 0.09 s |

Pick on this chip: Neural Engine. The 14.8 s is the cost an installer should absorb once.
