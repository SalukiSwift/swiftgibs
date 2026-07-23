#!/usr/bin/env bash
# Synthesize the SwiftGibs respawn-ready pip (Task 7: auto-respawn + ready pip).
# Same ogg format/loudness discipline as tools/make-hitsounds.sh and the reload
# metronome ticks (fpsgame/fps.cpp updatereloadmetronome(), tick_lo/mid/hi/ding
# in this same directory) -- short synth tone(s), soft afade in/out, alimiter,
# mono 44.1kHz libvorbis -- but deliberately SUBTLE: this fires once,
# automatically, the instant a dead player becomes eligible to respawn
# (respawnreadysound VARP), so it must sit at the quiet/low-attention end of
# the existing sound set. Contrast with hit_custom1/hit_custom2/streak above,
# which push alimiter level_in=2 to be loud and attention-grabbing on purpose --
# this one stays at level_in=1 (no boost) plus an explicit volume cut, and is
# shorter and softer-attacked than even the quietest metronome tick.
#
# Output: overlay/packages/sounds/swiftgibs/respawnready.ogg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/overlay/packages/sounds/swiftgibs"
mkdir -p "$OUT"

FF="ffmpeg -y -loglevel error"

# Single soft sine pip, 150ms total: 20ms fade-in (soft attack, no click),
# fade-out starting at 50ms and trailing to silence by 150ms. Held quiet
# (volume 0.45 cut before a non-boosting alimiter) so it reads as a gentle
# notification, not a hit/streak-style cue.
$FF -f lavfi -i "sine=f=740:d=0.15" \
  -filter_complex "afade=t=in:st=0:d=0.02,afade=t=out:st=0.05:d=0.10,volume=0.45,alimiter=level_in=1" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/respawnready.ogg"

echo "wrote respawnready.ogg to $OUT"
