#!/usr/bin/env bash
# Shared paths and preflight checks. Source from scripts/<group>/<name>.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd)"
VENDOR="$ROOT/vendor"
CONV="$VENDOR/mobius/models/stt/parakeet-tdt-v3-0.6b/coreml"
WORK="$ROOT/work"
OUT="$ROOT/out"
STAGE="$ROOT/models"
DATA="$ROOT/data"
SWIFT="$ROOT/swift"
REPORTS="$ROOT/reports"

FOLDER="parakeet-tdt-0.6b-v3"
BUNDLE_FP32="$OUT/orukeet-tdt-0.6b-v3-coreml"
BUNDLE_INT8="$OUT/orukeet-tdt-0.6b-v3-coreml-int8"
PARAKEET_REPO="FluidInference/parakeet-tdt-0.6b-v3-coreml"

die() { echo "error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
uvrun() { ( cd "$CONV" && uv run "$@" ); }

require_silicon() {
  [ "$(uname -s)" = "Darwin" ] || die "macOS required (found $(uname -s))"
  [ "$(uname -m)" = "arm64" ] || die "Apple Silicon arm64 required (found $(uname -m))"
}

# preflight [xcode] [swift] [env]
# Always checks macOS arm64, uv, git. Extra tokens add targeted checks.
preflight() {
  require_silicon
  have uv || die "missing uv (https://docs.astral.sh/uv/)"
  have git || die "missing git"
  for extra in "$@"; do
    case "$extra" in
      xcode) xcrun --find coremlcompiler >/dev/null 2>&1 || die "coremlcompiler not found; install Xcode then xcode-select --install" ;;
      swift) have swift || die "missing swift (install Xcode command line tools)" ;;
      env)   [ -d "$CONV/.venv" ] || die "converter env missing; run: make setup" ;;
    esac
  done
}
