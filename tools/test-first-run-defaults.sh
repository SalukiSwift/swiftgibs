#!/usr/bin/env bash
# Regression guard for overlay/autoexec.cfg's FIRST-RUN DEFAULTS block and its VERSIONED UPGRADE
# STEPS. Boots a REAL headless client once per scenario against a scratch home dir that holds the
# repo's overlay cfgs plus a per-scenario config.cfg, has it print the values it ended up with and
# quit, then asserts on both the live values (echoed by the -x init script, which the engine runs
# after config.cfg and autoexec.cfg) and the config.cfg the quit wrote back (what the NEXT launch
# will load). Scenarios:
#   1. fresh install (no config.cfg): the first-run block runs and stamps the current schema
#      version, so no upgrade step ever fires for a new player
#   2. returning player on an old schema: every step above their version forces its new default
#      exactly once and the stamp lands on the current version
#   3. returning player already on the current version who chose otherwise: left alone
# Usage: CLIENT=<sauer_client binary> DATA=<dir holding data/ and packages/> tools/test-first-run-defaults.sh
#   DATA may be an official 2020 Sauerbraten install or an assembled SwiftGibs bundle; only
#   data/stdlib.cfg, the fonts and data/menus.cfg are needed to boot to the init script (missing
#   SwiftGibs sounds just log an error). The client runs under tools/headless-client.sh (offscreen
#   video, dummy audio - never a real audio device under WSLg).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="${CLIENT:-}"
DATA="${DATA:-}"
[ -n "$CLIENT" ] && [ -x "$CLIENT" ] || { echo "usage: CLIENT=<sauer_client binary> DATA=<data dir> $0"; exit 2; }
[ -n "$DATA" ] && [ -f "$DATA/data/stdlib.cfg" ] || { echo "DATA must hold data/stdlib.cfg (official install or SwiftGibs bundle)"; exit 2; }
TMP="$(mktemp -d /tmp/sg-firstrun-$$-XXXX)"
trap 'rm -rf "$TMP"' EXIT

# The client searches its home dir first and then the -k package dir for EVERY file, config.cfg
# included, so a DATA that is a real install (whose root holds the owner's config.cfg and
# autoexec.cfg) would quietly feed those to the "fresh" scenario. Hand -k a clean dir that holds
# only the game data, so the scratch home dir is the one and only place a config can come from.
PKG="$TMP/pkg"
mkdir -p "$PKG"
ln -s "$DATA/data" "$PKG/data"
ln -s "$DATA/packages" "$PKG/packages"

# The schema version the first-run block stamps and the newest upgrade step lands on. Bump it in
# the same commit that adds a step, together with the rows below that spell out what that step
# must force.
CURRENT=5

# run_scenario <name> <config.cfg body or "-" for none>: boots the client with a fresh home dir,
# prints the SGTEST line it echoed, leaves the written-back config.cfg at $TMP/<name>/config.cfg.
run_scenario() {
  local name="$1" cfg="$2"
  local home="$TMP/$name"
  mkdir -p "$home"
  cp "$ROOT"/overlay/*.cfg "$home/"
  [ "$cfg" = "-" ] || printf '%s\n' "$cfg" > "$home/config.cfg"
  # -x runs last in init, after config.cfg and autoexec.cfg; quit writes config.cfg back and exits.
  local script='echo SGTEST (concatword setup= $swiftgibs_setup) (concatword clicktab= $guiclicktab) (concatword autospec= $autospecidle) (concatword clip= $cliplength); quit'
  ( cd "$home" && timeout 120 "$ROOT/tools/headless-client.sh" "$CLIENT" -k"$PKG" -q"$home" -x"$script" > "$home/run.log" 2>&1 ) || true
  grep -m1 '^SGTEST ' "$home/run.log" || { echo "FAIL: $name: the client never reached the init script; last lines:"; tail -5 "$home/run.log"; return 1; }
}

# expect_live <name> <live line> <field=value>...: every field must appear as a whole token of the
# live SGTEST line (so clicktab=1 never matches clicktab=10).
expect_live() {
  local name="$1" line="$2"; shift 2
  local ok=0 f tok found
  for f in "$@"; do
    found=0
    for tok in $line; do [ "$tok" = "$f" ] && found=1; done
    if [ "$found" = "1" ]; then echo "  ok   $name: live $f"
    else echo "  FAIL $name: live wanted $f, got: ${line#SGTEST }"; ok=1; fi
  done
  return $ok
}

# expect_saved <name> <regex>...: every regex must match a line of the config.cfg the quit wrote.
expect_saved() {
  local name="$1"; shift
  local ok=0 r cfg="$TMP/$name/config.cfg"
  [ -f "$cfg" ] || { echo "  FAIL $name: quit wrote no config.cfg"; return 1; }
  for r in "$@"; do
    if grep -q -E -- "$r" "$cfg"; then echo "  ok   $name: saved /$r/"
    else echo "  FAIL $name: saved config.cfg has no line matching /$r/"; ok=1; fi
  done
  return $ok
}

FAILED=0
echo "== first-run defaults and upgrade steps (schema v$CURRENT) =="

# 1. fresh install: no config.cfg at all
line="$(run_scenario fresh -)" || FAILED=1
expect_live fresh "$line" "setup=$CURRENT" clicktab=1 autospec=60 clip=20 || FAILED=1
expect_saved fresh "^swiftgibs_setup = \[$CURRENT\]\$" '^guiclicktab 1$' || FAILED=1

# 2a. returning player on schema v1: every later step must fire, oldest first
line="$(run_scenario returning-v1 $'swiftgibs_setup = 1\nautospecidle 0\ncliplength 1\nguiclicktab 0')" || FAILED=1
expect_live returning-v1 "$line" "setup=$CURRENT" clicktab=1 autospec=60 clip=20 || FAILED=1
expect_saved returning-v1 "^swiftgibs_setup = \[$CURRENT\]\$" '^guiclicktab 1$' || FAILED=1

# 2b. returning player on the previous schema (every SwiftGibs install before click tabs): only the
#     click-tab step fires, nothing older is re-forced
line="$(run_scenario returning-v4 $'swiftgibs_setup = 4\nautospecidle 45\ncliplength 30\nguiclicktab 0')" || FAILED=1
expect_live returning-v4 "$line" "setup=$CURRENT" clicktab=1 autospec=45 clip=30 || FAILED=1
expect_saved returning-v4 "^swiftgibs_setup = \[$CURRENT\]\$" '^guiclicktab 1$' || FAILED=1

# 3. returning player already current who switched hover tabs back on: their choice persists
line="$(run_scenario current-hover $'swiftgibs_setup = '"$CURRENT"$'\nguiclicktab 0')" || FAILED=1
expect_live current-hover "$line" "setup=$CURRENT" clicktab=0 || FAILED=1
expect_saved current-hover "^swiftgibs_setup = \[$CURRENT\]\$" '^guiclicktab 0$' || FAILED=1

[ "$FAILED" = "0" ] || { echo "FAILED: see the FAIL lines above"; exit 1; }
echo "ALL SCENARIOS PASS"
