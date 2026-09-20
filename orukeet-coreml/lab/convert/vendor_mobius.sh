#!/usr/bin/env bash
# Sparse checkout of the FluidInference converter at the commit the shipped Parakeet v3 graphs
# were produced from. Source only; the lab's own uv environment runs it.
set -euo pipefail
LAB="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$LAB/vendor/mobius"
URL="https://github.com/FluidInference/mobius.git"
SHA="4040a39f760290bb1d43a72dc82e5894f27b0f5c"
SUBDIR="models/stt/parakeet-tdt-v3-0.6b"
if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$LAB/vendor"
  git clone --filter=blob:none --no-checkout "$URL" "$DEST"
fi
cd "$DEST"
git sparse-checkout init --cone
git sparse-checkout set "$SUBDIR"
git checkout -q "$SHA"
[ -f "$SUBDIR/coreml/convert-parakeet.py" ] || { echo "converter missing after checkout"; exit 1; }
echo "mobius at $SHA: $DEST/$SUBDIR/coreml"
