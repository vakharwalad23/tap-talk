#!/usr/bin/env bash
# Download the Orukeet r3 checkpoint from the Core ML preview branch and verify its hash.
set -euo pipefail
DEST="$1"
URL="https://huggingface.co/oruk/orukeet/resolve/coreml-taptalk-preview-20260915/orukeet-v0.1.0.nemo"
SHA="031c8ddab4845aeced904a7cde8e8aa57993b2e344716cf83a545b079c473b56"
mkdir -p "$(dirname "$DEST")"
if [ ! -f "$DEST" ]; then
  curl -L -C - -o "$DEST" "$URL"
fi
got="$(shasum -a 256 "$DEST" | cut -d' ' -f1)"
[ "$got" = "$SHA" ] || { echo "sha256 mismatch: $got"; exit 1; }
echo "verified $DEST"
