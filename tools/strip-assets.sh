#!/usr/bin/env bash
# Stage a minimal, low-res Sauerbraten data tree for SwiftGibs.
# Usage: strip-assets.sh <pool-file> <stage-dir>
set -euo pipefail
SRC="${SRC:-$HOME/repos/sauerbraten}"
POOL="${1:?usage: strip-assets.sh <pool-file> <stage-dir>}"
STAGE="${2:?stage dir required}"
MAXPX=128

rm -rf "$STAGE"; mkdir -p "$STAGE/packages/base"

# 1) data/ wholesale (shaders, fonts, menus, default cfgs ~2.8MB)
cp -a "$SRC/data" "$STAGE/data"

# 2) all package dirs EXCEPT base (textures/models/skies/sounds/theme-packs)
for d in "$SRC"/packages/*/; do
  name=$(basename "$d")
  [ "$name" = base ] && continue
  cp -a "$d" "$STAGE/packages/$name"
done

# 3) base: only the pooled maps' files (.ogz/.cfg/.wpt/.jpg) — drops ~320 unused maps
while read -r m; do
  [ -z "$m" ] && continue
  for ext in ogz cfg wpt jpg; do
    f="$SRC/packages/base/$m.$ext"
    [ -f "$f" ] && cp "$f" "$STAGE/packages/base/"
  done
done < "$POOL"

# 4) crush every texture/skin/mapshot to <=128px (geometry files untouched)
find "$STAGE/packages" \( -iname '*.jpg' -o -iname '*.png' \) -print0 \
  | xargs -0 -P4 -I{} mogrify -resize "${MAXPX}x${MAXPX}>" "{}"

echo "stage size: $(du -sh "$STAGE" | cut -f1)"
