#!/usr/bin/env bash
# Standalone test for the map-manifest pieces (Task 4): no engine build
# needed - this only needs g++, fpsgame/sgsha256.{h,cpp}, and the generator.
#
# 1. Compiles fpsgame/sgsha256.cpp with a tiny main, plain g++, no engine
#    includes, and asserts the two FIPS 180-4 test vectors.
# 2. Runs build/make-map-manifest.sh against the official 2020 data and
#    asserts the line count (331) and that the fdm6 line's ogz hash matches
#    a fresh, independent `sha256sum` of the real file.
# fpsgame/sgsha256.{h,cpp} ship inside patches/21-map-streaming.patch, not in
# the raw repo tree - so this needs a patched tree to find them. Pass one as
# $1 (eg. one you already built with build/apply-patches.sh) to reuse it;
# otherwise this applies the patch stack itself into a scratch tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /tmp/sg-test-manifest.XXXXXX)"
TREE="${1:-}"
if [ -z "$TREE" ]; then
  TREE="$WORK/tree"
  "$ROOT/build/apply-patches.sh" "$TREE" >&2
fi
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/sgsha256_test.cpp" << 'EOF'
// Standalone FIPS 180-4 test vector check for fpsgame/sgsha256.{h,cpp}.
// Deliberately includes nothing from the engine - only sgsha256.h itself.
#include "sgsha256.h"
#include <stdio.h>
#include <string.h>

static int checkhex(const char *label, const uchar *data, int len, const char *expect)
{
    char out[65];
    sgsha256hex(data, len, out);
    if(strcmp(out, expect) != 0)
    {
        fprintf(stderr, "FAIL %s: got %s, expected %s\n", label, out, expect);
        return 1;
    }
    printf("OK %s: %s\n", label, out);
    return 0;
}

int main()
{
    int fails = 0;
    fails += checkhex("sha256(\"abc\")", (const uchar *)"abc", 3,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    fails += checkhex("sha256(\"\")", (const uchar *)"", 0,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    return fails ? 1 : 0;
}
EOF

echo "== compiling sgsha256 standalone (no engine includes) =="
g++ -Wall -I"$TREE/fpsgame" -o "$WORK/sgsha256_test" "$WORK/sgsha256_test.cpp" "$TREE/fpsgame/sgsha256.cpp"

echo "== FIPS 180-4 test vectors =="
"$WORK/sgsha256_test"

echo "== generator sanity: line count + fdm6 hash =="
"$ROOT/build/make-map-manifest.sh" > "$WORK/mapmanifest.cfg"

lines=$(wc -l < "$WORK/mapmanifest.cfg")
if [ "$lines" -ne 331 ]; then
  echo "FAIL: expected 331 manifest lines, got $lines" >&2
  exit 1
fi
echo "OK: manifest has 331 lines"

fdm6line=$(grep "^fdm6 " "$WORK/mapmanifest.cfg" || true)
if [ -z "$fdm6line" ]; then
  echo "FAIL: fdm6 not found in manifest" >&2
  exit 1
fi
fdm6hash=$(echo "$fdm6line" | cut -d' ' -f3)

SRC="$("$ROOT/build/fetch-official-data.sh")"
realhash=$(sha256sum "$SRC/packages/base/fdm6.ogz" | cut -d' ' -f1)
if [ "$fdm6hash" != "$realhash" ]; then
  echo "FAIL: fdm6 ogz hash mismatch: manifest=$fdm6hash real(sha256sum)=$realhash" >&2
  exit 1
fi
echo "OK: fdm6 ogz hash matches a fresh sha256sum ($fdm6hash)"

echo "ALL PASSED"
