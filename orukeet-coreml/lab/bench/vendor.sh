#!/usr/bin/env bash
# Sparse checkout of Nathan Roll's Core ML PR branch: corpus sealer, scorer, and the published
# evidence (sealed manifests, per-model hypotheses). Plus the four fixture clips from main.
set -euo pipefail
LAB="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$LAB/vendor/orukeet"
URL="https://github.com/Oruk-AI/orukeet.git"
SHA="852c3e355f20a111a2ee39f76677bc0ba65147bf"
if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$LAB/vendor"
  git clone --filter=blob:none --no-checkout "$URL" "$DEST"
fi
cd "$DEST"
git sparse-checkout init --cone
git sparse-checkout set export/coreml evaluation/standard_asr evidence/coreml-taptalk-20260915
git fetch -q origin "$SHA" main
git checkout -q "$SHA"
[ -f export/coreml/prepare_fleurs.py ] || { echo "prepare_fleurs.py missing"; exit 1; }
[ -f evaluation/standard_asr/scoring.py ] || { echo "scoring.py missing"; exit 1; }

FIX="$LAB/data/fixtures"
mkdir -p "$FIX"
for f in demos/fixtures/jfk.wav demos/multilingual/audio/fr_fr.source.wav \
         demos/multilingual/audio/es_419.source.wav demos/multilingual/audio/lv_lv.source.wav; do
  name="$(basename "$f")"
  [ -f "$FIX/$name" ] || git show "origin/main:$f" > "$FIX/$name"
done
ls -la "$FIX"
echo "orukeet at $SHA: $DEST"
