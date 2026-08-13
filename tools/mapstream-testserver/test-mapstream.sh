#!/usr/bin/env bash
# Task 5: fault-mode test for the map streaming downloader (fpsgame/mapstream.cpp).
#
# Two proof routes, both run here:
#
#  1. Full-stack compile-proof: build/apply-patches.sh + `make client` against
#     a completely fresh tree (or one passed as $1, for fast iteration) -
#     proves mapstream.cpp/sgsha256.cpp/sghttp.cpp compile and link cleanly
#     as part of the real client, exactly as shipped.
#
#  2. Standalone downloader harness: the SAME mapstream.cpp/sgsha256.cpp/
#     sghttp.cpp sources from that tree, compiled with harness-main.cpp/
#     harness-stubs.cpp (a minimal set of engine-symbol stubs - conoutf,
#     findfile/openrawfile/openfile, addcommand/svariable, renderprogress -
#     see harness-stubs.cpp) instead of the full renderer/console/scripting
#     engine, driven directly against the five fault-mode serve.py runs
#     below and asserted on console output + real filesystem outcomes.
#
#     This second route exists because the real client currently cannot
#     boot headless in this dev environment (a pre-existing WSL crash,
#     independently reproduced the same way by Tasks 2/3/4 earlier the same
#     day, and again here - see task-5-report.md); it is the task brief's
#     explicitly pre-authorized fallback for proving thread/network/
#     checksum/file behavior when the in-game route is blocked. It talks to
#     the real mapstreambegin()/mapstreamstate()/mapstreamprogress()/
#     mapstreamstatustext()/mapstreamcancel() contract functions directly -
#     the same 5 functions Task 6/7 build on - not a reimplementation.
#
# usage: test-mapstream.sh [existing-patched-tree]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="/tmp/sg-ms-$$-work"
mkdir -p "$WORK"

