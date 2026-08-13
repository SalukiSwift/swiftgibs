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
# MAPS=none (slim, default): mapshots + map cfgs only, .ogz/.wpt stream on demand (patch 21).
# MAPS=all (fat): every stock map baked in, for public-server compat / zero-network play.
# The archive filename carries an -allmaps suffix for the fat variant, but the folder INSIDE
# the archive is always "swiftgibs-win64" (see the zip line below) so both variants extract to,
# and update-swiftgibs.bat overlays onto, the same install directory.
MAPS="${MAPS:-none}"
ARCHIVE="swiftgibs-win64"
[ "$MAPS" = all ] && ARCHIVE="swiftgibs-win64-allmaps"

# 1) strip a low-res tree from the SAME install the exe comes from.
#    MAPS=none (default): ship only mapshots + map cfgs (.ogz/.wpt stream on demand, patch 21).
#    MAPS=all: ship every stock map so any public server's map loads with zero network use.
SRC="$INSTALL" MAPS="$MAPS" "$ROOT/tools/strip-assets.sh" "$STAGE"

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

# 3b) map manifest (patch 21's streaming downloader reads this): every bundle ships it, slim AND
# fat alike, so the client always knows the full 331-map catalogue (name/size/hash) even when
# most of those maps aren't physically present yet. Generated from the SAME install the maps
# themselves were staged from, so hashes always match what's actually on disk for MAPS=all.
"$ROOT/build/make-map-manifest.sh" "$INSTALL" > "$OUT/data/mapmanifest.cfg"

# 4) overlay last so it wins (autoexec, menus, crosshair, servers.cfg)
cp -a "$ROOT/overlay/." "$OUT/"
rm -f "$OUT/autoexec.source.cfg"   # internal reference file, don't ship

# 4b) attach the SwiftGibs + Friends tabs to the staged stock options menu; ship no user config
"$ROOT/build/integrate-menus.sh" "$OUT"
rm -f "$OUT/config.cfg" "$OUT/init.cfg"   # fresh VARP defaults + native-resolution auto-detect

# 4c) bundled ffmpeg (video export, clip-export feature): its own directory, sibling of bin64/
# data/packages, matching the engine's default clipexportffmpeg lookup path (ffmpeg/ffmpeg.exe,
# resolved relative to cwd - CreateProcess never searches PATH for a relative path that contains
# a directory separator, and cwd here is $OUT since swiftgibs.bat below launches from wherever it
# was double-clicked). GPL-licensed, never linked into the engine - see
# build/ffmpeg-licence/NOTICE.txt and docs/ffmpeg-provenance.md for exact version/checksum/
# source. Windows-only binary; nothing from another platform ends up in this bundle.
FFMPEG_DIR="$("$ROOT/build/fetch-ffmpeg.sh" win)"
mkdir -p "$OUT/ffmpeg"
cp "$FFMPEG_DIR/ffmpeg.exe" "$FFMPEG_DIR/LICENSE.txt" "$FFMPEG_DIR/NOTICE.txt" "$OUT/ffmpeg/"

# 5) portable launcher: '.' = home dir, so our root autoexec.cfg loads
printf '@echo off\r\nstart bin64\\sauerbraten.exe -q.\r\n' > "$OUT/swiftgibs.bat"

# 6) zip
cd "$ROOT/dist"
rm -f "$ARCHIVE.zip"
zip -rq "$ARCHIVE.zip" swiftgibs-win64
echo "bundle (MAPS=$MAPS): $(du -sh "$OUT" | cut -f1) | zip: $(du -sh "$ARCHIVE.zip" | cut -f1)"
