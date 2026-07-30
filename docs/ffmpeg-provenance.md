# ffmpeg provenance

SwiftGibs' clip video export feature bundles a prebuilt **ffmpeg** binary per platform and runs
it as a separate child process (fed raw frames over a pipe) - never linked into the engine. See
`docs/superpowers/specs/2026-07-30-clip-video-export-design.md`'s "Bundling ffmpeg" section for
why (short version: SwiftGibs is zlib licensed, ffmpeg builds that can encode H.264 are GPL, and
linking would force the whole engine binary to GPL - running it as a separate executable is mere
aggregation and keeps the two licences apart).

This file is the human-readable record of exactly which binary ships on each platform. The
executable source of truth is `build/fetch-ffmpeg.sh` (the URLs, SHA-256 hashes, and archive
paths it fetches from and verifies against) - if the two ever disagree, the script is correct
and this file is stale and should be updated to match.

**Nothing here is committed to git as a binary.** `build/fetch-ffmpeg.sh` downloads each archive
at bundle time, verifies its SHA-256 against the value recorded below BEFORE extracting or using
anything from it, and fails loudly (deletes the bad download, exits non-zero) on any mismatch.
Only this document, the fetch script itself, and a small (~35KB) committed copy of the GPLv3
licence text (`build/ffmpeg-licence/GPLv3.txt`) are tracked in the repo.

## Linux x86-64

| | |
|---|---|
| Provider | [johnvansickle.com/ffmpeg](https://johnvansickle.com/ffmpeg/) - the long-established static-Linux-ffmpeg build source |
| Version | **7.0.2** (`ffmpeg version 7.0.2-static`) |
| Download URL | `https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz` |
| Archive SHA-256 | `abda8d77ce8309141f83ab8edf0596834087c52467f6badf376a6a2a4c87cf67` |
| Archive MD5 (cross-check, published by the site) | `7fa72b652e19bf84c9461e332ea1cdf3` |
| Licence | **GPLv3** (`--enable-gpl --enable-version3`; `GPLv3.txt` ships inside the archive, byte-identical to the copy committed at `build/ffmpeg-licence/GPLv3.txt`) |
| Corresponding source | Full dependency source archive for this exact build: <https://johnvansickle.com/ffmpeg/release-source/>. Upstream FFmpeg release: <https://github.com/FFmpeg/FFmpeg/releases/tag/n7.0.2> |
| Binary extracted | `ffmpeg-7.0.2-amd64-static/ffmpeg` from the archive (only `ffmpeg` and `GPLv3.txt` are used; `ffprobe`, `qt-faststart`, manpages, and the vmaf model files are not shipped) |
| Binary size | 79,826,272 bytes (~76.1 MiB), genuinely fully static (`ldd` reports "not a dynamic executable") |
| Encoders confirmed present | `libx264` (H.264), `libvpx`/`libvpx-vp9` (VP8/VP9) - confirmed by actually running this exact downloaded binary's `-encoders` list and by piping synthetic raw frames through it to produce both a real MP4 (h264, verified with `ffprobe`) and a real WebM (vp9, verified with `ffprobe`) |

Chosen over the alternative checked (`BtbN/FFmpeg-Builds`' equivalent GPL static Linux tar.xz,
pinned release `autobuild-2026-07-29-13-36`, asset `ffmpeg-n8.1.2-31-g8c9502e9b0-linux64-gpl-8.1.tar.xz`,
SHA-256 `9fb60ff01e6574258dc76efdf94f901a651582da67b8edcfd10e8860233b7ef4`) specifically for size: that
build's `ffmpeg` binary alone is ~138 MiB (dynamically linked against glibc/libm/libpthread but
statically linked for every codec) versus 76.1 MiB here, for the same H.264/VP9 capability this
feature needs. Recorded here in case size trade-offs are revisited later - both are real,
checksum-verified, GPL, working builds.

## Windows x64

