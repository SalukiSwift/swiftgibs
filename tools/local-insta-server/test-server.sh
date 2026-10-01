#!/usr/bin/env bash
# End-to-end harness for the local insta server: builds the patched server,
# then proves from the wire (spawnprobe.cc, a real protocol-260 client) that
#   1. the server boots straight into instagib fdm6
#   2. a suicided player is auto-respawned with no N_TRYSPAWN sent
#   3. a player killed by a real rifle hit is auto-respawned
#   4. control: with autospawn 0 the same probe stays dead (the test can fail)
#   5. insta reload: off by default (control: no re-arm, 300ms follow-up shot
#      rejected), "/servcmd instareload on" re-arms the killer on a kill (self
#      N_SHOTFX + wrapped N_GUNSELECT) and the follow-up shot lands, and with a
#      master present only the master may toggle ("#instareload off" by chat)
# Shares /tmp/local-insta-server and port 28985 with test-client.sh: run one at a time.
#   6. instareloadgun 2 sends the chaingun as the re-arm fx gun
# Runs on test port 28985 so a live 28785 server is left alone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$(cd "$(dirname "$0")" && pwd)"
B=/tmp/local-insta-server
H=/tmp/local-insta-test-home
PORT=28985

"$ROOT/build/apply-patches.sh" "$B" >/dev/null
patch -p1 -d "$B" -s < "$DIR/local-insta-server.patch"
make -C "$B" -j"$(nproc)" server >/dev/null
g++ -O2 "$DIR/spawnprobe.cc" -o "$B/spawnprobe" -I"$B/enet/include" -L"$B/enet" -lenet

mkdir -p "$H"
SERVER_PID=""
stop_server() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""; }
trap stop_server EXIT

start_server() { # $1 = autospawn value, $2 = extra config lines (optional)
  printf 'serverport %s\nupdatemaster 0\nmaxclients 8\ndefaultmap "fdm6"\ndefaultmode 3\nautospawn %s\nautospawndelay 0\n%b' "$PORT" "$1" "${2:-}" > "$H/server-init.cfg"
  "$B/sauer_server" -q"$H" & SERVER_PID=$!
  sleep 1
}

FAILED=0
run_probe() { # $1 = scenario
  if "$B/spawnprobe" "$PORT" "$1"; then echo "  [$1] ok"; else echo "  [$1] FAILED"; FAILED=1; fi
}

echo "== autospawn 1: boot map/mode + suicide + real-kill respawn =="
start_server 1
run_probe suicide
run_probe kill
stop_server

echo "== autospawn 0 control: probe must stay dead =="
start_server 0
run_probe nospawn
stop_server

echo "== insta reload: off control, servcmd toggle, master-only rule (the probe claims master with /setmaster 1, as any player may while nobody holds it) =="
start_server 1
run_probe instareload-off
run_probe instareload
run_probe instareload-master
stop_server

echo "== insta reload: instareloadgun 2 re-arms with the chaingun fx =="
start_server 1 'instareloadgun 2\n'
SPAWNPROBE_FXGUN=2 run_probe instareload
stop_server

[ "$FAILED" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
