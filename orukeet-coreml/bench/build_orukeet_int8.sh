#!/usr/bin/env bash
# Build an int8-encoder Orukeet bundle so its precision matches Parakeet for a clean comparison.
# Only the encoder changes; decoder, JointDecisionv3, preprocessor, and vocab stay as converted.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONV="$ROOT/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
FOLDER="parakeet-tdt-0.6b-v3"
DST="$HERE/models/orukeet-int8/$FOLDER"
WORK="$HERE/work-int8"

rm -rf "$WORK"; mkdir -p "$WORK"
uv run --project "$CONV" python "$HERE/quantize_encoder.py" \
  --src "$CONV/parakeet_coreml/parakeet_encoder.mlpackage" \
  --dst "$WORK/Encoder.mlpackage"
xcrun coremlcompiler compile "$WORK/Encoder.mlpackage" "$WORK"

rm -rf "$DST"; mkdir -p "$(dirname "$DST")"
cp -R "$ROOT/out/orukeet-tdt-0.6b-v3-coreml" "$DST"
rm -rf "$DST/Encoder.mlmodelc"
cp -R "$WORK/Encoder.mlmodelc" "$DST/Encoder.mlmodelc"
rm -rf "$WORK"

echo "orukeet-int8: $DST"
du -sh "$DST"