| | |
|---|---|
| Provider | [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) - the build ffmpeg.org's own downloads page recommends for Windows |
| Version | **8.1.2** (`8.1.2-essentials_build-www.gyan.dev`) |
| Download URL | `https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-8.1.2-essentials_build.zip` |
| Archive SHA-256 | `db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec` (published alongside the download at `.../ffmpeg-8.1.2-essentials_build.zip.sha256`, independently re-verified against a real download here) |
| Licence | **GPLv3** - stated explicitly in the archive's own `README.txt` ("License: GPL v3") |
| Corresponding source | Exact upstream commit, stated in the archive's own `README.txt`: <https://github.com/FFmpeg/FFmpeg/commit/38b88335f9> |
| Binary extracted | `ffmpeg-8.1.2-essentials_build/bin/ffmpeg.exe` (the "essentials" build, not "full" - skips `ffplay.exe`/docs/presets we don't use; only `ffmpeg.exe` and `LICENSE` are used from it) |
| Binary size | 101,897,728 bytes (~97.2 MiB) |
| Encoders confirmed present | `libx264`, `libvpx` listed in the archive's own `README.txt` "External libraries" section. **Not execution-tested** - no Windows or Wine environment in this sandbox; see the task report for what was and wasn't exercised. |

## macOS arm64 (Apple Silicon)

| | |
|---|---|
| Provider | [ffmpeg.martin-riedl.de](https://ffmpeg.martin-riedl.de/) - one of the very few sources publishing native Apple Silicon (arm64) static ffmpeg builds with published checksums. (`evermeet.cx`, the other well-known macOS static-build source, explicitly states it does not build for Apple Silicon ARM.) |
| Version | **8.1.2** (`ffmpeg version 8.1.2-https://www.martin-riedl.de`, built with Apple clang 14.0.0) |
| Download URL | `https://ffmpeg.martin-riedl.de/download/macos/arm64/1783011502_8.1.2/ffmpeg.zip` |
| Archive SHA-256 | `ef1aa60006c7b77ce170c1608c08d8e4ba1c30c5746f2ac986ded932d0ac2c3c` (published alongside the download at the matching `.sha256` file, independently re-verified against a real download here) |
| Licence | **GPLv3** - confirmed via the build's own reported configuration (`--enable-gpl --enable-version3 ... --enable-libx264 --enable-libvpx`, fetched from `.../1783011502_8.1.2/versions.txt`) |
| Corresponding source | Build automation: <https://git.martin-riedl.de/ffmpeg/build-script>. Upstream FFmpeg release: <https://github.com/FFmpeg/FFmpeg/releases/tag/n8.1.2> |
| Binary extracted | `ffmpeg` (the archive is just the bare binary at its root - no version-suffixed folder, no bundled licence file, confirmed by inspecting the real downloaded archive) |
| Binary size | 65,637,248 bytes (~62.6 MiB), confirmed `Mach-O 64-bit arm64 executable` |
| Encoders present | `libx264`, `libvpx` both listed in the build's own reported configuration/library-version output. **Not execution-tested** - no macOS/Apple Silicon environment in this sandbox; see the task report for what was and wasn't exercised. |

This archive ships no licence file of its own, so the committed
`build/ffmpeg-licence/GPLv3.txt` (see below) is used for this platform's bundle too, same as the
other two.

## Why the versions don't match across platforms

Linux is pinned to 7.0.2 (johnvansickle.com's current numbered release at the time of writing);
Windows and macOS are pinned to 8.1.2. This is a deliberate trade-off, not an oversight: the
spec's non-negotiable is that all three platforms run **identical ffmpeg invocations** (same CLI
flags, same pixel format, same codecs - see `checkclipexport()` in `fpsgame/client.cpp`), which
7.0.2 and 8.1.2 both support identically for this feature's narrow use (rawvideo in on stdin,
libx264/libvpx-vp9 out); it does not require the three builds to share one version number. Given
that, Linux was pinned to whichever build was smaller for the same capability (see the size
comparison in the Linux section above) rather than to whichever had the highest version number.

## The shared GPLv3 licence text

`build/ffmpeg-licence/GPLv3.txt` (committed, ~35KB plain text) is a verbatim copy of the GPLv3
licence text as bundled by the Linux (johnvansickle.com) and Windows (gyan.dev) archives above -
confirmed byte-identical between those two independently-produced archives before committing it
(`sha256sum` match). It differs from the *current* text at gnu.org/licenses/gpl-3.0.txt only in
four now-outdated `http://` vs `https://` URLs in the boilerplate footer - not a substantive
difference. This same file is copied into all three platforms' `ffmpeg/LICENSE.txt`, including
macOS, whose own archive ships no licence file at all.

`build/ffmpeg-licence/NOTICE.txt` (also committed) is the plain-language attribution note copied
into every bundle's `ffmpeg/` folder, stating that ffmpeg is a separate program under its own
licence and pointing back at this document.

## Reproducing / repinning a build

Run `build/fetch-ffmpeg.sh <linux|win|mac>` - it downloads, verifies the SHA-256 above, extracts
just the binary + licence + notice, and prints the resulting directory. To move to a newer
version later: find a new pinned URL + published checksum from the same (or another reputable)
provider, verify licence and encoder support the same way this document does, update the
matching `case` branch in `build/fetch-ffmpeg.sh` (URL, SHA256, and the archive-internal path,
which is version-suffixed and must be updated together with the version), then update this
document to match. Do not repin by trusting a moving "latest"/"release" URL's *contents* without
re-verifying a checksum for that specific new download - only the pinned SHA-256 is what makes a
build reproducible.

## Size impact

Design-doc estimate at the time this feature was scoped: "roughly 40-80MB depending on the build
chosen." Actual, measured here: Linux +76.1 MiB, Windows +97.2 MiB, macOS +62.6 MiB (binary only;
the shared licence/notice text adds under 40KB more). Windows in particular lands above the
original estimate - these are full-featured reputable community static builds (many codecs and
filters beyond the `libx264`/`libvpx` this feature actually calls), not a custom minimal
encoder-only build, and "prefer official/reputable static builds" was the explicit brief rather
than compiling a bespoke minimal ffmpeg. April's Windows bundle was ~621MB before this; +97.2 MiB
is roughly a 15-16% increase. If this turns out to matter in practice, the follow-up would be a
custom `--disable-everything --enable-encoder=libx264,libvpx_vp9 ...` static build compiled from
source for each platform - a materially bigger undertaking than this task (real cross-compilation
per platform, ongoing maintenance of a custom build pipeline) and out of scope here.
