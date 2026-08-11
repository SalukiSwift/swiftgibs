#!/usr/bin/env bash
# Download, checksum-verify, and build the three SDL2 runtime libraries the Linux client needs
# (libSDL2, libSDL2_image, libSDL2_mixer) as LEAN shared libraries for bundling, so the Linux
# tarball runs out of the box on a machine with no SDL packages installed. Same shape as
# fetch-ffmpeg.sh / fetch-official-data.sh: idempotent cache, pinned URL + SHA-256 verified
# BEFORE anything is extracted or built, prints the usable output dir on stdout.
#
# Why build from source instead of copying the distro's .so files: Ubuntu's SDL2_image/SDL2_mixer
# link a large dependency web (libtiff, webp, fluidsynth, jack, modplug, ...), so shipping the
# distro libraries just moves the "not found" failure one level down on a fresh machine. Built
# here with stb-based decoders (PNG/JPG via stb_image, OGG via stb_vorbis - all vendored inside
# the SDL source, public-domain/MIT) and every external codec disabled, the three libraries
# depend on nothing beyond glibc + our own libSDL2. The NEEDED allowlist check at the bottom
# enforces that property on every build; a new dependency is a hard failure, not a surprise
# shipped to users.
#
# The versions are deliberately the SAME trio the mac build vendors as frameworks (see
# .github/workflows/release.yml mac-binary job): one SDL version story across platforms.
# Display/audio backends (X11, Wayland, ALSA, PulseAudio, PipeWire) are compiled in but
# dlopen()ed by SDL at runtime, so they are soft dependencies by design - SDL uses whichever
# the user's machine actually has. The configure-summary check below fails the build if a
# backend was silently dropped because a dev header was missing on the build machine.
#
# Full provenance (providers, hash cross-verification, licence) lives in docs/sdl-provenance.md;
# this script is the executable source of truth. If you ever repin, update both together.
#
# Usage: build/fetch-sdl-linux.sh
# Prints (on stdout, last line): the directory containing the three .so files + NOTICE.txt,
# ready to copy straight into a bundle's lib/ folder.
set -euo pipefail
CACHE="${SG_SDL_CACHE:-/tmp/sg-sdl-cache}"

SDL_VER=2.30.9
IMG_VER=2.8.2
MIX_VER=2.8.0
SDL_SHA256=24b574f71c87a763f50704bbb630cbe38298d544a1f890f099a4696b1d6beba4
IMG_SHA256=8f486bbfbcf8464dd58c9e5d93394ab0255ce68b51c5a966a918244820a76ddc
MIX_SHA256=1cfb34c87b26dbdbc7afd68c4f545c0116ab5f90bbfecc5aebe2a9cb4bb31549

OUT="$CACHE/out"
PINSET="$SDL_SHA256-$IMG_SHA256-$MIX_SHA256"

# Idempotent: reuse a previous build only if it was made from exactly the currently pinned
# sources (.pinset-ok records which - same pattern as fetch-ffmpeg.sh's .sha256-ok).
if [ -f "$OUT/.pinset-ok" ] && [ "$(cat "$OUT/.pinset-ok")" = "$PINSET" ]; then
  echo "$OUT"
  exit 0
fi

mkdir -p "$CACHE"

fetch() { # fetch <url> <dest> <sha256>
  local url="$1" dest="$2" want="$3" got
  if [ ! -f "$dest" ]; then
    echo "fetch-sdl-linux: downloading $url" >&2
    if command -v curl >/dev/null 2>&1; then curl -fL --retry 3 -o "$dest" "$url"
    else wget -q -O "$dest" "$url"; fi
  fi
  got="$(sha256sum "$dest" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    rm -f "$dest"
    {
      echo "fetch-sdl-linux: CHECKSUM MISMATCH - refusing to use this download"
      echo "  url:      $url"
      echo "  expected: $want"
      echo "  got:      $got"
      echo "  this does not match the pinned provenance in docs/sdl-provenance.md."
      echo "  the bad download has been deleted; nothing was extracted or built."
    } >&2
    exit 1
  fi
  echo "fetch-sdl-linux: checksum verified $(basename "$dest")" >&2
}

fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VER/SDL2-$SDL_VER.tar.gz" \
      "$CACHE/SDL2-$SDL_VER.tar.gz" "$SDL_SHA256"
fetch "https://github.com/libsdl-org/SDL_image/releases/download/release-$IMG_VER/SDL2_image-$IMG_VER.tar.gz" \
      "$CACHE/SDL2_image-$IMG_VER.tar.gz" "$IMG_SHA256"
fetch "https://github.com/libsdl-org/SDL_mixer/releases/download/release-$MIX_VER/SDL2_mixer-$MIX_VER.tar.gz" \
      "$CACHE/SDL2_mixer-$MIX_VER.tar.gz" "$MIX_SHA256"

SRC="$CACHE/src" PREFIX="$CACHE/prefix"
rm -rf "$SRC" "$PREFIX" "$OUT"
mkdir -p "$SRC"
tar -xzf "$CACHE/SDL2-$SDL_VER.tar.gz" -C "$SRC"
tar -xzf "$CACHE/SDL2_image-$IMG_VER.tar.gz" -C "$SRC"
tar -xzf "$CACHE/SDL2_mixer-$MIX_VER.tar.gz" -C "$SRC"

JOBS="$(nproc)"

# --- SDL2. Default feature detection; the summary check below is what makes "a dev header was
# missing so configure silently dropped a backend" a build failure instead of a broken bundle.
echo "fetch-sdl-linux: building SDL2 $SDL_VER" >&2
( cd "$SRC/SDL2-$SDL_VER" && ./configure --prefix="$PREFIX" --disable-static \
    > "$CACHE/configure-sdl2.log" 2>&1 && make -j"$JOBS" >/dev/null 2>&1 && make install >/dev/null 2>&1 ) \
  || { echo "fetch-sdl-linux: SDL2 build failed - see $CACHE/configure-sdl2.log" >&2; tail -20 "$CACHE/configure-sdl2.log" >&2; exit 1; }

