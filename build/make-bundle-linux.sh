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

SRC="$INSTALL" "$ROOT/tools/strip-assets.sh" "$STAGE"
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
# packages installed. The launcher below always prefers lib/ (bundled-first: a resolvable
# system SDL2 is no guarantee of symbol coverage, since SDL2's soname hasn't changed since
# 2.0.0); SWIFTGIBS_SYSTEM_SDL=1 is the escape hatch back to the distro's copy.
# Copied by glob (not named individually) so this can never drift from the SONAMES array
# that is the actual source of truth in fetch-sdl-linux.sh.
SDL_DIR="$("$ROOT/build/fetch-sdl-linux.sh")"
mkdir -p "$OUT/lib"
cp "$SDL_DIR"/libSDL2*.so.0 "$SDL_DIR/NOTICE.txt" "$OUT/lib/"

# Build-time sentinel assert: the launcher's half-extraction guard below hardcodes these two
# paths so it can check them without depending on anything that could itself be missing. Assert
# here that they actually exist in the bundle we just built, so the guard can never silently
# drift from what the bundle contains.
for sentinel in packages/textures/notexture.png data/glsl.cfg; do
  if [ ! -f "$OUT/$sentinel" ]; then
    echo "make-bundle-linux: sentinel file missing from the bundle: $sentinel" >&2
    echo "  the launcher's half-extraction guard checks for this exact path - fix the bundle" >&2
    echo "  contents or update both the guard in this script and this assert together." >&2
    exit 1
  fi
done

cat > "$OUT/swiftgibs.sh" <<'SH'
#!/usr/bin/env bash
# SwiftGibs launcher. Besides starting the game it catches the two ways a fresh install
# used to fail with a cryptic error (or not start at all):
cd "$(dirname "$0")" || { echo "SwiftGibs: could not cd to the launcher's own directory" >&2; exit 1; }

# 1) Half-extracted archive: notexture.png is the first file the engine hard-requires, and
# packages/ sorts late in the tarball, so a truncated extraction loses it. Fail with an
# explanation instead of the engine's "could not find core textures". (make-bundle-linux.sh
# asserts at build time that these two paths exist in every bundle it produces.)
if [ ! -f packages/textures/notexture.png ] || [ ! -f data/glsl.cfg ]; then
  echo "SwiftGibs: game data is missing or incomplete."
  echo "This usually means the archive was only partly extracted."
  echo "Delete this folder, then fully extract SwiftGibs-linux-x86_64.tar.gz again."
  exit 1
fi

# 2) SDL2 runtime: always prefer the bundled lean copies in lib/. Checking with ldd whether the
# system already resolves libSDL2/libSDL2_image/libSDL2_mixer is NOT a safe way to decide this -
# SDL2's soname hasn't changed since 2.0.0, so an old-but-present system SDL2 resolves fine and
# then dies at runtime with "symbol lookup error", and an unrelated "not found" (e.g. libGL,
# which is deliberately not bundled - see docs/sdl-provenance.md) would wrongly flip this to the
# bundled path anyway. Bundled-first matches the mac build's vendored-frameworks precedent.
# Set SWIFTGIBS_SYSTEM_SDL=1 to opt back into the distro's SDL2 (gets distro security/compat
# updates) if you know it's new enough.
if [ "${SWIFTGIBS_SYSTEM_SDL:-0}" != "1" ]; then
  export LD_LIBRARY_PATH="$PWD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

exec ./bin/swiftgibs -q.
SH
cp "$ROOT/updater/update-swiftgibs.sh" "$OUT/update-swiftgibs.sh"
chmod +x "$OUT/swiftgibs.sh" "$OUT/bin/swiftgibs" "$OUT/update-swiftgibs.sh"

cd "$ROOT/dist"; rm -f SwiftGibs-linux-x86_64.tar.gz
tar -czf SwiftGibs-linux-x86_64.tar.gz SwiftGibs-linux-x86_64
echo "linux bundle: $(du -sh "$OUT" | cut -f1) | tgz: $(du -sh SwiftGibs-linux-x86_64.tar.gz | cut -f1)"
