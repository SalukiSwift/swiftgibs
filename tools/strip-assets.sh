#!/usr/bin/env bash
# Stage a minimal, low-res Sauerbraten data tree for SwiftGibs.
# Usage: strip-assets.sh <stage-dir>
set -euo pipefail
SRC="${SRC:-$HOME/repos/sauerbraten}"
STAGE="${1:?usage: strip-assets.sh <stage-dir>}"
WORLD_PX="${WORLD_PX:-2}"   # world textures crushed to this many px (flat look); fonts/hud exempt

# A killed prior run can leave read-only package dirs in the stage (some install
# packages ship mode 555, e.g. the "staffy" skybox), which makes `rm -rf` fail on the
# next run. Make the leftover writable first so the clean always succeeds.
chmod -R u+w "$STAGE" 2>/dev/null || true
rm -rf "$STAGE"; mkdir -p "$STAGE/packages/base"

# 1) data/ wholesale (shaders, fonts, menus, default cfgs ~2.8MB)
cp -a "$SRC/data" "$STAGE/data"

# 2) all package dirs EXCEPT base (textures/models/skies/sounds/theme-packs)
for d in "$SRC"/packages/*/; do
  name=$(basename "$d")
  [ "$name" = base ] && continue
  cp -a "$d" "$STAGE/packages/$name"
done

# 3) base maps: ship everything under packages/base EXCEPT the 11 campaign/SP
#    mission maps (tools/campaign-maps.txt) - their menus were gutted (Task 1),
#    so nothing in-game can reach them, and fetching them on demand instead of
#    shipping them was a scrapped feature this script no longer supports (see
#    the map-streaming archive doc for the abandoned slim/fat variant split).
#    Guard first: the extraction logic below is a flat, non-recursive file
#    copy/find, so a subdirectory appearing under packages/base (none exist in
#    the 2020 official release as of writing) would silently vanish from the
#    stage. Fail loudly instead of guessing.
if [ -n "$(find "$SRC/packages/base" -mindepth 1 -type d)" ]; then
  echo "strip-assets: unexpected subdirectory under packages/base - update this script to handle it explicitly" >&2
  find "$SRC/packages/base" -mindepth 1 -type d >&2
  exit 1
fi
cp -a "$SRC/packages/base/." "$STAGE/packages/base/"
# `|| [ -n "$cmap" ]` keeps the loop body running on a final line that has no trailing
# newline (read still populates $cmap but returns nonzero at EOF in that case, which would
# otherwise silently drop the last entry in campaign-maps.txt).
while read -r cmap || [ -n "$cmap" ]; do
  [ -z "$cmap" ] && continue
  rm -f "$STAGE/packages/base/$cmap.ogz" "$STAGE/packages/base/$cmap.wpt" \
        "$STAGE/packages/base/$cmap.jpg" "$STAGE/packages/base/$cmap.cfg"
done < "$(dirname "$0")/campaign-maps.txt"

# make the stage writable: copies off a Windows mount (/mnt/c) come read-only,
# which would block the downscale below and the overlay copy later.
chmod -R u+w "$STAGE"

# 4) crush only WORLD textures/skins to <=WORLD_PX px (flat competitive look).
#    EXEMPT the UI/menu art so menus, icons, crosshairs and map thumbnails stay crisp:
#      fonts/hud  - glyph atlases (.cfg addresses chars by 512px pixel coords)
#      icons      - menu icons (checkbox/arrows/player-model/etc. — the blurry squares)
#      crosshairs - crosshair previews in options
#      particles  - effect sprites (look bad smushed)
#      base       - map .ogz live here; its .jpg are the map-picker thumbnails
#    Geometry files (.md*/.obj/.iqm) are untouched (not matched by the image find).
find "$STAGE/packages" -type d \( \
       -name fonts -o -name hud -o -name icons -o -name crosshairs -o -name particles -o -name base \
     \) -prune -o \
     -type f \( -iname '*.jpg' -o -iname '*.png' \) -print0 \
  | xargs -0 -P6 -I{} mogrify -resize "${WORLD_PX}x${WORLD_PX}>" "{}"

# 5) drop dead weight that's shipped but never used (zero visual/gameplay change, ~70MB):
#    - map background MUSIC (.ogg outside sounds/): SwiftGibs runs musicvol 0, so it never plays.
#      (sound EFFECTS live under packages/sounds/ and are kept.)
#    - high-res .dds textures: the stock cfgs load them via the "<dds>foo.png" prefix, which falls
#      back to foo.png when the .dds is absent -- so removing them just forces the crushed 2px .png
#      (smaller AND more consistent with the flat look; every .dds has a .png/.jpg counterpart).
find "$STAGE/packages" -iname '*.ogg' -not -path '*/sounds/*' -delete
find "$STAGE/packages" -iname '*.dds' -delete

# 6) drop sound files nothing references (list maintained by tools/scan-dead-sounds.sh)
# same trailing-newline hardening as the campaign-maps loop above.
while read -r dead || [ -n "$dead" ]; do
  [ -z "$dead" ] && continue
  rm -f "$STAGE/$dead"
done < "$(dirname "$0")/dead-sounds.txt"

echo "stage size: $(du -sh "$STAGE" | cut -f1)"
