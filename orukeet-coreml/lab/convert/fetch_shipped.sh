#!/usr/bin/env bash
# Fetch the Core ML preview Nathan published (greedy by default, or baseline), verify the archive
# hash, and compile it into models/shipped-<profile>/ exactly as TapTalk does on install. Every
# measurement in this lab is relative to that copy, so it must come from the pinned release, not
# from whatever a local TapTalk install happens to hold.
set -euo pipefail
PROFILE="${1:-greedy}"
LAB="$(cd "$(dirname "$0")/.." && pwd)"
REVISION="coreml-taptalk-preview-20260915"
case "$PROFILE" in
  greedy)   SHA="beccdc6f18c4b10527a764f6e3ab12e3e11b969220c0cee175b3bb7eaa94290e" ;;
  baseline) SHA="b2a6efc4ed3280c860f29b3e2e2ea242ade14c6482c94f1c8d3e8551d5edb626" ;;
  *) echo "profile must be greedy or baseline"; exit 1 ;;
esac
ZIP="$LAB/work/orukeet-r3-coreml-$PROFILE.zip"
PACKAGES="$LAB/models/shipped-$PROFILE-packages"
OUT="$LAB/models/shipped-$PROFILE"
URL="https://huggingface.co/oruk/orukeet/resolve/$REVISION/coreml/orukeet-r3-coreml-$PROFILE.zip"

mkdir -p "$LAB/work" "$LAB/models"
if [ ! -f "$ZIP" ]; then
  curl -L -C - -o "$ZIP" "$URL"
fi
got="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
[ "$got" = "$SHA" ] || { echo "sha256 mismatch for $ZIP: $got"; exit 1; }

if [ ! -f "$PACKAGES/parakeet_vocab.json" ]; then
  rm -rf "$PACKAGES" "$PACKAGES.tmp"
  mkdir -p "$PACKAGES.tmp"
  ditto -x -k "$ZIP" "$PACKAGES.tmp"
  # The archive has one top-level directory.
  mv "$PACKAGES.tmp/orukeet-r3-coreml-$PROFILE" "$PACKAGES"
  rm -rf "$PACKAGES.tmp"
fi

if [ ! -f "$OUT/parakeet_vocab.json" ]; then
  uv run --project "$LAB/bench" python "$LAB/convert/assemble_bundle.py" \
    --preprocessor "$PACKAGES/Preprocessor.mlpackage" --encoder "$PACKAGES/Encoder.mlpackage" \
    --decoder "$PACKAGES/Decoder.mlpackage" --joint "$PACKAGES/JointDecisionv3.mlpackage" \
    --vocab "$PACKAGES/parakeet_vocab.json" --out "$OUT"
fi
echo "shipped $PROFILE bundle: $OUT"
