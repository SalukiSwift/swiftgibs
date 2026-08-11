#!/usr/bin/env bash
# Assemble the Linux SwiftGibs bundle: native client + stripped official data + overlay + launcher.
# Usage: [INSTALL=<data-root>] build/make-bundle-linux.sh   (INSTALL defaults to fetch-official-data)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${INSTALL:-$("$ROOT/build/fetch-official-data.sh")}"
STAGE="${STAGE:-/tmp/swiftgibs-linux-stage}"
OUT="$ROOT/dist/SwiftGibs-linux-x86_64"

# Use a prebuilt client if present (CI supplies it from the native-binaries job); else build it.
if [ ! -f "$ROOT/dist/engines/linux-x86_64/sauer_client" ]; then
  "$ROOT/build/make-engine-linux.sh" >/dev/null
fi
rm -rf "$OUT"; mkdir -p "$OUT/bin"
cp "$ROOT/dist/engines/linux-x86_64/sauer_client" "$OUT/bin/swiftgibs"

SRC="$INSTALL" ALLMAPS="${ALLMAPS:-1}" "$ROOT/tools/strip-assets.sh" "$ROOT/maps/pool.txt" "$STAGE"
cp -a "$STAGE/data" "$OUT/data"; cp -a "$STAGE/packages" "$OUT/packages"
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

# Bundled SDL2 runtime (lean, source-built - see build/fetch-sdl-linux.sh and
# docs/sdl-provenance.md): lets the bundle run out of the box on a machine with no SDL
# packages installed. The launcher below only puts lib/ on the library path when the
# system's own SDL is missing, so a normal desktop keeps using its distro libraries.
SDL_DIR="$("$ROOT/build/fetch-sdl-linux.sh")"
mkdir -p "$OUT/lib"
cp "$SDL_DIR"/libSDL2-2.0.so.0 "$SDL_DIR"/libSDL2_image-2.0.so.0 "$SDL_DIR"/libSDL2_mixer-2.0.so.0 \
   "$SDL_DIR/NOTICE.txt" "$OUT/lib/"

cat > "$OUT/swiftgibs.sh" <<'SH'
#!/usr/bin/env bash
# SwiftGibs launcher. Besides starting the game it catches the two ways a fresh install
# used to fail with a cryptic error (or not start at all):
cd "$(dirname "$0")"

# 1) Half-extracted archive: notexture.png is the first file the engine hard-requires, and
# packages/ sorts late in the tarball, so a truncated extraction loses it. Fail with an
# explanation instead of the engine's "could not find core textures".
if [ ! -f packages/textures/notexture.png ] || [ ! -f data/glsl.cfg ]; then
  echo "SwiftGibs: game data is missing or incomplete."
  echo "This usually means the archive was only partly extracted."
  echo "Delete this folder, then fully extract SwiftGibs-linux-x86_64.tar.gz again."
  exit 1
fi

# 2) No SDL2 on the system: prefer the distro's libraries when they are all present (they
# get distro fixes and updates), otherwise fall back to the lean copies bundled in lib/,
# so the game runs with zero packages installed. If ldd itself is unavailable we can't
# tell, so use the bundled copies - the safe default either way.
if ! command -v ldd >/dev/null 2>&1 || ldd bin/swiftgibs 2>/dev/null | grep -q 'not found'; then
  export LD_LIBRARY_PATH="$PWD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

exec ./bin/swiftgibs -q.
SH
cp "$ROOT/updater/update-swiftgibs.sh" "$OUT/update-swiftgibs.sh"
chmod +x "$OUT/swiftgibs.sh" "$OUT/bin/swiftgibs" "$OUT/update-swiftgibs.sh"

cd "$ROOT/dist"; rm -f SwiftGibs-linux-x86_64.tar.gz
tar -czf SwiftGibs-linux-x86_64.tar.gz SwiftGibs-linux-x86_64
echo "linux bundle: $(du -sh "$OUT" | cut -f1) | tgz: $(du -sh SwiftGibs-linux-x86_64.tar.gz | cut -f1)"
