#!/usr/bin/env bash
# Build + run the MAPBATTLE test server (a local replica of the RUGBY-family
# intermission vote flow) on port 28885. 1-minute matches, 25s vote windows.
# Usage: tools/mapbattle-testserver/run-testserver.sh
# Connect from SwiftGibs with: /connect localhost 28885   (or the WSL IP from Windows)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
B=/tmp/mb-testserver
"$ROOT/build/apply-patches.sh" "$B" >/dev/null
patch -p1 -d "$B" -s < "$ROOT/tools/mapbattle-testserver/mapbattle-server.patch"
make -C "$B" -j"$(nproc)" server >/dev/null
H=/tmp/mb-testserver-home; mkdir -p "$H"
printf 'serverport 28885\nupdatemaster 0\nmaxclients 12\nserverdesc "MAPBATTLE test"\n' > "$H/server-init.cfg"
echo "MAPBATTLE test server on UDP 28885 (1-min matches; Ctrl-C stops it)"
exec "$B/sauer_server" -q"$H"
