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

# --- Mode 1: ok ---------------------------------------------------------------

echo "== mode: ok =="
start_server ok
hlog="$(run_harness ok fdm6)"
stop_server
if grep -q "fdm6: done" "$hlog" && grep -q "RESULT state=MS_DONE" "$hlog"; then pass "ok: MS_DONE logged"; else fail "ok: MS_DONE not logged ($(cat "$hlog"))"; fi
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
if grep -q "404" "$hlog" && grep -q "RESULT state=MS_FAILED" "$hlog"; then pass "missing: MS_FAILED \"404\""; else fail "missing: expected 404/MS_FAILED ($(cat "$hlog"))"; fi
assert_no_files fdm6 "missing"

# --- Mode 3: corrupt -----------------------------------------------------------

echo "== mode: corrupt =="
start_server corrupt
hlog="$(run_harness corrupt fdm6)"
stop_server
ATTEMPTS="$(grep -c "downloading fdm6.ogz" "$hlog" || true)"
[ "$ATTEMPTS" -eq 2 ] && pass "corrupt: exactly 2 fetch attempts logged" || fail "corrupt: saw $ATTEMPTS attempts, expected 2"
if grep -q "checksum mismatch" "$hlog" && grep -q "RESULT state=MS_FAILED" "$hlog"; then pass "corrupt: MS_FAILED \"checksum mismatch\""; else fail "corrupt: expected checksum mismatch/MS_FAILED ($(cat "$hlog"))"; fi
[ ! -e "$BUNDLE/packages/base/fdm6.ogz" ] && pass "corrupt: no .ogz" || fail "corrupt: .ogz should not exist"

# --- Mode 4: truncate ----------------------------------------------------------

echo "== mode: truncate =="
start_server truncate
hlog="$(run_harness truncate fdm6)"
stop_server
grep -q "RESULT state=MS_FAILED" "$hlog" && pass "truncate: MS_FAILED (short body vs Content-Length)" || fail "truncate: expected MS_FAILED ($(cat "$hlog"))"
[ ! -e "$BUNDLE/packages/base/fdm6.ogz" ] && pass "truncate: no .ogz" || fail "truncate: .ogz should not exist"

# --- Mode 5: stall + cancel -----------------------------------------------------

echo "== mode: stall =="
start_server stall
STARTMS=$(($(date +%s%N)/1000000))
hlog="$(run_harness stall fdm6 500)"
ENDMS=$(($(date +%s%N)/1000000))
stop_server
ELAPSED=$((ENDMS - STARTMS))
if grep -q "cancelled" "$hlog" && grep -q "RESULT state=MS_FAILED" "$hlog"; then pass "stall: MS_FAILED \"cancelled\""; else fail "stall: expected cancelled/MS_FAILED ($(cat "$hlog"))"; fi
if [ "$ELAPSED" -lt 2000 ]; then pass "stall: cancel took effect within 2s (${ELAPSED}ms)"; else fail "stall: took ${ELAPSED}ms, expected < 2000ms"; fi
assert_no_files fdm6 "stall"

# --- Bonus: a second manifest entry (not just fdm6) also streams cleanly ------

echo "== bonus: shindou (second manifest entry) in ok mode =="
start_server ok
hlog="$(run_harness ok shindou)"
stop_server
if grep -q "shindou: done" "$hlog" && [ -f "$BUNDLE/packages/base/shindou.ogz" ]; then
    pass "bonus: shindou (a different manifest entry) streams cleanly too"
else
    fail "bonus: shindou fetch failed ($(cat "$hlog"))"
fi

# --- Summary --------------------------------------------------------------

echo
if [ "$FAILED" -eq 0 ]; then
    echo "ALL PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
