#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
preflight xcode env
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -d "$BUNDLE_FP32" ] || die "float32 bundle missing at $BUNDLE_FP32; run: make convert"
SCRATCH="$WORK/int8"
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"

uvrun python "$SELF/quantize_encoder.py" \
  --src "$CONV/parakeet_coreml/parakeet_encoder.mlpackage" \
  --dst "$SCRATCH/Encoder.mlpackage"
xcrun coremlcompiler compile "$SCRATCH/Encoder.mlpackage" "$SCRATCH"

rm -rf "$BUNDLE_INT8"; mkdir -p "$(dirname "$BUNDLE_INT8")"
cp -R "$BUNDLE_FP32" "$BUNDLE_INT8"
rm -rf "$BUNDLE_INT8/Encoder.mlmodelc"
cp -R "$SCRATCH/Encoder.mlmodelc" "$BUNDLE_INT8/Encoder.mlmodelc"
rm -rf "$SCRATCH"

echo "bundle: $BUNDLE_INT8"
du -sh "$BUNDLE_INT8"
