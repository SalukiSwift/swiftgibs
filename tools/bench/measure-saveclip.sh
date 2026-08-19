#!/usr/bin/env bash
# Measures saveclip()'s FRAME-THREAD stall time via the sgclipstalldebug VAR-gated conoutf
# (perf-wave-1 Task 2 / Slate B, fpsgame/client.cpp). Runs a real scripted two-client local-bots
# match (the same architecture tools/bench/make-workload.sh uses and documents at length: bot AI
# runs entirely client-side - fpsgame/ai.o is only in CLIENT_OBJS, never SERVER_OBJS - and the
# server never echoes a client's own contributed position back to that same client, so a single
# client that owns the bots can never see their motion in its own ring; a second, independent
# observer client is required), fills that observer's clip ring with real 9-actor traffic
# (client A + 8 bots), then triggers `saveclip` N=5 times at fixed, spaced points via a timed
# cfg, capturing each call's frame-thread portion (ring snapshot + format + enqueue, or - on a
# pre-Task-2 build - the whole synchronous gzip+IO) in milliseconds.
#
# Usage: bash tools/bench/measure-saveclip.sh [CLIENT_BINARY]
#   CLIENT_BINARY - optional path to a pre-built sauer_client-compatible binary to test (must
#     recognize `clips`/`cliplength`/`clipmemcap`/`sgclipstalldebug`/`saveclip`/`addbot`/
#     `setmaster`/`mode`/`map` - i.e. any patched SwiftGibs client). If omitted, builds the
#     CURRENT patch stack fresh (matching test-bench.sh's "always test what patches/*.patch
#     currently contains" rule) and uses that.
#
# This is a general-purpose A/B tool, not itself a git-state switcher: to reproduce a genuine
# before/after comparison across the Task 2 threading change, build TWO client binaries (one
# from the patch state before the change, one from HEAD) and pass each to this script in turn -
# see the Task 2 report for exactly how the "before" (pre-Task-2, synchronous saveclip()) binary
# was built and instrumented for this script's own message format, since that instrumentation
# did not exist in the pre-Task-2 code (the whole point of the threading rework was to remove
# the synchronous path being measured).
#
# Output: every `sgclipstalldebug: saveclip frame-thread portion = N.NNNms` line from the
# scripted run, in order, plus a min/max/mean summary. WSL-valid: pure CPU work (ring
# snapshot/format/compress + local-loopback network), no GPU dependency in what's measured.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="/tmp/sg-measuresaveclip-$$"
mkdir -p "$S"
PORT=28799
N_SAVES=5

cleanup() {
  # exec-captured PIDs only (never pkill -f - project-wide hard rule, see make-workload.sh's own
  # comment for the incident this rule exists because of). Each PID is guarded individually and
  # NEVER defaulted to 0 - kill(0, sig) targets the entire current process group, so a bare
  # `kill "${BPID:-0}"` on a not-yet-set var would SIGTERM the caller (this script's own parent
  # shell) if cleanup ran before the PIDs were assigned (e.g. a build failure under `set -e`
  # firing the EXIT trap early). Only kill a PID that was actually captured.
  [ -n "${BPID:-}" ] && kill "$BPID" 2>/dev/null || true
  [ -n "${APID:-}" ] && kill "$APID" 2>/dev/null || true
  [ -n "${SERVERPID:-}" ] && kill "$SERVERPID" 2>/dev/null || true
}
trap cleanup EXIT

