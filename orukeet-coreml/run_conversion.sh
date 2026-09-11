#!/usr/bin/env bash
# Held: do not run until setup.sh completes and this recipe is reviewed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONV="$HERE/vendor/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
MODELS="$HERE/models"
REFERENCE="$HERE/reference"
NEMO="$MODELS/orukeet-v0.1.0.nemo"

[ -d "$CONV/.venv" ] || { echo "run setup.sh first (no env at $CONV/.venv)"; exit 1; }
mkdir -p "$MODELS" "$REFERENCE"

run() { ( cd "$CONV" && uv run "$@" ); }

run huggingface-cli download oruk/orukeet orukeet-v0.1.0.nemo --local-dir "$MODELS"

# Vocab and config are fetched only to verify the assembled bundle.
run huggingface-cli download FluidInference/parakeet-tdt-0.6b-v3-coreml \
  parakeet_vocab.json parakeet_v3_vocab.json config.json --local-dir "$REFERENCE"

# compile_modelc.py discovers the output by the fixed name parakeet_coreml.
run python convert-parakeet.py --nemo-path "$NEMO" --output-dir parakeet_coreml
run python compile_modelc.py

# Numeric check against the .nemo over the bundled 15s clip.
run python compare-components.py --output-dir parakeet_coreml --nemo-path "$NEMO" \
  --runs 10 --warmup 3

run python "$HERE/assemble_bundle.py" \
  --compiled "$CONV/compiled" \
  --reference "$REFERENCE" \
  --nemo "$NEMO" \
  --out "$HERE/out/orukeet-tdt-0.6b-v3-coreml"

echo
echo "Bundle: $HERE/out/orukeet-tdt-0.6b-v3-coreml"
