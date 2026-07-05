#!/usr/bin/env bash
# Make a patched, buildable copy of the vendored 2020 source.
# Usage: apply-patches.sh <dest-dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # repo root, location-independent
DEST="${1:?dest dir required}"
rm -rf "$DEST"; cp -r "$ROOT/vendor/sauer2020" "$DEST"; chmod -R u+w "$DEST"
# her 2020 enet fails on modern glibc (socklen_t); the mirror's enet builds clean and is
# protocol-identical. Swap it in when available; skip gracefully (CI/macOS may not need it).
# ENET_SRC overrides the source; SWAP_ENET=0 forces keeping the vendored enet.
ENET_SRC="${ENET_SRC:-$HOME/repos/sauerbraten/src/enet}"
if [ "${SWAP_ENET:-1}" = "1" ] && [ -d "$ENET_SRC" ]; then
  rm -rf "$DEST/enet"; cp -r "$ENET_SRC" "$DEST/enet"; chmod -R u+w "$DEST/enet"
  echo "enet: swapped from $ENET_SRC"
else
  echo "enet: keeping vendored (SWAP_ENET=${SWAP_ENET:-1}, ENET_SRC exists=$([ -d "$ENET_SRC" ] && echo yes || echo no))"
fi
shopt -s nullglob
for p in "$ROOT"/patches/*.patch; do
  echo "applying $(basename "$p")"; patch -d "$DEST" -p1 < "$p"
done
echo "patched source ready at $DEST"
