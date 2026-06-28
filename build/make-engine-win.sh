#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; B=/tmp/sg-engine-win
"$ROOT/build/apply-patches.sh" "$B"
# The Makefile requires "CROSS" in PLATFORM to activate x86_64-w64-mingw32-g++.
# MINGW64CROSS contains "MINGW", "64", and "CROSS".
# Also: -lzlib1 looks for zlib1.lib but the bundled import lib is zdll.lib; symlink it.
ln -sf zdll.lib "$B/lib64/zlib1.lib"
mkdir -p "$B/../bin64"                      # WINBIN target dir for the mingw client rule
make -C "$B" PLATFORM=MINGW64CROSS -j"$(nproc)" client
mkdir -p "$ROOT/dist/engines/win64"
cp "$B/../bin64/sauerbraten.exe" "$ROOT/dist/engines/win64/sauerbraten.exe"
file "$ROOT/dist/engines/win64/sauerbraten.exe"
