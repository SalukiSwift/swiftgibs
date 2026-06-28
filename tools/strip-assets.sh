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

# 4) crush WORLD textures/skins/mapshots to <=WORLD_PX px (flat competitive look).
#    EXEMPT the glyph atlases in packages/fonts + packages/hud: their .cfg addresses
#    characters by pixel coords assuming the original 512px atlas, so downscaling them
#    scrambles every glyph -> mangled fonts. Geometry files (.md*/.obj/.iqm) untouched.
find "$STAGE/packages" -type d \( -name fonts -o -name hud \) -prune -o \
     -type f \( -iname '*.jpg' -o -iname '*.png' \) -print0 \
  | xargs -0 -P6 -I{} mogrify -resize "${WORLD_PX}x${WORLD_PX}>" "{}"

echo "stage size: $(du -sh "$STAGE" | cut -f1)"
