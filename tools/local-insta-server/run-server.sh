#!/usr/bin/env bash
# Build + run the local instagib FFA server: fdm6, instant respawns, UDP 28785.
# Usage: tools/local-insta-server/run-server.sh
# Connect from Windows with: /connect <the IP this script prints>
# (NAT-mode WSL does NOT forward UDP over localhost - verified 2026-08-05, so
# /connect localhost fails from Windows; the WSL IP works and changes per reboot)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$(cd "$(dirname "$0")" && pwd)"
if pgrep -x sauer_server >/dev/null; then
  echo "A sauer_server is already running (stop it with: pkill sauer_server)"; exit 1
fi
B=/tmp/local-insta-server
"$ROOT/build/apply-patches.sh" "$B" >/dev/null
patch -p1 -d "$B" -s < "$DIR/local-insta-server.patch"
make -C "$B" -j"$(nproc)" server >/dev/null
echo "Local insta server: fdm6, instant respawns, UDP 28785 (Ctrl-C stops it)"
echo "Join from Windows SwiftGibs:  /connect $(hostname -I | awk '{print $1}')"
exec "$B/sauer_server" -q"$DIR"
