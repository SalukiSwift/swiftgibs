#!/usr/bin/env bash
# Assemble the shippable macOS SwiftGibs: code-only app + stripped install data.
# The code-only SwiftGibs.app (binary + embedded SDL2 frameworks + plist + icon, signed) comes from
# the mac-build GitHub Actions artifact; game data comes from a matching 2020 install.
#
# Signing is host-aware: on macOS the whole bundle is re-signed with Apple's own `codesign`; on a
# Linux bundling host (the release job) it is re-signed with `rcodesign`, the Apple-compatible signer.
#
# Usage:
#   APP_ZIP=/path/to/SwiftGibs-app-code.zip build/make-bundle-mac.sh   # CI artifact zip (release)
#   APP_DIR=/tmp/SwiftGibs.app             build/make-bundle-mac.sh    # a prebuilt .app (local mac)
# Override INSTALL to point at the game-data source; RCODESIGN forces the rcodesign path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Data source: explicit INSTALL wins; else her Windows install (WSL); else a local macOS
# Sauerbraten.app. The release job passes INSTALL=<official-data>, so CI is unaffected.
DEFAULT_INSTALL="/mnt/c/Program Files (x86)/Sauerbraten"
if [ "$(uname -s)" = "Darwin" ] && [ ! -d "$DEFAULT_INSTALL" ] \
   && [ -d "/Applications/Sauerbraten.app/Contents/Resources" ]; then
  DEFAULT_INSTALL="/Applications/Sauerbraten.app/Contents/Resources"
fi
INSTALL="${INSTALL:-$DEFAULT_INSTALL}"
APP_ZIP="${APP_ZIP:-}"
APP_DIR="${APP_DIR:-}"
STAGE="${STAGE:-/tmp/swiftgibs-mac-stage}"
OUT="$ROOT/dist/SwiftGibs.app"

rm -rf "$OUT" "$STAGE"; mkdir -p "$STAGE" "$ROOT/dist"

# 1) get the code-only app: a prebuilt .app (APP_DIR, e.g. a local mac build) or the CI artifact zip
if [ -n "$APP_DIR" ]; then
  test -d "$APP_DIR" || { echo "APP_DIR is not a directory: $APP_DIR"; exit 1; }
  cp -a "$APP_DIR" "$OUT"
elif [ -n "$APP_ZIP" ]; then
  unzip -q "$APP_ZIP" -d "$STAGE"
  test -d "$STAGE/SwiftGibs.app" || { echo "artifact missing SwiftGibs.app"; exit 1; }
  cp -a "$STAGE/SwiftGibs.app" "$OUT"
else
  echo "set APP_ZIP (CI artifact zip) or APP_DIR (a prebuilt SwiftGibs.app)"; exit 1
fi

# 2) strip a low-res data tree from the install (same as Windows; all 331 maps by default)
SRC="$INSTALL" ALLMAPS="${ALLMAPS:-1}" "$ROOT/tools/strip-assets.sh" "$ROOT/maps/pool.txt" "$STAGE/game"

# 3) game data lives in Contents/Resources (the Mac binary uses the bundle Resources as its data root)
RES="$OUT/Contents/Resources"
cp -a "$STAGE/game/data" "$RES/data"
cp -a "$STAGE/game/packages" "$RES/packages"
chmod -R u+w "$RES"

# 4) overlay last so it wins; drop the internal reference file
cp -a "$ROOT/overlay/." "$RES/"
rm -f "$RES/autoexec.source.cfg"

# 4b) attach the SwiftGibs + Cues + Friends tabs to the staged options menu (parity with the
#     win/linux bundlers; overlay/autoexec.cfg expects the bundler to do this). Ship no user config
#     so first launch gets fresh VARP defaults + native-resolution auto-detect.
"$ROOT/build/integrate-menus.sh" "$RES"
rm -f "$RES/config.cfg" "$RES/init.cfg"

# 5) RE-SIGN the whole bundle now that data is inside Contents/Resources. The code-only seal only
#    covered the binary + frameworks; adding data invalidates the CodeResources seal, and the arm64
#    binary + frameworks must stay validly signed (mandatory for Apple Silicon to run them).
if [ "$(uname -s)" = "Darwin" ] && [ -z "${RCODESIGN:-}" ]; then
  # macOS bundling host: Apple's own signer is authoritative
  codesign --force --deep --sign - "$OUT"
  codesign --verify --deep --strict --verbose=2 "$OUT"
else
  # Linux bundling host (release job), or an explicit RCODESIGN override:
  # rcodesign ad-hoc re-signs the complete bundle so the CodeResources seal matches what we ship.
  # (rcodesign's own `verify` is documented-buggy on ad-hoc sigs; Apple-acceptance is proven in CI.)
  RCODESIGN="${RCODESIGN:-rcodesign}"
  "$RCODESIGN" sign "$OUT"
  "$RCODESIGN" print-signature-info "$OUT/Contents/MacOS/sauerbraten" 2>&1 \
    | grep -iE 'signed|identifier|code_digest|flags|adhoc' | head -6 || true
fi

# 6) updater script ships as a sibling of SwiftGibs.app (not part of the bundle, so it
#    survives being replaced when it updates the app). zip preserves the executable bit
#    in its external file attributes (verified: `zip -rqy` round-trips 755 through
#    `unzip` unchanged), so no post-unzip chmod is needed.
cp "$ROOT/updater/update-swiftgibs.command" "$ROOT/dist/update-swiftgibs.command"
chmod +x "$ROOT/dist/update-swiftgibs.command"

# 7) zip the .app for distribution (standard on macOS; -y preserves the framework symlinks)
cd "$ROOT/dist"; rm -f SwiftGibs-mac.zip
zip -rqy SwiftGibs-mac.zip SwiftGibs.app update-swiftgibs.command
echo "mac bundle: $(du -sh "$OUT" | cut -f1) | zip: $(du -sh SwiftGibs-mac.zip | cut -f1)"
