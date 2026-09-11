#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBIUS_URL="https://github.com/FluidInference/mobius.git"
MOBIUS_SHA="4040a39f760290bb1d43a72dc82e5894f27b0f5c"
SUBDIR="models/stt/parakeet-tdt-v3-0.6b/coreml"
VENDOR="$HERE/vendor/mobius"

command -v uv >/dev/null || { echo "uv not found on PATH"; exit 1; }
command -v git >/dev/null || { echo "git not found on PATH"; exit 1; }

# Fetch only the converter directory; blobs resolve lazily.
if [ ! -d "$VENDOR/.git" ]; then
  git clone --filter=blob:none --no-checkout "$MOBIUS_URL" "$VENDOR"
fi
cd "$VENDOR"
git sparse-checkout init --cone
git sparse-checkout set "$SUBDIR"
git checkout "$MOBIUS_SHA"

CONV="$VENDOR/$SUBDIR"
[ -f "$CONV/pyproject.toml" ] || { echo "converter not found at $CONV"; exit 1; }

cd "$CONV"
uv sync

echo
echo "Env ready:     $CONV/.venv"
echo "Converter dir: $CONV"
