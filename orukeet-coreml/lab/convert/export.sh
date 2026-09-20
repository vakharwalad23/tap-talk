#!/usr/bin/env bash
# Trace and convert every component from the .nemo with the vendored mobius converter, unchanged,
# inside the lab's uv environment. The mlprogram default precision is FP16; no palettization.
set -euo pipefail
NEMO="$1"
OUT="$2"
LAB="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$LAB/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
[ -f "$NEMO" ] || { echo "missing $NEMO (run: make nemo)"; exit 1; }
[ -f "$CONV/convert-parakeet.py" ] || { echo "converter missing (run: make setup)"; exit 1; }
mkdir -p "$OUT"
# The script resolves its trace audio relative to its own location, so run it from its directory.
cd "$CONV"
uv run --project "$LAB" python convert-parakeet.py --nemo-path "$NEMO" --output-dir "$OUT"
ls -la "$OUT"
