#!/usr/bin/env bash
# Runs the SwiftGibs benchmark: 1 warmup pass + N measured passes (default 3).
# Usage: run-benchmark.sh [passes]. Results: benchresults.csv next to this script.
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
echo "warmup pass..."; run_pass
BEFORE=$(wc -l < "$BH/benchresults.csv" 2>/dev/null || echo 0)
for i in $(seq 1 "$PASSES"); do echo "measured pass $i/$PASSES..."; run_pass; done
AFTER=$(wc -l < "$BH/benchresults.csv" 2>/dev/null || echo 0)
[ "$AFTER" -ge $((BEFORE + PASSES)) ] || { echo "BENCH FAILED: expected $PASSES new rows, got $((AFTER-BEFORE))"; exit 1; }
cp "$BH/benchresults.csv" "$HERE/benchresults.csv"
# The warmup pass row is intentionally left in the CSV file - the summary below prints only
# the last N (measured) rows. Simpler than filtering, and the utc column disambiguates.
echo "== results (last $PASSES passes) =="
head -1 "$HERE/benchresults.csv"; tail -n "$PASSES" "$HERE/benchresults.csv"
