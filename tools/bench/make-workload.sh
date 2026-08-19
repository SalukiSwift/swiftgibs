#!/usr/bin/env bash
# Records the canonical benchmark workload: a ~2min local 8-bot insta match,
# captured with the patch-17 recorder. Output: workload-<ver>.dmo next to this
# script. The committed workload is IMMUTABLE - cutting a new one is a new
# version, because benchmark numbers are only comparable on the same demo.
#
# TWO-CLIENT CAPTURE, REQUIRED (fix round 1, 2026-08-19): bot AI runs entirely
# client-side (fpsgame/ai.o is only in CLIENT_OBJS, never SERVER_OBJS - a real
# dedicated server has no AI code at all) - the client that owns the bots (via
# addbot) computes their movement and pushes each bot's position UP to the
# server as its own uplink traffic. The server never echoes a client's own
# contributed positions back to that same client. So a single client that is
# BOTH the bot owner AND the recorder can structurally never see bot motion in
# its own recording - it was only ever going to capture its own position and
# reliable/kill-feed traffic (verified against a real recorded file: chan-0
# held exactly one pcn, and stopped 18.8% into the recording). No timing
# change fixes this; it needs a second, independent client to observe the
# match from the server's normal broadcast path:
#   - Client A connects, becomes master (addbot requires ci->privilege - see
#     fpsgame/aiman.h reqadd()), mapvotes the target map+mode (passes
#     instantly: A is the only eligible voter at that point, checkvotes()
#     resolves 1 > maxvotes/2), and owns all 8 bots for the whole session.
#   - Client B connects separately, purely to record. As a normal (non-owner)
#     client it receives A's position plus all 8 bots' positions as ordinary
#     server-relayed broadcast traffic, so its togglerecord clip captures the
#     real match.
# Both connect only to a private dedicated server this script starts itself
# (127.0.0.1, a random-ish high port - loopback needs no WSL-IP workaround,
# unlike LAN play) and built from this repo's own patched tree - NOT
# tools/local-insta-server, which is a real and useful local dev tool but is
# untracked/uncommitted in this repo (confirmed: `git ls-files` and `git log
# --all` both show nothing for that path, on any branch) - a committed,
# reproducible generator can't depend on it. Map+mode load via a normal
# mapvote instead of that tool's defaultmap/defaultmode cvars, and bot
# respawn relies on vanilla per-bot AI logic (ai.cpp decides for itself when
# a bot should respawn) rather than that tool's autospawn cvar, which is
# human-convenience-only (self-spawn already works for bots without it).
set -euo pipefail
VER="${1:?usage: make-workload.sh v1 [map]}"; MAP="${2:-ot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S=/tmp/sg-benchwl-$$; mkdir -p "$S"
PORT=28790

bash "$ROOT/build/apply-patches.sh" "$S/tree"
make -C "$S/tree" -j4 client
bash "$ROOT/build/apply-patches.sh" "$S/servertree"
make -C "$S/servertree" -j4 server

cp -r "$ROOT/dist/SwiftGibs-linux-x86_64" "$S/bundle"
cp "$S/tree/sauer_client" "$S/bundle/sauer_client"
if ! find "$S/bundle/packages" -iname "$MAP.ogz" 2>/dev/null | grep -q .; then
  echo "map $MAP.ogz not found anywhere under the bundle's packages/ - aborting" >&2
  exit 1
fi

mkdir -p "$S/serverhome" "$S/homeA" "$S/homeB"
cat > "$S/serverhome/server-init.cfg" <<EOF
serverport $PORT
updatemaster 0
maxclients 4
serverdesc "SwiftGibs bench workload gen (private, ephemeral)"
EOF

cat > "$S/homeA/a.cfg" <<EOF
connect 127.0.0.1 $PORT
sleep 3000 [mode 3; map "$MAP"]
sleep 7000 [setmaster 1]
sleep 8000 [addbot 60]
sleep 8300 [addbot 60]
sleep 8600 [addbot 60]
sleep 8900 [addbot 60]
sleep 9200 [addbot 60]
sleep 9500 [addbot 60]
sleep 9800 [addbot 60]
sleep 10100 [addbot 60]
sleep 200000 [quit]
EOF

cat > "$S/homeB/b.cfg" <<'EOF'
connect 127.0.0.1 PORTPLACEHOLDER
sleep 5000 [togglerecord]
sleep 125000 [togglerecord]
sleep 128000 [quit]
EOF
sed -i "s/PORTPLACEHOLDER/$PORT/" "$S/homeB/b.cfg"

(cd "$S/servertree" && ./sauer_server -q"$S/serverhome" > "$S/server.log" 2>&1) &
SERVERPID=$!
sleep 2

(cd "$S/bundle" && SDL_AUDIODRIVER=dummy ./sauer_client -q"$S/homeA" -w640 -h480 -t0 '-xexec a.cfg' > "$S/a.log" 2>&1) &
APID=$!
sleep 15   # let A connect, claim master, mapvote, and spawn+settle all 8 bots

(cd "$S/bundle" && SDL_AUDIODRIVER=dummy ./sauer_client -q"$S/homeB" -w640 -h480 -t0 '-xexec b.cfg' > "$S/b.log" 2>&1) &
BPID=$!
wait "$BPID" || true

# kill: $APID/$SERVERPID are the "(cd ... && cmd) &" subshells, not the actual
# sauer_client/sauer_server children they exec'd (bash forks a real child process
# for the compound command rather than exec-replacing it) - killing just the
# subshell PID leaves the game binary running. Match on this run's unique $S path
# instead, which is scoped to exactly the two processes this invocation started.
kill "$APID" "$SERVERPID" 2>/dev/null || true
pkill -f "sauer_client -q$S/homeA" 2>/dev/null || true
pkill -f "sauer_server -q$S/serverhome" 2>/dev/null || true

REC=$(ls -t "$S/homeB/clips/"*rec*.dmo 2>/dev/null | head -1)
[ -n "$REC" ] || { echo "no recording produced" >&2; exit 1; }
cp "$REC" "$(dirname "$0")/workload-$VER.dmo"
echo "workload written: tools/bench/workload-$VER.dmo ($(du -h "$REC" | cut -f1))"
