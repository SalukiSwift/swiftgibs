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
