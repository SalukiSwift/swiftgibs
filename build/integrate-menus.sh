#!/usr/bin/env bash
# Attach the SwiftGibs / Cues / Audio / Clips / Friends tabs to the stock Esc->options gui by splicing five literal lines
# (which call aliases defined in overlay/menus_settings.cfg) into the staged data/menus.cfg, right
# before the options gui's closing `] "game"`. Also performs build-time surgery on six stock options
# rows that clash with settings SwiftGibs manages itself (player brightness, forced player models,
# hit-crosshair markers, the built-in crosshair picker, bilinear filtering, the chat-console checkbox)
# so a fresh stock data/menus.cfg can never silently ship those foot-guns next to SwiftGibs' own tabs.
# Also strips the stock singleplayer campaign menu (main-menu "campaign.." button + the campaign/
# armyofone/privatestansauer guis) - SwiftGibs is multiplayer-instagib-only, so those rows/guis and
# the bot-only singleplayer maps they point at have no use here.
# Idempotent (splice + surgery are gated on the same "already integrated" check). The splice heredoc
# writes to disk immediately, but the surgery heredoc below only writes after all its checks pass, so
# a run interrupted (or a surgery pattern that failed to match) between the two steps can leave a
# staged menus.cfg that is spliced but NOT surgered. The tab-splice marker alone is therefore not
# proof the file is fully integrated: a re-run below re-verifies surgery completion (all ten leftover
# patterns absent and the replacement pointer row present) before trusting the marker, and if the file
# is spliced-but-not-surgered it completes the surgery step (safe to re-run: its patterns match
# pre-surgery text) rather than silently reporting success.
# Usage: integrate-menus.sh <staged-root-containing-data/menus.cfg>
set -euo pipefail
ROOT="${1:?staged root}"
M="$ROOT/data/menus.cfg"
[ -f "$M" ] || { echo "integrate-menus: no $M"; exit 1; }

SPLICE_DONE=0
if grep -q 'guitab "SwiftGibs"' "$M"; then SPLICE_DONE=1; fi

if [ "$SPLICE_DONE" = "1" ]; then
    # Marker present: don't trust it blindly, verify the surgery step actually completed too.
    if python3 - "$M" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
leftovers = [
    b"fullbrightmodels",
    b'guicheckbox "force matching player models" forceplayermodels',
    b'guicheckbox "hits" hitcrosshair',
    b'guibutton "crosshair: "',
    b'guicheckbox "bilinear filtering"',
    b'guicheckbox "chat console" miniconfilter',
    b'showgui campaign',
    b'"sp lost"',
    b'newgui armyofone',
    b'newgui privatestansauer',
]
pointer = b'guitext "^f4player brightness is tuned for SwiftGibs flat colours"'
ok = all(b.count(pat) == 0 for pat in leftovers) and b.count(pointer) >= 1
sys.exit(0 if ok else 1)
PY
    then
        echo "integrate-menus: already integrated"; exit 0
    fi
    echo "integrate-menus: staged menus.cfg is spliced but not surgered (previous run interrupted?) - completing surgery" >&2
else
    python3 - "$M" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
nl = b"\r\n" if b"\r\n" in b else b"\n"
anchor = b'showfileeditor "autoexec.cfg" -64 13'   # last item of the stock options gui
i = b.find(anchor)
assert i >= 0, "integrate-menus: options anchor (showfileeditor autoexec.cfg) not found — data/menus.cfg changed?"
close = b.find(b'] "game"', i)                     # the options gui closing bracket after the anchor
assert close >= 0, "integrate-menus: options closing `] \"game\"` not found after anchor"
ins = (b'    guitab "SwiftGibs"' + nl + b'    sgSwiftgibsTab' + nl +
       b'    guitab "Cues"' + nl + b'    sgCuesTab' + nl +
       b'    guitab "Audio"' + nl + b'    sgAudioTab' + nl +
       b'    guitab "Clips"' + nl + b'    sgClipsTab' + nl +
       b'    guitab "Friends"' + nl + b'    sgFriendsTab' + nl)
open(p, "wb").write(b[:close] + ins + b[close:])
print("integrate-menus: attached SwiftGibs + Cues + Audio + Clips + Friends tabs to", p)
PY
fi

