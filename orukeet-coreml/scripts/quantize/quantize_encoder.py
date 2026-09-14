#!/usr/bin/env python3
# Quantize the Orukeet encoder to int8 (linear, per-channel) so it matches Parakeet's int8 encoder.
# Weight-only quantization; the graph and its input/output shapes are unchanged.
import argparse
from pathlib import Path

import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, required=True, help="float32 encoder .mlpackage")
    ap.add_argument("--dst", type=Path, required=True, help="int8 encoder .mlpackage to write")
    args = ap.parse_args()

    model = ct.models.MLModel(str(args.src), compute_units=ct.ComputeUnit.CPU_ONLY)
    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode="linear", granularity="per_channel"))
    quantized = linear_quantize_weights(model, config)
    quantized.save(str(args.dst))
    print(f"wrote {args.dst}")


if __name__ == "__main__":
    main()
