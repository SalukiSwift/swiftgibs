#!/usr/bin/env bash
# Lists sound files in the official data referenced by nothing (safe to strip).
#
# A sound file is DEAD only if nothing references it: not registered/alt-registered
# in data/sounds.cfg (order-indexed hardcoded cube sounds; cfg lines themselves are
# never removed by this scan), not a mapsound/altmapsound in any official
# packages/**/*.cfg (streamed maps must keep working), and not a string literal in
# vendor+patched game code (fpsgame). Conservative by design: correctness beats
# megabytes, so anything ambiguous counts as "referenced".
#
# Pattern notes vs. the original draft:
#
# 1. Added `altmapsound` to the cfg-command alternation below. engine/sound.cpp
#    defines it as the mapsound analogue of altsound (COMMAND(altmapsound, "si"))
#    but the official 2020 data has zero calls to it today -- so this is a
#    latent-gap fix (a real reference class the original pattern didn't cover),
#    not one that changes current output.
#
# 2. Added a dynamic-directory pass (DYNDIRS below). packages/base/triforts.cfg
#    builds its ambience mapsound names at runtime via concatword:
#      mapsound (concatword "razgriz/" $arg2 ".ogg") (...) $arg4
#      setmapsound 0 "ambient_night_01" 70 -1
#      setmapsound 1 "energy_hum_01"    100 -1   ... (15 total)
#    The literal string this scan can grep is just "razgriz/" -- the actual
#    filename is assembled at cfg-eval time from $arg2, which a static line-based
#    scan cannot resolve. Without this pass, all 15 files under
#    packages/sounds/razgriz/ were false-positived as dead (verified by hand:
#    every one of them is a real setmapsound call target in triforts.cfg). Since
#    we can't resolve the exact filename, we conservatively keep the WHOLE
#    directory that concatword builds paths under. Spot-checked: this is the only
#    concatword+mapsound/altmapsound construction anywhere in the official 2020
#    data (confirmed by grepping every concatword call in data/ and packages/ for
#    one that's also in a file using mapsound/altmapsound); the many other
#    concatword calls in the data build alias names, chat strings, etc, not sound
#    paths.
#
# Everything else (registersound/altsound/mapsound coverage, fpsgame-only code
# scan) was spot-checked against the real official data and patched tree and
# left as-is: rpggame/rpg.cpp also has a couple of hardcoded sound-name literals,
# but rpggame is not compiled into the client (absent from the Makefile's
# CLIENT_OBJS) and every sound it names (aard/jump, aard/land, free/splash1,
# free/splash2) is already registered in data/sounds.cfg regardless, so widening
# the code scan there would not change the result.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$("$ROOT/build/fetch-official-data.sh")}"
TREE="${TREE:?apply-patches tree with patched fpsgame sources}"   # for code refs
REFS=/tmp/sg-sndscan-$$-refs.txt
DYNDIRS=/tmp/sg-sndscan-$$-dyndirs.txt
: > "$REFS"
: > "$DYNDIRS"
# cfg references: registersound/altsound/mapsound/altmapsound paths (first quoted or bare token after the command)
grep -rhoE '(registersound|altsound|mapsound|altmapsound)[[:space:]]+"?[^"[:space:]]+' \
  "$SRC/data" "$SRC/packages" | sed -E 's/^[a-z]+[[:space:]]+"?//' >> "$REFS"
# code references: any quoted string containing a '/' under fpsgame (covers game-registered paths)
grep -rhoE '"[A-Za-z0-9_/ .-]+/[A-Za-z0-9_/ .-]+"' "$TREE/fpsgame" | tr -d '"' >> "$REFS"
sort -u "$REFS" -o "$REFS"
# dynamic cfg references: mapsound/altmapsound whose filename is built by concatword
# from a literal directory prefix (see note 2 above) -- keep the whole directory.
grep -rhoE '(mapsound|altmapsound)[[:space:]]*\([[:space:]]*concatword[[:space:]]+"[A-Za-z0-9_/-]*/"' \
  "$SRC/data" "$SRC/packages" | grep -oE '"[A-Za-z0-9_/-]*/"' | tr -d '"' | sort -u >> "$DYNDIRS"
find "$SRC/packages/sounds" -type f \( -iname '*.ogg' -o -iname '*.wav' \) | while read -r f; do
  rel="${f#"$SRC/"}"                                  # packages/sounds/author/file.ogg
  base="${rel#packages/sounds/}"; base="${base%.*}"   # author/file  (cfg refs omit dir+ext)
  if grep -qF "$base" "$REFS"; then continue; fi
  dyn=0
  while read -r dir; do
    [ -z "$dir" ] && continue
    case "$base" in "$dir"*) dyn=1; break ;; esac
  done < "$DYNDIRS"
  [ "$dyn" = 1 ] && continue
  echo "$rel"
done | sort
rm -f "$REFS" "$DYNDIRS"
