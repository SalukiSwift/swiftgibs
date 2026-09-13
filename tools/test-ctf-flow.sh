#!/usr/bin/env bash
# Regression guard for the CTF match-flow round (patch 22). Extracts the REAL decision code from a
# patched tree and asserts its full matrix, so a logic hole a screenshot cannot show (a wrong
# placement count, "you won" for a spectator) cannot come back unnoticed.
#   1. end-of-match banner: wording + colour class (sgendbannerresult, fpsgame/fps.cpp)
#   2. round-end escalation: the clock's whole-second count, the once-per-second beep latch and the
#      final-minute pulse window (the sgtimercue unit, fpsgame/fps.cpp)
#   3. flag-not-home warning: the can't-capture decision (sgflagwarnactive, fpsgame/ctf.h) and the
#      plain-ctf gate its HUD call passes it
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

# ---- 2. round-end escalation -------------------------------------------------------------------
# Every threshold counts TOTAL seconds left, the way the clock counts them before drawgameclock()
# splits off the minutes: a count taken after that split reads 1:10 as 10 and beeps or pulses in the
# last seconds of every minute. The latch is fed frame by frame the way updateworld() feeds it
# (msleft = maplimit-lastmillis, live = every gate but the clock) at normal and 10x game speed,
# through hitches, a paused clock, intermission and overtime.
timercue_test() {
  echo "== round-end escalation =="
  extract_block "$TREE/fpsgame/fps.cpp" "sgtimercue" "$TMP/timercue-unit.inc" || return 1
  cat > "$TMP/timercue.cpp" <<'CPP'
#include <stdio.h>
#include <string.h>
#include <math.h>
// Minimal stand-ins for the only engine pieces the unit may touch (shared/tools.h). Anything else it
// reaches for (maplimit, lastmillis, intermission, sgtimercue...) is engine state and fails to
// compile here, which is the point.
#define PI (3.1415927f)
template<class T> static inline T max(T a, T b) { return a > b ? a : b; }
template<class T> static inline T min(T a, T b) { return a < b ? a : b; }

#include "timercue-unit.inc"

static int ran = 0, bad = 0;
static void check(const char *what, bool ok, const char *got, const char *want)
{
    printf("%s %-72s -> %s (want %s)\n", ok ? "  ok  " : "  FAIL", what, got, want);
    ran++;
    if(!ok) bad++;
}

static void remaining(int msleft, int want, const char *reads)
{
    char what[96], got[16], w[16];
    snprintf(what, sizeof(what), "count: %dms left is %s", msleft, reads);
    int r = sgtimerremaining(msleft);
    snprintf(got, sizeof(got), "%d", r); snprintf(w, sizeof(w), "%d", want);
    check(what, r == want, got, w);
}

// One match clock seen frame by frame, the beeps it produced written out in order (a runaway latch
// that beeps every frame is cut off with "..." rather than overrunning the buffer).
struct clockrun
{
    int lastbeep, len; char beeps[256];
    clockrun() : lastbeep(-1), len(0) { beeps[0] = '\0'; }
    void frame(int msleft, bool live)
    {
        int r = sgtimerremaining(msleft);
        if(!sgtimerbeepdue(live, r, lastbeep)) return;
        if(len >= 200) { if(beeps[len-1] != '.') len += snprintf(beeps + len, sizeof(beeps) - len, " ..."); return; }
        len += snprintf(beeps + len, sizeof(beeps) - len, len ? " %d" : "%d", r);
    }
    void run(int from, int to, int step) { for(int t = from; t >= to; t -= step) frame(t, true); }
};
static void beeps(const char *what, const clockrun &c, const char *want)
{
    char w[64]; snprintf(w, sizeof(w), "\"%s\"", want);
    char got[300]; snprintf(got, sizeof(got), "\"%s\"", c.beeps);
    check(what, !strcmp(c.beeps, want), got, w);
}

// msleft of each pulse peak (a sample above the one before and not below the one after), 10ms samples.
static int peaks(int from, int to, int *at, int maxat)
{
    int n = 0; float prev = 0, cur = 0, next = 0, g;
    for(int t = from; t >= to; t -= 10)
    {
        sgtimerpulse(t + 10, prev, g); sgtimerpulse(t, cur, g); sgtimerpulse(t - 10, next, g);
        if(cur > prev && cur >= next && n < maxat) at[n++] = t;
    }
    return n;
}
static bool evenlyspaced(const int *at, int n, int gap, int mod)
{
    if(n < 3) return false;
    for(int i = 1; i < n; i++) if(at[i-1] - at[i] != gap) return false;
    return mod <= 0 || at[0] % mod == 0;
}

int main()
{
    const char *all10 = "10 9 8 7 6 5 4 3 2 1";
    // ---- the count: total seconds, exactly as the clock shows them (1:00 is 60, 0:59 is 59) ----
    remaining(600000, 600, "10:00");
    remaining(70000, 70, "1:10 (70, not the 10 of 1:10)");
    remaining(60000, 60, "1:00");
    remaining(59001, 60, "still 1:00");
    remaining(59000, 59, "0:59, where the stock clock turns gameclocklowcolour");
    remaining(10001, 11, "0:11");
    remaining(10000, 10, "0:10");
    remaining(9001, 10, "still 0:10");
    remaining(1, 1, "0:01");
    remaining(0, 0, "0:00");
    remaining(-2500, 0, "past the limit, 0:00");

    // ---- the beep latch: 10 down to 1, each exactly once, however the frames fall ----
    { clockrun c; c.run(75000, -2000, 16); beeps("beeps: 60fps frames from 1:15 to past the limit", c, all10); }
    { clockrun c; c.run(75003, -2000, 167); beeps("beeps: gamespeed 1000 frames (167ms of game time each)", c, all10); }
    { clockrun c; c.run(75000, -2000, 1000); beeps("beeps: frames landing exactly on every second change", c, all10); }
    { clockrun c; c.run(12000, -2000, 1500); beeps("beeps: 1.5s hitches beep each new value once, never a missed one late", c, "9 8 6 5 3 2"); }
    { clockrun c; c.run(75000, 5000, 16); for(int i = 0; i < 500; i++) c.frame(5000, true); c.run(4984, -2000, 16);
      beeps("beeps: clock paused at 0:05 for 500 frames", c, all10); }
    { clockrun c; for(int t = 75000; t >= -2000; t -= 16) c.frame(t, false);
      beeps("beeps: gate closed throughout (cue below 2, untimed, not connected)", c, ""); }
    { clockrun c; for(int t = 15000; t >= -2000; t -= 16) c.frame(t, t > 4000);
      beeps("beeps: intermission at 0:04 (score limit): nothing after it", c, "10 9 8 7 6 5"); }
    { clockrun c; for(int t = 15000; t >= -2000; t -= 16) c.frame(t, t <= 6500);
      beeps("beeps: sound switched on at 0:06.5 joins at the current second", c, "7 6 5 4 3 2 1"); }
    { clockrun c; c.run(75000, 5000, 16); c.run(120000, -2000, 16);
      beeps("beeps: overtime at 0:05 puts 2:00 back: re-armed, 10..1 again", c, "10 9 8 7 6 5 10 9 8 7 6 5 4 3 2 1"); }
    { clockrun c; c.run(15000, 9500, 16); c.run(120000, -2000, 16);   // only a re-arm lets a countdown restart on the value last beeped
      beeps("beeps: time moved back out right after the 0:10 beep: the next 0:10 beeps", c, "10 10 9 8 7 6 5 4 3 2 1"); }
    { clockrun c; c.run(15000, 3000, 16); c.run(7000, -2000, 16);
      beeps("beeps: limit moved from 0:03 to 0:07: the new seconds beep again", c, "10 9 8 7 6 5 4 3 7 6 5 4 3 2 1"); }

    // ---- the pulse: on from 0:59 (with the low colour) to 0:01, stronger and faster for the last ten ----
    { bool any = false; float s, g; char got[48] = "none";
      for(int t = 600000; t >= 59001; t -= 7) if(sgtimerpulse(t, s, g) || s != 1 || g != 0) { snprintf(got, sizeof(got), "pulse at %dms", t); any = true; break; }
      check("pulse: none while the clock reads 1:00 or more (10:00 down to 1:00)", !any, got, "none"); }
    { float s, g; bool on = sgtimerpulse(59000, s, g);
      check("pulse: starts at 0:59, the frame the stock clock turns low colour", on, on ? "on" : "off", "on"); }
    { float s, g; bool on = sgtimerpulse(1, s, g);
      check("pulse: still on at 0:01", on, on ? "on" : "off", "on"); }
    { bool any = false; float s, g;
      for(int t = 0; t >= -5000; t -= 7) if(sgtimerpulse(t, s, g) || s != 1 || g != 0) any = true;
      check("pulse: none at 0:00 or past the limit", !any, any ? "pulse" : "none", "none"); }
    { bool ok = true; float s, g; char got[64] = "all within";
      for(int t = 61000; t >= -1000; t--) { sgtimerpulse(t, s, g); if(s < 1 || g < 0 || g > 1) { snprintf(got, sizeof(got), "scale %.3f glow %.3f at %dms", s, g, t); ok = false; break; } }
      check("pulse: never smaller than the stock clock, glow within 0..1", ok, got, "all within"); }
    { float s, g, minute = 0, ten = 0, minuteg = 0, teng = 0; char got[64];
      for(int t = 59000; t > 10000; t--) { sgtimerpulse(t, s, g); minute = max(minute, s); minuteg = max(minuteg, g); }
      for(int t = 10000; t >= 1; t--) { sgtimerpulse(t, s, g); ten = max(ten, s); teng = max(teng, g); }
      snprintf(got, sizeof(got), "peak scale %.2f vs %.2f, glow %.2f vs %.2f", ten, minute, teng, minuteg);
      check("pulse: stronger in the last ten seconds than before", ten > minute && teng > minuteg, got, "both higher"); }
    { int at[64], n = peaks(58990, 10010, at, 64); char got[48]; snprintf(got, sizeof(got), "%d peaks, first at %dms", n, n ? at[0] : 0);
      check("pulse: breathes once every 2s from 0:59 to 0:11", evenlyspaced(at, n, 2000, 0), got, "every 2000ms"); }
    { int at[64], n = peaks(9990, 10, at, 64); char got[48]; snprintf(got, sizeof(got), "%d peaks, first at %dms", n, n ? at[0] : 0);
      check("pulse: kicks every 1s in the last ten, on the second change (the beep)", evenlyspaced(at, n, 1000, 1000), got, "every 1000ms, on whole seconds"); }
    { char got[16]; int c = sgtimerglow(0xFFC040, 0); snprintf(got, sizeof(got), "%06X", c);
      check("glow 0 keeps the stock colour", c == 0xFFC040, got, "FFC040"); }
    { char got[16]; int c = sgtimerglow(0xFFC040, 1); snprintf(got, sizeof(got), "%06X", c);
      check("glow 1 is white", c == 0xFFFFFF, got, "FFFFFF"); }
    { char got[16]; int c = sgtimerglow(0x204080, 0.5f); snprintf(got, sizeof(got), "%06X", c);
      int r = (c>>16)&0xFF, gr = (c>>8)&0xFF, b = c&0xFF;
      check("glow 0.5 lands each channel halfway to white", r >= 0x8F && r <= 0x90 && gr >= 0x9F && gr <= 0xA0 && b >= 0xBF && b <= 0xC0, got, "8F9FBF (+1)"); }

    if(bad) { printf("FAILED: %d of %d case(s)\n", bad, ran); return 1; }
    printf("ALL %d CASES PASS\n", ran);
    return 0;
}
CPP
  g++ -O0 -Wall -fsigned-char -I"$TMP" -o "$TMP/timercue" "$TMP/timercue.cpp" || { echo "FAIL: timer cue unit did not compile standalone (engine state leaked in?)"; return 1; }
  "$TMP/timercue" || return 1
}

