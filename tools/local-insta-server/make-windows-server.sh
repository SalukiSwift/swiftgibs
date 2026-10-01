#!/usr/bin/env bash
# Cross-build the local insta server as a NATIVE WINDOWS binary and deploy it
# next to its config + launcher, so players on the same WiFi can join.
#
# Why native rather than the WSL server: NAT-mode WSL does not forward UDP, and
# Windows `netsh portproxy` is TCP-only, so a WSL-hosted Sauerbraten server is
# unreachable from other machines on the LAN. Running it on Windows directly
# sidesteps both limits.
#
# Usage: tools/local-insta-server/make-windows-server.sh [dest-dir]
# Default dest is a "SwiftGibs-Server" folder on the Windows desktop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [ $# -ge 1 ]; then
  DEST="$1"
else
  WINDESK="$(powershell.exe -NoProfile -Command '[Environment]::GetFolderPath("Desktop")' 2>/dev/null | tr -d '\r')"
  [ -n "$WINDESK" ] || { echo "could not find the Windows desktop; pass a dest dir explicitly" >&2; exit 1; }
  DEST="$(wslpath -u "$WINDESK")/SwiftGibs-Server"
fi

B=/tmp/sg-insta-win
"$ROOT/build/apply-patches.sh" "$B" >/dev/null
patch -p1 -d "$B" -s < "$DIR/local-insta-server.patch"
# The Makefile needs "CROSS" in PLATFORM to pick the mingw toolchain, and
# -lzlib1 looks for zlib1.lib while the bundled import lib is zdll.lib.
ln -sf zdll.lib "$B/lib64/zlib1.lib"
mkdir -p "$B/../bin64"                      # WINBIN target dir for the mingw rule
make -C "$B" PLATFORM=MINGW64CROSS -j"$(nproc)" server >/dev/null

mkdir -p "$DEST"
cp "$B/../bin64/sauer_server.exe" "$DEST/"
cp "$ROOT/vendor/windows-dlls/zlib1.dll" "$DEST/"
for f in server-init.cfg run-server.bat; do
  sed 's/$/\r/' "$DIR/$f" > "$DEST/$f"    # Windows wants CRLF
done

echo "deployed to: $DEST"
echo "run run-server.bat there (say yes to the one-time firewall prompt)"
