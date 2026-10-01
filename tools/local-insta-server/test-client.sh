#!/usr/bin/env bash
# Client-side proof for insta reload against a REAL, otherwise-stock Sauerbraten 2020 client.
# test-server.sh proves the server half from the wire; this proves the half that matters to a
# player: the stock client's own rifle gate (fpsgame/weapon.cpp shoot(), lastmillis - lastaction
# >= gunwait) really opens ~250ms after a kill because of the re-arm pair, with no client change.
#
# The client is the vanilla tree at $VANILLA_SRC plus harness-client.patch, which only adds
# script hooks (probeattack/probespawn/probenear/probeaimat/probereload) so a -x script can drive it; the
# message handling, weapon code and gate are untouched. It runs headless: SDL offscreen video,
# dummy audio (WSLg would otherwise play every shot on the real speakers).
#
# Per mode (MODES, default "on off": on, then off as the control), with spawnprobe's "idle" scenario standing in as
# victim (cn 0) and bystander (cn 1):
#   1. client joins, spawns, "/servcmd instareload <mode>"
#   2. aims at the victim (the idle probe parks it 10 units ahead of the client), fires once
#   3. 350ms later dumps its reload state, aims at the bystander (12 ahead, 7 aside), holds fire 100ms
#   on:  state shows gunwait=250 lastattackgun=0 (fist re-arm), and the bystander dies well
#        inside the stock 1500ms (idle probe reports the gap)
#   off: state shows gunwait=1500, no shot happens in that window, the bystander survives
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$(cd "$(dirname "$0")" && pwd)"
VANILLA_SRC="${VANILLA_SRC:-$HOME/repos/sauerbraten/src}"   # stock 2020 source + objects
GAME_DIR="${GAME_DIR:-$HOME/repos/sauerbraten}"             # packages/ + data/ for the client
B=/tmp/local-insta-server          # patched server tree (same as test-server.sh)
C=/tmp/local-insta-client          # harness client tree
H=/tmp/local-insta-client-home     # server home for this test
CH=/tmp/local-insta-client-chome   # client home (config.cfg etc. land here, not in $GAME_DIR)
PORT=28985

"$ROOT/build/apply-patches.sh" "$B" >/dev/null
patch -p1 -d "$B" -s < "$DIR/local-insta-server.patch"
make -C "$B" -j"$(nproc)" server >/dev/null
g++ -O2 "$DIR/spawnprobe.cc" -o "$B/spawnprobe" -I"$B/enet/include" -L"$B/enet" -lenet

if [ ! -x "$C/sauer_client" ] || [ "$DIR/harness-client.patch" -nt "$C/sauer_client" ]; then
  echo "building harness client from $VANILLA_SRC (one-off)"
  rm -rf "$C"; cp -a "$VANILLA_SRC" "$C"
  patch -p1 -d "$C" -s < "$DIR/harness-client.patch"
  make -C "$C" -j"$(nproc)" client >/dev/null
fi

mkdir -p "$H" "$CH"
SERVER_PID=""; PROBE_PID=""
cleanup() {
  [ -n "$PROBE_PID" ] && kill "$PROBE_PID" 2>/dev/null || true
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""; PROBE_PID=""
}
trap cleanup EXIT

