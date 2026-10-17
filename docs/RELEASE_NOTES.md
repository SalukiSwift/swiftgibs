# SwiftGibs v1.4.0

Two new match cues for CTF and every other timed mode, menu tabs that no longer switch by
accident, and a fix for friends looking like teammates outside team modes.

## End-of-match banner

- When a match ends you now get a short centre-screen verdict instead of having to read the
  scoreboard: **VICTORY**, **DEFEAT** or **DRAW** in team modes, your placing in FFA
  ("3rd of 8", gold "VICTORY - 1st of 8" if you topped it), **WON** / **LOST** in a duel,
  and "GOOD WINS" style wording when spectating. It stays about four seconds and fades.
- It never fires for a match you did not play: joining a server that is already at
  intermission shows nothing.
- On by default. Toggle it on the new **match cues** page (Esc > options > Cues tab >
  "match cues.."), or `sgendbanner 0`.

## Final-minute timer cue

- With the clock hidden (the SwiftGibs default), the last minute used to pass unannounced.
  Now the clock appears at 0:59 in the low-time colour and breathes, and for the final ten
  seconds it kicks on each second with one beep per second, so you know exactly how long
  you have for that last cap or frag.
- Three settings on the match cues page: **Off**, **Pulse** (clock only) and **Pulse + beeps**
  (the default), plus a beep volume slider that plays the beep as you drag it.
- Nothing plays at intermission or during a new match's early minutes; the cue only runs in
  live timed matches. Both cues are saved with your profile.

## Menu tabs switch on click

- Hovering the cursor over a tab header used to switch the options tab, which made it easy to
  land on the wrong tab while reaching for a setting. Tabs now switch when you click them.
- Existing installs are switched over once on first launch. If you preferred hover, untick
  "click tab" on the first page of Esc > options and that choice sticks.

## Fixed

- **Friends no longer look like teammates in FFA and duels.** Friends were drawn in the
  ally-cyan skin outside team modes, which made a friend on the other side of a 1v1 read as
  an ally. They now get the ordinary opponent skin there (orange only if you have opted in to
  enemy-friend highlighting); team modes are unchanged.

## Download

- **Windows:** `swiftgibs-win64.zip` - or run `update-swiftgibs.bat` in your existing folder
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - or double-click `update-swiftgibs.command` next to the app
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz` - or run `update-swiftgibs.sh` in the game folder


# SwiftGibs v1.3.1

A robustness release: Linux now runs out of the box, a startup crash on broken graphics
drivers is fixed, and some build/CI hardening went in alongside. No gameplay changes.

## Linux runs out of the box

- **No system SDL packages needed.** The Linux download now bundles its own lean copies of
  the three SDL2 runtime libraries it needs (SDL2, SDL2_image, SDL2_mixer), built from the
  official SDL source with everything except what SwiftGibs actually uses stripped out. A
  fresh machine with nothing installed can just run the game.
- Already have a newer SDL2 on your system and want to use it instead? Set
  `SWIFTGIBS_SYSTEM_SDL=1` before launching to opt back into your distro's copies.
- If a previous download only partly extracted (interrupted transfer, disk full, etc.), the
  launcher now says so clearly instead of failing with a confusing error.

## Fixed a startup crash on broken or software-only graphics drivers

- Machines with broken or software-only OpenGL (some VMs, remote desktop sessions, old or
  misconfigured drivers) could crash immediately on startup with a stack overflow. A
  reentrancy guard now breaks the recursion that caused it, and the one texture load that
  triggered it in the first place has been fixed at the source. Everything renders exactly
  the same as before on a normal, working graphics setup.

## Small build and CI hardening

- The release build now checks that the bundled SDL libraries actually cover every symbol
  the client needs, so a version bump or repin that breaks compatibility fails the build
  instead of shipping something broken.
- The SDL version pins used across the Linux and macOS builds are now checked for agreement,
  and downloads that fail partway through clean up after themselves instead of leaving a
  truncated file behind.

## Download

- **Windows:** `swiftgibs-win64.zip` - or run `update-swiftgibs.bat` in your existing folder
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - or double-click `update-swiftgibs.command` next to the app
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz` - or run `update-swiftgibs.sh` in the game folder
