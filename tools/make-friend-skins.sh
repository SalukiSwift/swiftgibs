#!/usr/bin/env bash
# Generate green (friend-teammate) + purple (friend-enemy) model skins for SwiftGibs,
# hue-shifted from her install's stock blue/red skins and crushed to 2px to match the flat look.
set -euo pipefail
SRC="${SRC:-/mnt/c/Program Files (x86)/Sauerbraten}/packages/models"
OUT="${OUT:-$HOME/repos/swiftgibs/overlay/packages/models}"
WORLD_PX="${WORLD_PX:-2}"
GREEN_MOD="${GREEN_MOD:-100,120,40}"     # blue(~240deg) -> green(~120deg): rotate -108deg (tuned: hue=40 centres all 5 models at 101-128deg)
PURPLE_MOD="${PURPLE_MOD:-100,150,78}"   # red(~0deg) -> bright red-leaning magenta(~320deg): rotate -40deg, +sat

# recolor <src-img> <modulate> <out-img>  (hue-shift, boost sat, crush to WORLD_PX, flatten alpha-safe)
recolor(){ convert "$1" -modulate "$2" -resize "${WORLD_PX}x${WORLD_PX}>" "$3"; }
# variant cfg: copy stock team cfg, drop <dds>, rename albedo(s) only  (sed args 4..N: from=to)
mkcfg(){ local in="$1" out="$2" m; shift 2; local s='s/<dds>//g'; for m in "$@"; do s="$s; s/${m%=*}/${m#*=}/g"; done; sed -e "$s" "$in" > "$out"; }

gen(){ # gen <model> <cfgname> <green_mod_pairs...> -- <purple_mod_pairs...>
  local m="$1" cfg="$2"; shift 2
  local greens=() purples=() seen_sep=0
  for a in "$@"; do [ "$a" = -- ] && { seen_sep=1; continue; }; [ $seen_sep -eq 0 ] && greens+=("$a") || purples+=("$a"); done
  mkdir -p "$OUT/$m/green" "$OUT/$m/purple"
  for p in "${greens[@]}";  do recolor "$SRC/$m/${p%=*}" "$GREEN_MOD"  "$OUT/$m/${p#*=}"; done
  for p in "${purples[@]}"; do recolor "$SRC/$m/${p%=*}" "$PURPLE_MOD" "$OUT/$m/${p#*=}"; done
  mkcfg "$SRC/$m/blue/$cfg" "$OUT/$m/green/$cfg"  "${greens[@]/=/=}"  # rename blue->green albedos
  mkcfg "$SRC/$m/red/$cfg"  "$OUT/$m/purple/$cfg" "${purples[@]/=/=}" # rename red->purple albedos
}

gen mrfixit       md5.cfg Bodyblue.png=Bodygreen.png Headblue.png=Headgreen.png \
  -- Bodyred.png=Bodypurple.png Headred.png=Headpurple.png
gen snoutx10k     md5.cfg upper_b.png=upper_g.png lower_b.png=lower_g.png \
  -- upper_r.png=upper_p.png lower_r.png=lower_p.png
gen ogro2         iqm.cfg blue.jpg=green.jpg \
  -- red.jpg=purple.jpg
gen inky          md5.cfg inky_blue.png=inky_green.png inky_wings_blue.png=inky_wings_green.png \
  -- inky_red.png=inky_purple.png inky_wings_red.png=inky_wings_purple.png
gen captaincannon md5.cfg cc_head_blue.png=cc_head_green.png cc_body_blue.png=cc_body_green.png \
  -- cc_head_red.png=cc_head_purple.png cc_body_red.png=cc_body_purple.png
echo "friend skins generated under $OUT"
