#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
preflight swift

MANIFEST="${MANIFEST:-$DATA/fleurs-full/manifest.jsonl}"
RAW="${RAW:-$REPORTS/_raw}"
BIN="$SWIFT/.build/release/ttbench"

[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST (run make data)"
[ -x "$BIN" ] || die "harness not built: $BIN (run make build)"
mkdir -p "$RAW"

pass() {
  local out="$1" dir="$2" label="$3"
  [ -d "$dir/$FOLDER" ] || die "staged model missing: $dir/$FOLDER (run make models)"
  echo "=== $out ==="
  "$BIN" --manifest "$MANIFEST" --model-dir "$dir/$FOLDER" --label "$label" --out "$RAW/$out.json"
}

# Parakeet is deterministic, so a single pass serves both precision comparisons.
pass parakeet     "$STAGE/parakeet"     parakeet
pass orukeet-fp32 "$STAGE/orukeet-fp32" orukeet
pass orukeet-int8 "$STAGE/orukeet-int8" orukeet

echo "raw results in $RAW"
