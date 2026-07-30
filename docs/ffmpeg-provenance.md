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

**Switched providers 2026-07-30** (see "Why the Linux provider changed" below) - was
johnvansickle.com through 2026-07-29; see git history for that entry if you need it.

| | |
|---|---|
| Provider | [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (GitHub) - a CI-built, fully open-source auto-build pipeline that publishes exact, pinned dependency versions per release (see "Corresponding source" below) |
| Version | **n8.1.2-21-gce3c09c101** (21 commits past the upstream `n8.1.2` tag) |
| Release tag | `autobuild-2026-06-30-13-34` - deliberately the LAST auto-build of June 2026, not the newest available at the time this was pinned. BtbN's own retention policy keeps only the last 14 daily auto-builds but keeps the last build of every month for two years - a month-end tag is the only kind that won't 404 within weeks. **When repinning this in future, always pick a month-end tag for the same reason**, or explicitly accept a shorter retention window and document it. |
| Download URL | `https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-06-30-13-34/ffmpeg-n8.1.2-21-gce3c09c101-linux64-gpl-8.1.tar.xz` |
| Archive SHA-256 | `0ba73bbd93472c7622f6dec26d334c5e62e64d858d072490b2844320970456cd` (independently re-verified against a real download here; also matches the `checksums.sha256` file BtbN publishes alongside the same release) |
| Licence | **GPLv3** (`--enable-gpl --enable-version3`, confirmed via the binary's own `-version` output; `LICENSE.txt` ships inside the archive, byte-identical to the copy committed at `build/ffmpeg-licence/GPLv3.txt`) |
| Corresponding source | **Upstream FFmpeg**: exact commit <https://github.com/FFmpeg/FFmpeg/commit/ce3c09c101c83add623774d414a9f9498caf5c25> (2026-06-29). **Build scripts + exact per-dependency pins**: the BtbN/FFmpeg-Builds repository at the exact commit that produced this release, <https://github.com/BtbN/FFmpeg-Builds/tree/7a83528ea3431e9eca982a712bc3a7cd0789d5d0> (resolved from the release's own git tag, not "current master" - the pins below move over time, confirmed by comparing against master at the time this was written, which already differed for libvpx/libopus). Each statically-linked GPL-relevant dependency has its own script under `scripts.d/` with an explicit `SCRIPT_REPO`/`SCRIPT_COMMIT` - the three that matter for the encoders this feature uses, read directly from that exact commit: `libx264` from `https://code.videolan.org/videolan/x264.git` @ `0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee` (`scripts.d/50-x264.sh`); `libvpx` from `https://chromium.googlesource.com/webm/libvpx` @ `1963b530e4b09d1edf1339d3ad26a3aa5a5a7ac6` (`scripts.d/50-libvpx.sh`); `libopus` from `https://github.com/xiph/opus.git` @ `f8f99516092f4311a9b0784f190ff982df8eb2e6` (`scripts.d/50-libopus.sh`). This is a genuine, verifiable improvement over the previous provider - see below. |
| Binary extracted | `ffmpeg-n8.1.2-21-gce3c09c101-linux64-gpl-8.1/bin/ffmpeg` from the archive (only `ffmpeg` and `LICENSE.txt` are used; `ffprobe`, manpages, and presets are not shipped) |
| Binary size | 143,838,792 bytes (~137.2 MiB), dynamically linked against glibc/libm/libpthread but statically linked for every codec (confirmed via `file`) |
| Encoders confirmed present | `libx264` (H.264), `libvpx-vp9` (VP9), `aac` (native encoder), `libopus` - confirmed by actually running this exact downloaded binary's `-encoders` list and by piping synthetic raw frames/tones through it to produce a real MP4 (h264), a real WebM (vp9), a real AAC stream, and a real Opus stream, all verified with `ffprobe` |

### Why the Linux provider changed

A review of this document found that the "corresponding source" link for the previous provider
(johnvansickle.com) was wrong: both `release-source/` and `git-source/` on that site (checked
directly, not assumed) are dated **2018-11-10** and contain `ffmpeg-4.1`/`ffmpeg-git` plus
unpinned `libx264`/`libvpx`/`libx265` snapshots from that same date - six years and several major
versions behind the `7.0.2` binary this project actually shipped. That is not the GPL
corresponding source for the binary being distributed; johnvansickle.com simply hasn't updated
those pages since 2018 even though the binary releases themselves are current, and there is no
way to reconstruct which exact dependency versions went into any specific johnvansickle.com
release from public information (the maintainer doesn't publish that anywhere), so "mirror a
correct snapshot ourselves" was not achievable for that binary either - only switching providers
gives a genuinely truthful answer.

BtbN/FFmpeg-Builds was chosen (over reverting to "best-effort, no exact source" honesty) because
it actually solves the underlying problem: every dependency's exact pinned commit is checked into
the same repository that builds the binary, at the same commit, so "corresponding source" is a
real, verifiable, reproducible claim rather than a broken link. The cost is size (~137 MiB vs the
previous ~76 MiB) and a monthly-tag discipline requirement (above) - both accepted deliberately in
exchange for actually being able to meet the GPL obligation this document exists to record.
Windows (gyan.dev, exact upstream commit) and macOS (martin-riedl.de, maintained build-script
repo) were already adequate and are unchanged by this.

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

## Why the versions don't (quite) match across platforms

As of the 2026-07-30 Linux repin, all three platforms are effectively on **8.1.2**: Linux is
`n8.1.2-21-gce3c09c101` (21 commits past the upstream tag, from BtbN's own 8.1.2 branch build),
Windows and macOS are the plain `8.1.2` tag. They are not byte-identical builds (different CI
pipelines, different exact dependency versions per the per-platform provenance above), but the
spec's actual non-negotiable is that all three platforms run **identical ffmpeg invocations**
(same CLI flags, same pixel format, same codecs - see `checkclipexport()` in
`fpsgame/client.cpp`), which all three satisfy identically for this feature's narrow use (rawvideo
in on stdin, libx264/libvpx-vp9/aac/libopus out) regardless of the exact patch-level commit each
was built from. (Before 2026-07-30, Linux was pinned to a smaller but corresponding-source-stale
7.0.2 build - see "Why the Linux provider changed" above.)

## The shared GPLv3 licence text

`build/ffmpeg-licence/GPLv3.txt` (committed, ~35KB plain text) is a verbatim copy of the GPLv3
licence text as bundled by the Linux (BtbN/FFmpeg-Builds) and Windows (gyan.dev) archives above -
confirmed byte-identical between those two independently-produced archives (`sha256sum` match,
re-checked again after the 2026-07-30 Linux provider switch - still byte-identical to the new
BtbN archive's own `LICENSE.txt`). It differs from the *current* text at gnu.org/licenses/gpl-3.0.txt
only in four now-outdated `http://` vs `https://` URLs in the boilerplate footer - not a
substantive difference. This same file is copied into all three platforms' `ffmpeg/LICENSE.txt`,
including macOS, whose own archive ships no licence file at all.

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
chosen." Actual, measured here: Linux +137.2 MiB, Windows +97.2 MiB, macOS +62.6 MiB (binary only;
the shared licence/notice text adds under 40KB more). Windows and Linux both land above the
original estimate - these are full-featured reputable community static builds (many codecs and
filters beyond the `libx264`/`libvpx`/`aac`/`libopus` this feature actually calls), not a custom
minimal encoder-only build, and "prefer official/reputable static builds" was the explicit brief
rather than compiling a bespoke minimal ffmpeg. Linux grew again on 2026-07-30 specifically (was
+76.1 MiB) when its provider changed from johnvansickle.com to BtbN/FFmpeg-Builds - a deliberate,
disclosed trade (see "Why the Linux provider changed" above): the previous, smaller build could
not be traced to genuine corresponding source, and correctness took priority over size here. If
size turns out to matter more than expected in practice, the follow-up would be a custom
`--disable-everything --enable-encoder=libx264,libvpx_vp9,aac,libopus ...` static build compiled
from source for each platform (pinning our own dependency versions directly, sidestepping this
whole trade-off) - a materially bigger undertaking than either of these tasks (real
cross-compilation per platform, ongoing maintenance of a custom build pipeline) and out of scope
here.
