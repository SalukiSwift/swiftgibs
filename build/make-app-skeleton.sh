#!/usr/bin/env bash
# Assemble the code-only SwiftGibs.app: binary + embedded SDL2 frameworks + plist + icon,
# then ad-hoc codesign. NO game data (added later by make-bundle-mac.sh). Runs on macOS.
# Usage: make-app-skeleton.sh <built-client> <frameworks-dir> <out.app>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="${1:?built client binary}"; FWDIR="${2:?frameworks dir}"; APP="${3:?out .app path}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/vendor/sauer2020/xcode/sauerbraten.plist" "$APP/Contents/Info.plist"
cp "$ROOT/vendor/sauer2020/xcode/sauerbraten.icns" "$APP/Contents/Resources/sauerbraten.icns"
cp "$CLIENT" "$APP/Contents/MacOS/sauerbraten"           # matches CFBundleExecutable
chmod +x "$APP/Contents/MacOS/sauerbraten"
for fw in SDL2 SDL2_image SDL2_mixer; do
  cp -R "$FWDIR/$fw.framework" "$APP/Contents/Frameworks/"
done
# the Makefile already added rpath @executable_path/../Frameworks during the Darwin build;
# add it again defensively (no-op / harmless error if already present)
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/sauerbraten" 2>/dev/null || true
# sign frameworks first, then the app (deep) -- ad-hoc; mandatory for arm64 to run at all
for fw in "$APP"/Contents/Frameworks/*.framework; do codesign --force --sign - "$fw"; done
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
echo "app skeleton: $APP"
