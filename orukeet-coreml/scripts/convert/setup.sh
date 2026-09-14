#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
preflight xcode swift

MOBIUS_URL="https://github.com/FluidInference/mobius.git"
MOBIUS_SHA="4040a39f760290bb1d43a72dc82e5894f27b0f5c"
SUBDIR="models/stt/parakeet-tdt-v3-0.6b/coreml"

# Fetch only the converter directory; blobs resolve lazily.
if [ ! -d "$VENDOR/mobius/.git" ]; then
  git clone --filter=blob:none --no-checkout "$MOBIUS_URL" "$VENDOR/mobius"
fi
cd "$VENDOR/mobius"
git sparse-checkout init --cone
git sparse-checkout set "$SUBDIR"
git checkout "$MOBIUS_SHA"

[ -f "$CONV/pyproject.toml" ] || die "converter not found at $CONV"
cd "$CONV"
uv sync

echo "env ready: $CONV/.venv"
