#!/usr/bin/env bash
# Trace and convert every component at a shorter fixed audio window. Patches a copy of the
# vendored converter (kept alongside the original so its sibling imports keep working) instead of
# editing the vendored file: (a) the trace window becomes WINDOW_SECONDS instead of the hardcoded
# 15 s; (b) the preprocessor's flexible ct.RangeDim input becomes a fixed shape, matching how the
# lab already reuses a fixed-shape preprocessor for the 15 s window (see docs/bundles.md).
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: export_window.sh NEMO SECONDS OUT" >&2
  exit 1
fi

NEMO="$1"
WINDOW="$2"
OUT="$3"
LAB="$(cd "$(dirname "$0")/.." && pwd)"
CONV="$LAB/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
SRC="$CONV/convert-parakeet.py"
DST="$CONV/convert-parakeet-window.py"

[ -f "$NEMO" ] || { echo "missing $NEMO (run: make nemo)"; exit 1; }
[ -f "$SRC" ] || { echo "converter missing (run: make setup)"; exit 1; }
mkdir -p "$OUT"

cp -f "$SRC" "$DST"

if ! grep -qx 'import os' "$DST"; then
  perl -pi -e 's/^from __future__ import annotations$/from __future__ import annotations\nimport os/' "$DST"
fi

perl -pi -e 's/max_audio_seconds=15\.0,/max_audio_seconds=float(os.environ["WINDOW_SECONDS"]),/' "$DST"
perl -pi -e 's/shape=\(1, ct\.RangeDim\(1, max_samples\)\),/shape=(1, max_samples),/' "$DST"

if ! grep -qx 'import os' "$DST" || ! grep -q 'os\.environ\["WINDOW_SECONDS"\]' "$DST"; then
  echo "export_window.sh: patch (a) max_audio_seconds -> WINDOW_SECONDS did not apply to $DST" >&2
  exit 1
fi
if grep -q 'ct\.RangeDim' "$DST"; then
  echo "export_window.sh: patch (b) RangeDim -> fixed shape did not apply to $DST" >&2
  exit 1
fi
FIXED_SHAPE_COUNT=$(grep -c 'shape=(1, max_samples),' "$DST" || true)
if [ "${FIXED_SHAPE_COUNT:-0}" -lt 2 ]; then
  echo "export_window.sh: expected fixed preprocessor input shape not found in $DST" >&2
  exit 1
fi

# The script resolves its trace audio relative to its own location, so run it from its directory.
cd "$CONV"
WINDOW_SECONDS="$WINDOW" uv run --project "$LAB" python convert-parakeet-window.py --nemo-path "$NEMO" --output-dir "$OUT"
ls -la "$OUT"
