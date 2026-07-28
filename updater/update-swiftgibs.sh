#!/bin/sh
# Updates the SwiftGibs folder this script lives inside to the latest GitHub
# release. Your own files (config.cfg, friends.cfg, stats.cfg, screenshots)
# are not in the release tarball, so a plain overlay-copy never deletes them.
#
# This script lives INSIDE the SwiftGibs-linux-x86_64 folder it updates (same
# as swiftgibs.sh) - same problem update-swiftgibs.bat solves on Windows: a
# running script can't safely delete the directory that contains it. First
# move: copy self to a temp dir and re-exec from there, passing the original
# game dir along as an argument.
#
# Plain POSIX sh. Uses curl if present, else wget. Needs tar (with gzip
# support - `tar -z` shells out to a `gzip` binary, standard on every
# mainstream distro) and standard coreutils (cp, mv, mktemp, chmod).
#
# Override the download URL for testing:
#   UPDATE_URL_OVERRIDE=http://127.0.0.1:8000/SwiftGibs-linux-x86_64.tar.gz ./update-swiftgibs.sh
# Defaults to the real evergreen "latest release" asset.

set -e

if [ "$1" != "--run" ]; then
  GAMEDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  TMPCOPY="${TMPDIR:-/tmp}/swiftgibs-updater.sh"
  cp "$0" "$TMPCOPY"
  chmod +x "$TMPCOPY"
  exec "$TMPCOPY" --run "$GAMEDIR"
fi

GAMEDIR="$2"
URL="${UPDATE_URL_OVERRIDE:-https://github.com/SalukiSwift/swiftgibs/releases/latest/download/SwiftGibs-linux-x86_64.tar.gz}"

echo ""
echo "SwiftGibs updater"
echo "-----------------"
echo "This downloads the latest release and updates the game in:"
echo "  $GAMEDIR"
echo "Your settings, friends and stats are kept."
echo ""

if command -v curl >/dev/null 2>&1; then
  DL="curl -L --fail --progress-bar -o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -q -O"
else
  echo "Need curl or wget to download the update - neither was found."
  exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
  echo "tar was not found - can't unpack the update."
  exit 1
fi

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/swiftgibs-update.XXXXXX") || {
  echo "Could not create a temp directory."
  exit 1
}
# Also best-effort clean up the self-copy of this script we exec'd into
# (see the --run dance above) - $0 is that copy's path in this re-exec'd
# process. Must not affect the script's exit code either way.
cleanup() {
  rm -rf "$TMPD"
  rm -f "$0" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

TARBALL="$TMPD/SwiftGibs-linux-x86_64.tar.gz"

echo "Downloading the latest release..."
if ! $DL "$TARBALL" "$URL"; then
  echo ""
  echo "Download failed - check your internet connection and try again."
  exit 1
fi

echo ""
echo "Verifying download..."
if ! tar -tzf "$TARBALL" >/dev/null 2>&1; then
  echo ""
  echo "Download looks corrupt - the update was NOT applied. Try again."
  exit 1
fi

echo "Unpacking..."
EXTRACT="$TMPD/extract"
mkdir -p "$EXTRACT"
if ! tar -xzf "$TARBALL" -C "$EXTRACT"; then
  echo ""
  echo "Unpack failed - the update was NOT applied. Try again."
  exit 1
fi

NEWDIR="$EXTRACT/SwiftGibs-linux-x86_64"
if [ ! -d "$NEWDIR" ] || [ ! -f "$NEWDIR/swiftgibs.sh" ]; then
  echo ""
  echo "That download doesn't look like a SwiftGibs release - the update was NOT applied."
  exit 1
fi

echo ""
echo "Updating game files..."

# Copy the new tree over the old one: this overwrites shared files and adds
# new ones, but never deletes files that only exist in GAMEDIR (your
# config.cfg, friends.cfg, stats.cfg, screenshots, saved profiles) - the same
# keep-extra-files behaviour update-swiftgibs.bat gets from robocopy /E.
if ! cp -a "$NEWDIR/." "$GAMEDIR/"; then
  echo ""
  echo "Update failed while copying files. Your existing install may be"
  echo "partially updated - run this again to finish the job."
  exit 1
fi
chmod +x "$GAMEDIR/swiftgibs.sh" "$GAMEDIR/bin/swiftgibs" "$GAMEDIR/update-swiftgibs.sh" 2>/dev/null || true

echo ""
echo "Done - SwiftGibs is up to date. Run ./swiftgibs.sh as usual."
echo "(Your settings, friends and stats were not touched.)"
