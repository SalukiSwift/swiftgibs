#!/usr/bin/env bash
# Stage a minimal, low-res Sauerbraten data tree for SwiftGibs.
# Usage: [MAPS=none|all] strip-assets.sh <stage-dir>
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

# 3) base maps. MAPS=all ships every map (fat variant); MAPS=none (slim, default)
#    ships only mapshots + map cfgs - .ogz/.wpt stream on demand (patch 21).
#    Guard first: the extraction logic below is a flat, non-recursive file
#    copy/find, so a subdirectory appearing under packages/base (none exist in
#    the 2020 official release as of writing) would silently vanish from the
#    stage in the none case, or copy correctly-but-unnoticed in the all case.
#    Fail loudly instead of guessing.
if [ -n "$(find "$SRC/packages/base" -mindepth 1 -type d)" ]; then
  echo "strip-assets: unexpected subdirectory under packages/base - update this script to handle it explicitly" >&2
  find "$SRC/packages/base" -mindepth 1 -type d >&2
  exit 1
fi
case "${MAPS:-none}" in
  all)  cp -a "$SRC/packages/base/." "$STAGE/packages/base/" ;;
  none) find "$SRC/packages/base" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.cfg' -o -iname '*.txt' \) -exec cp {} "$STAGE/packages/base/" \; ;;
  *) echo "strip-assets: MAPS must be none|all" >&2; exit 1 ;;
esac

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
while read -r dead; do
  [ -z "$dead" ] && continue
  rm -f "$STAGE/$dead"
done < "$(dirname "$0")/dead-sounds.txt"

echo "stage size: $(du -sh "$STAGE" | cut -f1)"
