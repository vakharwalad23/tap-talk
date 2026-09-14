#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
preflight xcode env
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NEMO="$WORK/orukeet-v0.1.0.nemo"
mkdir -p "$WORK"

run() { ( cd "$CONV" && uv run "$@" ); }

run huggingface-cli download oruk/orukeet orukeet-v0.1.0.nemo --local-dir "$WORK"

# Vocab and config are fetched only to verify the assembled bundle.
run huggingface-cli download "$PARAKEET_REPO" \
  parakeet_vocab.json parakeet_v3_vocab.json config.json --local-dir "$WORK/reference"

# compile_modelc.py discovers the output by the fixed name parakeet_coreml.
run python convert-parakeet.py --nemo-path "$NEMO" --output-dir parakeet_coreml
run python compile_modelc.py

# Numeric check against the .nemo over the bundled 15s clip.
run python compare-components.py --output-dir parakeet_coreml --nemo-path "$NEMO" \
  --runs 10 --warmup 3

run python "$SELF/assemble_bundle.py" \
  --compiled "$CONV/compiled" \
  --reference "$WORK/reference" \
  --nemo "$NEMO" \
  --out "$BUNDLE_FP32"

echo "bundle: $BUNDLE_FP32"
