# SwiftGibs v1.1.4

Talk to us and stay current: in-game feedback, an update banner, and a one-click updater.

## New

- **In-game feedback (F8).** Press F8 mid-game to report a bug or send an idea: it snaps a screenshot of that exact moment, opens the feedback page right over the action, and posts your report to this repo's public issues - no account needed. Reports are anonymous unless you tick "sign with my player name", and each one carries the telemetry that helps us fix things: version, platform, map, mode, position, fps, and your match stats. A checkbox drops the screenshot if you'd rather not send it. F8 is only claimed if you haven't bound it to something else; the page is also under Esc > options > SwiftGibs > send feedback.
- **Update banner.** The main menu tells you when a newer SwiftGibs release is out. The check is silent and instant; offline just means no banner.
- **One-click updater.** Run `update-swiftgibs.bat` in the game folder and it downloads the latest release and updates in place. Your settings, friends, and stats are kept.
- **Version stamp.** The main menu always shows the client version in the bottom-right corner.
- **Desktop shortcut helper.** Run `make-shortcut.bat` once for a proper SwiftGibs desktop shortcut with the game's icon and no console window.

## Download

- **Windows:** `swiftgibs-win64.zip`
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - first launch: right-click, **Open**, **Open**
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz`
