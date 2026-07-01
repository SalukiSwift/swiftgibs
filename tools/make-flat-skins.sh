#!/usr/bin/env bash
# Generate SOLID team-colour player skins for SwiftGibs (blue/cyan/red/orange), one variant dir per
# colour per model, mirroring tools/make-friend-skins.sh's layout. Skins are solid fills (the model shape
# still shows via silhouette + geometry) crushed to 2px like the rest of the flat look. Selected per player
# by team+friend in patches/06 (flat model style).
set -euo pipefail
SRC="${SRC:-/mnt/c/Program Files (x86)/Sauerbraten}/packages/models"
OUT="${OUT:-$HOME/repos/swiftgibs/overlay/packages/models}"
WORLD_PX="${WORLD_PX:-2}"
declare -A COL=( [blue]="77,115,255" [cyan]="26,230,255" [red]="255,64,51" [orange]="255,128,31" )

# solid <src-template-img> <r,g,b> <out-img>  (solid-fill the colour, keep dims/alpha, crush to WORLD_PX)
solid(){ convert "$1" -fill "rgb(${2})" -colorize 100 -resize "${WORLD_PX}x${WORLD_PX}>" -strip "$3"; }
# mkcfg <in-cfg> <out-cfg> <from=to>...  (copy team cfg, drop <dds>, rename albedo(s))
mkcfg(){ local in="$1" out="$2"; shift 2; local s='s/<dds>//g' m; for m in "$@"; do s="$s; s/${m%=*}/${m#*=}/g"; done; sed -e "$s" "$in" > "$out"; }

# gen <model> <cfg> <blue-albedo>...   -- builds flat{blue,cyan,red,orange}/ from the model's blue albedos
gen(){
  local m="$1" cfg="$2"; shift 2; local c a out ren
  for c in blue cyan red orange; do
    mkdir -p "$OUT/$m/flat$c"; ren=()
    for a in "$@"; do
      out="${a%.*}_${c}.${a##*.}"                       # e.g. upper_b.png -> upper_b_cyan.png (in model root)
      solid "$SRC/$m/$a" "${COL[$c]}" "$OUT/$m/$out"
      ren+=("$a=$out")
    done
    mkcfg "$SRC/$m/blue/$cfg" "$OUT/$m/flat$c/$cfg" "${ren[@]}"
  done
}

gen mrfixit       md5.cfg Bodyblue.png Headblue.png
gen snoutx10k     md5.cfg upper_b.png lower_b.png
gen ogro2         iqm.cfg blue.jpg
gen inky          md5.cfg inky_blue.png inky_wings_blue.png
gen captaincannon md5.cfg cc_head_blue.png cc_body_blue.png
echo "flat skins generated under $OUT"
