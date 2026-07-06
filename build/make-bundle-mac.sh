#!/usr/bin/env bash
# Assemble the shippable macOS SwiftGibs: CI-built code app + stripped install data.
# The code-only SwiftGibs.app (binary + embedded SDL2 frameworks + plist + icon, signed) comes
# from the mac-build GitHub Actions artifact; game data comes from a matching 2020 install.
# Usage: APP_ZIP=/path/to/SwiftGibs-app-code.zip build/make-bundle-mac.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${INSTALL:-/mnt/c/Program Files (x86)/Sauerbraten}"   # override for CI/official data
APP_ZIP="${APP_ZIP:?set APP_ZIP to the downloaded CI artifact zip}"
STAGE="${STAGE:-/tmp/swiftgibs-mac-stage}"
OUT="$ROOT/dist/SwiftGibs.app"

rm -rf "$OUT" "$STAGE"; mkdir -p "$STAGE"

# 1) unpack the CI code app (artifact zip wraps SwiftGibs.app)
unzip -q "$APP_ZIP" -d "$STAGE"
test -d "$STAGE/SwiftGibs.app" || { echo "artifact missing SwiftGibs.app"; exit 1; }
cp -a "$STAGE/SwiftGibs.app" "$OUT"

# 2) strip a low-res data tree from her install (same as Windows; all 331 maps by default)
SRC="$INSTALL" ALLMAPS="${ALLMAPS:-1}" "$ROOT/tools/strip-assets.sh" "$ROOT/maps/pool.txt" "$STAGE/game"

# 3) game data lives in Contents/Resources (the Mac binary uses the bundle Resources as its data root)
RES="$OUT/Contents/Resources"
cp -a "$STAGE/game/data" "$RES/data"
cp -a "$STAGE/game/packages" "$RES/packages"
chmod -R u+w "$RES"

# 4) overlay last so it wins; drop the internal reference file; ship NO config.cfg (fresh VARP defaults)
cp -a "$ROOT/overlay/." "$RES/"
rm -f "$RES/autoexec.source.cfg"

# 5) RE-SIGN the whole bundle now that data is inside Contents/Resources. The CI ad-hoc seal only
#    covered the code-only app; adding data invalidates it. rcodesign (Linux-capable Apple signer)
#    ad-hoc re-signs the complete bundle so the CodeResources seal matches what we ship, and the
#    arm64 binary + frameworks stay validly signed (mandatory for Apple Silicon to run them).
RCODESIGN="${RCODESIGN:-rcodesign}"
"$RCODESIGN" sign "$OUT"
# (rcodesign's own `verify` is documented-buggy on ad-hoc sigs; Apple-acceptance is proven in CI)
"$RCODESIGN" print-signature-info "$OUT/Contents/MacOS/sauerbraten" 2>&1 | grep -iE 'signed|identifier|code_digest|flags|adhoc' | head -6 || true

# 6) zip the .app for distribution (standard on macOS; -y preserves the framework symlinks)
cd "$ROOT/dist"; rm -f SwiftGibs-mac.zip
zip -rqy SwiftGibs-mac.zip SwiftGibs.app
echo "mac bundle: $(du -sh "$OUT" | cut -f1) | zip: $(du -sh SwiftGibs-mac.zip | cut -f1)"
