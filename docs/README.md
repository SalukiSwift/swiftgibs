# SwiftGibs (M1, Windows)

Stripped-down instagib Sauerbraten with Swift's competitive config. Unzip and run.

## Install
1. Unzip `swiftgibs-win64.zip` anywhere.
2. Double-click `swiftgibs.bat`.

## Play
- It launches at your monitor's native resolution with the competitive config.
- Press **F3** for the SwiftGibs menu: connect to the server, or start a local instagib match vs bots.
- For Swift's 1440p rig: open the console (`T`, then `/exec display-mine.cfg`) or add `exec display-mine.cfg` to `autoexec.cfg`.

## What's different from stock
- Frags + deaths show on the scoreboard in **every** mode, including CTF.
- Only ~12 competitive maps; all textures are low-res (tiny download, runs on weak PCs).

## M2 features (patched engine)
- **Server browser shows only instagib servers** by default. Toggle in the F3 menu
  ("server browser: insta servers only") or `/filterinstaservers 0` in the console.
- **Scoreboard** shows frags + deaths + **KDR** in every mode (including CTF). Enable
  accuracy/damage columns in the F3 menu or with `/showacc 1` / `/showdmg 1`
  (accurate for your own row; other players need server extinfo).
- ARM/Raspberry Pi build is **experimental** (cross-compiled, not yet tested on hardware).

## M3 features (friends + scoreboard options)

- **Friends:** open the **friends** menu from the main menu, the in-game **Esc** menu, or
  **F3 → "friends..."**. Add a friend by typing their name (press Enter), or pick from the
  players currently in your game. A friend's name shows **green** in the scoreboard, kill log,
  chat, join/leave messages, and above their head. Your own name shows **cyan**, and your frags
  read "**Swift** fragged …" instead of "you". Friends save to `friends.cfg` and persist across
  launches. Toggle highlighting with `/highlightfriends` and `/highlightself`; retune colors
  with `/friendcolor`, `/selfcolor`.

- **Scoreboard columns:** **F3 → "scoreboard columns..."** lets you toggle the frags / deaths /
  KDR / accuracy / damage / captures columns on and off, plus the friend/self highlight toggles.

**Known notes:**
- The "in game now" list in the friends menu may include your own name during solo/local play
  (harmless).
- On non-instagib official servers, a friend's powerup icon may sit slightly off next to their
  overhead name (never happens in instagib).

## Friend team visuals (green / purple)
- Friends on **your team** render as a **green** player model and a **green triangle** on the minimap.
- Friends on the **enemy team** render in **bright red-leaning purple** (still clearly an enemy, just marked as your friend).
- The old `*` next to friend names is gone — the green name/color is the marker now.
- Team modes only (FFA still uses the green name highlight from M3). Toggle with `/friendmodels`,
  `/friendblip` (and the master `/highlightfriends`). Colors are baked into the skins/blip textures;
  regenerate with `tools/make-friend-skins.sh` (tune `GREEN_MOD`/`PURPLE_MOD`).

## Reload countdown (rifle)
A **beat-locked** countdown fills the rifle's 1.5s reload, then a bright **green READY flash** + crosshair
pop fires the instant you can shoot again — so it's unmistakable when you're ready. The crosshair stays
**faded but aimable** during the count (brightening toward ready). Colours count you down:
**cyan → amber → red**, then **green** GO.
Pick a style or turn it off in **F3 → "reload countdown..."** — seven styles plus Off:
- **Rings** — 3 cyan rings, one drops per beat, a punch on each beat.
- **Pulse** — an expanding ring ping per beat (additive glow), brightest on the last beat.
- **Collapse** — a ring contracts into the crosshair, arriving exactly at fire-time ("charging up").
- **Sweep** — a clock-arc fills around the crosshair, completing the full circle right at ready.
- **Pips** — 3 charges ringing the crosshair, depleting one per beat.
- **Crosshair Pulse** — the crosshair itself breathes on each beat (minimalist, no extra HUD).
- **Digits** — a small 3-2-1 number **below** the crosshair (never covers your aim).
Your choice persists. (Console: `/reloadcount 0..7`; preview with `/reloadcountdemo`.)

### Reload metronome (sound)
An optional **audio metronome** over the reload — **tick · tick · tick · ding!**, where the ticks land
on the beats (with the pulses/blips) and the **ding is the instant you can fire**. Reload by ear, even
with the visuals off. Two flavours: **Flat** (same tick each beat) or **Rising** (ticks climb in pitch
up to the ding). Pick it in **F3 → "reload sound (metronome)..."** (or `/reloadmetronome 0..2` — 0 off,
1 flat, 2 rising); volume via `/reloadmetrovol 0..1`. Default **off**. The sounds live in
`packages/sounds/swiftgibs/` — swap in your own `.ogg` if you like.

## Map-vote panel (intermission)
At the end of a match a **pop-up panel** shows the maps people are voting for — each with a **mapshot
preview**, its game mode, a **live vote count**, and a **vote** button. **Click a mapshot or its button to
cast (or change) your vote** — no more squinting at the tiny top-left log. The current leader is marked
**`>`** and your own pick is tagged **(your vote)**; the list is sorted most-voted first.

It **auto-opens at intermission** (toggle that with the **"auto-open at intermission"** checkbox in the
panel, or `/mapvotepopup 0`), and you can open it any time with the **`V`** key. The console still prints
the usual suggest messages.

This is **client-side only** (so SwiftGibs stays compatible with normal Sauerbraten servers): the counts
are reconstructed from the server's *"X suggests &lt;mode&gt; on map &lt;map&gt;"* messages. On stock servers
that's accurate; a server that rewords those messages just shows fewer/no counts — it never breaks. Maps
without a mapshot show a placeholder cube; on a very busy server only the top few candidates fit
(the rest are notice-lined).

## Flat player models
Players render as clean **flat solid team colours** for maximum visibility — the normal character shape,
skinned in one solid colour so you can read teams and friends at a glance:

- **teammate blue · friend cyan · enemy red · friend-on-enemy orange**

The minimap friend blip is **cyan** to match. Models are rendered bright but not blown out
(`fullbrightmodels 90` — high enough to see clearly in dark maps, low enough to keep the colour vivid). This
is **purely visual and client-side**, so it stays fully compatible with official servers.