# require the backends a Linux desktop actually uses; each maps to a -dev package on the builder
# (see the apt list in .github/workflows/release.yml and docs/sdl-provenance.md). The tokens are
# exactly how SDL2's configure summary names them ("pulse", not "pulseaudio").
video_line="$(grep -i '^Video drivers' "$CACHE/configure-sdl2.log" || true)"
audio_line="$(grep -i '^Audio drivers' "$CACHE/configure-sdl2.log" || true)"
for want in x11 wayland; do
  case "$video_line" in *"$want"*) ;; *)
    echo "fetch-sdl-linux: SDL2 configured WITHOUT $want video support - a dev header is missing on this machine." >&2
    echo "  summary was: $video_line" >&2
    echo "  install the SDL build deps (see release.yml's apt-get line) and re-run." >&2
    exit 1;;
  esac
done
for want in alsa pulse pipewire; do
  case "$audio_line" in *"$want"*) ;; *)
    echo "fetch-sdl-linux: SDL2 configured WITHOUT $want audio support - a dev header is missing on this machine." >&2
    echo "  summary was: $audio_line" >&2
    echo "  install the SDL build deps (see release.yml's apt-get line) and re-run." >&2
    exit 1;;
  esac
done

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" SDL2_CONFIG="$PREFIX/bin/sdl2-config"

# --- SDL2_image: stb_image handles the PNG/JPG the game data actually contains; every external
# codec off (the engine loads .dds itself, and nothing in packages/ is tif/webp/avif/jxl).
echo "fetch-sdl-linux: building SDL2_image $IMG_VER" >&2
( cd "$SRC/SDL2_image-$IMG_VER" && ./configure --prefix="$PREFIX" --disable-static \
    --enable-stb-image --disable-avif --disable-jxl --disable-tif --disable-webp \
    > "$CACHE/configure-img.log" 2>&1 && make -j"$JOBS" >/dev/null 2>&1 && make install >/dev/null 2>&1 ) \
  || { echo "fetch-sdl-linux: SDL2_image build failed - see $CACHE/configure-img.log" >&2; tail -20 "$CACHE/configure-img.log" >&2; exit 1; }

# --- SDL2_mixer: sound effects are .ogg and .wav; wave support is built in and stb_vorbis
# (the default ogg backend) is vendored in the source. Everything else off - the game ships
# no mod/midi/flac/mp3/opus audio (map background music is stripped by tools/strip-assets.sh
# and musicvol is 0).
echo "fetch-sdl-linux: building SDL2_mixer $MIX_VER" >&2
( cd "$SRC/SDL2_mixer-$MIX_VER" && ./configure --prefix="$PREFIX" --disable-static \
    --disable-music-mod --disable-music-midi --disable-music-flac --disable-music-mp3 \
    --disable-music-opus --disable-music-wavpack --disable-music-cmd \
    > "$CACHE/configure-mix.log" 2>&1 && make -j"$JOBS" >/dev/null 2>&1 && make install >/dev/null 2>&1 ) \
  || { echo "fetch-sdl-linux: SDL2_mixer build failed - see $CACHE/configure-mix.log" >&2; tail -20 "$CACHE/configure-mix.log" >&2; exit 1; }

# --- Collect the three libraries under their SONAME filenames (what the client binary's
# NEEDED entries ask the loader for), then enforce the leanness contract.
mkdir -p "$OUT"
for so in libSDL2-2.0.so.0 libSDL2_image-2.0.so.0 libSDL2_mixer-2.0.so.0; do
  cp -L "$PREFIX/lib/$so" "$OUT/$so"
  strip --strip-unneeded "$OUT/$so"   # debug symbols are ~10MB of the unstripped libSDL2 alone
done

ALLOW='libSDL2-2.0.so.0|libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-x86-64.so.2'
for so in libSDL2-2.0.so.0 libSDL2_image-2.0.so.0 libSDL2_mixer-2.0.so.0; do
  bad="$(readelf -d "$OUT/$so" | awk '/\(NEEDED\)/{gsub(/[\[\]]/,""); print $NF}' | grep -Ev "^($ALLOW)$" || true)"
  if [ -n "$bad" ]; then
    echo "fetch-sdl-linux: $so grew unexpected dependencies - it would NOT run on a bare machine:" >&2
    echo "$bad" >&2
    echo "  (a configure default probably changed; adjust the --disable flags or the allowlist," >&2
    echo "  and update docs/sdl-provenance.md to match.)" >&2
    exit 1
  fi
done
echo "fetch-sdl-linux: dependency allowlist check passed" >&2

# --- Licence notice: all three are zlib-licensed; ship their licence texts verbatim.
{
  echo "SwiftGibs bundles the following libraries, built unmodified from the official"
  echo "libsdl-org source releases (https://github.com/libsdl-org). All three are"
  echo "zlib-licensed. Build recipe: build/fetch-sdl-linux.sh in the SwiftGibs repo;"
  echo "provenance: docs/sdl-provenance.md."
  for lib in "SDL2-$SDL_VER" "SDL2_image-$IMG_VER" "SDL2_mixer-$MIX_VER"; do
    echo; echo "===== $lib ====="
    cat "$SRC/$lib/LICENSE.txt"
  done
} > "$OUT/NOTICE.txt"

echo "$PINSET" > "$OUT/.pinset-ok"
echo "fetch-sdl-linux: done - $(du -sh "$OUT" | cut -f1) in $OUT" >&2
echo "$OUT"
