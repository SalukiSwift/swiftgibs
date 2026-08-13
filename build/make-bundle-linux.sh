#!/usr/bin/env bash
# Assemble the Linux SwiftGibs bundle: native client + stripped official data + overlay + launcher.
# Usage: [INSTALL=<data-root>] build/make-bundle-linux.sh   (INSTALL defaults to fetch-official-data)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${INSTALL:-$("$ROOT/build/fetch-official-data.sh")}"
STAGE="${STAGE:-/tmp/swiftgibs-linux-stage}"
OUT="$ROOT/dist/SwiftGibs-linux-x86_64"
# MAPS=none (slim, default): mapshots + map cfgs only, .ogz/.wpt stream on demand (patch 21).
# MAPS=all (fat): every stock map baked in, for public-server compat / zero-network play.
# The archive filename carries an -allmaps suffix for the fat variant, but the folder INSIDE
# the archive is always "SwiftGibs-linux-x86_64" (see the tar line below) so both variants
# extract to, and update-swiftgibs.sh overlays onto, the same install directory.
MAPS="${MAPS:-none}"
ARCHIVE="SwiftGibs-linux-x86_64"
[ "$MAPS" = all ] && ARCHIVE="SwiftGibs-linux-x86_64-allmaps"

# Use a prebuilt client if present (CI supplies it from the native-binaries job); else build it.
if [ ! -f "$ROOT/dist/engines/linux-x86_64/sauer_client" ]; then
  "$ROOT/build/make-engine-linux.sh" >/dev/null
fi
rm -rf "$OUT"; mkdir -p "$OUT/bin"
cp "$ROOT/dist/engines/linux-x86_64/sauer_client" "$OUT/bin/swiftgibs"

SRC="$INSTALL" MAPS="$MAPS" "$ROOT/tools/strip-assets.sh" "$STAGE"
cp -a "$STAGE/data" "$OUT/data"; cp -a "$STAGE/packages" "$OUT/packages"

# Map manifest (patch 21's streaming downloader reads this): every bundle ships it, slim AND
# fat alike, so the client always knows the full 331-map catalogue (name/size/hash) even when
# most of those maps aren't physically present yet. Generated from the SAME install the maps
# themselves were staged from, so hashes always match what's actually on disk for MAPS=all.
"$ROOT/build/make-map-manifest.sh" "$INSTALL" > "$OUT/data/mapmanifest.cfg"

cp -a "$ROOT/overlay/." "$OUT/"; rm -f "$OUT/autoexec.source.cfg"
"$ROOT/build/integrate-menus.sh" "$OUT"
rm -f "$OUT/config.cfg" "$OUT/init.cfg"

# Bundled ffmpeg (video export, clip-export feature): its own directory, sibling of bin/data/
# packages, matching the engine's default clipexportffmpeg lookup path (ffmpeg/ffmpeg, resolved
# relative to cwd - guaranteed to be $OUT since swiftgibs.sh below `cd`s here first). GPL-licensed,
# never linked into the engine - see build/ffmpeg-licence/NOTICE.txt and
# docs/ffmpeg-provenance.md for exact version/checksum/source. Linux-only binary; nothing from
# another platform ends up in this bundle.
FFMPEG_DIR="$("$ROOT/build/fetch-ffmpeg.sh" linux)"
mkdir -p "$OUT/ffmpeg"
cp "$FFMPEG_DIR/ffmpeg" "$FFMPEG_DIR/LICENSE.txt" "$FFMPEG_DIR/NOTICE.txt" "$OUT/ffmpeg/"
chmod +x "$OUT/ffmpeg/ffmpeg"

cat > "$OUT/swiftgibs.sh" <<'SH'
#!/usr/bin/env bash
cd "$(dirname "$0")" && exec ./bin/swiftgibs -q.
SH
cp "$ROOT/updater/update-swiftgibs.sh" "$OUT/update-swiftgibs.sh"
chmod +x "$OUT/swiftgibs.sh" "$OUT/bin/swiftgibs" "$OUT/update-swiftgibs.sh"

cd "$ROOT/dist"; rm -f "$ARCHIVE.tar.gz"
tar -czf "$ARCHIVE.tar.gz" SwiftGibs-linux-x86_64
echo "linux bundle (MAPS=$MAPS): $(du -sh "$OUT" | cut -f1) | tgz: $(du -sh "$ARCHIVE.tar.gz" | cut -f1)"
