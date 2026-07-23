#!/usr/bin/env bash
# Synthesize the SwiftGibs respawn-ready countdown (Task 7: auto-respawn + ready
# pip; Task 8: 3-2-1 countdown tones ahead of it). Same ogg format/loudness
# discipline as tools/make-hitsounds.sh and the reload metronome ticks
# (fpsgame/fps.cpp updatereloadmetronome(), tick_lo/mid/hi/ding in this same
# directory) -- short synth tone(s), soft afade in/out, alimiter, mono
# 44.1kHz libvorbis -- but this whole family is deliberately SUBTLE: it plays
# automatically while a player is already dead and waiting, so it must sit at
# the quiet/low-attention end of the existing sound set. Contrast with
# hit_custom1/hit_custom2/streak, which push alimiter level_in=2 to be loud
# and attention-grabbing on purpose -- everything here stays at level_in=1
# (no boost) plus an explicit volume cut.
#
# Two outputs, played by checkautorespawn() (patches/16-profiles.patch):
#   respawncount.ogg  - three soft LOW tones at T-3s/T-2s/T-1s before the
#                        estimated respawn-ready moment (the "3-2-1"). A
#                        220Hz+110Hz blend, lowpassed to 550Hz for a muted/
#                        filtered thud, clearly lower-pitched and softer than
#                        both the metronome ticks (884-1573Hz, measured via
#                        FFT) and respawnready.ogg itself (740Hz) -- and
#                        1-second spaced rather than the metronome's
#                        500ms-spaced rising ticks+ding, so the two cues
#                        can't be confused for each other.
#   respawnready.ogg  - unchanged from Task 7: the brighter "go" tone played
#                        once, right when a respawn attempt should actually
#                        succeed. Regenerated here byte-for-byte equivalent
#                        (libvorbis re-encodes with a fresh random stream
#                        serial each run, so a diff is expected even though
#                        the audio content and volumedetect numbers are
#                        identical) -- kept in this script for the record
#                        and for anyone who needs to regenerate the whole
#                        family from scratch.
#
# Output: overlay/packages/sounds/swiftgibs/{respawncount,respawnready}.ogg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/overlay/packages/sounds/swiftgibs"
mkdir -p "$OUT"

FF="ffmpeg -y -loglevel error"

# --- respawncount.ogg: one soft low countdown tone, 120ms total ---
# 220Hz sine (main) blended with a 110Hz sine (sub, quieter) for a rounder
# "thud" rather than a thin single-pitch beep, then lowpassed at 550Hz to
# strip it toward a muted/filtered character. 18ms fade-in (soft attack, no
# click), fade-out from 45ms trailing to silence by 120ms. volume 0.62 before
# a non-boosting alimiter keeps it at-or-below respawnready.ogg's loudness
# (measured via -af volumedetect: respawncount.ogg mean -35.6dB/max -27.5dB
# vs respawnready.ogg mean -31.2dB/max -24.9dB -- both quieter on both
# measures, matching the "soft" half of the brief).
$FF -f lavfi -i "sine=f=220:d=0.12" -f lavfi -i "sine=f=110:d=0.12" \
  -filter_complex "[0:a]volume=0.7[a];[1:a]volume=0.5[b];[a][b]amix=inputs=2:duration=first:dropout_transition=0,lowpass=f=550,afade=t=in:st=0:d=0.018,afade=t=out:st=0.045:d=0.075,volume=0.62,alimiter=level_in=1" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/respawncount.ogg"

# --- respawnready.ogg: single soft sine "go" pip, 150ms total (Task 7, unchanged) ---
# 20ms fade-in (soft attack, no click), fade-out starting at 50ms and
# trailing to silence by 150ms. Held quiet (volume 0.45 cut before a
# non-boosting alimiter) so it reads as a gentle notification, not a
# hit/streak-style cue -- and noticeably brighter/higher (740Hz, single pure
# tone) than the three low countdown tones above, so it reads as the
# distinct "go" moment rather than a fourth countdown beat.
$FF -f lavfi -i "sine=f=740:d=0.15" \
  -filter_complex "afade=t=in:st=0:d=0.02,afade=t=out:st=0.05:d=0.10,volume=0.45,alimiter=level_in=1" \
  -c:a libvorbis -q:a 4 -ar 44100 -ac 1 "$OUT/respawnready.ogg"

echo "wrote respawncount.ogg and respawnready.ogg to $OUT"
