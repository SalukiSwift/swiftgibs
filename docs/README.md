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
