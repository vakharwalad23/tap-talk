#!/usr/bin/env bash
# Fuse the decoder and joint+decision head into one Core ML graph with the vendored fusion
# script, then check its parity against the chained fp32 reference, inside the lab's uv env.
set -euo pipefail
NEMO="$1"
OUT="$2"
LAB="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$LAB/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
[ -f "$NEMO" ] || { echo "missing $NEMO (run: make nemo)"; exit 1; }
[ -f "$CONV/fuse_decoder_joint.py" ] || { echo "fusion script missing (run: make setup)"; exit 1; }
mkdir -p "$OUT"
# Canonicalize before the cd below, so a relative OUT still lands here and not under $CONV.
OUT="$(cd "$OUT" && pwd)"
# The script imports individual_components from its own directory, so run it from there.
cd "$CONV"
uv run --project "$LAB" python fuse_decoder_joint.py export --nemo-path "$NEMO" --output-dir "$OUT"
uv run --project "$LAB" python fuse_decoder_joint.py parity --build-dir "$OUT" | tee "$OUT/parity.txt"
ls -la "$OUT"