if [ $# -ge 1 ]; then
  CLIENT_BIN="$1"
  [ -x "$CLIENT_BIN" ] || { echo "not an executable: $CLIENT_BIN" >&2; exit 1; }
  echo "using pre-built client: $CLIENT_BIN"
else
  echo "no client given - building the current patch stack fresh"
  bash "$ROOT/build/apply-patches.sh" "$S/tree"
  make -C "$S/tree" -j"$(nproc)" client
  CLIENT_BIN="$S/tree/sauer_client"
fi

# Server: always built fresh from the CURRENT patch stack regardless of which client is under
# test - fpsgame/client.cpp (where all of Slate B lives) is never compiled into the STANDALONE
# server build at all (fpsgame/ai.o and fpsgame/client.o are CLIENT_OBJS-only in the Makefile),
# so the server side is identical no matter which client binary this run is measuring.
bash "$ROOT/build/apply-patches.sh" "$S/servertree"
make -C "$S/servertree" -j"$(nproc)" server
SERVER_BIN="$S/servertree/sauer_server"
[ -x "$SERVER_BIN" ] || { echo "no server binary at $SERVER_BIN" >&2; exit 1; }

cp -r "$ROOT/dist/SwiftGibs-linux-x86_64" "$S/bundle"
cp "$CLIENT_BIN" "$S/bundle/sauer_client"
chmod +x "$S/bundle/sauer_client"

mkdir -p "$S/serverhome" "$S/homeA" "$S/homeB"
cat > "$S/serverhome/server-init.cfg" <<EOF
serverport $PORT
updatemaster 0
maxclients 4
serverdesc "SwiftGibs measure-saveclip (private, ephemeral)"
EOF

cat > "$S/homeA/a.cfg" <<EOF
connect 127.0.0.1 $PORT
sleep 3000 [mode 3; map "ot"]
sleep 7000 [setmaster 1]
sleep 8000 [addbot 60]
sleep 8300 [addbot 60]
sleep 8600 [addbot 60]
sleep 8900 [addbot 60]
sleep 9200 [addbot 60]
sleep 9500 [addbot 60]
sleep 9800 [addbot 60]
sleep 10100 [addbot 60]
sleep 120000 [quit]
EOF

# Client B (observer + measurer): let the match run for 30s after connecting (bots settle by
# ~10.5s server-side; this gives a well-filled ring with real multi-actor traffic - the same
# margin the correctness-gate runs used), a generous ring (cliplength/clipmemcap raised so
# saveclip's snapshot+format cost is representative of a busy match, not a near-empty ring),
# then N_SAVES saveclip calls spaced 4s apart so each call's ring content and console log entry
# stay distinguishable.
{
  echo "connect 127.0.0.1 $PORT"
  echo "clips 1"
  echo "cliplength 20"
  echo "clipmemcap 16"
  echo "sgclipstalldebug 1"
  T=30000
  for i in $(seq 1 "$N_SAVES"); do
    echo "sleep $T [saveclip]"
    T=$((T + 4000))
  done
  echo "sleep $((T + 2000)) [quit]"
} > "$S/homeB/b.cfg"

echo "== starting private server + two clients =="
(cd "$S" && exec "$SERVER_BIN" -q"$S/serverhome") > "$S/server.log" 2>&1 &
SERVERPID=$!
sleep 2

(cd "$S/bundle" && SDL_AUDIODRIVER=dummy exec ./sauer_client -q"$S/homeA" -w640 -h480 -t0 '-xexec a.cfg') > "$S/a.log" 2>&1 &
APID=$!
sleep 15

(cd "$S/bundle" && SDL_AUDIODRIVER=dummy exec ./sauer_client -q"$S/homeB" -w640 -h480 -t0 '-xexec b.cfg') > "$S/b.log" 2>&1 &
BPID=$!

echo "waiting for client B to finish (bounded poll, up to 90s)..."
WAITED=0
while kill -0 "$BPID" 2>/dev/null; do
  sleep 5
  WAITED=$((WAITED + 5))
  if [ "$WAITED" -ge 90 ]; then
    echo "client B still running after 90s - killing and continuing (log below may be partial)" >&2
    break
  fi
done

kill "$APID" "$SERVERPID" 2>/dev/null || true
sleep 1

echo
echo "== results (tools/bench/measure-saveclip.sh) =="
LINES="$(grep -o 'sgclipstalldebug: saveclip frame-thread portion = [0-9.]*ms' "$S/b.log" || true)"
if [ -z "$LINES" ]; then
  echo "FAIL: no sgclipstalldebug lines found in client B's log ($S/b.log preserved for inspection)" >&2
  exit 1
fi
COUNT="$(echo "$LINES" | wc -l)"
echo "captured $COUNT saveclip call(s) (expected $N_SAVES):"
echo "$LINES" | nl -ba
echo "$LINES" | grep -o '[0-9.]*ms' | sed 's/ms$//' > "$S/values.txt"
awk '
  { sum += $1; if (NR==1 || $1<min) min=$1; if (NR==1 || $1>max) max=$1; n++ }
  END { if (n>0) printf "min=%.3fms max=%.3fms mean=%.3fms n=%d\n", min, max, sum/n, n }
' "$S/values.txt"
echo
echo "scratch tree: $S (removed on next run of this script under the same PID space; not auto-deleted here so logs remain inspectable)"
