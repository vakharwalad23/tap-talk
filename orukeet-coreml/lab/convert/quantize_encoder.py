#!/usr/bin/env python3
# Weight-only int8 quantization of the FP16 encoder export. Symmetric per-channel is the recipe
# FluidInference used for Encoder_v2; asymmetric is kept as an option for the latency A/B.
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
    ap.add_argument("--src", type=Path, required=True, help="FP16 encoder .mlpackage")
    ap.add_argument("--dst", type=Path, required=True, help="int8 encoder .mlpackage to write")
    ap.add_argument("--mode", default="linear_symmetric", choices=["linear_symmetric", "linear"])
    args = ap.parse_args()
    if args.dst.exists():
        raise SystemExit(f"{args.dst} exists; remove it first")
    model = ct.models.MLModel(str(args.src), compute_units=ct.ComputeUnit.CPU_ONLY)
    config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(mode=args.mode, dtype="int8", granularity="per_channel")
    )
    quantized = linear_quantize_weights(model, config)
    quantized.save(str(args.dst))
    weights = args.dst / "Data/com.apple.CoreML/weights/weight.bin"
    print(f"wrote {args.dst} ({weights.stat().st_size / 1e6:.1f} MB weights, mode {args.mode})")


if __name__ == "__main__":
    main()
