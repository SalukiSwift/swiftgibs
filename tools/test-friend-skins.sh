#!/usr/bin/env bash
# Regression guard for the flat player-skin choice (patch 10).
# Extracts the REAL decision line from a patched tree and asserts the full matrix, so the
# FFA hole that made friends look like teammates (cyan) cannot come back unnoticed.
# Usage: [TREE=<patched tree>] tools/test-friend-skins.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="${TREE:-}"
TMP="$(mktemp -d /tmp/sg-skintest-$$-XXXX)"
trap 'rm -rf "$TMP"' EXIT
if [ -z "$TREE" ]; then TREE="$TMP/tree"; "$ROOT/build/apply-patches.sh" "$TREE" >/dev/null 2>&1; fi

LINE="$(grep -h 'const char \*fc = flatteam' "$TREE/fpsgame/render.cpp" | head -1 | sed 's/^[[:space:]]*//')"
[ -n "$LINE" ] || { echo "FAIL: could not find the flat-skin decision line in $TREE/fpsgame/render.cpp"; exit 1; }
echo "under test: $LINE"

cat > "$TMP/t.cpp" <<CPP
#include <stdio.h>
#include <string.h>
static const char *pick(int flatteam, bool flatfriend, int enemyfriendhl)
{
    $LINE
    return fc;
}
struct C { int team; bool fr; int efhl; const char *want; };
int main()
{
    C cases[] = {
        // teammate: friends stay cyan, others blue
        {1,false,0,"flatblue"}, {1,true,0,"flatcyan"}, {1,true,1,"flatcyan"},
        // enemy team: friend highlighted only when opted in
        {2,false,0,"flatred"},  {2,true,0,"flatred"},  {2,true,1,"flatorange"},
        // FFA/1v1 (no teams): everyone is an enemy - MUST match the enemy row
        {0,false,0,"flatred"},  {0,true,0,"flatred"},  {0,true,1,"flatorange"},
    };
    int bad = 0;
    for(size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); i++)
    {
        const char *got = pick(cases[i].team, cases[i].fr, cases[i].efhl);
        bool ok = !strcmp(got, cases[i].want);
        printf("%s team=%d friend=%d enemyfriendhl=%d -> %-10s (want %s)\n",
               ok ? "  ok  " : "  FAIL", cases[i].team, cases[i].fr, cases[i].efhl, got, cases[i].want);
        if(!ok) bad++;
    }
    if(bad) { printf("FAILED: %d case(s)\n", bad); return 1; }
    printf("ALL %zu CASES PASS\n", sizeof(cases)/sizeof(cases[0]));
    return 0;
}
CPP
g++ -O0 -o "$TMP/t" "$TMP/t.cpp"
"$TMP/t"