# ---- 3. flag-not-home warning ------------------------------------------------------------------
# A carrier cannot capture while their own flag is off its stand, so the warning fires only in that
# moment: plain ctf, carrying the enemy flag, own flag not home (carried or dropped), and strictly
# closer to its stand than sgflagwarndist. drawhud() gathers those inputs from the real flags and the
# unit decides, so every other combination must stay quiet, including exactly at the limit. The HUD
# call must gate on m_ctf_only: protect and hold share ctf.h's drawhud() but score differently, and a
# plain m_ctf gate would switch the warning on in both.
flagwarn_test() {
  echo "== flag-not-home warning =="
  extract_block "$TREE/fpsgame/ctf.h" "sgflagwarn" "$TMP/flagwarn-unit.inc" || return 1
  cat > "$TMP/flagwarn.cpp" <<'CPP'
#include <stdio.h>
#include <string.h>
// No engine stand-ins at all: the unit takes plain values. Anything it reaches for (m_ctf_only,
// sgflagwarndist, flags, the hud player...) is engine state and fails to compile here, which is the point.

#include "flagwarn-unit.inc"

static int ran = 0, bad = 0;
static void expect(const char *what, bool ctfonly, bool carrying, bool ownhome, float dist, int warndist, bool want)
{
    bool got = sgflagwarnactive(ctfonly, carrying, ownhome, dist, warndist);
    printf("%s %-58s ctf %d carrying %d own home %d, %6g from stand, limit %3d -> %-5s (want %s)\n",
           got == want ? "  ok  " : "  FAIL", what, ctfonly, carrying, ownhome, dist, warndist, got ? "WARN" : "quiet", want ? "WARN" : "quiet");
    ran++;
    if(got != want) bad++;
}

int main()
{
    const int D = 48;   // sgflagwarndist default: 3 x FLAGRADIUS (16), the real capture radius
    // ---- the can't-cap moment: carrying, own flag away, near its stand ----
    expect("running in to the stand", true, true, false, 40, D, true);
    expect("inside the capture radius, where a home flag would score", true, true, false, 15.9f, D, true);
    expect("standing on the stand", true, true, false, 0, D, true);
    expect("just inside the limit", true, true, false, 47.99f, D, true);
    // ---- any one condition missing: quiet ----
    expect("not plain ctf (another mode, or protect / hold)", false, true, false, 40, D, false);
    expect("not carrying", true, false, false, 40, D, false);
    expect("own flag home: the capture works", true, true, true, 40, D, false);
    expect("far from the stand", true, true, false, 900, D, false);
    expect("exactly at the limit (strictly less than)", true, true, false, 48, D, false);
    expect("no own flag found (the gather's home, 1e16 away)", true, true, true, 1e16f, D, false);
    // ---- the limit is sgflagwarndist over its whole range (16..256) ----
    expect("limit 16: 15.9 is inside", true, true, false, 15.9f, 16, true);
    expect("limit 16: exactly 16 is outside", true, true, false, 16, 16, false);
    expect("limit 256: 48 is inside (a wider limit warns earlier)", true, true, false, 48, 256, true);
    expect("limit 256: 255.9 is inside", true, true, false, 255.9f, 256, true);
    expect("limit 256: exactly 256 is outside", true, true, false, 256, 256, false);
    // ---- all 16 combinations of (plain ctf, carrying, own flag home, near): exactly one warns ----
    {
        char got[512] = "";
        int len = 0;
        for(int c = 0; c < 16; c++)
        {
            bool ctf = c&1, carrying = c&2, ownhome = c&4, near = c&8;
            if(!sgflagwarnactive(ctf, carrying, ownhome, near ? 20.0f : 100.0f, D)) continue;
            len += snprintf(got + len, sizeof(got) - len, "%s(ctf %d, carrying %d, own home %d, near %d)", len ? " " : "", ctf, carrying, ownhome, near);
        }
        const char *want = "(ctf 1, carrying 1, own home 0, near 1)";
        bool ok = !strcmp(got, want);
        printf("%s %-58s -> %s (want %s)\n", ok ? "  ok  " : "  FAIL", "all 16 combinations: only the can't-cap moment warns", len ? got : "none", want);
        ran++;
        if(!ok) bad++;
    }

    if(bad) { printf("FAILED: %d of %d case(s)\n", bad, ran); return 1; }
    printf("ALL %d CASES PASS\n", ran);
    return 0;
}
CPP
  g++ -O0 -Wall -fsigned-char -I"$TMP" -o "$TMP/flagwarn" "$TMP/flagwarn.cpp" || { echo "FAIL: flag warning unit did not compile standalone (engine state leaked in?)"; return 1; }
  "$TMP/flagwarn" || return 1
  local gated
  gated="$(tr -d '\r' < "$TREE/fpsgame/ctf.h" | grep -c 'sgflagwarnactive(m_ctf_only, ' || true)"
  [ "$gated" = "1" ] || { echo "FAIL: expected exactly 1 call gating the unit on m_ctf_only in fpsgame/ctf.h, found $gated - a plain m_ctf gate would warn in protect and hold"; return 1; }
  echo "  ok   the HUD call gates the unit on m_ctf_only"
}

FAILED=0
banner_test || FAILED=1
timercue_test || FAILED=1
flagwarn_test || FAILED=1
[ "$FAILED" = "0" ] || { echo "FAILED: see the FAIL lines above"; exit 1; }
echo "ALL SECTIONS PASS"
