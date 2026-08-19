#!/usr/bin/env bash
# Runs the SwiftGibs PACED benchmark (sgbenchpaced, patch 24): 1 warmup pass + N measured
# passes at a FIXED fps cap. Mirrors run-benchmark.sh's structure exactly - see that script's
# own header comment for the shared platform/homedir/LD_LIBRARY_PATH rationale (not repeated
# here): fresh bench-home-run/ every invocation, the same exec-shipped-autoexec chain (measure
# the SHIPPED first-run defaults, not a blank slate), the same CSV-growth-detection convention,
# no pkill anywhere (sequential single-process passes only).
#
# Usage: run-benchmark-paced.sh <passes> <capfps> [demo]
#   passes  - number of MEASURED passes (required). A warmup pass always runs first at the same
#             cap and is not counted towards this - same convention as run-benchmark.sh's own
#             warmup-then-N-measured-passes shape.
#   capfps  - the fps cap sgbenchpaced forces via setvar("maxfps", ...) for the whole run (see
#             patch 24's module comment in fpsgame/client.cpp for why this is safe to force in
#             memory and never explicitly restored).
#   demo    - demo file, relative to the bundle's data dir convention (default:
#             data/bench/workload-v1.dmo, the same canonical workload sgbench uses - patch 24
#             does not add a second workload).
#
# Results: benchpacing.csv next to this script (latest run, every pass from this invocation
# appended), plus a timestamped benchpacing-<yyyymmdd-hhmmss>.csv archive - same "keep the
# stable name AND archive under a timestamp" convention as run-benchmark.sh's
# benchresults.csv/benchresults-<ts>.csv pair. This script never touches benchresults.csv or
# its header - that is sgbench's file, untouched by patch 24 (see the design spec). bench-home-run/
# itself (where the engine actually writes benchpacing.csv first) is wiped and recreated at the
# start of every invocation, so nothing left only in there survives.
#
# sgbenchpaced has no per-pass frame-time dump (no benchframes-<row>.csv equivalent) - only the
# aggregate CSV row - so there is nothing else to archive out of bench-home-run/ here.
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: run-benchmark-paced.sh <passes> <capfps> [demo]" >&2; exit 1; }
PASSES="$1"
CAPFPS="$2"
DEMO="${3:-data/bench/workload-v1.dmo}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

case "$(uname -s)" in
  Darwin) CLIENT="$HERE/../MacOS/sauerbraten" ;;
  *)      CLIENT="$HERE/bin/swiftgibs" ;;
esac
[ -x "$CLIENT" ] || { echo "BENCH FAILED: client binary not found at $CLIENT"; exit 1; }

# Same bundled-SDL2 preference as run-benchmark.sh - bin/swiftgibs is a raw binary, not the
# swiftgibs.sh launcher, so this runner has to set up LD_LIBRARY_PATH itself.
if [ "$(uname -s)" != "Darwin" ] && [ "${SWIFTGIBS_SYSTEM_SDL:-0}" != "1" ] && [ -d "$HERE/lib" ]; then
  export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

BH="$HERE/bench-home-run"; rm -rf "$BH"; mkdir -p "$BH"
# Same exec-shipped-autoexec chain as run-benchmark.sh (see its own comment for the
# absolute-path rationale - a bare "autoexec.cfg" would re-exec itself via findfile()'s
# homedir-first lookup). A paced run still measures the shipped first-run defaults layered
# under the pinned bench overrides; sgbenchpaced itself forces maxfps for the run via setvar()
# at command-execution time (patch 24), which runs AFTER this profile's own "maxfps 0" line
# and so always wins, exactly as vsync's own pinned-last-wins comment in bench-home/autoexec.cfg
# already documents for that var.
{
  printf 'exec "%s/autoexec.cfg"\n' "$HERE"
  cat "$HERE/bench-home/autoexec.cfg"
} > "$BH/autoexec.cfg"
printf 'sgbenchpaced "%s" %s\n' "$DEMO" "$CAPFPS" > "$BH/bench.cfg"
run_pass() { "$CLIENT" -q"$BH" '-xexec bench.cfg' >/dev/null 2>&1 || true; }   # fullscreen comes from the profile, no -t flag

# Same header-exclusion counting fix as run-benchmark.sh's datarows() - benchreportpaced()
# (patch 24) writes the header and the first data row together in one openfile("a") call too,
# so counting wc -l directly would double-count the header as growth on this invocation's very
# first success.
datarows() {
  if [ -f "$1" ]; then
    local lines; lines=$(wc -l < "$1")
    echo $((lines - 1))
  else
    echo 0
  fi
}

echo "warmup pass (capfps=$CAPFPS)..."; run_pass
BEFORE=$(datarows "$BH/benchpacing.csv")
for i in $(seq 1 "$PASSES"); do echo "measured pass $i/$PASSES (capfps=$CAPFPS)..."; run_pass; done
AFTER=$(datarows "$BH/benchpacing.csv")
[ "$AFTER" -ge $((BEFORE + PASSES)) ] || { echo "BENCH FAILED: expected $PASSES new rows, got $((AFTER-BEFORE))"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%S)"
cp "$BH/benchpacing.csv" "$HERE/benchpacing.csv"
# Keep the latest results at the stable benchpacing.csv name (above) for tools/scripts that
# always read that path, but ALSO archive this invocation's full CSV under a timestamped name so
# an earlier run's rows are never silently clobbered by a later one.
cp "$BH/benchpacing.csv" "$HERE/benchpacing-$TS.csv"

# The warmup pass row is intentionally left in the CSV file - the summary below prints only
# the last N (measured) rows. Simpler than filtering, and the utc column disambiguates.
echo "== results (last $PASSES passes) =="
head -1 "$HERE/benchpacing.csv"; tail -n "$PASSES" "$HERE/benchpacing.csv"
