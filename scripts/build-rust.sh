#!/bin/bash
set -e
cd "$(dirname "$0")/../core"

cargo build --release

cargo run --release --bin uniffi-bindgen generate \
    --library target/release/libtap_talk_core.a \
    --language swift \
    --out-dir ../TapTalk/Generated

echo "Built: core/target/release/libtap_talk_core.a"
echo "Generated: TapTalk/Generated/"
