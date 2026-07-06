#!/usr/bin/env bash
# Assemble the Linux SwiftGibs bundle: native client + stripped official data + overlay + launcher.
# Usage: [INSTALL=<data-root>] build/make-bundle-linux.sh   (INSTALL defaults to fetch-official-data)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="${INSTALL:-$("$ROOT/build/fetch-official-data.sh")}"
STAGE="${STAGE:-/tmp/swiftgibs-linux-stage}"
OUT="$ROOT/dist/SwiftGibs-linux-x86_64"

"$ROOT/build/make-engine-linux.sh" >/dev/null
rm -rf "$OUT"; mkdir -p "$OUT/bin"
cp "$ROOT/dist/engines/linux-x86_64/sauer_client" "$OUT/bin/swiftgibs"

SRC="$INSTALL" ALLMAPS="${ALLMAPS:-1}" "$ROOT/tools/strip-assets.sh" "$ROOT/maps/pool.txt" "$STAGE"
cp -a "$STAGE/data" "$OUT/data"; cp -a "$STAGE/packages" "$OUT/packages"
cp -a "$ROOT/overlay/." "$OUT/"; rm -f "$OUT/autoexec.source.cfg"
"$ROOT/build/integrate-menus.sh" "$OUT"
rm -f "$OUT/config.cfg" "$OUT/init.cfg"

cat > "$OUT/swiftgibs.sh" <<'SH'
#!/usr/bin/env bash
cd "$(dirname "$0")" && exec ./bin/swiftgibs -q.
SH
chmod +x "$OUT/swiftgibs.sh" "$OUT/bin/swiftgibs"

cd "$ROOT/dist"; rm -f SwiftGibs-linux-x86_64.tar.gz
tar -czf SwiftGibs-linux-x86_64.tar.gz SwiftGibs-linux-x86_64
echo "linux bundle: $(du -sh "$OUT" | cut -f1) | tgz: $(du -sh SwiftGibs-linux-x86_64.tar.gz | cut -f1)"
