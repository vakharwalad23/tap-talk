#!/usr/bin/env bash
# Score the raw passes into the four full-FLEURS reports (english and multilingual, fp32 and int8).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW="$HERE/reports/_raw"
OUT="$HERE/reports/fleurs-full"

for f in parakeet orukeet-fp32 orukeet-int8; do
  [ -f "$RAW/$f.json" ] || { echo "missing $RAW/$f.json (run run_full_bench.sh first)"; exit 1; }
done

score() {
  local dir="$1"; shift
  mkdir -p "$OUT/$dir"
  python3 "$HERE/score.py" --out "$OUT/$dir/summary.md" "$@" >/dev/null
  echo "$dir"
}

score multilingual-fp32 --results "$RAW/parakeet.json" "$RAW/orukeet-fp32.json"
score multilingual-int8 --results "$RAW/parakeet.json" "$RAW/orukeet-int8.json"
score english-fp32 --only-lang en_us --results "$RAW/parakeet.json" "$RAW/orukeet-fp32.json"
score english-int8 --only-lang en_us --results "$RAW/parakeet.json" "$RAW/orukeet-int8.json"

echo "reports in $OUT"