# --- Stock options surgery + campaign menu gut ------------------------------
# Also runs to complete a spliced-but-not-surgered file left behind by an interrupted prior run
# (see the SPLICE_DONE branch above) - safe to re-run because every pattern below still matches
# pre-surgery text exactly once in that case.
# Six stock options rows clash with settings SwiftGibs manages itself (its own player-brightness
# controls, forced-model/hitmarker/crosshair/filtering behaviour that would otherwise fight the
# SwiftGibs tabs). Remove/replace them here, on the STAGED copy only, never edit vendor/ or a real
# install. Four more entries gut the singleplayer campaign menu (main-menu button + the campaign/
# armyofone/privatestansauer guis) - SwiftGibs is multiplayer-only. Every pattern below must match
# EXACTLY ONCE; a miss means the stock data/menus.cfg changed shape, so this fails loudly (exit 1)
# rather than silently shipping un-surgered rows.
python3 - "$M" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
nl = b"\r\n" if b"\r\n" in b else b"\n"

def block(*lines):
    return nl.join(lines)

before_guitab_count = b.count(b"guitab ")
before_crosshairsize_count = b.count(b"guislider crosshairsize")

# (label, old, new): old must appear exactly once in the file; new (b"" removes cleanly) replaces it.
surgeries = [
    ("game tab: fullbrightmodels checkbox+4 radios -> single pointer row", block(
        b'    guilist [',
        b'        guicheckbox "fullbright player models" fullbrightmodels 60 0',
        b'        if $fullbrightmodels [',
        b'            guibar',
        b'            guiradio "subtle" fullbrightmodels 60',
        b'            guibar',
        b'            guiradio "bright" fullbrightmodels 100',
        b'            guibar',
        b'            guiradio "overbright" fullbrightmodels 150',
        b'            guibar',
        b'            guiradio "max" fullbrightmodels 200',
        b'        ]',
        b'    ]',
    ), block(
        b'    guitext "^f4player brightness is tuned for SwiftGibs flat colours"',
    )),
    ("game tab: forceplayermodels checkbox removed (keep teamskins)", block(
        b'    guilist [',
        b'        guicheckbox "force matching player models" forceplayermodels',
        b'        guibar',
        b'        guicheckbox "always use team skins" teamskins',
        b'    ]',
    ), block(
        b'    guilist [',
        b'        guicheckbox "always use team skins" teamskins',
        b'    ]',
    )),
    ("hud tab: hitcrosshair checkbox removed (keep crosshairfx/crosshaircolors/teamcrosshair)", block(
        b'    guilist [',
        b'        guicheckbox "crosshair effects" crosshairfx',
        b'        if $crosshairfx [',
        b'            guibar',
        b'            guicheckbox "health colors" crosshaircolors',
        b'            guibar',
        b'            guicheckbox "teammates" teamcrosshair',
        b'            guibar',
        b'            guicheckbox "hits" hitcrosshair 425',
        b'        ]',
        b'    ]',
    ), block(
        b'    guilist [',
        b'        guicheckbox "crosshair effects" crosshairfx',
        b'        if $crosshairfx [',
        b'            guibar',
        b'            guicheckbox "health colors" crosshaircolors',
        b'            guibar',
        b'            guicheckbox "teammates" teamcrosshair',
        b'        ]',
        b'    ]',
    )),
    ("mouse tab: crosshair picker button+image removed (keep guislider crosshairsize + the crosshair gui)", block(
        b'    guilist [',
        b'        guibutton "crosshair: " [showgui crosshair]',
        b'        guiimage (getcrosshair) [showgui crosshair] 0.5',
        b'    ]',
    ) + nl, b""),
    ("display tab: bilinear filtering checkbox removed (keep trilinear)", block(
        b'    guilist [',
        b'        guicheckbox "bilinear filtering" bilinear',
        b'        guibar',
        b'        guicheckbox "trilinear filtering (mipmaps)" trilinear',
        b'    ]',
    ), block(
        b'    guilist [',
        b'        guicheckbox "trilinear filtering (mipmaps)" trilinear',
        b'    ]',
    )),
    ("console tab: chat console (miniconfilter) checkbox removed", block(
        b'    guicheckbox "chat console" miniconfilter 0x300 0',
    ) + nl, b""),
    ("main menu: campaign button removed", block(
        b'        guibutton "campaign.."       "showgui campaign"',
    ) + nl, b""),
    ("campaign gui removed", block(
        b'newgui campaign [',
        b'    guibutton "start Private Stan Sauer"           "showgui privatestansauer"',
        b'    guibutton "start An Army Of One"               "showgui armyofone"',
        b'    guibutton "start Lost"                         "sp lost" "cube"',
        b'    guibutton "start Meltdown"                     "sp skrsp1" "cube"',
        b'    guibutton "start Missile Pass"                 "sp crnsp1" "cube"',
        b'    guibutton "start Level 9"                      "sp level9" "cube"',
        b'    guibar',
        b'    guibutton "start DMSP map.."                   "mode -2; showgui maps"',
        b'    guicheckbox "slow motion"                      "slowmosp"',
        b'    guitext   "skill (default: 3)"',
        b'    guislider skill',
        b']',
    ) + nl, b""),
    ("armyofone gui removed", block(
        b'newgui armyofone [',
        b'    guilist [',
        b'        guilist [',
        b'            guibutton "Part I"   "sp mpsp6a" "cube"',
        b'            guibutton "Part II"  "sp mpsp6b" "cube"',
        b'            guibutton "Part III" "sp mpsp6c" "cube"',
        b'        ]',
        b'        showmapshot (substr $guirolloveraction 3)',
        b'    ]',
        b'] "An Army Of One"',
    ) + nl, b""),
    ("privatestansauer gui removed", block(
        b'newgui privatestansauer [',
        b'    guilist [',
        b'        guilist [',
        b'            guibutton "Run N\' Gun Part I"        "sp mpsp9a" "cube"',
        b'            guibutton "Run N\' Gun Part II"       "sp mpsp9b" "cube"',
        b'            guibutton "Run N\' Gun Part III"      "sp mpsp9c" "cube"',
        b'            guibutton "THE SERIOUSLY BIG VALLEY" "sp mpsp10" "cube"',
        b'        ]',
        b'        showmapshot (substr $guirolloveraction 3)',
        b'    ]',
        b'] "Private Stan Sauer"',
    ) + nl, b""),
]

