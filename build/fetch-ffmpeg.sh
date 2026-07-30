#!/usr/bin/env bash
# Download, checksum-verify, and extract just the ffmpeg binary for one platform, from a
# pinned, reputable static build - the same shape as fetch-official-data.sh (idempotent cache,
# prints the usable root path on stdout) but for ffmpeg instead of the game data.
#
# Full provenance for every platform (which provider, exact version, why that provider, the
# licence, and a link to the corresponding source for that exact build) lives in
# docs/ffmpeg-provenance.md. THIS SCRIPT is the single source of truth for the actual
# URL/SHA-256/internal-archive-path used to fetch and extract each one; if you ever repin a
# platform to a newer build, update the case block below AND docs/ffmpeg-provenance.md together
# - they must always agree, and the doc exists so a future session doesn't have to reverse this
# script to find out where a binary came from.
#
# The downloaded archive's SHA-256 is checked BEFORE anything is extracted or used. A mismatch
# is a hard failure (removes the bad file, never bundles it, never falls back to "close enough")
# - see the design doc's licensing section: a wrong/tampered ffmpeg is a supply-chain risk, not
# just a build nuisance.
#
# ffmpeg's own GPLv3 licence text is NOT re-fetched per platform - the copies bundled inside the
# Linux (johnvansickle.com) and Windows (gyan.dev) archives are byte-identical (checked), so a
# single verbatim copy is committed at build/ffmpeg-licence/GPLv3.txt and reused for all three
# platforms, including macOS (whose own archive ships no licence file at all).
#
# Usage: build/fetch-ffmpeg.sh <linux|win|mac>
# Prints (on stdout, last line): the directory containing the extracted ffmpeg binary + licence
# + notice text, ready to copy straight into a bundle's ffmpeg/ folder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:?usage: fetch-ffmpeg.sh <linux|win|mac>}"
CACHE="${SG_FFMPEG_CACHE:-/tmp/sg-ffmpeg-cache}/$PLATFORM"

case "$PLATFORM" in
  linux)
    # johnvansickle.com: the long-established, widely-used static-Linux-ffmpeg source (GPLv3,
    # genuinely fully static - no dynamic deps at all, confirmed via ldd). Notably smaller than
    # the alternatives checked (BtbN/FFmpeg-Builds' equivalent GPL static tar.xz is ~125MB vs
    # this ~40MB), which matters given the size budget - see docs/ffmpeg-provenance.md.
    URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
    SHA256="abda8d77ce8309141f83ab8edf0596834087c52467f6badf376a6a2a4c87cf67"
    ARCHIVE_NAME="ffmpeg-release-amd64-static.tar.xz"
    ARCHIVE_BIN_PATH="ffmpeg-7.0.2-amd64-static/ffmpeg"     # update this prefix if SHA256/version above is ever repinned
    BINNAME="ffmpeg"
    ;;
  win)
    # gyan.dev: the build ffmpeg.org's own downloads page recommends for Windows. "essentials"
    # (not "full") to skip ffplay/ffprobe/docs/extra filters we don't use; still GPL and still
    # carries libx264 + libvpx (confirmed via the archive's own README.txt).
    URL="https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-8.1.2-essentials_build.zip"
    SHA256="db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec"
    ARCHIVE_NAME="ffmpeg-8.1.2-essentials_build.zip"
    ARCHIVE_BIN_PATH="ffmpeg-8.1.2-essentials_build/bin/ffmpeg.exe"   # update this prefix if SHA256/version above is ever repinned
    BINNAME="ffmpeg.exe"
    ;;
  mac)
    # ffmpeg.martin-riedl.de: one of the very few sources publishing native Apple Silicon
    # (arm64) static ffmpeg builds with published checksums - evermeet.cx, the other well-known
    # macOS static-build source, explicitly does not build for arm64. GPLv3, libx264 + libvpx
    # both present (confirmed via the build's own -version/configuration output).
    URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1783011502_8.1.2/ffmpeg.zip"
    SHA256="ef1aa60006c7b77ce170c1608c08d8e4ba1c30c5746f2ac986ded932d0ac2c3c"
    ARCHIVE_NAME="ffmpeg-macos-arm64-8.1.2.zip"
    ARCHIVE_BIN_PATH="ffmpeg"    # this archive is just the bare binary at its root, no version-suffixed folder
    BINNAME="ffmpeg"
    ;;
  *)
    echo "fetch-ffmpeg: unknown platform \"$PLATFORM\" (want linux, win, or mac)" >&2
    exit 1
    ;;
esac

OUT="$CACHE/extracted"

# Idempotent: a previous run's extracted binary is reused as-is if it's already been verified
# against the CURRENT pinned checksum (not just "a" checksum from some earlier run before this
# platform was repinned - .sha256-ok stores exactly which hash it was verified against).
if [ -f "$OUT/$BINNAME" ] && [ -f "$OUT/.sha256-ok" ] && [ "$(cat "$OUT/.sha256-ok")" = "$SHA256" ]; then
  echo "$OUT"
  exit 0
fi

mkdir -p "$CACHE"
ARCHIVE="$CACHE/$ARCHIVE_NAME"
echo "fetch-ffmpeg ($PLATFORM): downloading $URL" >&2
rm -f "$ARCHIVE"
curl -fL --retry 3 -o "$ARCHIVE" "$URL"

GOT="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
if [ "$GOT" != "$SHA256" ]; then
  rm -f "$ARCHIVE"
  {
    echo "fetch-ffmpeg ($PLATFORM): CHECKSUM MISMATCH - refusing to use this download"
    echo "  url:      $URL"
    echo "  expected: $SHA256"
    echo "  got:      $GOT"
    echo "  this does not match the pinned provenance in docs/ffmpeg-provenance.md."
    echo "  the bad download has been deleted; nothing was extracted or bundled."
  } >&2
  exit 1
fi
echo "fetch-ffmpeg ($PLATFORM): checksum verified ($SHA256)" >&2

rm -rf "$OUT"; mkdir -p "$OUT"
case "$PLATFORM" in
  linux) tar -xJf "$ARCHIVE" -O "$ARCHIVE_BIN_PATH" > "$OUT/$BINNAME"; chmod +x "$OUT/$BINNAME" ;;
  win)   unzip -p "$ARCHIVE" "$ARCHIVE_BIN_PATH" > "$OUT/$BINNAME" ;;
  mac)   unzip -p "$ARCHIVE" "$ARCHIVE_BIN_PATH" > "$OUT/$BINNAME"; chmod +x "$OUT/$BINNAME" ;;
esac
test -s "$OUT/$BINNAME" || { echo "fetch-ffmpeg ($PLATFORM): extraction produced an empty/missing binary" >&2; exit 1; }

cp "$ROOT/build/ffmpeg-licence/GPLv3.txt" "$OUT/LICENSE.txt"
cp "$ROOT/build/ffmpeg-licence/NOTICE.txt" "$OUT/NOTICE.txt"

echo "$SHA256" > "$OUT/.sha256-ok"
echo "$OUT"
