#!/usr/bin/env bash
# Score one raw-pass directory into fp32 and int8 reports, grouped by whatever langs the data holds.
# Used for datasets that are not the FLEURS 25 (e.g. LibriSpeech). RAW and DEST are required.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RAW="${RAW:?set RAW to the raw-pass directory}"
DEST="${DEST:?set DEST to the report output directory}"
for f in parakeet orukeet-fp32 orukeet-int8; do
  [ -f "$RAW/$f.json" ] || die "missing $RAW/$f.json"
done

mkdir -p "$DEST/fp32" "$DEST/int8"
python3 "$SELF/score.py" --out "$DEST/fp32/summary.md" \
  --results "$RAW/parakeet.json" "$RAW/orukeet-fp32.json" >/dev/null
python3 "$SELF/score.py" --out "$DEST/int8/summary.md" \
  --results "$RAW/parakeet.json" "$RAW/orukeet-int8.json" >/dev/null
echo "reports in $DEST"
