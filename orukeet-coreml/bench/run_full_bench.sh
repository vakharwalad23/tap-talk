#!/usr/bin/env bash
# Full FLEURS run: transcribe every clip once per model (parakeet int8, orukeet fp32, orukeet int8).
# Parakeet is deterministic, so one pass serves both precision comparisons. Long running.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/fleurs-full/manifest.jsonl"
RAW="$HERE/reports/_raw"
BIN="$HERE/.build/release/ttbench"

[ -f "$MANIFEST" ] || { echo "missing manifest: $MANIFEST (run fleurs_prep first)"; exit 1; }
[ -x "$BIN" ] || { echo "missing binary: $BIN (swift build -c release)"; exit 1; }
mkdir -p "$RAW"

run() {
  local label="$1" dir="$2"
  echo "=== $label ==="
  "$BIN" --manifest "$MANIFEST" --model-dir "$dir" --label "$3" --out "$RAW/$label.json"
}

run parakeet     "$HERE/models/parakeet/parakeet-tdt-0.6b-v3"     parakeet
run orukeet-fp32 "$HERE/models/orukeet/parakeet-tdt-0.6b-v3"      orukeet
run orukeet-int8 "$HERE/models/orukeet-int8/parakeet-tdt-0.6b-v3" orukeet

echo "raw results in $RAW"
