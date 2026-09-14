#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RAW="${RAW:-$REPORTS/_raw}"
DEST="${REPORT_DEST:-$REPORTS/fleurs-full}"

for f in parakeet orukeet-fp32 orukeet-int8; do
  [ -f "$RAW/$f.json" ] || die "missing $RAW/$f.json (run make bench-run first)"
done

score() {
  local dir="$1"; shift
  mkdir -p "$DEST/$dir"
  python3 "$SELF/score.py" --out "$DEST/$dir/summary.md" "$@" >/dev/null
  echo "$dir"
}

score multilingual-fp32 --results "$RAW/parakeet.json" "$RAW/orukeet-fp32.json"
score multilingual-int8 --results "$RAW/parakeet.json" "$RAW/orukeet-int8.json"
score english-fp32 --only-lang en_us --results "$RAW/parakeet.json" "$RAW/orukeet-fp32.json"
score english-int8 --only-lang en_us --results "$RAW/parakeet.json" "$RAW/orukeet-int8.json"

echo "reports in $DEST"
