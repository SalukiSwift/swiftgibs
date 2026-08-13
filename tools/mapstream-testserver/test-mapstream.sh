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
    local mode="$1" dir="${2:-$MAPSUBSET}"
    LOG="$WORK/serve-$mode.log"
    # A single simple command, not "cd dir && python3 ... &" - backgrounding a
    # compound list captures $! for a subshell wrapper, not the real server
    # PID (found the hard way during development: the wrapper PID's `kill`
    # left the actual python3 process running and the next mode's bind failed
    # with "address already in use"). Absolute paths avoid needing cd at all.
    # Task 7: optional 2nd arg lets a scenario serve a DIFFERENT directory
    # than the shared 3-map $MAPSUBSET (eg one with a file deliberately
    # missing, to make that one manifest entry 404 while the others serve
    # normally) without mutating $MAPSUBSET itself, which every other
    # section of this script also reuses.
    python3 "$HERE/serve.py" "$dir" "$PORT" "$mode" > "$LOG" 2>&1 &
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

# Task 7: runs the harness in --all mode (the bulk sweep) against the
# currently-running server, with an optional cancel-after-ms. Does NOT touch
# packages/base/ - callers set that up themselves (pre-seeding a file for the
# skip-existing case is part of what these scenarios are proving). Writes to
# $WORK/all-<label>.log and echoes that path.
run_all_harness()
{
    local label="$1" cancelafter="${2:-0}"
    local hlog="$WORK/all-$label.log"
    ( cd "$BUNDLE" && MAPSTREAM_TEST_URL="http://127.0.0.1:$PORT" "$HARNESS" --all "$cancelafter" > "$hlog" 2>&1 ) || true
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

# --- Task 7: bulk "download all maps" sweep (harness --all) -----------------
# Route taken per task-5/6-report.md: the real client cannot boot headless in
# this environment (same pre-existing WSL crash, re-confirmed the same way
# earlier the same day - see this task's own report). These scenarios drive
# harness-main.cpp's runallscenario(), which calls mapstreamallbegin()/
# mapstreamallisactive()/mapstreamalldonecount()/mapstreamalltotalcount()/
# mapstreamallfailedcount()/mapstreamallcancel() directly - the exact same
# public contract the mapstreamall/mapstreamallsync/mapstreamallcancel
# ICOMMANDs (and therefore the menu) wrap.

echo "== bulk: 1 pre-present + 1 ok + 1 404 -> exact final counters =="
clean_bundle_maps
# ALLSUBSET is a SEPARATE serving directory from the shared $MAPSUBSET (which
# every earlier section in this script also reuses) with shindou's files
# deliberately absent, so a request for shindou 404s while fdm6/reissen still
# serve normally - the manifest itself (already generated from the full
# 3-map $MAPSUBSET above) still lists all three.
ALLSUBSET="$WORK/allsubset/packages/base"
mkdir -p "$ALLSUBSET"
cp "$MAPSUBSET/fdm6.ogz" "$MAPSUBSET/fdm6.wpt" "$MAPSUBSET/reissen.ogz" "$MAPSUBSET/reissen.wpt" "$ALLSUBSET/"
# fdm6 pre-seeded as deliberate garbage (not a real map) - proves skip-
# existing is presence-only and genuinely never touches the network for it
# (same style as the "hook: map already present" scenario above).
echo "not a real map, just a marker the sweep must not overwrite" > "$BUNDLE/packages/base/fdm6.ogz"
MARKERSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" | cut -d' ' -f1)"
start_server ok "$ALLSUBSET"
hlog="$(run_all_harness mixed)"
stop_server
assert_count_eq "RESULT done=2 total=3 failed=1 active=0" 1 "$hlog" "bulk/mixed: exact final counters (1 pre-present + 1 fetched + 1 failed, active=0)"
AFTERSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" | cut -d' ' -f1)"
[ "$AFTERSHA" = "$MARKERSHA" ] && pass "bulk/mixed: pre-present fdm6 left byte-for-byte untouched (skip-existing never re-fetches)" || fail "bulk/mixed: pre-present fdm6 was overwritten"
if [ -f "$BUNDLE/packages/base/reissen.ogz" ] && [ ! -e "$BUNDLE/packages/base/reissen.ogz.part" ]; then
    GOTSHA="$(sha256sum "$BUNDLE/packages/base/reissen.ogz" | cut -d' ' -f1)"
    WANTSHA="$(grep '^reissen ' "$BUNDLE/data/mapmanifest.cfg" | awk '{print $3}')"
    [ "$GOTSHA" = "$WANTSHA" ] && pass "bulk/mixed: reissen fetched, hash matches manifest, no .part" || fail "bulk/mixed: reissen hash mismatch ($GOTSHA vs $WANTSHA)"
else
    fail "bulk/mixed: reissen.ogz missing or .part left behind"
fi
[ -f "$BUNDLE/packages/base/reissen.wpt" ] && pass "bulk/mixed: reissen wpt also fetched" || fail "bulk/mixed: reissen wpt missing"
assert_no_files shindou "bulk/mixed (the 404'd entry)"

echo "== bulk: retry after failure -> skip-existing makes it a natural retry =="
# Re-running against a server where shindou now serves too (same ALLSUBSET,
# topped up) should skip the two already-downloaded maps by presence and
# only fetch the previously-failed one - proving "retry failed" (the menu's
# retry button is literally mapstreamall again) actually converges.
cp "$MAPSUBSET/shindou.ogz" "$MAPSUBSET/shindou.wpt" "$ALLSUBSET/"
start_server ok "$ALLSUBSET"
hlog="$(run_all_harness retry)"
stop_server
assert_count_eq "RESULT done=3 total=3 failed=0 active=0" 1 "$hlog" "bulk/retry: all 3 present after retry, 0 failed"
GOTSHA="$(sha256sum "$BUNDLE/packages/base/shindou.ogz" 2>/dev/null | cut -d' ' -f1)"
WANTSHA="$(grep '^shindou ' "$BUNDLE/data/mapmanifest.cfg" | awk '{print $3}')"
[ "$GOTSHA" = "$WANTSHA" ] && pass "bulk/retry: shindou fetched this time, hash matches manifest" || fail "bulk/retry: shindou hash mismatch ($GOTSHA vs $WANTSHA)"
# fdm6 is still the ORIGINAL garbage marker - a retry must never re-verify or
# re-fetch an already-present file, only ever check presence.
AFTERSHA="$(sha256sum "$BUNDLE/packages/base/fdm6.ogz" | cut -d' ' -f1)"
[ "$AFTERSHA" = "$MARKERSHA" ] && pass "bulk/retry: fdm6 still untouched (skip-existing, not skip-if-successful-before)" || fail "bulk/retry: fdm6 was touched on retry"

echo "== bulk: cancel mid-sweep -> clean state, sane counters =="
clean_bundle_maps
# mode=stall holds every request open past a half-body write (see serve.py's
# own comment) - the sweep's first file never completes, giving the cancel
# something real to interrupt (same reasoning as the single-file stall test
# above).
start_server stall "$ALLSUBSET"
STARTMS=$(($(date +%s%N)/1000000))
hlog="$(run_all_harness cancel 400)"
ENDMS=$(($(date +%s%N)/1000000))
stop_server
ELAPSED=$((ENDMS - STARTMS))
assert_count_eq "cancel requested" 1 "$hlog" "bulk/cancel: cancel logged exactly once"
if [ "$ELAPSED" -lt 2000 ]; then pass "bulk/cancel: sweep stopped within 2s (${ELAPSED}ms)"; else fail "bulk/cancel: took ${ELAPSED}ms, expected < 2000ms"; fi
RESULTLINE="$(grep "RESULT" "$hlog" || true)"
DONE="$(echo "$RESULTLINE" | grep -oP 'done=\K[0-9]+' || echo -1)"
FAILED="$(echo "$RESULTLINE" | grep -oP 'failed=\K[0-9]+' || echo -1)"
TOTAL="$(echo "$RESULTLINE" | grep -oP 'total=\K[0-9]+' || echo -1)"
ACTIVE="$(echo "$RESULTLINE" | grep -oP 'active=\K[0-9]+' || echo -1)"
if [ "$ACTIVE" = "0" ] && [ $((DONE + FAILED)) -le "$TOTAL" ]; then
    pass "bulk/cancel: counters sane after cancel (done=$DONE failed=$FAILED total=$TOTAL active=$ACTIVE)"
else
    fail "bulk/cancel: counters not sane: $RESULTLINE"
fi
assert_no_files fdm6 "bulk/cancel"
assert_no_files reissen "bulk/cancel"
assert_no_files shindou "bulk/cancel"

# --- Summary --------------------------------------------------------------

echo
if [ "$FAILED" -eq 0 ]; then
    echo "ALL PASSED"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
