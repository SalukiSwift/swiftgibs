#!/usr/bin/env bash
# Deploy this directory's local-insta-server.patch to the live Scringle Insta server on the
# Hetzner box (ops notes: ~/swiftcraft-server.md). The box keeps the patched source it was built
# from in /opt/scringle-insta/src, so an update is: revert the patch the box was built with,
# apply this one, rebuild, swap the binary (old one kept beside it), restart the service.
#
# The box remembers which patch it has as src/applied-local-insta-server.patch (written by this
# script). The first deploy predates that file, so pass the patch it was built with:
#   OLD_PATCH=/path/to/previous/local-insta-server.patch tools/local-insta-server/deploy-scringle.sh
# DRY_RUN=1 only checks that both patch steps would apply cleanly (touches nothing outside
# $APP/deploy/ on the box).
# The service config (server-init.cfg) is never touched; add `instareload 1` there by hand if the
# mode should boot on.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="${HOST:-root@46.225.180.173}"
APP=/opt/scringle-insta
NEW="$DIR/local-insta-server.patch"
OLD="${OLD_PATCH:-}"

ssh "$HOST" "mkdir -p $APP/deploy"
scp -q "$NEW" "$HOST:$APP/deploy/incoming.patch"
[ -n "$OLD" ] && scp -q "$OLD" "$HOST:$APP/deploy/previous.patch"

ssh "$HOST" bash -s "$APP" "${DRY_RUN:-0}" "$([ -n "$OLD" ] && echo 1 || echo 0)" <<'REMOTE'
set -euo pipefail
APP=$1 DRY=$2 HAVEOLD=$3
cd "$APP/src"
RECORD="$APP/src/applied-local-insta-server.patch"   # the patch the box's src currently carries
if [ -f "$RECORD" ]; then OLD="$RECORD"; elif [ "$HAVEOLD" = 1 ]; then OLD="$APP/deploy/previous.patch"; else echo "no record of the box's current patch: pass OLD_PATCH"; exit 1; fi
echo "== revert current patch (dry run) =="; patch -R -p1 --fuzz=0 --dry-run < "$OLD"
echo "== apply incoming patch on the reverted tree (dry run via scratch copy) =="
rm -rf "$APP/deploy/scratch"; mkdir -p "$APP/deploy/scratch/fpsgame"; cp fpsgame/server.cpp "$APP/deploy/scratch/fpsgame/"
( cd "$APP/deploy/scratch" && patch -R -p1 --fuzz=0 -s < "$OLD" && patch -p1 --fuzz=0 --dry-run < "$APP/deploy/incoming.patch" )
if [ "$DRY" = 1 ]; then echo "DRY RUN OK: both steps apply cleanly; nothing changed"; exit 0; fi
patch -R -p1 --fuzz=0 < "$OLD"
patch -p1 --fuzz=0 < "$APP/deploy/incoming.patch"
cp "$APP/deploy/incoming.patch" "$RECORD"
echo "== build =="; make -j"$(nproc)" server > "$APP/deploy/build.log" 2>&1 || { tail -20 "$APP/deploy/build.log"; echo "note: build failed; src and $RECORD carry the NEW patch, the live binary is unchanged"; exit 1; }
STAMP=$(date +%F-%H%M%S)
cp -p "$APP/sauer_server" "$APP/sauer_server.bak-$STAMP"
install -o sauer -g sauer -m 755 sauer_server "$APP/sauer_server"
# A refused/failed start must reach the rollback below, not exit under set -e.
systemctl restart scringle-insta || true
sleep 2
if ! systemctl is-active --quiet scringle-insta; then
  echo "!! new server did not come up - rolling back to sauer_server.bak-$STAMP"
  journalctl -u scringle-insta -n 20 --no-pager || true
  install -o sauer -g sauer -m 755 "$APP/sauer_server.bak-$STAMP" "$APP/sauer_server"
  systemctl reset-failed scringle-insta || true   # a crash loop can trip the start limit
  systemctl restart scringle-insta || true; sleep 2
  systemctl is-active --quiet scringle-insta && echo "rolled back: old binary running again" || echo "!! rollback did not come up either - fix by hand"
  echo "note: src and $RECORD now carry the NEW patch while the live binary is the OLD one"
  exit 1
fi
journalctl -u scringle-insta -n 3 --no-pager
echo "deployed; previous binary kept as sauer_server.bak-$STAMP"
REMOTE
