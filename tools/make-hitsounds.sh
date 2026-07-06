#!/usr/bin/env bash
# Synthesize the six selectable hit-sound alternates with ffmpeg.
# Mirrors the reload-metronome sound style (short sine/partials + afade + alimiter,
# libvorbis output) so the new sounds sit alongside tick_lo/tick_mid/tick_hi/ding.
#
# Output: overlay/packages/sounds/swiftgibs/hit_{tf2,quake,unreal,cod,custom1,custom2}.ogg
# All six are short (<250ms), punchy, mono, 44.1kHz vorbis - matching the existing
# swiftgibs sound assets.
#
# Also emits streak.ogg: a short (~230ms) rising three-note flourish for the
# killstreak milestone ding (Task 5), same mono/44.1kHz/vorbis style.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/overlay/packages/sounds/swiftgibs"
mkdir -p "$OUT"

FF="ffmpeg -y -loglevel error"

# --- hit_tf2: bright rising two-tone ding (TF2-style crit/hit ding) ---
$FF -f lavfi -i "sine=f=880:d=0.05" -f lavfi -i "sine=f=1320:d=0.06" \
  -filter_complex "[0][1]concat=n=2:v=0:a=1,afade=t=out:st=0.09:d=0.02,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/hit_tf2.ogg"

# --- hit_quake: short sharp blip (single quick sine burst) ---
$FF -f lavfi -i "sine=f=1400:d=0.05" \
  -af "afade=t=out:st=0.03:d=0.02,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/hit_quake.ogg"

# --- hit_unreal: metallic tink (two dissonant close-frequency partials ringing out) ---
$FF -f lavfi -i "sine=f=2400:d=0.08" -f lavfi -i "sine=f=3100:d=0.08" \
  -filter_complex "[0][1]amix=inputs=2:duration=longest,afade=t=out:st=0.02:d=0.06,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/hit_unreal.ogg"

# --- hit_cod: dry click-thap (filtered noise burst, no tonal ring) ---
$FF -f lavfi -i "anoisesrc=d=0.04:c=pink:r=44100:a=0.9" \
  -af "lowpass=f=3000,afade=t=out:st=0.01:d=0.03,alimiter=level_in=2" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/hit_cod.ogg"

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

echo "wrote hit_tf2.ogg hit_quake.ogg hit_unreal.ogg hit_cod.ogg hit_custom1.ogg hit_custom2.ogg streak.ogg to $OUT"
