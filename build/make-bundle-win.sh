#!/usr/bin/env bash
# Assemble the Windows SwiftGibs bundle: stock binary + data BOTH from a
# matching Sauerbraten install. The stock exe and its data/maps/shaders are
# version-locked -- pairing the exe with a DIFFERENT release's data (e.g. the git
# mirror) gives blank maps, broken icons, and shader errors. So we always strip
# from the same install the exe comes from.
# Usage: make-bundle-win.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # repo root, location-independent (works in CI)
INSTALL="${INSTALL:-/mnt/c/Program Files (x86)/Sauerbraten}"   # 2020 install (override for CI/official data)
WINBIN="$INSTALL/bin64"
OUT="$ROOT/dist/swiftgibs-win64"
STAGE="${STAGE:-/tmp/swiftgibs-stage}"

# 1) strip a low-res tree from the SAME install the exe comes from.
#    ALLMAPS=1 (default): ship every stock map so any public server's map loads.
#    Set ALLMAPS=0 to ship only the curated pool in maps/pool.txt (RUGBY rotation + venice + local
#    bot-match maps) for a ~halved download, at the cost of maps outside the pool not loading.
SRC="$INSTALL" ALLMAPS="${ALLMAPS:-1}" "$ROOT/tools/strip-assets.sh" "$ROOT/maps/pool.txt" "$STAGE"

rm -rf "$OUT"; mkdir -p "$OUT/bin64"

# 2) stock client + runtime DLLs only (exclude EOS/EAC/p1xbraten/pdb/uninstall)
# patched SwiftGibs engine (M2); fall back to stock if not built yet
if [ -f "$ROOT/dist/engines/win64/sauerbraten.exe" ]; then
  cp "$ROOT/dist/engines/win64/sauerbraten.exe" "$OUT/bin64/"
else
  echo "WARN: patched exe missing, using stock"; cp "$WINBIN/sauerbraten.exe" "$OUT/bin64/"
fi
cp "$ROOT"/vendor/windows-dlls/*.dll "$OUT/bin64/"   # vendored redistributable runtime DLLs (no local install needed)

# 3) staged data + packages (make writable -- copies off /mnt/c come read-only)
cp -a "$STAGE/data" "$OUT/data"
cp -a "$STAGE/packages" "$OUT/packages"
chmod -R u+w "$OUT"

# 4) overlay last so it wins (autoexec, menus, crosshair, servers.cfg)
cp -a "$ROOT/overlay/." "$OUT/"
rm -f "$OUT/autoexec.source.cfg"   # internal reference file, don't ship

# 4b) attach the SwiftGibs + Friends tabs to the staged stock options menu; ship no user config
"$ROOT/build/integrate-menus.sh" "$OUT"
rm -f "$OUT/config.cfg" "$OUT/init.cfg"   # fresh VARP defaults + native-resolution auto-detect

# 5) portable launcher: '.' = home dir, so our root autoexec.cfg loads
printf '@echo off\r\nstart bin64\\sauerbraten.exe -q.\r\n' > "$OUT/swiftgibs.bat"

# 6) zip
cd "$ROOT/dist"
rm -f swiftgibs-win64.zip
zip -rq swiftgibs-win64.zip swiftgibs-win64
echo "bundle: $(du -sh "$OUT" | cut -f1) | zip: $(du -sh swiftgibs-win64.zip | cut -f1)"
