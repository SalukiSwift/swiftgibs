#!/usr/bin/env bash
# Stage a minimal, low-res Sauerbraten data tree for SwiftGibs.
# Usage: strip-assets.sh <pool-file> <stage-dir>
set -euo pipefail
SRC="${SRC:-$HOME/repos/sauerbraten}"
POOL="${1:?usage: strip-assets.sh <pool-file> <stage-dir>}"
STAGE="${2:?stage dir required}"
WORLD_PX="${WORLD_PX:-2}"   # world textures crushed to this many px (flat look); fonts/hud exempt

rm -rf "$STAGE"; mkdir -p "$STAGE/packages/base"

# 1) data/ wholesale (shaders, fonts, menus, default cfgs ~2.8MB)
cp -a "$SRC/data" "$STAGE/data"

# 2) all package dirs EXCEPT base (textures/models/skies/sounds/theme-packs)
for d in "$SRC"/packages/*/; do
  name=$(basename "$d")
  [ "$name" = base ] && continue
  cp -a "$d" "$STAGE/packages/$name"
done

# 3) base maps. ALLMAPS=1 ships every map (full public-server compat); otherwise
#    only the curated pool (tiny, for local + own-server play).
if [ "${ALLMAPS:-0}" = 1 ]; then
  cp -a "$SRC/packages/base/." "$STAGE/packages/base/"
else
  while read -r m; do
    [ -z "$m" ] && continue
    for ext in ogz cfg wpt jpg; do
      f="$SRC/packages/base/$m.$ext"
      [ -f "$f" ] && cp "$f" "$STAGE/packages/base/"
    done
  done < "$POOL"
fi

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

echo "stage size: $(du -sh "$STAGE" | cut -f1)"
