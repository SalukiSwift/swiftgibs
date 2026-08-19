#!/usr/bin/env bash
# SwiftGibs benchmark mode: end-to-end regression gate.
#
# This is the round's before/after check for every future performance-optimization patch:
# build the CURRENT patch stack from scratch, assemble the real Linux bundle, then run every
# exact-count assertion the plan calls for:
#
#   1. `sgbenchselftest` prints the exact pinned line (the percentile/1%low/stutter math has
#      not silently drifted - see tools/bench/README.md for the formulas).
#   2. `sgbench data/bench/workload-v1.dmo`, run via the real run-benchmark.sh (1 warmup + 1
#      measured pass), produces the exact CSV header, exactly 3 lines total (header + warmup
#      row + 1 measured row), the measured row's `seconds` in [115,135], and `frames` > 500.
#   3. A normal client boot (shipped autoexec.cfg, no bench overrides) still renders and can
#      take a screenshot - file exists and is >10KB, i.e. not a black/crashed launch.
#
# Every assertion is an exact-count check, not a presence-grep: a wrong header, a missing row,
# an out-of-range `seconds`, or a too-small screenshot all fail the run.
#
# Usage: bash tools/bench/test-bench.sh
# Exit 0 = every assertion passed. Exit 1 = first failure, printed as a `FAIL:` line.
#
# Safe to run twice back-to-back with no manual cleanup between runs: every invocation uses a
# fresh, private /tmp/sg-bench4-<pid>-* scratch tree (this process's own PID in the name, never
# reused) and the bundle's own bench-home-run (via run-benchmark.sh, which rm -rf's and
# recreates it every time) - never the bundle's real player config or homedir.
#
# Runtime: dominated by the client compile (~1-3min) and the workload's own ~120s x2 real-time
# playback (warmup + 1 measured pass) - expect ~5min for one run, ~10min+ for two back-to-back.
# That is expected, not a hang.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="/tmp/sg-bench4-$$-work"
rm -rf "$WORK"; mkdir -p "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
ok()   { echo "OK: $1"; }

export SDL_AUDIODRIVER=dummy

BUNDLE="$ROOT/dist/SwiftGibs-linux-x86_64"

echo "== Step 1: fresh patched build + bundle assembly =="
# Force a fresh client compile every run - this script must always test whatever
# patches/*.patch currently contains, never a stale binary left over from an earlier session.
rm -f "$ROOT/dist/engines/linux-x86_64/sauer_client"

if bash "$ROOT/build/make-bundle-linux.sh"; then
  ok "bundle assembled via build/make-bundle-linux.sh"
else
  # Fallback: only reachable if the real pipeline itself cannot run (e.g. official-data cache
  # went cold and there is no network). Requires a bundle skeleton to already exist from a
  # prior successful run - it overlays a freshly compiled client + refreshed bench files onto
  # it rather than re-fetching/re-stripping the ~1GB of official game data.
  echo "build/make-bundle-linux.sh failed - falling back to manual dist-based assembly" >&2
  [ -d "$BUNDLE" ] || fail "no existing $BUNDLE to fall back onto, and make-bundle-linux.sh failed - cannot proceed"
  BUILDTREE="$WORK/tree"
  bash "$ROOT/build/apply-patches.sh" "$BUILDTREE"
  make -C "$BUILDTREE" -j8 client
  mkdir -p "$BUNDLE/bin"
  cp "$BUILDTREE/sauer_client" "$BUNDLE/bin/swiftgibs"
  chmod +x "$BUNDLE/bin/swiftgibs"
  mkdir -p "$BUNDLE/data/bench"
  cp "$ROOT/tools/bench/workload-v1.dmo" "$BUNDLE/data/bench/workload-v1.dmo"
  cp "$ROOT/tools/bench/run-benchmark.sh" "$BUNDLE/run-benchmark.sh"
  chmod +x "$BUNDLE/run-benchmark.sh"
  rm -rf "$BUNDLE/bench-home"; cp -a "$ROOT/tools/bench/bench-home" "$BUNDLE/bench-home"
  ok "bundle overlaid manually (client + bench files refreshed onto the existing $BUNDLE)"
fi

CLIENT="$BUNDLE/bin/swiftgibs"
[ -x "$CLIENT" ] || fail "no client binary at $CLIENT after assembly"

# Same bundled-SDL2 preference run-benchmark.sh uses - bin/swiftgibs is a raw binary, not the
# swiftgibs.sh launcher, so a direct invocation has to set this up itself.
if [ -d "$BUNDLE/lib" ] && [ "${SWIFTGIBS_SYSTEM_SDL:-0}" != "1" ]; then
  export LD_LIBRARY_PATH="$BUNDLE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

