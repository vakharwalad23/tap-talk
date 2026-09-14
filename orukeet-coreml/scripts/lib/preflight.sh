#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
preflight "$@"
echo "preflight ok: macOS $(uname -m), uv present, git present"
