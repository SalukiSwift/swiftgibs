# SwiftGibs v1.2.0

Instant replays, video export, and a smarter client. This is the biggest SwiftGibs release yet.

## Replay clips and recordings

- **F10 saves the last minute of play as a clip**, any time, from a rolling in-memory buffer.
  Nothing is written to disk until you ask. Clips are standard demo files, so they play back in
  any Sauerbraten client.
- **F9 starts and stops a manual recording** of the whole match, and there is an optional
  record-every-match mode plus an optional auto-clip on killstreaks.
- **Clips get their own tab** in Esc, options, with a browser page: newest first, labelled by
  time, map and mode, one click to watch.
- Playback has been tuned hard for fidelity: your view is reconstructed on the recording's own
  timeline, kills land with the crosshair exactly on the victim (pause on a kill frame and
  check), and the whole scene shares one clock so beams, sounds and aim always agree.

## Video export

- **Export any clip to MP4 or WebM** from the export page: pick resolution up to your own,
  frame rate, quality, and whether to include the game's audio. Everything is bundled; there is
  nothing to install.
- **Export from another player's point of view.** Pick any player found in the clip. Their
  shots line up just like yours. (Real players only; a bot's view has no movement data.)
- **Lossless export** (FFV1 in MKV) for editing masters, with honest size estimates shown
  before you start.
- **Name your export** or keep the automatic timestamped name. When the export finishes you are
  returned to the main menu with a confirmation line.
- Exports capture at exactly even frame timing, show your normal HUD (toggleable for a clean
  cinematic look), and play through mid-clip map changes instead of giving up.

## Server browser

- **Favourites:** tick the checkbox on any server row to pin it to the top with a gold
  highlight. Survives restarts.
- **Password prompt:** clicking a passworded server now pops a password box in the menu, and a
  successful password is remembered per server and supplied automatically next time. (Saved
  passwords are stored as plain text in your game folder, so use throwaway passwords for game
  servers.)

## Smarter auto-respawn

- **AFK-aware:** if you have not touched the mouse or keyboard for 30 seconds and you die, the
  client stops auto-respawning you until you are back, and after a minute dead while idle it
  moves you to spectator so your team is not carrying a ghost. It only ever does that on
  servers where you can rejoin yourself, so it can never trap you. Both thresholds are
  adjustable in the new idle settings page, and 0 disables either.

## Also

- Per-match FPS statistics (average, 1 percent lows, stutter count) with an in-game page and a
  CSV benchmark log.
- The reload metronome's final ready ping has its own toggle (from v1.1.10).
- Many smaller fixes found in real playtesting, including menu scaling, click handling in the
  server browser, and export reliability.

## Download

- **Windows:** `swiftgibs-win64.zip` - or run `update-swiftgibs.bat` in your existing folder
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - or double-click `update-swiftgibs.command` next to the app
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz` - or run `update-swiftgibs.sh` in the game folder