echo
echo "== Step 2: sgbenchselftest exact-line assertion =="
SELFTEST_HOME="$WORK/selftest-home"; mkdir -p "$SELFTEST_HOME"
printf 'sgbenchselftest\nquit\n' > "$SELFTEST_HOME/selftest.cfg"
SELFTEST_LOG="$WORK/selftest.log"
RC=0
(cd "$BUNDLE" && timeout 60 "$CLIENT" -q"$SELFTEST_HOME" '-xexec selftest.cfg') > "$SELFTEST_LOG" 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "sgbenchselftest run exited $RC (expected 0 - see $SELFTEST_LOG)"

EXPECTED_SELFTEST='BENCH SELFTEST: n=10 p50=10.00 p95=30.00 p99=30.00 onepctlow=33.33 worst=30.00 stutters=1'
ACTUAL_SELFTEST="$(grep -m1 '^BENCH SELFTEST:' "$SELFTEST_LOG" || true)"
[ "$ACTUAL_SELFTEST" = "$EXPECTED_SELFTEST" ] || fail "selftest line mismatch:
  got:  [$ACTUAL_SELFTEST]
  want: [$EXPECTED_SELFTEST]
  (full log: $SELFTEST_LOG)"
ok "selftest line exact match"

echo
echo "== Step 3: sgbench workload-v1 pass via run-benchmark.sh =="
rm -f "$BUNDLE/benchresults.csv"
RUNLOG="$WORK/run-benchmark.log"
RC=0
(cd "$BUNDLE" && timeout 400 ./run-benchmark.sh 1) > "$RUNLOG" 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "run-benchmark.sh exited $RC (see $RUNLOG)"

CSV="$BUNDLE/benchresults.csv"
[ -f "$CSV" ] || fail "no benchresults.csv produced at $CSV (see $RUNLOG)"

EXPECTED_HEADER='utc,version,platform,demo,frames,seconds,avgfps,p50ms,p95ms,p99ms,onepctlow_fps,worst_ms,stutters,width,height'
ACTUAL_HEADER="$(head -n1 "$CSV")"
[ "$ACTUAL_HEADER" = "$EXPECTED_HEADER" ] || fail "CSV header mismatch:
  got:  [$ACTUAL_HEADER]
  want: [$EXPECTED_HEADER]"

LINES=$(wc -l < "$CSV")
[ "$LINES" -eq 3 ] || fail "CSV row count mismatch: expected 3 lines (header + warmup row + 1 measured row), got $LINES ($CSV)"

LASTROW="$(tail -n1 "$CSV")"
FRAMES_VAL=$(echo "$LASTROW" | cut -d, -f5)
SECONDS_VAL=$(echo "$LASTROW" | cut -d, -f6)
case "$FRAMES_VAL" in ''|*[!0-9]*) fail "frames field not a plain integer: [$FRAMES_VAL] (row: $LASTROW)";; esac
[ "$FRAMES_VAL" -gt 500 ] || fail "frames $FRAMES_VAL not > 500 (row: $LASTROW)"
awk -v s="$SECONDS_VAL" 'BEGIN { exit (s+0 < 115 || s+0 > 135) }' </dev/null || fail "seconds $SECONDS_VAL out of [115,135] (row: $LASTROW)"
ok "sgbench pass: header exact, 3 CSV lines, frames=$FRAMES_VAL seconds=$SECONDS_VAL"

echo
echo "== Step 4: normal-boot screenshot regression =="
BOOT_HOME="$WORK/boot-home"; mkdir -p "$BOOT_HOME"
# No autoexec.cfg of our own in this homedir: the engine's own findfile() falls through to the
# bundle's real shipped autoexec.cfg (nothing to shadow it here, unlike the bench profile),
# which is exactly what a normal first launch does. Our -xexec script runs AFTER that autoexec
# (engine/main.cpp: execfile(game::autoexec()) happens before the -x initscript), so it only
# needs to schedule a screenshot + quit.
cat > "$BOOT_HOME/boot.cfg" <<'EOF'
sleep 4000 [screenshot "bootcheck"]
sleep 6000 [quit]
EOF
BOOT_LOG="$WORK/boot.log"
RC=0
(cd "$BUNDLE" && timeout 60 "$CLIENT" -q"$BOOT_HOME" '-xexec boot.cfg') > "$BOOT_LOG" 2>&1 || RC=$?
[ "$RC" -eq 0 ] || fail "normal-boot run exited $RC (see $BOOT_LOG)"

SHOT="$BOOT_HOME/screenshot/bootcheck.png"
[ -f "$SHOT" ] || fail "no boot screenshot produced at $SHOT (see $BOOT_LOG)"
SHOT_BYTES=$(wc -c < "$SHOT")
[ "$SHOT_BYTES" -gt 10240 ] || fail "boot screenshot too small: $SHOT_BYTES bytes (expected >10KB - looks like a black/blank frame)"
ok "boot screenshot: $SHOT_BYTES bytes"

echo
echo "ALL PASS"
