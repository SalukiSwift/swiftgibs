#!/usr/bin/env bash
# Regression guard for the CTF match-flow round (patch 22). Extracts the REAL decision code from a
# patched tree and asserts its full matrix, so a logic hole a screenshot cannot show (a wrong
# placement count, "you won" for a spectator) cannot come back unnoticed.
#   1. end-of-match banner: wording + colour class (sgendbannerresult, fpsgame/fps.cpp)
# Usage: [TREE=<patched tree>] tools/test-ctf-flow.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="${TREE:-}"
TMP="$(mktemp -d /tmp/sg-ctfflowtest-$$-XXXX)"
trap 'rm -rf "$TMP"' EXIT
if [ -z "$TREE" ]; then
  TREE="$TMP/tree"
  "$ROOT/build/apply-patches.sh" "$TREE" > "$TMP/apply.log" 2>&1 || {
    echo "FAIL: apply-patches.sh failed; last lines:"; tail -20 "$TMP/apply.log"; exit 1; }
fi

# extract_block <file> <marker> <out>: copies the lines strictly between the "<marker>: begin" and
# "<marker>: end" lines of <file> into <out>, CRs stripped (vendor sources are CRLF). Each marker
# must occur exactly once, in order, or the test would be testing the wrong code.
extract_block() {
  local file="$1" marker="$2" out="$3" m n
  for m in begin end; do
    n="$(grep -c "$marker: $m" "$file" || true)"
    [ "$n" = "1" ] || { echo "FAIL: expected exactly 1 '$marker: $m' line in ${file#"$TREE"/}, found $n - the test would be testing the wrong code"; return 1; }
  done
  [ "$(grep -n "$marker: begin" "$file" | cut -d: -f1)" -lt "$(grep -n "$marker: end" "$file" | cut -d: -f1)" ] || {
    echo "FAIL: '$marker: end' comes before '$marker: begin' in ${file#"$TREE"/}"; return 1; }
  tr -d '\r' < "$file" | sed -n "/$marker: begin/,/$marker: end/p" | sed '1d;$d' > "$out"
  echo "under test: $marker, $(wc -l < "$out") lines from ${file#"$TREE"/}"
}

