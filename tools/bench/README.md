# SwiftGibs benchmark mode

`sgbench <demofile>` (engine command, patch 22) plays a `.dmo` recording back **uncapped**
(`maxfps` pacing is a no-op for the duration of the run - `limitfps()` returns immediately while
`sgbench` is measuring) and times every main-loop iteration with the OS performance counter, not
the engine's own integer-millisecond clock. GPU vsync is a separate setting from that uncap and
is not touched by `sgbench` itself - the bench profile (`bench-home/autoexec.cfg`) explicitly
pins `vsync 0` so it can never silently pace a run either. It
reuses the stock demo player unchanged - there is no separate "benchmark playback" code path,
only measurement layered on top of ordinary local demo playback.

This directory ships everything needed to run that benchmark the same way every time:

- `workload-v1.dmo` - the canonical workload (see **Workload immutability**, below).
- `bench-home/autoexec.cfg` - the pinned profile of overrides (fpsstats off, fullscreen on,
  sound on, uncapped fps) layered on top of the shipped config.
- `run-benchmark.sh` / `run-benchmark.bat` - the runner, shipped at the root of the Linux and
  Windows bundles next to the game binary. The Mac bundle deliberately ships WITHOUT the
  benchmark: running it inside the signed .app would modify sealed Resources and break the
  app's code signature.
- `test-bench.sh` - the automated regression gate: builds the current patch stack, assembles a
  bundle, and asserts every result exactly. This is what to run before/after any performance
  change to prove nothing broke.

## Running the benchmark

### Windows

Inside your SwiftGibs folder (next to `bin64\sauerbraten.exe`), double-click
`run-benchmark.bat`, or run it from a terminal with an explicit pass count:

```
run-benchmark.bat 5
```

With no argument it defaults to 3 measured passes. Either way it always does **1 warmup pass
first** (JIT/shader/disk-cache warmup, discarded) before the measured passes. Results are
written to `benchresults.csv` next to the `.bat` file - one row per pass, warmup included, so
you can see it if you want to but it's not part of any "last N" summary. Every run also archives
a full timestamped copy as `benchresults-<yyyymmdd-hhmmss>.csv` next to it, so an earlier run's
rows are never silently overwritten by a later one - see **Where the files actually land**,
below, for the whole picture. The window stays open (`pause`) at the end so it doesn't vanish
before you can read the results.

