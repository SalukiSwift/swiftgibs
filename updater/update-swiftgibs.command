#!/bin/sh
# Updates the SwiftGibs.app that lives next to this .command file to the
# latest GitHub release. Your settings, friends and stats live in
# ~/Library/Application Support/sauerbraten, NOT inside the app bundle, so
# they are never touched by this script.
#
# This script does not live inside SwiftGibs.app (it's a sibling file, not
# part of the bundle we replace), so unlike the Linux/Windows updaters it
# never needs to copy itself away before it can replace anything.
#
# KEY FACT: curl does not set the com.apple.quarantine extended attribute
# that a Safari/Finder download gets, so a SwiftGibs.app placed here by curl
# is not quarantined and skips the right-click -> Open ritual on next launch.
# We also defensively strip any quarantine flag from the new app in case one
# is present anyway, ignoring errors if xattr isn't available.
#
# Written as plain POSIX sh so it runs the same under macOS's stock bash 3.2
# (Terminal's default interpreter for .command files) and under a real
# POSIX shell (used for logic testing on Linux). No bashisms.
#
# Override the download URL for testing:
#   UPDATE_URL_OVERRIDE=http://127.0.0.1:8000/SwiftGibs-mac.zip ./update-swiftgibs.command
# Defaults to the real evergreen "latest release" asset.

set -e

# cd to the folder this script lives in, so SwiftGibs.app is just "./SwiftGibs.app"
# regardless of where the user double-clicked from.
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SELF_DIR"

URL="${UPDATE_URL_OVERRIDE:-https://github.com/SalukiSwift/swiftgibs/releases/latest/download/SwiftGibs-mac.zip}"

echo ""
echo "SwiftGibs updater"
echo "-----------------"
echo "This downloads the latest release and updates SwiftGibs.app in:"
echo "  $SELF_DIR"
echo "Your settings, friends and stats live in Application Support and are"
echo "never touched."
echo ""

if ! command -v curl >/dev/null 2>&1; then
  echo "curl was not found - can't download the update. Install curl and try again."
  exit 1
fi
if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip was not found - can't unpack the update."
  exit 1
fi

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/swiftgibs-update.XXXXXX") || {
  echo "Could not create a temp directory."
  exit 1
}
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT INT TERM

ZIP="$TMPD/SwiftGibs-mac.zip"

echo "Downloading the latest release..."
if ! curl -L --fail --progress-bar -o "$ZIP" "$URL"; then
  echo ""
  echo "Download failed - check your internet connection and try again."
  exit 1
fi

echo ""
echo "Verifying download..."
if ! unzip -tqq "$ZIP" >/dev/null 2>&1; then
  echo ""
  echo "Download looks corrupt - the update was NOT applied. Try again."
  exit 1
fi

echo "Unpacking..."
EXTRACT="$TMPD/extract"
mkdir -p "$EXTRACT"
if ! unzip -q "$ZIP" -d "$EXTRACT"; then
  echo ""
  echo "Unpack failed - the update was NOT applied. Try again."
  exit 1
fi

if [ ! -d "$EXTRACT/SwiftGibs.app" ]; then
  echo ""
  echo "That download doesn't look like a SwiftGibs release - the update was NOT applied."
  exit 1
fi

# Defensively drop any quarantine flag from the new app before it's installed
# (curl downloads don't get one, but be safe if some tool in the chain added it).
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$EXTRACT/SwiftGibs.app" 2>/dev/null || true
fi

echo ""
echo "Updating game files..."

# Keep the old app as a .bak until the new one is confirmed in place, so a
# failure here never leaves you with no working app. mv is used when possible
# (near-instant rename); cp -a is the fallback if the temp dir and this
# folder are on different volumes.
#
# The backup rename itself is checked for success (returns 2 if it fails).
# If we can't even get the existing app safely out of the way - e.g. it's
# running off a read-only volume like a still-mounted DMG - we must NOT touch
# SwiftGibs.app at all: no rm -rf, no overwrite attempt. Only once the .bak
# provably exists do we move on to the (destructive) install step.
install_new_app() {
  if [ -d SwiftGibs.app ]; then
    rm -rf SwiftGibs.app.bak
    if ! mv SwiftGibs.app SwiftGibs.app.bak; then
      return 2
    fi
  fi
  if mv "$EXTRACT/SwiftGibs.app" SwiftGibs.app 2>/dev/null; then
    return 0
  fi
  rm -rf SwiftGibs.app
  cp -a "$EXTRACT/SwiftGibs.app" SwiftGibs.app
}

install_status=0
install_new_app || install_status=$?

if [ "$install_status" -eq 0 ]; then
  rm -rf SwiftGibs.app.bak
elif [ "$install_status" -eq 2 ]; then
  echo ""
  echo "Update failed: couldn't back up your existing SwiftGibs.app before"
  echo "installing the update, so nothing was changed - SwiftGibs.app is exactly"
  echo "as it was before you ran this."
  echo "This usually means SwiftGibs.app is on a read-only location right now"
  echo "(for example, running it straight off a mounted disk image). Copy"
  echo "SwiftGibs.app (and this updater) to a normal writable folder, such as"
  echo "/Applications, and run the updater again from there."
  exit 1
else
  echo ""
  echo "Update failed while installing the new app."
  if [ -d SwiftGibs.app.bak ]; then
    echo "Restoring your previous copy..."
    rm -rf SwiftGibs.app
    mv SwiftGibs.app.bak SwiftGibs.app
  fi
  exit 1
fi

echo ""
echo "Done - SwiftGibs is up to date. Just launch SwiftGibs as usual."
echo "(Your settings, friends and stats were not touched.)"
