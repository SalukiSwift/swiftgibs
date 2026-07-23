# SwiftGibs v1.1.8

Die less boring. Respawn smarter, save your setups, and stop fighting the menus.

## New

- **Auto-respawn.** The instant your respawn wait is up, you are back in - no click.
  Honours CTF-family servers' spawn delays properly. Paired with a **respawn countdown**:
  three soft low tones count the final seconds (clearly distinct from the reload
  metronome), then a brighter go tone at the moment you can spawn. Both on by default,
  both toggleable in the SwiftGibs tab.
- **Preference profiles.** Save your entire SwiftGibs setup under a name and switch
  between profiles in a click: Esc > options > SwiftGibs > "profiles..". Captures every
  SwiftGibs setting; leaves your name, friends, stats and keybinds alone.
- **Clean screenshots.** F12 now takes a screenshot without the HUD (toggle "clean
  screenshots" off if you want the HUD in). Your own F12 rebind is respected.
- **Rebindable SwiftGibs keys.** Expanded map, vote panel, feedback shot, quick play,
  deep zoom and screenshot all appear in the stock keys menu, rebindable like any
  other action.
- **Chat scrollback polish.** A subtle scrollbar shows where you are while scrolling
  chat history, and closing chat snaps you back to the newest messages.

## Fixed

- **Cue previews work mid-match.** Auditioning countdowns, flashes and hit markers from
  the Esc menu now works while you are dead or spectating - previously the demos
  silently refused exactly when you had time to browse them.
- **Hit-marker previews show a crosshair.** X-flash, Ring-out and Notch now demo
  against a crosshair reference like Classic always did.
- **Deep zoom obeys your zoom mode.** If you use click-to-toggle zoom, the thumb-button
  deep zoom now toggles too (hold mode unchanged).
- **Flag popup reworded.** "FLAG TAKEN" with "RUN IT HOME" (or "HOLD IT!" in hold modes).
- **Stock options no longer fight SwiftGibs.** Six stock settings rows that silently
  broke SwiftGibs-managed features (crosshair picker, hit-crosshair, fullbright radios,
  force-models, bilinear, chat-console) are removed or replaced with pointers.
- Cue colours button sits in its own row instead of hiding at the screen edge.

## Download

- **Windows:** `swiftgibs-win64.zip` - or run `update-swiftgibs.bat` in your existing folder
- **macOS (Apple Silicon):** `SwiftGibs-mac.zip` - first launch: right-click, **Open**, **Open**
- **Linux (x86-64):** `SwiftGibs-linux-x86_64.tar.gz`