Safe to run without thinking about it: `run-benchmark.bat` always uses its own throwaway
`bench-home-run\` profile folder (wiped and recreated at the start of every run) - it never
touches your real SwiftGibs settings, keybinds, or saved servers.

### Linux / Ubuntu

From inside the extracted bundle (next to `bin/swiftgibs`):

```
bash run-benchmark.sh 5
```

Same semantics as the Windows version: 1 discarded warmup pass + N measured passes (default 3),
results in `benchresults.csv` next to the script (plus the same timestamped archive - see
**Where the files actually land**, below), its own throwaway `bench-home-run/` profile directory
every time.

### The regression gate: `test-bench.sh`

```
bash tools/bench/test-bench.sh
```

Run this from the repo (not a shipped bundle) after any change to the engine, the bench patch,
or the workload. It rebuilds the client from the current `patches/*.patch` stack, assembles a
fresh Linux bundle, and checks the whole pipeline still behaves exactly as specified: the exact
`sgbenchselftest` line, an exact CSV header/row-count/range from a real `sgbench` pass, and a
non-black boot screenshot. Exit 0 means everything passed; exit 1 prints a `FAIL:` line
explaining the first thing that didn't. Takes several minutes (client compile + a real ~120s
workload playback) - that's expected, not a hang.

## Reading `benchresults.csv`

One header row, then one data row per pass (warmup passes are included - the `utc` timestamp is
what distinguishes them from measured ones):

```
utc,version,platform,demo,frames,seconds,avgfps,p50ms,p95ms,p99ms,onepctlow_fps,worst_ms,stutters,width,height
```

| Column | Meaning |
|---|---|
| `utc` | Row-write time, `YYYY-MM-DDTHH:MM:SSZ`. |
| `version` | SwiftGibs version string. Comes from `swiftgibsversion`, an alias only ever set by the **shipped** `autoexec.cfg` - see "Where `version` comes from", below. |
| `platform` | `linux` / `windows` / `mac`, compiled in. |
| `demo` | The `.dmo` filename passed to `sgbench`, echoed verbatim. |
| `frames` | Count of frames actually captured (after the 2000ms settling window - see below). |
| `seconds` | Sum of all captured frame times, in seconds. For `workload-v1.dmo` this should land in roughly 115-135s (the recording is a ~120s window; playback paces itself to real elapsed wall-clock time, not render fps, so this doesn't vary much run to run). |
| `avgfps` | `frames / seconds`. |
| `p50ms` / `p95ms` / `p99ms` | Frame-time percentiles in milliseconds - see **Formulas**, below. |
| `onepctlow_fps` | "1% low" fps - see **Formulas**, below. |
| `worst_ms` | The single slowest captured frame, in ms (`= p100`). |
| `stutters` | Count of frames more than 2x the median frame time - see **Formulas**, below. |
| `width` / `height` | Render resolution at capture time. Deliberately **not** pinned by the bench profile - the engine picks whatever the desktop/window resolution actually was, so a change here is itself a signal worth noticing, not noise to filter out. |

If `benchdumpframes` is left at its default (`1`), each row also writes a companion
`benchframes-<row>.csv` - one raw frame time (ms) per line, in capture order, for whichever row
number that pass was. Set `benchdumpframes 0` in a profile to skip that if you don't need the
raw samples. See **Where the files actually land**, immediately below, for where that file ends
up - it is NOT written next to `benchresults.csv` by the engine itself.

### Where the files actually land

The engine only ever knows about its own `-q` homedir, `bench-home-run/` - every
`benchresults.csv` row and every `benchframes-<row>.csv` dump is written **inside** it first.
`bench-home-run/` is `rm -rf`'d and recreated at the very start of every `run-benchmark.sh`/
`.bat` invocation, so anything left only in there is gone the next time you run the benchmark.

The runner is what moves things out to somewhere durable, next to itself (next to the `.sh`/
`.bat` file, i.e. the bundle root), at the end of a successful run:

- `benchresults.csv` - overwritten with the latest full run every time (stable name, for
  tools/scripts that always read this exact path).
- `benchresults-<yyyymmdd-hhmmss>.csv` - a full copy of the same file, archived under this
  invocation's timestamp, so an earlier run's rows are never silently lost to a later one.
- `benchframes-<yyyymmdd-hhmmss>-<row>.csv` - one copy per `benchframes-<row>.csv` the engine
  wrote inside `bench-home-run/` this invocation, renamed with the same invocation timestamp so
  repeated runs never collide or overwrite each other's raw dumps.

If a run fails before reaching that copy step (the CSV-row-growth check fails), nothing gets
copied out and the stale `bench-home-run/` from that failed attempt is what the next invocation
wipes - there is nothing left to inspect after the fact from a failed run's raw dumps.

### Formulas (equivalent to the engine source, `patches/22-benchmark.patch`)

Plain-English descriptions below, each paired with the actual C++ expression from
`benchcomputestats()`/`benchpercentile()` in the patch - read the patch itself as the source of
truth if the two ever look like they disagree.

**Measurement window**: only frames where the demo is actively playing *and* at least 2000ms
(perf-counter time) have passed since playback started are recorded at all - this discards
map-load/settling time. Timing itself is `SDL_GetPerformanceCounter()` deltas between
consecutive main-loop iterations, converted to ms via `SDL_GetPerformanceFrequency()` - never
the engine's own integer-millisecond clock.

**Percentiles** (`p50`/`p95`/`p99`/`worst`): sort a copy of the captured frame times (the
original capture order is never disturbed). Nearest-rank, truncating (not rounding) the index:

```cpp
size_t idx = min(size_t(n-1), size_t(k/100.0*n));
return sorted[idx];
```

`worst_ms` is `sorted[n-1]`, i.e. `p(100)`.

**1% low fps**: average the worst 1% of frame times (by ms, i.e. the slowest), then convert that
average back to fps:

```cpp
int worstcount = max(1, n/100);
double worstsum = 0;
for(int i = 0; i < worstcount; i++) worstsum += sorted[n-1-i];
out.onepctlow = float(1000.0 / (worstsum/worstcount));
```

**Stutters**: count of frames whose time is more than 2x the **full-run** median (`p50`, computed
once over the whole capture - see the comparability note just below, this is NOT a rolling
window):

```cpp
for(int i = 0; i < n; i++) if(src[i] > 2.0f*out.p50) stutters++;
```

**`stutters` here is not comparable to `fpsstats.csv`'s `stutter_count`.** They sound like the
same metric and are not: `fpsstats.csv` (patch 18, per-match in-game stats) flags a frame as a
stutter against a **running median of the last 16 sampled frames** (`FPSSTATS_MEDIANWIN`,
recomputed continuously as the match plays), so it reacts to the game's own frame-rate drifting
over time. `benchresults.csv`'s `stutters` (above) uses one **fixed median over the entire
capture**, computed once at the end. The same recording can legitimately produce different
stutter counts from the two column depending on how much the frame-rate trends during the run -
never treat them as the same number measured two ways.

`sgbenchselftest` exists purely to pin this exact math down against a fixed 10-value fixture
(`{10,10,10,10,10,10,10,10,30,10}`), independent of any real demo or hardware - it should always
print exactly:

```
BENCH SELFTEST: n=10 p50=10.00 p95=30.00 p99=30.00 onepctlow=33.33 worst=30.00 stutters=1
```

If that line ever changes, the percentile/1%-low/stutter math itself has drifted - `test-bench.sh`
asserts this line exact-match on every run for exactly that reason.

## Where `version` comes from

`swiftgibsversion` is an alias that is **only** ever set inside the shipped `overlay/autoexec.cfg`
(the real, player-facing config at the bundle root) - the bench profile at `bench-home/autoexec.cfg`
deliberately does not set it. `run-benchmark.sh`/`.bat` generate the actual runtime config,
`bench-home-run/autoexec.cfg`, as:

```
exec "<absolute path to the bundle's real autoexec.cfg>"
<bench-home/autoexec.cfg's overrides, appended>
```

i.e. every bench pass execs the real shipped config **first** (so it measures the same
first-run defaults - `shaderdetail`, `blood`, `ragdoll`, `hidedead`, `forceplayermodels`, and
`swiftgibsversion` among them - a real player gets), then layers the pinned bench overrides
(fpsstats off, fullscreen on, uncapped fps, etc.) on top. If `version` is ever blank in a CSV
row, the exec chain got broken somewhere - it should never happen with the shipped runners as
committed.

## Heads up: the launch-time update check fires during every bench pass

Because each pass execs the real shipped `autoexec.cfg`, it also runs that config's normal
launch-time update check (`checkupdate $swiftgibsversion`, a call to the SwiftGibs update relay)
exactly as a real launch would. It is bounded and silent-on-failure - worst case it adds about
7.5s **before** the measured window starts (the 2000ms settling discard is on top of that, not
instead of it) - it never touches frame measurement itself. On an offline machine (no network,
CI, an air-gapped test box) it just waits out that timeout and continues normally; nothing about
the benchmark needs network access to work, and nothing in this toolset adds any network call of
its own.

## Workload immutability

`workload-v1.dmo` is **immutable once cut**. Benchmark numbers are only meaningful when compared
against runs of the *same* recording - re-recording it, even with identical settings, changes
bot AI/RNG timing enough to shift the numbers and silently invalidate any historical comparison.
Cutting a new workload is a new version (`workload-v2.dmo`, etc. via
`tools/bench/make-workload.sh`), never an overwrite of an existing one. `workload-v1.dmo` is a
~120s local 8-bot instagib match on `ot`, recorded from a second observer client so bot motion
is captured as real server-relayed traffic (see `make-workload.sh`'s own comments for why a
single client can't do this).

## llvmpipe numbers are meaningless

If `sgbench`/`run-benchmark` is run on a machine without a real GPU driver - a software
rasterizer like Mesa's `llvmpipe` (common in WSL/CI/VMs with no GPU passthrough) - the resulting
`avgfps`/percentile/1%-low numbers are **not real performance data**. They only confirm the
pipeline runs end to end (client boots, demo plays, CSV is written, exit is clean) - useful as a
functional smoke test, useless as an optimization signal. Check the client's own startup log
("Renderer: ...") to see which path a given run took. Only trust numbers gathered on hardware
with a real GPU driver.
