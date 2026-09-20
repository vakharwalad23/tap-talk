#!/usr/bin/env bash
# Seal Nathan's two 64-clip FLEURS regression corpora with his own script, then prove every
# fixture hash matches his published manifests so scores are comparable clip for clip.
set -euo pipefail
LAB="$(cd "$(dirname "$0")/.." && pwd)"
V="$LAB/vendor/orukeet"
EV="$V/evidence/coreml-taptalk-20260915"
PY="uv run --project $LAB/bench python"
# python.org builds ship no CA bundle; point urllib at certifi so the sealer can reach Hugging Face.
export SSL_CERT_FILE="$($PY -c "import certifi; print(certifi.where())")"
[ -f "$V/export/coreml/prepare_fleurs.py" ] || { echo "run: make vendor"; exit 1; }
cd "$LAB"
seal() {
  local out="$1"; shift
  [ -f "$out/manifest.json" ] && return 0
  local resume=()
  [ -d "$out" ] && resume=(--resume)
  $PY "$V/export/coreml/prepare_fleurs.py" --output "$out" --per-language 8 ${resume[@]+"${resume[@]}"} "$@"
}
seal data/fleurs-a
seal data/fleurs-b --skip-per-language 8
$PY bench/verify_corpus.py --corpus data/fleurs-a/manifest.json --expected "$EV/fleurs/corpus.json"
$PY bench/verify_corpus.py --corpus data/fleurs-b/manifest.json --expected "$EV/holdout/corpus.json"
