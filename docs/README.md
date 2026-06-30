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
- Friends on the **enemy team** render in **bright purple** (still clearly an enemy, just marked as your friend).
- The old `*` next to friend names is gone — the green name/color is the marker now.
- Team modes only (FFA still uses the green name highlight from M3). Toggle with `/friendmodels`,
  `/friendblip` (and the master `/highlightfriends`). Colors are baked into the skins/blip textures;
  regenerate with `tools/make-friend-skins.sh` (tune `GREEN_MOD`/`PURPLE_MOD`).

## Reload countdown (rifle)
A rhythmic countdown fills the rifle's 1.5s reload, then the crosshair snaps back to full when you can fire.
The crosshair stays visible but **faded** during the count (brightening as you near ready) so you can keep aiming.
Pick a style or turn it off in **F3 → "reload countdown..."** — seven styles plus Off:
- **Number styles:** Drift (fade + shrink in place), Slam (bold amber punch), Zoom (rushes in, red), Tick (small & subtle).
- **Graphical styles:** Rings (3 cyan rings collapse inward, one per beat), Wedges (3 amber reticle prongs count down), Pulse (a bright ring pings outward each beat).
Your choice persists. (Console: `/reloadcount 0..7`; preview with `/reloadcountdemo`.)
