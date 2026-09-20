# Fused decoder+joint

Idea: the shipped decode loop dispatches Decoder then JointDecisionv3 as two separate Core ML
calls per joint step. Fusing them into one graph halves the per-step dispatch count.
FluidInference measured 1.11x on their own decode loop for this graph shape. The decoder LSTM has
no ANE kernel (`ios17.lstm`), so the win is CPU dispatch overhead, not a Neural Engine placement
change.

## Build

```bash
make fused    # out/fused/: fp32 reference pair, fused fp32 and fp16 mlpackages, parity.txt
```

`convert/fuse.sh` runs the vendored `fuse_decoder_joint.py export` (fp32 decoder, fp32
joint_decision reference pair, plus the fused graph in fp32 and fp16), then its `parity` command,
with output captured to `out/fused/parity.txt`. On this machine the whole run, model load through
parity, finished in about 12 seconds; the encoder is untouched, so this is far cheaper than
`make export`.

`decoder_joint_decision_fp16.mlmodelc` and `decoder_joint_decision_fp32.mlmodelc` are compiled
from the matching mlpackages with `xcrun coremlcompiler compile`; `make fused` builds the
mlpackages and does not compile them yet.

| File | Disk |
|---|---|
| decoder_fp32.mlpackage (parity reference) | 45 MB |
| joint_decision_fp32.mlpackage (parity reference) | 24 MB |
| decoder_joint_decision_fp32.mlpackage / .mlmodelc | 69 MB each |
| decoder_joint_decision_fp16.mlpackage / .mlmodelc | 35 MB each |
| out/fused total | 277 MB |

## Interface

Real names, shapes and types read from the compiled spec with coremltools
(`out/fused/interface.txt`); fp16 and fp32 declare the same interface, only the weights differ.

| Input | Shape | Type |
|---|---|---|
| targets | [1, 1] | int32 |
| target_length | [1] | int32 |
| h_in | [2, 1, 640] | float32 |
| c_in | [2, 1, 640] | float32 |
| encoder_step | [1, 1024, 1] | float32 |

| Output | Shape | Type |
|---|---|---|
| token_id | [1, 1, 1] | int32 |
| token_prob | [1, 1, 1] | float32 |
| duration | [1, 1, 1] | int32 |
| top_k_ids | [1, 1, 1, 64] | int32 |
| top_k_logits | [1, 1, 1, 64] | float32 |
| h_out | [2, 1, 640] | float32 |
| c_out | [2, 1, 640] | float32 |

A drop-in superset of the shipped Decoder + JointDecisionv3: one call replaces the two. Host
semantics on blank emission: re-feed the previous targets/h_in/c_in unchanged, since the LSTM
recompute is deterministic. `top_k_ids` and `top_k_logits` carry the 64-entry top-K that the
greedy profile prunes away; a pruned fused variant, keeping only token_id/token_prob/duration,
can follow the same op-pruning approach as `convert/prune_joint.py`.

## Parity

`fuse_decoder_joint.py parity` runs 50 steps of random encoder frames through the fused fp32
graph against the chained fp32 decoder + joint_decision reference, evolving decoder state along
the reference path (`out/fused/parity.txt`):

```
steps=50  token_id mismatches=0
  max|delta| token_prob     0.000e+00
  max|delta| top_k_logits   0.000e+00
  max|delta| duration       0.000e+00
  max|delta| h_out          0.000e+00
  max|delta| c_out          0.000e+00
PARITY PASS (gate < 1e-5 on prob/state)
```

Exact match at fp32, not merely within tolerance.

## Measure

```bash
make decode AUDIO=data/fixtures/jfk.wav FUSED=out/fused/decoder_joint_decision_fp16.mlmodelc
```

`swift/Sources/ttdecode` already has a `FusedStepper` and a `--fused <model.mlmodelc>` flag built
to this exact input/output contract. The `decode` Makefile target does not yet forward a `FUSED`
variable to it, only `JOINT`; it needs a `$(if $(FUSED),--fused "$(FUSED)",)` clause before this
command exercises the fused graph. Not measured yet.

A smoke run only, to confirm the graph loads and predicts (`fuse_decoder_joint.py bench
--build-dir out/fused --shipped-dir models/shipped-greedy --warmup 3 --runs 30`), taken while a
large test suite was running on this machine, so these are not measurements:

```
cpuOnly    separate 0.589 ms (p95 0.653)   fused 0.559 ms (p95 0.591)   speedup 1.05x
cpuAndGPU  separate 0.579 ms (p95 0.610)   fused 0.553 ms (p95 0.596)   speedup 1.05x
cpuAndNE   separate 0.583 ms (p95 0.641)   fused 0.562 ms (p95 0.630)   speedup 1.04x
all        separate 0.591 ms (p95 0.654)   fused 0.568 ms (p95 0.622)   speedup 1.04x
```

## Verdict

Pending. Parity is exact and the graph runs; the open question is decode-loop latency against
the shipped bundle's 48.0 ms own-loop baseline (results.md), which needs the `FUSED` wiring in
the `decode` target and a clean machine to measure on.