SERVER_PID=""
cleanup()
{
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then kill "$SERVER_PID" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

FAILED=0
fail() { echo "FAIL: $1" >&2; FAILED=1; }
pass() { echo "PASS: $1"; }

# --- Route 1: fresh-stack compile-proof -------------------------------------

TREE="${1:-}"
if [ -z "$TREE" ]; then
    TREE="$WORK/tree"
    echo "== applying full patch stack into $TREE =="
    "$ROOT/build/apply-patches.sh" "$TREE" >&2
fi

echo "== building the tree client (compile-proof) =="
make -C "$TREE" -j"$(nproc)" client >&2
[ -x "$TREE/sauer_client" ] && pass "tree client builds" || fail "tree client did not build"

# --- Standalone harness build ------------------------------------------------

echo "== building the standalone mapstream harness =="
HARNESS="$WORK/mapstream-harness"
g++ -O0 -g -fsigned-char -fno-exceptions -fno-rtti -Wall \
    -I"$TREE/shared" -I"$TREE/engine" -I"$TREE/fpsgame" -I"$TREE/enet/include" \
    $(sdl2-config --cflags) \
    "$HERE/harness-main.cpp" "$HERE/harness-stubs.cpp" \
    "$TREE/fpsgame/mapstream.cpp" "$TREE/fpsgame/sgsha256.cpp" "$TREE/fpsgame/sghttp.cpp" \
    -L"$TREE/enet" -lenet $(sdl2-config --libs) -lz -lGL \
    -o "$HARNESS" >&2
[ -x "$HARNESS" ] && pass "standalone harness builds" || fail "standalone harness did not build"

# --- Stage a 3-map mini bundle -----------------------------------------------
# Real official maps (per the brief: "generate with make-map-manifest.sh
# against a 3-map subset dir") - fdm6 (has a wpt), shindou (has a wpt),
# reissen (has a wpt, largest of the three at ~3MB) - a mix of sizes plus
# full ogz+wpt coverage.

echo "== staging a 3-map mini bundle =="
OFFICIAL="$("$ROOT/build/fetch-official-data.sh")"
MAPSUBSET="$WORK/mapsubset/packages/base"
mkdir -p "$MAPSUBSET"
for m in fdm6 shindou reissen; do
    cp "$OFFICIAL/packages/base/$m.ogz" "$MAPSUBSET/"
    cp "$OFFICIAL/packages/base/$m.wpt" "$MAPSUBSET/"
done

BUNDLE="$WORK/testbundle"
mkdir -p "$BUNDLE/data" "$BUNDLE/packages/base"
"$ROOT/build/make-map-manifest.sh" "$WORK/mapsubset" > "$BUNDLE/data/mapmanifest.cfg"
MANIFESTLINES="$(wc -l < "$BUNDLE/data/mapmanifest.cfg")"
[ "$MANIFESTLINES" -eq 3 ] && pass "mini manifest lists 3 real maps" || fail "mini manifest has $MANIFESTLINES lines, expected 3"
grep -q "^fdm6 " "$BUNDLE/data/mapmanifest.cfg" || fail "mini manifest missing fdm6 entry"

# --- Server + harness lifecycle helpers --------------------------------------

PORT=8099
LOG=""

start_server()
{
    local mode="$1"
    LOG="$WORK/serve-$mode.log"
    # A single simple command, not "cd dir && python3 ... &" - backgrounding a
    # compound list captures $! for a subshell wrapper, not the real server
    # PID (found the hard way during development: the wrapper PID's `kill`
    # left the actual python3 process running and the next mode's bind failed
    # with "address already in use"). Absolute paths avoid needing cd at all.
    python3 "$HERE/serve.py" "$MAPSUBSET" "$PORT" "$mode" > "$LOG" 2>&1 &
    SERVER_PID=$!
    echo "$SERVER_PID" > "$WORK/serve-$mode.pid"
    sleep 0.3
}

stop_server()
{
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then kill "$SERVER_PID" 2>/dev/null || true; fi
    SERVER_PID=""
    sleep 0.2
}

# Runs the harness against the currently-running server for `name`, with an
# optional cancel-after-ms. Resets packages/base/ to empty first (each mode
# starts clean). Writes harness stdout to $WORK/harness-<name>-<mode>.log and
# echoes that path.
run_harness()
{
    local mode="$1" name="$2" cancelafter="${3:-0}"
    rm -rf "${BUNDLE:?}/packages/base"
    mkdir -p "$BUNDLE/packages/base"
    local hlog="$WORK/harness-$name-$mode.log"
    ( cd "$BUNDLE" && MAPSTREAM_TEST_URL="http://127.0.0.1:$PORT" "$HARNESS" "$name" "$cancelafter" > "$hlog" 2>&1 ) || true
    echo "$hlog"
}

# Task 6: runs the harness in --hook mode (mimics the changemap seam's own
# orchestration sequence - see harness-main.cpp's runhookscenario()). Unlike
# run_harness() above, this does NOT wipe packages/base/ first - the "already
# present" scenario below needs a pre-seeded file to survive the call.
# Writes to $WORK/hook-<name>-<mode>.log and echoes that path.
run_hook_harness()
{
    local mode="$1" name="$2" cancelafter="${3:-0}"
    local hlog="$WORK/hook-$name-$mode.log"
    ( cd "$BUNDLE" && MAPSTREAM_TEST_URL="http://127.0.0.1:$PORT" "$HARNESS" --hook "$name" "$cancelafter" > "$hlog" 2>&1 ) || true
    echo "$hlog"
}

clean_bundle_maps()
{
    rm -rf "${BUNDLE:?}/packages/base"
    mkdir -p "$BUNDLE/packages/base"
}

assert_no_files()
{
    local name="$1" desc="$2"
    if [ -e "$BUNDLE/packages/base/$name.ogz" ] || [ -e "$BUNDLE/packages/base/$name.ogz.part" ] \
       || [ -e "$BUNDLE/packages/base/$name.wpt" ] || [ -e "$BUNDLE/packages/base/$name.wpt.part" ]; then
        fail "$desc: expected no files left behind, found: $(ls "$BUNDLE/packages/base" 2>/dev/null | tr '\n' ' ')"
    else
        pass "$desc: no files left behind"
    fi
}

# Exact-count check for final-outcome log lines, not just presence (grep -q).
# Covers the settext-before-state race fixed in mapstreamwaitloop()/harness-
# main.cpp's mirror loop: the worker publishes statustext before flipping the
# state atomic, so the poll loop can observe the already-final text one tick
# before state catches up, print it there, then (pre-fix) print the identical
# line again unconditionally after the loop. An exact count of 1 is what
# actually catches a regression of that dedupe; "at least one" would not.
assert_count_eq()
{
    local pattern="$1" want="$2" hlog="$3" desc="$4"
    local got
    got="$(grep -c -- "$pattern" "$hlog" || true)"
    if [ "$got" -eq "$want" ]; then
        pass "$desc"
    else
        fail "$desc (saw $got occurrence(s) of \"$pattern\", expected $want) - log: $(cat "$hlog")"
    fi
}

# --- Mode 1: ok ---------------------------------------------------------------

echo "== mode: ok =="
start_server ok
hlog="$(run_harness ok fdm6)"
stop_server
assert_count_eq "fdm6: done" 1 "$hlog" "ok: MS_DONE outcome line logged exactly once"
assert_count_eq "RESULT state=MS_DONE" 1 "$hlog" "ok: RESULT line logged exactly once"
if [ -f "$BUNDLE/packages/base/fdm6.ogz" ] && [ ! -e "$BUNDLE/packages/base/fdm6.ogz.part" ]; then
    pass "ok: .ogz appears, .part gone"
else
    fail "ok: .ogz missing or .part still present"
fi
GOTSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" 2>/dev/null | cut -d' ' -f1)"
WANTSHA="$(grep '^fdm6 ' "$BUNDLE/data/mapmanifest.cfg" | awk '{print $3}')"
[ "$GOTSHA" = "$WANTSHA" ] && pass "ok: hash matches manifest" || fail "ok: hash mismatch ($GOTSHA vs $WANTSHA)"
[ -f "$BUNDLE/packages/base/fdm6.wpt" ] && pass "ok: wpt also fetched" || fail "ok: wpt missing"

# --- Mode 2: missing -----------------------------------------------------------

echo "== mode: missing =="
start_server missing
hlog="$(run_harness missing fdm6)"
stop_server
assert_count_eq "404" 1 "$hlog" "missing: MS_FAILED \"404\" outcome line logged exactly once"
assert_count_eq "RESULT state=MS_FAILED" 1 "$hlog" "missing: RESULT line logged exactly once"
assert_no_files fdm6 "missing"

# --- Mode 3: corrupt -----------------------------------------------------------

echo "== mode: corrupt =="
start_server corrupt
hlog="$(run_harness corrupt fdm6)"
stop_server
ATTEMPTS="$(grep -c "downloading fdm6.ogz" "$hlog" || true)"
[ "$ATTEMPTS" -eq 2 ] && pass "corrupt: exactly 2 fetch attempts logged" || fail "corrupt: saw $ATTEMPTS attempts, expected 2"
assert_count_eq "checksum mismatch" 1 "$hlog" "corrupt: MS_FAILED \"checksum mismatch\" outcome line logged exactly once"
assert_count_eq "RESULT state=MS_FAILED" 1 "$hlog" "corrupt: RESULT line logged exactly once"
[ ! -e "$BUNDLE/packages/base/fdm6.ogz" ] && pass "corrupt: no .ogz" || fail "corrupt: .ogz should not exist"

# --- Mode 4: truncate ----------------------------------------------------------

echo "== mode: truncate =="
start_server truncate
hlog="$(run_harness truncate fdm6)"
stop_server
# truncate resolves via the same checksum-mismatch path as corrupt (a short
# body naturally fails its hash check - see mapstream.cpp's Mechanics, which
# specifies only a checksum check, no separate length check).
assert_count_eq "checksum mismatch" 1 "$hlog" "truncate: MS_FAILED \"checksum mismatch\" (short body vs Content-Length) outcome line logged exactly once"
assert_count_eq "RESULT state=MS_FAILED" 1 "$hlog" "truncate: RESULT line logged exactly once"
[ ! -e "$BUNDLE/packages/base/fdm6.ogz" ] && pass "truncate: no .ogz" || fail "truncate: .ogz should not exist"

# --- Mode 5: stall + cancel -----------------------------------------------------

echo "== mode: stall =="
start_server stall
STARTMS=$(($(date +%s%N)/1000000))
hlog="$(run_harness stall fdm6 500)"
ENDMS=$(($(date +%s%N)/1000000))
stop_server
ELAPSED=$((ENDMS - STARTMS))
assert_count_eq "cancelled" 1 "$hlog" "stall: MS_FAILED \"cancelled\" outcome line logged exactly once"
assert_count_eq "RESULT state=MS_FAILED" 1 "$hlog" "stall: RESULT line logged exactly once"
if [ "$ELAPSED" -lt 2000 ]; then pass "stall: cancel took effect within 2s (${ELAPSED}ms)"; else fail "stall: took ${ELAPSED}ms, expected < 2000ms"; fi
assert_no_files fdm6 "stall"

# --- Bonus: a second manifest entry (not just fdm6) also streams cleanly ------

echo "== bonus: shindou (second manifest entry) in ok mode =="
start_server ok
hlog="$(run_harness ok shindou)"
stop_server
assert_count_eq "shindou: done" 1 "$hlog" "bonus: shindou MS_DONE outcome line logged exactly once"
[ -f "$BUNDLE/packages/base/shindou.ogz" ] && pass "bonus: shindou (a different manifest entry) streams cleanly too" || fail "bonus: shindou.ogz missing"

# --- Task 6: changemap-hook orchestration (harness --hook) -------------------
# Route taken per task-6-report.md: the real client cannot boot headless in
# this environment (same pre-existing WSL crash, re-confirmed the same way as
# Tasks 2-5 earlier the same day). These scenarios drive harness-main.cpp's
# runhookscenario(), which mirrors the fpsgame/client.cpp seam's own
# precondition chain and while(MS_ACTIVE)/interceptkey-simulated-cancel loop
# line for line - proving the hook's LOGIC; the seam's wiring into
# fpsgame/client.cpp itself is proven by the compile-proof above (Route 1).

echo "== hook: map already present -> never touches the network =="
clean_bundle_maps
echo "not a real map, just a marker the hook must not overwrite" > "$BUNDLE/packages/base/fdm6.ogz"
MARKERSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" | cut -d' ' -f1)"
start_server ok
hlog="$(run_hook_harness ok fdm6)"
stop_server
assert_count_eq "present=yes" 1 "$hlog" "hook/present: reports present=yes"
assert_count_eq "skip (already present)" 1 "$hlog" "hook/present: skip line logged"
if grep -q "downloading" "$hlog"; then fail "hook/present: should never contact the network, but a download line was logged"; else pass "hook/present: no download attempted"; fi
AFTERSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" | cut -d' ' -f1)"
[ "$AFTERSHA" = "$MARKERSHA" ] && pass "hook/present: existing file left untouched" || fail "hook/present: existing file was overwritten"

echo "== hook: unknown map name -> skip, no manifest entry =="
clean_bundle_maps
start_server ok
hlog="$(run_hook_harness ok notarealmapname)"
stop_server
assert_count_eq "present=no" 1 "$hlog" "hook/unknown: reports present=no"
assert_count_eq "skip (no manifest entry)" 1 "$hlog" "hook/unknown: skip line logged"
assert_no_files notarealmapname "hook/unknown"

echo "== hook: success flow (ok mode, file absent) =="
clean_bundle_maps
start_server ok
hlog="$(run_hook_harness ok fdm6)"
stop_server
assert_count_eq "present=no" 1 "$hlog" "hook/ok: reports present=no"
assert_count_eq "RESULT state=MS_DONE" 1 "$hlog" "hook/ok: RESULT line logged exactly once"
if grep -q "map download failed" "$hlog"; then fail "hook/ok: unexpected failure line on a successful fetch"; else pass "hook/ok: no failure line"; fi
GOTSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" 2>/dev/null | cut -d' ' -f1)"
WANTSHA="$(grep '^fdm6 ' "$BUNDLE/data/mapmanifest.cfg" | awk '{print $3}')"
[ "$GOTSHA" = "$WANTSHA" ] && pass "hook/ok: hash matches manifest (load_world would now find it)" || fail "hook/ok: hash mismatch ($GOTSHA vs $WANTSHA)"
[ ! -e "$BUNDLE/packages/base/fdm6.ogz.part" ] && pass "hook/ok: no .part left behind" || fail "hook/ok: stray .part"

echo "== hook: ESC mid-download (stall mode) -> immediate empty-world degrade =="
clean_bundle_maps
start_server stall
STARTMS=$(($(date +%s%N)/1000000))
hlog="$(run_hook_harness stall fdm6 500)"
ENDMS=$(($(date +%s%N)/1000000))
stop_server
ELAPSED=$((ENDMS - STARTMS))
assert_count_eq "interceptkey(ESC) -> cancel" 1 "$hlog" "hook/esc: simulated ESC cancel logged exactly once"
assert_count_eq "map download failed" 1 "$hlog" "hook/esc: outcome line (same text the real seam's conoutf would print) logged exactly once"
# RESULT here can legitimately read MS_FAILED or MS_OTHER (still MS_ACTIVE):
# the hook (both the harness's copy and the real seam) calls mapstreamcancel()
# then breaks and reads state again on the very next line, with no
# synchronization point in between - the worker thread settles to MS_FAILED
# within one wait tick (~250ms, same latency Task 5 measured/documented),
# which can be a few ms after this immediate read. Harmless: the file-state
# and no-hang guarantees below are unaffected either way, and the console
# text printed is real (whatever mapstreamstatustext() held at that instant).
if grep -q "RESULT state=MS_FAILED" "$hlog" || grep -q "RESULT state=MS_OTHER" "$hlog"; then
    pass "hook/esc: RESULT reflects the cancel (MS_FAILED, or MS_ACTIVE-at-the-instant-of-break)"
else
    fail "hook/esc: unexpected RESULT line: $(grep RESULT "$hlog")"
fi
if [ "$ELAPSED" -lt 2000 ]; then pass "hook/esc: loop exited (no hang) within 2s (${ELAPSED}ms)"; else fail "hook/esc: took ${ELAPSED}ms, expected < 2000ms (looks hung)"; fi
assert_no_files fdm6 "hook/esc"

echo "== hook: 404 -> failure outcome without any cancel =="
clean_bundle_maps
start_server missing
hlog="$(run_hook_harness missing fdm6)"
stop_server
assert_count_eq "map download failed" 1 "$hlog" "hook/404: outcome line logged exactly once"
grep -q "404" "$hlog" && pass "hook/404: outcome text carries the HTTP status" || fail "hook/404: expected \"404\" in the outcome text"
assert_count_eq "RESULT state=MS_FAILED" 1 "$hlog" "hook/404: RESULT line logged exactly once"
assert_no_files fdm6 "hook/404"

# --- Summary --------------------------------------------------------------

echo
if [ "$FAILED" -eq 0 ]; then
    echo "ALL PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
