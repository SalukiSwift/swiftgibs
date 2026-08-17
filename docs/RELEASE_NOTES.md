# SwiftGibs v1.3.0

A smaller download, shorter clips by default, and steadier feedback/update networking under
the hood.

## Campaign content removed

- **The single-player campaign is gone.** The campaign menu, the 11 campaign maps, and sounds
  that were only used by them are out of the bundle. Multiplayer instagib maps are untouched -
  nothing you actually play on has changed.
- **Smaller download:** about 569MB zipped for Windows.
- Upgrading from an older version keeps roughly 23MB of now-unused campaign files on disk (the
  updater only adds and changes files, it never deletes them) - a fresh install does not have
  them at all.

## Clips default to 20 seconds

- **F10 clips are 20 seconds by default now, not a minute**, and the setting is in seconds
  (5-600) instead of minutes.
- Existing configs and saved settings profiles are migrated automatically to the new default
  the first time they load under v1.3.0. If you had already tuned your own clip length, set it
  once more after updating and it will stick from then on.
- You may see one harmless red "valid range" line in the console on first launch while your old
  config is read - the correct 20-second default is applied right after it.

## Feedback and update checks reworked

- The plain-HTTP networking behind in-game feedback (F8) and the launch-time update check was
  rebuilt internally: clearer failure messages, and a fix for a macOS build issue that had been
  silently blocking new mac releases.
- The update check now shows "checking for updates.. (esc to skip)" instead of possibly hanging
  silently on a bad connection - press Esc to skip it if it's ever slow.

## Download

- **Windows:** `swiftgibs-win64.zip` - or run `update-swiftgibs.bat` in your existing folder
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - or double-click `update-swiftgibs.command` next to the app
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz` - or run `update-swiftgibs.sh` in the game folder
