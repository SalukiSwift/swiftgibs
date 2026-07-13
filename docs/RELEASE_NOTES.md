# SwiftGibs v1.1.1

A fix release for v1.1. Windows and Linux builds are unchanged apart from the name fix below; **macOS users should definitely update** — the v1.1 mac app could not launch from Finder.

## Fixed

- **macOS: the app now launches.** The v1.1 `SwiftGibs.app` failed with "cannot find data files" when opened from Finder; the engine now locates the bundle's own data and stores your settings in `~/Library/Application Support/SwiftGibs`. The mac bundle also ships the SwiftGibs / Cues / Friends settings tabs it was missing. *(Contributed by Becky Conning — thanks!)*
- **Your player name now sticks.** v1.1 shipped a config line that reset the player name to "Swift" on every launch. Set your name once; it persists.

## Download

- **Windows:** `swiftgibs-win64.zip`
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` — first launch: right-click → **Open** → **Open** (one-time Gatekeeper step)
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz`

Settings and friends carry over. If v1.1 renamed you to "Swift", just set your name again — it'll stay put now.