# ---- 1. end-of-match banner --------------------------------------------------------------------
# The engine hands the unit game::players, which INCLUDES the local player (initclient() adds
# player1), so every case lists self among the players. A unit that counted self twice reads a
# duel as "VICTORY - 1st of 3" and fails every duel row.
banner_test() {
  echo "== end-of-match banner wording =="
  extract_block "$TREE/fpsgame/fps.cpp" "sgendbannerresult" "$TMP/banner-unit.inc" || return 1
  cat > "$TMP/banner.cpp" <<'CPP'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
// Minimal stand-ins for the only engine pieces the unit may touch (shared/tools.h, shared/ents.h,
// fpsgame/game.h). Anything else it reaches for (player1, m_teammode, lastmillis...) is engine
// state and fails to compile here, which is the point.
typedef unsigned char uchar;
typedef char string[260];
template<class T> struct vector
{
    T buf[32]; int len;
    vector() : len(0) {}
    int length() const { return len; }
    T &operator[](int i) { return buf[i]; }
    const T &operator[](int i) const { return buf[i]; }
    void add(const T &x) { buf[len++] = x; }
};
#define loopv(v) for(int i = 0; i<(v).length(); i++)
static char *copystring(char *d, const char *s, size_t len) { size_t n = strlen(s); if(n > len-1) n = len-1; memcpy(d, s, n); d[n] = 0; return d; }
static void nformatstring(char *d, int len, const char *fmt, ...) { va_list v; va_start(v, fmt); vsnprintf(d, len, fmt, v); va_end(v); d[len-1] = 0; }
static uchar cubeupper(uchar c) { return toupper(c); }   // the engine's is a charset table; ASCII is all these cases use
enum { CS_ALIVE = 0, CS_DEAD, CS_SPAWNING, CS_LAGGED, CS_EDITING, CS_SPECTATOR };
struct fpsent { int state, frags; string name, team; };

#include "banner-unit.inc"

// One match as the engine sees it at intermission: the players list (self included) plus what
// getbestteams()/getbestplayers() reported for it.
struct match
{
    fpsent ents[32]; int n;
    vector<fpsent *> players, bestplayers;
    vector<const char *> bestteams;
    match() : n(0) {}
    fpsent *add(const char *name, const char *team, int state, int frags)
    {
        fpsent &e = ents[n++];
        e.state = state; e.frags = frags;
        copystring(e.name, name, sizeof(e.name)); copystring(e.team, team, sizeof(e.team));
        players.add(&e);
        return &e;
    }
};

static int ran = 0, bad = 0;
static const char *classname(int c) { return c == SGEND_WIN ? "win" : c == SGEND_LOSS ? "loss" : c == SGEND_NEUTRAL ? "neutral" : "?"; }
static void expect(const char *what, bool teammode, const match &m, const fpsent *self, const char *want, int wantclass)
{
    string text; text[0] = '\0';
    int got = sgendbannerresult(text, sizeof(text), teammode, self, m.players, m.bestteams, m.bestplayers);
    bool ok = !strcmp(text, want) && got == wantclass;
    printf("%s %-56s -> %-20s %-7s (want %s, %s)\n", ok ? "  ok  " : "  FAIL", what, text, classname(got), want, classname(wantclass));
    ran++;
    if(!ok) bad++;
}

// FFA placement row: self with exactly place-1 players ahead and total-place behind.
static void ffaplace(int place, int total, const char *want, int wantclass)
{
    match m;
    for(int i = 0; i < place-1; i++) m.add("ahead", "", CS_ALIVE, 50);
    fpsent *self = m.add("april", "", CS_ALIVE, 20);
    for(int i = place; i < total; i++) m.add("behind", "", CS_ALIVE, 5);
    char what[64]; snprintf(what, sizeof(what), "ffa, playing: place %d of %d", place, total);
    expect(what, false, m, self, want, wantclass);
}

int main()
{
    // ---- team modes, playing: VICTORY / DEFEAT / DRAW, never a placement ----
    { match m; fpsent *self = m.add("april", "good", CS_ALIVE, 2); m.add("bot", "good", CS_ALIVE, 30); m.add("bot", "evil", CS_DEAD, 10); m.add("bot", "evil", CS_ALIVE, 5);
      m.bestteams.add("good");
      expect("team, playing: own team won (self bottom-fragger)", true, m, self, "VICTORY", SGEND_WIN); }
    { match m; m.add("bot", "good", CS_ALIVE, 30); fpsent *self = m.add("april", "good", CS_ALIVE, 25); m.add("bot", "evil", CS_ALIVE, 10);
      m.bestteams.add("evil");
      expect("team, playing: other team won (self top-fragger)", true, m, self, "DEFEAT", SGEND_LOSS); }
    { match m; fpsent *self = m.add("april", "evil", CS_ALIVE, 4); m.add("bot", "good", CS_ALIVE, 4);
      m.bestteams.add("good"); m.bestteams.add("evil");
      expect("team, playing: teams level", true, m, self, "DRAW", SGEND_NEUTRAL); }
    { match m; fpsent *self = m.add("april", "good", CS_ALIVE, 6); m.add("bot", "evil", CS_ALIVE, 3);
      expect("team, playing: no team reported (0-0 ctf lists none)", true, m, self, "DRAW", SGEND_NEUTRAL); }
    // ---- team modes, spectating: informative, team name upper-cased, never "you" ----
    { match m; fpsent *self = m.add("april", "good", CS_SPECTATOR, 0); m.add("bot", "good", CS_ALIVE, 3); m.add("bot", "evil", CS_ALIVE, 9);
      m.bestteams.add("evil");
      expect("team, spectating: evil won (spectator's own team lost)", true, m, self, "EVIL WINS", SGEND_NEUTRAL); }
    { match m; m.add("bot", "good", CS_ALIVE, 7); fpsent *self = m.add("april", "evil", CS_SPECTATOR, 0); m.add("bot", "evil", CS_ALIVE, 2);
      m.bestteams.add("good");
      expect("team, spectating: good won", true, m, self, "GOOD WINS", SGEND_NEUTRAL); }
    { match m; fpsent *self = m.add("april", "good", CS_SPECTATOR, 0); m.add("bot", "good", CS_ALIVE, 5); m.add("bot", "evil", CS_ALIVE, 5);
      m.bestteams.add("good"); m.bestteams.add("evil");
      expect("team, spectating: teams level", true, m, self, "DRAW", SGEND_NEUTRAL); }
    { match m; fpsent *self = m.add("april", "good", CS_SPECTATOR, 0);
      expect("team, spectating: no team reported at all", true, m, self, "DRAW", SGEND_NEUTRAL); }
    // ---- duel (exactly 2 scoring players incl. self): WON / LOST / DRAW ----
    { match m; fpsent *self = m.add("april", "", CS_ALIVE, 10); m.add("bot", "", CS_ALIVE, 5);
      m.bestplayers.add(self);
      expect("duel, playing: self ahead", false, m, self, "WON", SGEND_WIN); }
    { match m; m.add("bot", "", CS_ALIVE, 10); fpsent *self = m.add("april", "", CS_ALIVE, 5);
      m.bestplayers.add(&m.ents[0]);
      expect("duel, playing: self behind", false, m, self, "LOST", SGEND_LOSS); }
    { match m; fpsent *self = m.add("april", "", CS_ALIVE, 7); m.add("bot", "", CS_ALIVE, 7);
      m.bestplayers.add(self); m.bestplayers.add(&m.ents[1]);
      expect("duel, playing: level frags", false, m, self, "DRAW", SGEND_NEUTRAL); }
    { match m; m.add("spec", "", CS_SPECTATOR, 0); fpsent *self = m.add("april", "", CS_ALIVE, 3); m.add("spec", "", CS_SPECTATOR, 0); m.add("bot", "", CS_ALIVE, 1);
      m.bestplayers.add(self);
      expect("duel, playing: spectators never make it an FFA", false, m, self, "WON", SGEND_WIN); }
    { match m; fpsent *self = m.add("april", "", CS_ALIVE, 1); m.add("bot", "", CS_DEAD, 4);
      m.bestplayers.add(&m.ents[1]);
      expect("duel, playing: opponent dead at the whistle still counts", false, m, self, "LOST", SGEND_LOSS); }
    // ---- FFA, playing: placement among scoring players, competition ranking ----
    { match m; fpsent *self = m.add("april", "", CS_ALIVE, 40); for(int i = 0; i < 7; i++) m.add("bot", "", i%2 ? CS_ALIVE : CS_DEAD, 10+i);
      m.bestplayers.add(self);
      expect("ffa, playing: top of 8", false, m, self, "VICTORY - 1st of 8", SGEND_WIN); }
    ffaplace(2, 8, "2nd of 8", SGEND_NEUTRAL);
    ffaplace(3, 8, "3rd of 8", SGEND_NEUTRAL);
    ffaplace(4, 8, "4th of 8", SGEND_NEUTRAL);
    ffaplace(8, 8, "8th of 8", SGEND_NEUTRAL);
    ffaplace(11, 25, "11th of 25", SGEND_NEUTRAL);
    ffaplace(12, 25, "12th of 25", SGEND_NEUTRAL);
    ffaplace(13, 25, "13th of 25", SGEND_NEUTRAL);
    ffaplace(21, 25, "21st of 25", SGEND_NEUTRAL);
    ffaplace(22, 25, "22nd of 25", SGEND_NEUTRAL);
    ffaplace(23, 25, "23rd of 25", SGEND_NEUTRAL);
    { match m; m.add("bot", "", CS_ALIVE, 10); fpsent *self = m.add("april", "", CS_ALIVE, 10); m.add("bot", "", CS_ALIVE, 3);
      m.bestplayers.add(&m.ents[0]); m.bestplayers.add(self);
      expect("ffa, playing: shared first reads 1st", false, m, self, "VICTORY - 1st of 3", SGEND_WIN); }
    { match m; m.add("bot", "", CS_ALIVE, 9); m.add("bot", "", CS_ALIVE, 9); fpsent *self = m.add("april", "", CS_ALIVE, 4); m.add("bot", "", CS_ALIVE, 4);
      m.bestplayers.add(&m.ents[0]); m.bestplayers.add(&m.ents[1]);
      expect("ffa, playing: two level ahead -> 3rd, not 2nd", false, m, self, "3rd of 4", SGEND_NEUTRAL); }
    { match m; m.add("spec", "", CS_SPECTATOR, 0); m.add("bot", "", CS_ALIVE, 9); fpsent *self = m.add("april", "", CS_ALIVE, 4); m.add("spec", "", CS_SPECTATOR, 0); m.add("bot", "", CS_ALIVE, 1); m.add("spec", "", CS_SPECTATOR, 0);
      m.bestplayers.add(&m.ents[1]);
      expect("ffa, playing: spectators never counted", false, m, self, "2nd of 3", SGEND_NEUTRAL); }
    { match m; fpsent *self = m.add("april", "", CS_ALIVE, 0);
      m.bestplayers.add(self);
      expect("ffa, playing: alone on the server", false, m, self, "VICTORY - 1st of 1", SGEND_WIN); }
    // ---- FFA / duel, spectating: "<name> WINS" (name case kept) or DRAW ----
    { match m; fpsent *self = m.add("april", "", CS_SPECTATOR, 0); m.add("Coda", "", CS_ALIVE, 12); m.add("bot", "", CS_ALIVE, 5); m.add("bot", "", CS_ALIVE, 1);
      m.bestplayers.add(&m.ents[1]);
      expect("ffa, spectating: sole winner keeps the name's case", false, m, self, "Coda WINS", SGEND_NEUTRAL); }
    { match m; m.add("bot", "", CS_ALIVE, 8); m.add("SalukiSwift", "", CS_ALIVE, 8); fpsent *self = m.add("april", "", CS_SPECTATOR, 0); m.add("bot", "", CS_ALIVE, 2);
      m.bestplayers.add(&m.ents[1]); m.bestplayers.add(&m.ents[0]);
      expect("ffa, spectating: level at the top", false, m, self, "DRAW", SGEND_NEUTRAL); }
    { match m; fpsent *self = m.add("april", "", CS_SPECTATOR, 0); m.add("spec", "", CS_SPECTATOR, 0);
      expect("ffa, spectating: nobody scoring", false, m, self, "DRAW", SGEND_NEUTRAL); }
    { match m; m.add("bot", "", CS_ALIVE, 6); fpsent *self = m.add("april", "", CS_SPECTATOR, 0); m.add("Coda", "", CS_ALIVE, 2);
      m.bestplayers.add(&m.ents[0]);
      expect("duel, spectating: never WON/LOST", false, m, self, "bot WINS", SGEND_NEUTRAL); }

    if(bad) { printf("FAILED: %d of %d case(s)\n", bad, ran); return 1; }
    printf("ALL %d CASES PASS\n", ran);
    return 0;
}
CPP
  g++ -O0 -Wall -fsigned-char -I"$TMP" -o "$TMP/banner" "$TMP/banner.cpp" || { echo "FAIL: banner unit did not compile standalone (engine state leaked in?)"; return 1; }
  "$TMP/banner" || return 1
}

FAILED=0
banner_test || FAILED=1
[ "$FAILED" = "0" ] || { echo "FAILED: see the FAIL lines above"; exit 1; }
echo "ALL SECTIONS PASS"
