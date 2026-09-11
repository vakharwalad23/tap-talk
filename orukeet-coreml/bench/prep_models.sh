#!/usr/bin/env bash
# Stage both models locally in the identical layout AsrModels.load(from:) expects, so the
# benchmark runs on any Mac without depending on the FluidAudio cache location.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CONV="$ROOT/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
MODELS="$HERE/models"
FOLDER="parakeet-tdt-0.6b-v3"

rm -rf "$MODELS/orukeet/$FOLDER"
mkdir -p "$MODELS/orukeet"
cp -R "$ROOT/out/orukeet-tdt-0.6b-v3-coreml" "$MODELS/orukeet/$FOLDER"

# Parakeet: copy the installed FluidAudio cache when present, else download the required files.
CACHE="$HOME/Library/Application Support/FluidAudio/Models/$FOLDER"
rm -rf "$MODELS/parakeet/$FOLDER"
mkdir -p "$MODELS/parakeet"
if [ -d "$CACHE" ]; then
  cp -R "$CACHE" "$MODELS/parakeet/$FOLDER"
else
  uv run --project "$CONV" huggingface-cli download FluidInference/parakeet-tdt-0.6b-v3-coreml \
    --include "Preprocessor.mlmodelc/*" "Encoder.mlmodelc/*" "Decoder.mlmodelc/*" \
    "JointDecisionv3.mlmodelc/*" config.json parakeet_vocab.json parakeet_v3_vocab.json \
    --local-dir "$MODELS/parakeet/$FOLDER"
fi

echo "parakeet: $MODELS/parakeet/$FOLDER"
echo "orukeet:  $MODELS/orukeet/$FOLDER"
