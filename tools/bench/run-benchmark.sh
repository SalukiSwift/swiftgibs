#!/usr/bin/env bash
# Runs the SwiftGibs benchmark: 1 warmup pass + N measured passes (default 3).
# Usage: run-benchmark.sh [passes]. Results: benchresults.csv next to this script (latest run),
# plus a timestamped benchresults-<yyyymmdd-hhmmss>.csv archive and any benchframes-<row>.csv
# per-frame dumps copied out under the same timestamp prefix - both also land next to this
# script. bench-home-run/ itself (where the engine actually writes those files first) is wiped
# and recreated at the start of every invocation, so nothing left only in there survives.
#
# Shared between the Linux and Mac bundles (both platform bundlers copy this same file to
# their bundle root / Contents/Resources - see build/make-bundle-{linux,mac}.sh). The two
# platforms differ in where the client binary lives and whether the process needs an explicit
# cd first:
#   - Linux: binary is bin/swiftgibs, and the engine resolves data/ + packages/ relative to
#     the process's cwd with no argv0/basepath logic at all (confirmed empirically in Task
#     1/2 of this plan - every headless run there had to cd into the bundle dir first, or the
#     engine fails with "could not find core textures").
#   - Mac: binary is Contents/MacOS/sauerbraten, one level up from Contents/Resources (where
#     this script and data/ both live). patches/13-mac-datadir.patch makes the engine chdir to
#     SDL_GetBasePath() itself at startup, so this script's own cwd doesn't matter there - but
#     cd-ing first is harmless and keeps one code path for both platforms.
set -euo pipefail
PASSES="${1:-3}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

case "$(uname -s)" in
  Darwin) CLIENT="$HERE/../MacOS/sauerbraten" ;;
  *)      CLIENT="$HERE/bin/swiftgibs" ;;
esac
[ -x "$CLIENT" ] || { echo "BENCH FAILED: client binary not found at $CLIENT"; exit 1; }

# Linux bundle ships its own lean SDL2 runtime in lib/ (see make-bundle-linux.sh) so it runs
# on a machine with no SDL2 installed; bin/swiftgibs is not a launcher script (unlike
# swiftgibs.sh) so this runner has to set the same LD_LIBRARY_PATH preference itself.
# SWIFTGIBS_SYSTEM_SDL=1 is the same escape hatch swiftgibs.sh offers.
if [ "$(uname -s)" != "Darwin" ] && [ "${SWIFTGIBS_SYSTEM_SDL:-0}" != "1" ] && [ -d "$HERE/lib" ]; then
  export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

BH="$HERE/bench-home-run"; rm -rf "$BH"; mkdir -p "$BH"
# The benchmark must measure the SHIPPED SwiftGibs config, not an isolated blank slate: build
# bench-home-run/autoexec.cfg by execing the bundle's real staged autoexec.cfg FIRST (this is
# what sets the shipped first-run defaults - shaderdetail, blood, ragdoll, hidedead,
# forceplayermodels, swiftgibsversion, etc.), THEN appending this repo's pinned bench
# overrides on top, exactly as bench-home/autoexec.cfg's own top comment documents.
#
# The exec target must be an ABSOLUTE path, not the bare filename "autoexec.cfg": the engine's
# findfile() (shared/stream.cpp) always checks the -q homedir FIRST for any bare filename, and
# this generated file IS bench-home-run/autoexec.cfg - a bare `exec "autoexec.cfg"` from
# inside it would just find and re-exec itself (infinite recursion). An absolute path dodges
# this: findfile()'s homedir-prefix check concatenates homedir+filename, which garbles an
# absolute path into a nonexistent string, so that check fails and falls through to its own
# final fallback of returning the filename exactly as given - fopen() then resolves that
# absolute path correctly, regardless of cwd or homedir.
{
  printf 'exec "%s/autoexec.cfg"\n' "$HERE"
  cat "$HERE/bench-home/autoexec.cfg"
} > "$BH/autoexec.cfg"
printf 'sgbench "data/bench/workload-v1.dmo"\n' > "$BH/bench.cfg"
run_pass() { "$CLIENT" -q"$BH" '-xexec bench.cfg' >/dev/null 2>&1 || true; }   # fullscreen comes from the profile, no -t flag

# Data-row count only (excludes the header line): benchreport() (patch 22) always writes the
# header and that row's data together in one openfile("a") call, so the CSV is either absent
# (0 data rows) or has a header plus >=1 data row - never a bare header. Counting wc -l directly
# double-counts the header as if it were a row of growth: on this invocation's very first
# success (BEFORE captured right after the warmup pass, when the file has just been created for
# the first time), that one extra line let PASSES-1 real measured successes still satisfy
# `AFTER >= BEFORE + PASSES` - a silently-too-lenient gate. Subtracting the header fixes it.
datarows() {
  if [ -f "$1" ]; then
    local lines; lines=$(wc -l < "$1")
    echo $((lines - 1))
  else
    echo 0
  fi
}

echo "warmup pass..."; run_pass
BEFORE=$(datarows "$BH/benchresults.csv")
for i in $(seq 1 "$PASSES"); do echo "measured pass $i/$PASSES..."; run_pass; done
AFTER=$(datarows "$BH/benchresults.csv")
[ "$AFTER" -ge $((BEFORE + PASSES)) ] || { echo "BENCH FAILED: expected $PASSES new rows, got $((AFTER-BEFORE))"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%S)"
cp "$BH/benchresults.csv" "$HERE/benchresults.csv"
# Keep the latest results at the stable benchresults.csv name (above) for tools/scripts that
# always read that path, but ALSO archive this invocation's full CSV under a timestamped name so
# an earlier run's rows are never silently clobbered by a later one.
cp "$BH/benchresults.csv" "$HERE/benchresults-$TS.csv"

# benchframes-<row>.csv (per-pass raw frame-time dumps, one ms value per line - see
# benchdumpframes in patch 22, on by default) live inside bench-home-run, which the very next
# invocation's `rm -rf "$BH"` above wipes unconditionally. Copy every dump out next to
# benchresults.csv, under this invocation's timestamp, before it's lost.
shopt -s nullglob
for f in "$BH"/benchframes-*.csv; do
  base="$(basename "$f")"                       # benchframes-<row>.csv
  cp "$f" "$HERE/benchframes-$TS-${base#benchframes-}"
done
shopt -u nullglob

# The warmup pass row is intentionally left in the CSV file - the summary below prints only
# the last N (measured) rows. Simpler than filtering, and the utc column disambiguates.
echo "== results (last $PASSES passes) =="
head -1 "$HERE/benchresults.csv"; tail -n "$PASSES" "$HERE/benchresults.csv"
