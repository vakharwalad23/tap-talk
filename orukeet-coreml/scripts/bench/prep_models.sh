#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
preflight env

# Parakeet is fetched from Hugging Face (it ships Core ML upstream), never from a local install,
# so the benchmark reproduces on any machine. Orukeet comes from our converted bundles.
stage_local() {
  local src="$1" name="$2"
  [ -d "$src" ] || die "$name bundle missing at $src"
  rm -rf "${STAGE:?}/$name/$FOLDER"
  mkdir -p "$STAGE/$name"
  cp -R "$src" "$STAGE/$name/$FOLDER"
}

rm -rf "${STAGE:?}/parakeet/$FOLDER"
mkdir -p "$STAGE/parakeet"
uvrun huggingface-cli download "$PARAKEET_REPO" \
  --include "Preprocessor.mlmodelc/*" "Encoder.mlmodelc/*" "Decoder.mlmodelc/*" \
  "JointDecisionv3.mlmodelc/*" config.json parakeet_vocab.json parakeet_v3_vocab.json \
  --local-dir "$STAGE/parakeet/$FOLDER"
rm -rf "$STAGE/parakeet/$FOLDER/.cache"

stage_local "$BUNDLE_FP32" orukeet-fp32
[ -d "$BUNDLE_INT8" ] && stage_local "$BUNDLE_INT8" orukeet-int8 || echo "note: int8 bundle absent; run make quantize to include it"

echo "staged under $STAGE"
