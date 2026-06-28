#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B=/tmp/sg-engine-linux

"$ROOT/build/apply-patches.sh" "$B"
make -C "$B" -j"$(nproc)" client
mkdir -p "$ROOT/dist/engines/linux-x86_64"
cp "$B/sauer_client" "$ROOT/dist/engines/linux-x86_64/sauer_client"

OUT="$ROOT/dist/engines/linux-x86_64/sauer_client"
echo "linux engine built:"
ls -lh "$OUT"
file "$OUT"