# NOT surgered, deliberately: data/menus.cfg's own `spmaps`/`allmaps` alias definitions (used by
# `showcustommaps` to decide whether the current map counts as "custom") still list all 11
# campaign map names (lost/skrsp1/crnsp1/level9/mpsp6a-c/mpsp9a-c/mpsp10) even though the actual
# .ogz/.wpt/.jpg/.cfg files for them are stripped from the bundle by tools/strip-assets.sh. This
# is intentional, not an oversight: an upgrader's existing install can still have the OLD campaign
# map files sitting on disk (the updater only adds/changes files, never deletes - see
# docs/RELEASE_NOTES.md's v1.3.0 note), and if `spmaps`/`allmaps` no longer listed those 11 names,
# `showcustommaps` would start flagging that stale leftover clutter as "custom maps" and surfacing
# it in the custom-maps browser. Keeping the names in the list keeps that browser clean for
# upgraders without needing to touch stock menus.cfg further. A future cleanup that wants to strip
# these too should only do so once no supported install can still be carrying the old files.

for label, old, new in surgeries:
    n = b.count(old)
    assert n == 1, ("integrate-menus: surgery target missing or ambiguous (%d matches) for: %s, "
                     "stock data/menus.cfg changed shape, surgery patterns need updating" % (n, label))
    b = b.replace(old, new, 1)

# Hard verify: every removed row's distinctive text is fully gone (fail loud on any leftover).
leftovers = [
    b"fullbrightmodels",
    b'guicheckbox "force matching player models" forceplayermodels',
    b'guicheckbox "hits" hitcrosshair',
    b'guibutton "crosshair: "',
    b'guicheckbox "bilinear filtering"',
    b'guicheckbox "chat console" miniconfilter',
    b'showgui campaign',
    b'"sp lost"',
    b'newgui armyofone',
    b'newgui privatestansauer',
]
for pat in leftovers:
    n = b.count(pat)
    assert n == 0, "integrate-menus: surgery leftover found after removal: %r (%d hits), surgery incomplete" % (pat, n)

# Hard verify: rows/tabs that must survive the surgery are still present.
for keep in (b'guicheckbox "always use team skins" teamskins',
             b'guicheckbox "health colors" crosshaircolors',
             b'guicheckbox "teammates" teamcrosshair',
             b'guicheckbox "trilinear filtering (mipmaps)" trilinear',
             b'guitext "crosshair size"',
             b'guitab "SwiftGibs"', b'guitab "Cues"', b'guitab "Audio"', b'guitab "Clips"', b'guitab "Friends"',
             b'] "bot match"'):
    assert b.count(keep) >= 1, "integrate-menus: expected row/tab missing after surgery: %r" % keep

after_crosshairsize_count = b.count(b"guislider crosshairsize")
assert after_crosshairsize_count == before_crosshairsize_count, (
    "integrate-menus: guislider crosshairsize count changed (%d -> %d), crosshair picker surgery "
    "clipped the slider" % (before_crosshairsize_count, after_crosshairsize_count))

after_guitab_count = b.count(b"guitab ")
assert after_guitab_count == before_guitab_count, (
    "integrate-menus: guitab count changed during surgery (%d -> %d), a tab line was accidentally "
    "touched" % (before_guitab_count, after_guitab_count))

open(p, "wb").write(b)
print("integrate-menus: stock options surgery + campaign menu gut complete (%d/%d rows) on" % (len(surgeries), len(surgeries)), p)
PY
