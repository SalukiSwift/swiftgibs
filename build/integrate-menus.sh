#!/usr/bin/env bash
# Attach the SwiftGibs + Friends tabs to the stock Esc->options gui by splicing four literal lines
# (which call aliases defined in overlay/menus_settings.cfg) into the staged data/menus.cfg, right
# before the options gui's closing `] "game"`. Idempotent.
# Usage: integrate-menus.sh <staged-root-containing-data/menus.cfg>
set -euo pipefail
ROOT="${1:?staged root}"
M="$ROOT/data/menus.cfg"
[ -f "$M" ] || { echo "integrate-menus: no $M"; exit 1; }
if grep -q 'guitab "SwiftGibs"' "$M"; then echo "integrate-menus: already integrated"; exit 0; fi
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
       b'    guitab "Friends"' + nl + b'    sgFriendsTab' + nl)
open(p, "wb").write(b[:close] + ins + b[close:])
print("integrate-menus: attached SwiftGibs + Friends tabs to", p)
PY
