#!/usr/bin/env bash
# Make a patched, buildable copy of the vendored 2020 source.
# Usage: apply-patches.sh <dest-dir>
set -euo pipefail
ROOT="$HOME/repos/swiftgibs"
DEST="${1:?dest dir required}"
rm -rf "$DEST"; cp -r "$ROOT/vendor/sauer2020" "$DEST"; chmod -R u+w "$DEST"
# her 2020 enet fails on modern glibc (socklen_t); the mirror's enet builds clean
# and is protocol-identical for our purposes. Native (Linux/ARM) builds only.
rm -rf "$DEST/enet"; cp -r "$HOME/repos/sauerbraten/src/enet" "$DEST/enet"; chmod -R u+w "$DEST/enet"
shopt -s nullglob
for p in "$ROOT"/patches/*.patch; do
  echo "applying $(basename "$p")"; patch -d "$DEST" -p1 < "$p"
done
echo "patched source ready at $DEST"
