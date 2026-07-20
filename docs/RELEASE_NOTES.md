# SwiftGibs v1.1.5

The biggest SwiftGibs release yet: new timing cues, hit markers, streak fx, a whole-map overlay, deep zoom, weapon sounds with real pitch control, a sensitivity translator, and reorganised menus.

## New

- **Hit markers.** Visual confirmation at your crosshair every time you land a shot: X-flash (on by default), Ring-out, or Notch. Scales with damage, pairs with your hit sound. Pick yours in Cues.
- **New countdowns: Slam and Orbit.** Two punchy, beat-locked replacements for the weakest reload countdowns. Slam hammers bars in from the screen edges one beat at a time; Orbit laps a comet around your crosshair, spiralling inward until it dives at fire-time. (Rings, Sweep, and Pips retired.)
- **Cue colours.** Hue-shift, monochrome, and opacity controls for the countdown and the ready flash, with live previews as you drag. Defaults keep the classic look.
- **Streak fx.** Killstreak milestones now hit: "N STREAK" slams centre-screen with a shockwave (or pick the subtle counter pulse, or turn it off). Plus a streak leaderboard: your top 5 killstreaks ever, with the map and date each was set, on the career stats page, and an optional best-streak scoreboard column.
- **Expanded map.** Press M for a whole-stage overhead map with your position and facing, teammates, friends, and flag positions live. Teammates only, never enemies. Press M again to close.
- **Deep zoom.** Hold a thumb button (Mouse6/7) for a much tighter zoom than right-click, for picking off far targets. Strength slider in the SwiftGibs tab.
- **Flag-carry popup.** "YOU HAVE THE FLAG - RUN IT HOME" punches up the moment you grab it, so a flag never goes unnoticed again. On by default, toggleable.
- **Weapon sounds.** Give your rifle a Laser, Zap, or Thump fire sound, and add an optional reload-charge soundscape (rising laser charge or building hum) over the 1.5s reload. Your ears only: enemies always sound stock so you can still read their shots.
- **Pitch everything.** A real pitch engine: hit sounds, fire sounds, and reload charges all have continuous pitch sliders from 50% to 200%, previewed live.
- **Sensitivity translator.** Bring your aim from CS/Source/TF2, Quake, Apex, Overwatch, CoD, or Valorant: type your sens, get the exact SwiftGibs equivalent, apply it with one click. Also shows your current sens expressed in every other game.
- **Blocky lighting (optional).** A crisp pixelated-shadow look for the flat world, discovered via an in-game feedback report from isa - thanks isa! Opt in from the SwiftGibs tab; applies on the next map load.
- **Enemy-friend highlighting is now opt-in.** Friends on the enemy team render plain enemy red by default so team reads stay instant; tick "incl. enemy friends" to give them a distinct crimson tint (redder and subtler than the old orange).

## Changed

- **Menus reorganised into four themed tabs:** SwiftGibs (general and HUD), Cues (everything you see), Audio (everything you hear), and Friends, with clearer section headers throughout. Everything still previews live.
- Career stats page now shows both all-time and this-session best streaks.
- Hit sound preview respects your pitch setting.
- Nothing about your saved settings changes on upgrade: your existing choices and binds are never overwritten, and M / Mouse6 / Mouse7 are only claimed if you haven't bound them yourself.

## Download

- **Windows:** `swiftgibs-win64.zip` - or run `update-swiftgibs.bat` in your existing folder
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - first launch: right-click, **Open**, **Open**
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz`
