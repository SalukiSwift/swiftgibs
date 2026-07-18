# SwiftGibs

**A stripped-down, instagib-only build of [Cube 2: Sauerbraten](http://sauerbraten.org/), tuned for clarity, speed, and low-end machines while staying compatible with official servers.**

SwiftGibs takes the classic open-source arena shooter and strips it to its fastest, most readable form: pure instagib (one shot, one kill), a flat high-visibility art style, a competitive config baked in, and quality-of-life features that make the game easier to *read*, never easier to *cheat*. Download a bundle, launch, and play. It joins the same public servers as stock Sauerbraten.

> **Why "SwiftGibs"?** Built by Swift for playing instagib with friends. Gibs included.

## Highlights

- **Instagib-first.** Insta-only menus, an insta-only server browser filter, and a config dialed for competitive rifle play (high FPS cap, clean view, no clutter).
- **Flat high-visibility players.** Everyone renders as a solid team colour: teammate blue, friend cyan, enemy red, friend-on-enemy orange. You read fights at a glance. Purely visual and client-side.
- **Flat low-detail world.** World textures crushed to a flat competitive look; fonts, HUD, and map thumbnails stay crisp. Runs on potatoes.
- **Expanded scoreboard.** Frags in every mode (including CTF), deaths, KDR, captures, optional accuracy and damage. All toggleable.
- **Friends system.** Name-based friends list; friends are highlighted in-game and on the minimap. Manage them from a dedicated Friends settings tab.
- **Swifties Bog.** A private server for Swift's crew. Type the password once in the Friends tab and the join button takes you straight there. (Power users: `keepserver salukiswift.com 28785 <password>` makes the browser row one-click too.)
- **Reload feedback, your way.** An optional 3-2-1 rifle-reload countdown (9 styles including Collapse and Edge-beats), an independent fire-ready flash (8 styles from a subtle Thin-ring to a bold Edge-pulse), and a tick-tick-tick-ding metronome. All off by default. Mix and match.
- **Hit and streak feedback.** Selectable hit-marker sounds with an adjustable volume and a preview button, a per-life killstreak counter with optional milestone dings, and a career stats page tracking your frags, deaths, accuracy, damage, and best streak.
- **Readable chat.** Scroll back through chat with the mouse wheel while you type, or open a dedicated Chat History page.
- **Non-obscuring teammate crosshair.** Over a teammate, your crosshair tints blue instead of the aim-blocking circle-slash icon (friendly fire is usually on).
- **Native settings.** All SwiftGibs options live in the regular Esc > options menu as SwiftGibs, Timing Cues, and Friends tabs. F3 is a quick-play launcher for instant bot matches.
- **Live previews.** Selecting any cue demonstrates it on the spot: countdown and ready-flash styles play out right over the menu (main menu included, with a pulsing crosshair where a style needs one), and hit sounds, volumes, and the killstreak ding audition as you click.
- **In-game feedback.** Found a bug or got an idea? Press **F8** mid-game (or Esc > options > SwiftGibs > send feedback) and your report lands on this repo's public issues, complete with a screenshot of that moment and the telemetry that helps us fix it (map, position, fps, match stats). Reports are anonymous unless you tick "sign with my player name". No account needed. F8 is only claimed if you haven't bound it yourself.
- **Easy updates.** The main menu tells you when a newer release is out; run `update-swiftgibs.bat` in the game folder and it fetches the latest version while keeping your settings, friends and stats.
- **Just works.** Auto-detects your monitor's native resolution and launches fullscreen on first run. No config needed.
- **Server-compatible.** No protocol changes; every feature is client-side. Play on any official or public Sauerbraten server.

## Download and play

Grab the latest build for your platform from the **[Releases](../../releases)** page.

### Windows
1. Download `swiftgibs-win64.zip` and unzip it.
2. Open the `swiftgibs-win64` folder and double-click `swiftgibs.bat`.
3. Optional: double-click `make-shortcut.bat` once to get a **SwiftGibs** shortcut on your
   Desktop with the proper icon - launch from there from then on.

### macOS (Apple Silicon)
1. Download `SwiftGibs-mac.zip` and unzip it to get `SwiftGibs.app`.
2. First launch only: right-click (or Control-click) `SwiftGibs.app`, choose **Open**, then **Open** again.
   macOS blocks unsigned apps on a normal double-click; this one-time step tells it you trust the app. After that, a normal double-click works.
   If it still refuses (newer macOS can be stricter): System Settings > Privacy & Security > "Open Anyway".

### Linux (x86-64)
1. Download `SwiftGibs-linux-x86_64.tar.gz` and extract it.
2. Run `./swiftgibs.sh`.
   Needs system SDL2, e.g. `sudo apt install libsdl2-2.0-0 libsdl2-image-2.0-0 libsdl2-mixer-2.0-0`.

Your settings and saved friends live in your user config directory and persist between updates.

## Playing

- Move and shoot like any Sauerbraten client. It's instagib: you spawn with the rifle, one hit kills.
- **F3** opens Quick Play: launch an instant bot match (FFA, Team, or CTF), add bots, or jump into settings.
- **Esc > options** has the SwiftGibs tab (server filter, scoreboard columns, friend highlighting, career stats, chat history, hit sounds, killstreak feedback, teammate crosshair, send feedback), the Timing Cues tab (reload countdown, ready flash, and metronome with volume - every choice previews itself over the menu), and the Friends tab (quick-add, who's in game, joining Swifties Bog, and a full manage-friends page).
- The server browser is filtered to instagib-family servers by default (toggle it in the SwiftGibs tab).

### Feedback cues

Independent settings under the Timing Cues tab (all off by default except where noted); picking any option plays a live demo:

| Setting | What it is | Options |
|---|---|---|
| Countdown | the 3-2-1 during the rifle's reload | **Off** (default), Rings, Pulse, Collapse, Sweep, Pips, Crosshair-Pulse, Digits, Edge-beats |
| Ready flash | the flash the instant you can fire again | **Off** (default), Pip, Dot, Thin-ring, Ring-ping, Bloom, Burst, Edge-pulse |
| Metronome | audio tick-tick-tick-ding over the reload | **Off** (default), Flat, Rising, plus volume |
| Hit sound | the marker sound when you land a hit | **Stock** (default) or an alternate, plus an adjustable volume and preview |
| Killstreak | per-life streak counter, with optional milestone dings | Counter **on** by default; milestone sound off |

## Design philosophy: clarity, not cheating

SwiftGibs adds quality-of-life and readability, never an unfair edge. The line we hold: a feature is fine if a spectator would call it "just easier to see," and out if it does something the base game deliberately won't let you.

Flat team colours, a clean HUD, and the teammate crosshair are all clarity and safety features (the teammate indicator ships in stock Sauerbraten). We deliberately do not add an enemy-target crosshair, aim assist, wall-hacks, or anything that gives an offensive advantage over players on a stock client. It stays a legit competitive config you can take onto public servers.

## Build from source

SwiftGibs is the vendored 2020 Sauerbraten source (`vendor/sauer2020/`) plus a stack of small, self-contained patches (`patches/`) and a pure-data overlay (`overlay/`). The engine changes are all client-side.

```bash
# apply the patch stack to a build dir
build/apply-patches.sh /tmp/sg-src

# build the client for your platform
build/make-engine-linux.sh          # Linux (native)
build/make-engine-win.sh            # Windows (mingw cross-compile)
#   macOS: built in CI on an Apple Silicon runner (.github/workflows/mac.yml)

# assemble a playable bundle (engine + stripped data + overlay)
build/make-bundle-win.sh            # Windows .zip
build/make-bundle-mac.sh            # macOS .app (APP_DIR=/tmp/SwiftGibs.app for a local build;
                                    #   re-signed with Apple codesign on macOS, rcodesign on Linux)
```

- `patches/NN-*.patch` are the engine changes, applied in order. Each is one focused feature (server filter, scoreboard, friends, reload feedback, flat models, and so on).
- `overlay/` holds menus, autoexec, crosshair, and flat skins: pure data layered over the stock game.
- `build/integrate-menus.sh` splices the SwiftGibs, Timing Cues, and Friends tabs into the stock options menu at bundle time.
- `tools/strip-assets.sh` produces the flat low-res data tree from a Sauerbraten install (or the official release archive).

Releases are built reproducibly in GitHub Actions from the official 2020 Sauerbraten data, so no local install is required.

## Compatibility

SwiftGibs is version-locked to the 2020 Sauerbraten release: the patched engine and its bundled game data come from the same release, so maps, shaders, and models all match. Every feature is client-side with no protocol changes, so SwiftGibs connects to any standard Sauerbraten server and plays cleanly alongside stock clients.

## Credits and license

SwiftGibs is a modified build of Cube 2: Sauerbraten, created by Wouter van Oortmerssen, Lee Salzman, Mike Dysart, Robert Pointon, Quinton Reeves, and the Sauerbraten community. All original engine code and game content belong to their respective authors.

- Engine code is under the zlib license (see `vendor/sauer2020/`). SwiftGibs' modifications are provided under the same license and are plainly marked as an altered version.
- Game content (maps, textures, models, sounds) ships under its original licenses; the license files travel inside each release bundle.

SwiftGibs is a fan-made competitive config, not affiliated with or endorsed by the Sauerbraten project.
