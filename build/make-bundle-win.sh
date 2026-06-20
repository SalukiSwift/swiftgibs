#!/usr/bin/env bash
# Assemble the Windows SwiftGibs bundle from a staged tree + overlay + stock binary.
# Usage: make-bundle-win.sh <stage-dir>
set -euo pipefail
ROOT="$HOME/repos/swiftgibs"
STAGE="${1:?stage dir required}"
WINBIN="/mnt/c/Program Files (x86)/Sauerbraten/bin64"
OUT="$ROOT/dist/swiftgibs-win64"

rm -rf "$OUT"; mkdir -p "$OUT/bin64"

# stock client + runtime DLLs only (exclude EOS/EAC/p1xbraten/pdb/uninstall)
cp "$WINBIN/sauerbraten.exe" "$OUT/bin64/"
find "$WINBIN" -maxdepth 1 -name '*.dll' ! -iname 'EOSSDK*' -exec cp {} "$OUT/bin64/" \;

# staged data + packages
cp -a "$STAGE/data" "$OUT/data"
cp -a "$STAGE/packages" "$OUT/packages"

# overlay last so it wins (autoexec, menus, crosshair, q009, servers.cfg)
cp -a "$ROOT/overlay/." "$OUT/"
rm -f "$OUT/autoexec.source.cfg"   # internal reference file, don't ship

# portable launcher: '.' = home dir, so our root autoexec.cfg loads
printf '@echo off\r\nstart bin64\\sauerbraten.exe -q.\r\n' > "$OUT/swiftgibs.bat"

# zip
cd "$ROOT/dist"
rm -f swiftgibs-win64.zip
zip -rq swiftgibs-win64.zip swiftgibs-win64
echo "bundle: $(du -sh "$OUT" | cut -f1) | zip: $(du -sh swiftgibs-win64.zip | cut -f1)"
