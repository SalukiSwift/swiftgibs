#!/usr/bin/env bash
# Download + extract the official 2020 Sauerbraten release (which contains data/ + packages/) into a
# cache and print its root path on stdout, so bundle scripts can use it as SRC/INSTALL. Idempotent.
set -euo pipefail
CACHE="${SG_DATA_CACHE:-/tmp/sg-official-data}"
ROOT="$CACHE/sauerbraten"
if [ -d "$ROOT/data" ] && [ -d "$ROOT/packages" ]; then echo "$ROOT"; exit 0; fi
mkdir -p "$CACHE"
URL="https://downloads.sourceforge.net/project/sauerbraten/sauerbraten/2020_11_29/sauerbraten_2020_12_29_linux.tar.bz2"
echo "fetching official 2020 Sauerbraten data (~986MB)..." >&2
curl -fL --retry 3 -o "$CACHE/sauer.tar.bz2" "$URL"
tar -xjf "$CACHE/sauer.tar.bz2" -C "$CACHE"
test -d "$ROOT/data" && test -d "$ROOT/packages" || { echo "fetch-official-data: extract missing data/packages" >&2; exit 1; }
echo "$ROOT"