FAILED=0
run_mode() { # $1 = on|off
  local mode=$1
  local clog="$H/client-$mode.log" plog="$H/probe-$mode.log"
  printf 'serverport %s\nupdatemaster 0\nmaxclients 8\ndefaultmap "fdm6"\ndefaultmode 3\nautospawn 1\nautospawndelay 0\npublicserver 2\n' "$PORT" > "$H/server-init.cfg"
  "$B/sauer_server" -q"$H" > "$H/server-$mode.log" 2>&1 & SERVER_PID=$!
  sleep 1
  SPAWNPROBE_IDLE_MS=90000 "$B/spawnprobe" "$PORT" idle > "$plog" 2>&1 & PROBE_PID=$!
  sleep 1
  # Nested sleeps are relative to the enclosing step. Spawn attempts repeat because map load time
  # on software GL varies; probespawn is a no-op while alive (pressing fire would shoot the
  # victim parked in front of us before the mode is even set).
  local script="name probex; connect 127.0.0.1 $PORT; \
sleep 20000 [probespawn]; \
sleep 25000 [probespawn]; \
sleep 28000 [servcmd \"instareload $mode\"; probereload spawned]; \
sleep 30000 [probeaimat 0; sleep 300 [probereload prekill; probeattack 1; sleep 100 [probeattack 0]; \
  sleep 350 [probereload postkill; probeaimat 1; sleep 200 [probereload prefollow; probeattack 1; sleep 100 [probeattack 0; probereload postfollow]]]]]; \
sleep 36000 [probereload end; quit]"
  (cd "$GAME_DIR" && timeout 90 env SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy "$C/sauer_client" -q"$CH" -w640 -h480 -x"$script" > "$clog" 2>&1) || true
  sleep 1
  cleanup
  echo "--- mode $mode: client PROBE lines ---"; grep "^PROBE\|you fragged\|insta reload" "$clog" || true
  echo "--- mode $mode: idle probe ---"; cat "$plog"
  # postkill is dumped ~350ms after the kill shot; postfollow ~100ms into the second trigger pull.
  # since = ms since the client's last shot (its lastaction); a fresh rifle shot resets it to ~0
  # and puts gunwait back to 1500. The fist re-arm leaves lastattackgun=0 behind as its fingerprint,
  # and gunwait reads 250 until the client's own shoot() has passed that mark, then 0.
  local post follow psince fsince
  post=$(grep "^PROBE postkill" "$clog" || true); follow=$(grep "^PROBE postfollow" "$clog" || true)
  psince=$(sed -n 's/.* since=\([0-9-]*\) .*/\1/p' <<< "$post"); fsince=$(sed -n 's/.* since=\([0-9-]*\) .*/\1/p' <<< "$follow")
  if ! grep -q "you fragged victim" "$clog"; then echo "  [$mode] FAILED: real client never killed the victim (map load/aim problem?)"; FAILED=1; return; fi
  if [ "$mode" = on ]; then
    [[ "$post" == *"lastattackgun=0 "* && "$post" == *"gunselect=4 "* && ( "$post" == *"gunwait=250 "* || "$post" == *"gunwait=0 "* ) ]] \
      || { echo "  [on] FAILED: client not re-armed after the kill (want lastattackgun=0 gunselect=4 gunwait<=250)"; FAILED=1; }
    # (the second kill re-arms again at once, so postfollow shows the fist fingerprint, not 1500)
    [[ -n "$fsince" && "$fsince" -lt 300 ]] || { echo "  [on] FAILED: client did not fire again inside the stock 1500ms gate"; FAILED=1; }
    local gap; gap=$(sed -n 's/^RESULT gap \([0-9]*\)ms.*/\1/p' "$plog")
    if [ -z "$gap" ] || [ "$gap" -ge 1000 ]; then echo "  [on] FAILED: bystander not killed within 1000ms of the victim (gap='${gap:-none}')"; FAILED=1; fi
    if [ "$FAILED" = 0 ]; then echo "  [on] ok: stock client re-armed on the kill and its next shot landed ${gap}ms after the kill (stock gate is 1500ms)"; fi
  else
    [[ "$post" == *"gunwait=1500 "* && "$post" == *"lastattackgun=4 "* ]] || { echo "  [off] FAILED: expected the stock gate (gunwait=1500 lastattackgun=4) with the mode off"; FAILED=1; }
    [[ -n "$fsince" && "$fsince" -gt 500 ]] || { echo "  [off] FAILED: client fired again inside the stock gate with the mode off"; FAILED=1; }
    if grep -q "^DIED bystander" "$plog"; then echo "  [off] FAILED: bystander died with the mode off"; FAILED=1; else echo "  [off] ok: control - stock gate held, no second shot"; fi
  fi
}

for m in ${MODES:-on off}; do run_mode "$m"; done
[ "$FAILED" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
