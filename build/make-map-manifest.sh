#!/usr/bin/env bash
# Emit the map manifest for the official 2020 data on stdout.
set -euo pipefail
SRC="${1:-$("$(dirname "$0")/fetch-official-data.sh")}"
cd "$SRC/packages/base"
for ogz in *.ogz; do
  name="${ogz%.ogz}"
  line="$name $(stat -c%s "$ogz") $(sha256sum "$ogz" | cut -d' ' -f1)"
  if [ -f "$name.wpt" ]; then line="$line $(stat -c%s "$name.wpt") $(sha256sum "$name.wpt" | cut -d' ' -f1)"; fi
  echo "$line"
done
