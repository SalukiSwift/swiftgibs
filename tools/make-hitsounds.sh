#!/usr/bin/env bash
# Synthesize the SYNTH hit-sound alternates with ffmpeg.
# Mirrors the reload-metronome sound style (short sine/partials + afade + alimiter,
# libvorbis output) so the new sounds sit alongside tick_lo/tick_mid/tick_hi/ding.
#
# Output: overlay/packages/sounds/swiftgibs/hit_{custom1,custom2}.ogg
#
# NOTE: hit_tf2 / hit_quake / hit_cod are NO LONGER synthesized here. They are the
# REAL game hit sounds (TF2 default doot extracted from the game's VPK, Quake 3, and
# a CoD hitmarker), silence-trimmed + peak-normalized and committed directly to the
# overlay. Do NOT regenerate them -- this script would overwrite the real audio with
# crude synths. The remaining synths below are short, mono, 44.1kHz vorbis.
#
# Also emits streak.ogg: a short (~230ms) rising three-note flourish for the
# killstreak milestone ding (Task 5), same mono/44.1kHz/vorbis style.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/overlay/packages/sounds/swiftgibs"
mkdir -p "$OUT"

FF="ffmpeg -y -loglevel error"

# (hit_tf2, hit_quake and hit_cod are real game rips now -- committed directly, not
#  synthesized. The Unreal slot was removed entirely -- no source audio and April cut it.)

# --- hit_custom1: satisfying rising synth ping (perfect-fifth two-tone) ---
$FF -f lavfi -i "sine=f=660:d=0.05" -f lavfi -i "sine=f=990:d=0.08" \
  -filter_complex "[0][1]concat=n=2:v=0:a=1,afade=t=out:st=0.08:d=0.04,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/hit_custom1.ogg"

# --- hit_custom2: satisfying synth ping (stacked fifth chord, short decay) ---
$FF -f lavfi -i "sine=f=1046:d=0.06" -f lavfi -i "sine=f=1568:d=0.06" \
  -filter_complex "[0][1]amix=inputs=2:duration=longest,afade=t=out:st=0.02:d=0.05,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/hit_custom2.ogg"

# --- streak: killstreak milestone (rising three-note major-arpeggio flourish) ---
$FF -f lavfi -i "sine=f=523:d=0.07" -f lavfi -i "sine=f=659:d=0.07" -f lavfi -i "sine=f=784:d=0.09" \
  -filter_complex "[0][1][2]concat=n=3:v=0:a=1,afade=t=out:st=0.20:d=0.03,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/streak.ogg"

echo "wrote hit_custom1.ogg hit_custom2.ogg streak.ogg to $OUT (tf2/quake/cod are real rips, not regenerated; unreal removed)"
