# Building bundles

A bundle is the layout TapTalk installs: `Preprocessor`, `Encoder`, `Decoder`,
`JointDecisionv3` as `.mlmodelc`, plus `parakeet_vocab.json`.

## Export

```bash
make export     # out/export/, about 10 minutes
```

Runs the vendored mobius `convert-parakeet.py` on the `.nemo`, unchanged. Output:
`parakeet_encoder.mlpackage` (FP16, 1.1 GB), `parakeet_decoder.mlpackage`,
`parakeet_joint_decision_single_step.mlpackage` (the joint with top-64 outputs), the preprocessor,
and `metadata.json` (15 s window, 240000 samples, vocab 8192, 5 duration bins).

## Encoder variants

```bash
make int8        # out/encoders/int8sym.mlpackage   int8 per-channel, symmetric
make int8-asym   # out/encoders/int8asym.mlpackage  int8 per-channel, asymmetric (the June recipe)
```

`convert/quantize_encoder.py` applies coremltools `linear_quantize_weights` to the FP16 export.
The symmetric export is byte-for-byte the size of FluidInference's `Encoder_v2` (594,211,328
bytes), so the recipe matches theirs.

## Greedy joint

```bash
make greedy-joint   # out/joint/greedy.mlpackage
```

`convert/prune_joint.py` removes the top-64 outputs and the ops only they need, 63 to 52 ops, the
same transformation as Nathan's `optimize_joint.py`.

## Assemble

```bash
make bundles
```

Writes three bundles under `out/bundles/`: `orukeet-int8sym-greedy`, `orukeet-fp16-greedy`, and,
if the asymmetric encoder exists, `orukeet-int8asym-greedy`. `convert/assemble_bundle.py` compiles
each package with `coremlcompiler` and records per-file hashes in `bundle.json`.

The preprocessor is taken from the shipped bundle, not from the export. It has no learned weights,
and the mobius export of it accepts a variable-length input that runs 8x slower on the CPU
(11 ms per clip against 1.4 ms) and produces slightly different features.

## Sizes

| Bundle | Disk |
|---|---|
| shipped greedy (6-bit palette) | 461 MB |
| int8 symmetric or asymmetric | 603 MB |
| FP16 | 1.1 GB |
