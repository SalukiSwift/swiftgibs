# Bundled SDL provenance (Linux)

The Linux bundle ships lean, source-built copies of the three SDL2 runtime libraries the client
links (`libSDL2`, `libSDL2_image`, `libSDL2_mixer`) in its `lib/` folder, so the tarball runs
out of the box on a machine with no SDL packages installed. The launcher (`swiftgibs.sh`) is
bundled-first: it always puts `lib/` on the library path via `LD_LIBRARY_PATH`, the same
precedent the mac build sets with its vendored frameworks. This is deliberate, not a fallback -
`ldd`-style soname resolution cannot tell whether a system SDL2 is new enough (the soname hasn't
changed since 2.0.0, so an old system copy resolves fine and then fails at runtime with a symbol
lookup error) and can misfire on an unrelated missing library. Set `SWIFTGIBS_SYSTEM_SDL=1`
before launching to opt back into the distro's SDL2 if you know it's new enough.

This file is the human-readable record of exactly what ships and why. The executable source of
truth is `build/fetch-sdl-linux.sh` (URLs, SHA-256 pins, configure flags, and the dependency
allowlist it enforces) - if the two ever disagree, the script is correct and this file is stale
and should be updated to match. Nothing here is committed to git as a binary; the script
downloads and verifies each source archive at bundle time and fails loudly on any mismatch.

## Why source-built instead of the distro's .so files

Ubuntu's `libSDL2_image`/`libSDL2_mixer` packages link a large web of external codecs (libtiff,
libwebp, fluidsynth, modplug, jack, and more). Copying those .so files into the bundle just
moves the "not found" failure one level down on a fresh machine. Built from source with the
SDL projects' own vendored stb decoders and every external codec disabled, the three libraries
need nothing beyond glibc - `fetch-sdl-linux.sh` verifies this on every build by checking each
library's `NEEDED` entries against an allowlist (`libc`, `libm`, `libdl`, `libpthread`,
`librt`, the dynamic loader, and our own `libSDL2`). A new external dependency is a hard build
failure, not a surprise shipped to users.

Display and audio backends (X11, Wayland, KMS/DRM, ALSA, PulseAudio, PipeWire) are compiled in
but loaded with `dlopen()` at runtime - SDL's standard design - so they are soft dependencies:
the game uses whichever the user's desktop actually provides. The fetch script fails the build
if configure silently dropped X11, Wayland, ALSA, Pulse, or PipeWire support because a dev
header was missing on the build machine (the apt list lives in `.github/workflows/release.yml`).

## Versions and pins

Deliberately the SAME versions the mac build vendors as official frameworks (see the
`mac-binary` job in `.github/workflows/release.yml`): one SDL version story across platforms.

| Library | Version | Archive SHA-256 |
|---|---|---|
| SDL2 | 2.30.9 | `24b574f71c87a763f50704bbb630cbe38298d544a1f890f099a4696b1d6beba4` |
| SDL2_image | 2.8.2 | `8f486bbfbcf8464dd58c9e5d93394ab0255ce68b51c5a966a918244820a76ddc` |
| SDL2_mixer | 2.8.0 | `1cfb34c87b26dbdbc7afd68c4f545c0116ab5f90bbfecc5aebe2a9cb4bb31549` |

- Provider: the official libsdl-org GitHub releases
  (`https://github.com/libsdl-org/{SDL,SDL_image,SDL_mixer}/releases/download/release-<ver>/...tar.gz`).
- Each SHA-256 was computed from a real download and independently cross-checked against a
  second download of the same archive from libsdl.org's own mirror
  (`https://www.libsdl.org/release/` and `/projects/*/release/`) on 2026-08-12 - the two hosts
  agreed byte-for-byte. libsdl-org publishes GPG signatures, not checksums, so two independent
  hosts agreeing is the verification used here.
- Licence: all three are zlib-licensed; their licence texts ship verbatim in the bundle at
  `lib/NOTICE.txt`. The stb decoders compiled inside them are public-domain/MIT, vendored in
  the official SDL source archives (nothing extra is downloaded).

## What is enabled

- SDL2: default feature set; all platform backends dlopen'd as described above.
- SDL2_image: stb_image for PNG and JPG (all the game's data), plus SDL_image's built-in
  no-dependency loaders. External codecs disabled: avif, jxl, tif, webp. (The engine loads
  .dds itself, and `tools/strip-assets.sh` deletes bundled .dds anyway.)
- SDL2_mixer: built-in WAV plus stb_vorbis for OGG - the only two formats in `packages/sounds/`.
  Disabled: mod, midi, flac, mp3, opus, wavpack, cmd. (Map background music is stripped from
  the bundle and `musicvol` is 0.)

Verified on real hardware 2026-08-12 (Ubuntu 24.04, RTX 3070, X11): the client runs the full
menu on the bundled trio alone (`LD_LIBRARY_PATH` forced to `lib/`), and standalone decode
tests against the bundled libraries load game .ogg (stb_vorbis), .jpg, and .png files
correctly.

## Size impact

~2.8MB uncompressed (libSDL2 2.5MB + image 179KB + mixer 152KB, stripped) in a ~630MB bundle.

## What the bundle still expects from the system

The client binary itself also links `libX11`, `libGL`, `libz`, and `libstdc++`. These are not
bundled deliberately: every graphical Linux desktop ships them (libGL comes from the GPU
driver and must NOT be overridden; libX11 is present on X11 and Wayland/XWayland desktops
alike; libz and libstdc++ are base-system on every mainstream distro). A machine with no GPU
driver at all cannot run the game regardless of what we bundle.
