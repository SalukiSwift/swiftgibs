#!/usr/bin/env bash
# SwiftGibs ARM engine build (Raspberry Pi 4/5 + Mesa desktop-GL) — EXPERIMENTAL / DEFERRED.
#
# Two ways to build the patched ARM binary:
#
#   (A) NATIVE on a Raspberry Pi  (recommended — actually testable there):
#         git clone the repo onto the Pi (with vendor/sauer2020 + patches), install
#         build deps (g++ make libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev), then
#         run THIS script on the Pi — uname is aarch64, so it does a native build.
#
#   (B) CROSS-compile from x86 (blind, untested — needs arm64 SDL via ports multiarch):
#         sudo dpkg --add-architecture arm64
#         echo 'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main universe' \
#             | sudo tee /etc/apt/sources.list.d/arm64-ports.list
#         sudo apt-get update
#         sudo apt-get install -y libsdl2-dev:arm64 libsdl2-image-dev:arm64 libsdl2-mixer-dev:arm64
#       (g++-aarch64-linux-gnu is already installed.) Then run this script on x86.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; B=/tmp/sg-engine-arm
"$ROOT/build/apply-patches.sh" "$B"

if [ "$(uname -m)" = "aarch64" ]; then
  make -C "$B" -j"$(nproc)" client                       # native Pi build
else
  command -v aarch64-linux-gnu-g++ >/dev/null || { echo "need: sudo apt install g++-aarch64-linux-gnu"; exit 1; }
  ls /usr/lib/aarch64-linux-gnu/libSDL2*.so >/dev/null 2>&1 \
    || { echo "need arm64 SDL libs — see option (B) in this script's header"; exit 1; }
  make -C "$B" -j"$(nproc)" client \
    CXX=aarch64-linux-gnu-g++ \
    CLIENT_INCLUDES="-Ishared -Iengine -Ifpsgame -Ienet/include -I/usr/include/SDL2" \
    CLIENT_LIBS="-Lenet -lenet -lSDL2 -lSDL2_image -lSDL2_mixer -lz -lGL -lrt"
fi

mkdir -p "$ROOT/dist/engines/linux-arm64"
cp "$B/sauer_client" "$ROOT/dist/engines/linux-arm64/sauer_client"
file "$ROOT/dist/engines/linux-arm64/sauer_client"
echo "ARM build done (EXPERIMENTAL — verify on real Pi 4/5 hardware before trusting)."
