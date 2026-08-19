@echo off
rem SwiftGibs benchmark: 1 warmup + %1 measured passes (default 3).
rem Results: benchresults.csv next to this file (latest run), plus a timestamped
rem benchresults-<yyyymmdd-hhmmss>.csv archive and any benchframes-<row>.csv per-frame dumps
rem copied out under the same timestamp prefix - both also land next to this file.
rem bench-home-run\ itself (where the engine actually writes those files first) is wiped and
rem recreated at the start of every invocation, so nothing left only in there survives.
rem Safe: uses its own bench-home-run profile dir, never touches your real SwiftGibs config.
setlocal
set PASSES=%1
if "%PASSES%"=="" set PASSES=3
set HERE=%~dp0
cd /d "%HERE%"

if not exist "%HERE%bin64\sauerbraten.exe" (
  echo SwiftGibs benchmark: could not find bin64\sauerbraten.exe next to this file.
  echo Make sure run-benchmark.bat is still inside your SwiftGibs folder.
  pause
  exit /b 1
)

set BH=%HERE%bench-home-run
if exist "%BH%" rmdir /s /q "%BH%"
mkdir "%BH%"

rem Measure the SHIPPED SwiftGibs config, not an isolated blank slate: exec the bundle's real
rem staged autoexec.cfg FIRST (shaderdetail, blood, ragdoll, hidedead, forceplayermodels,
rem swiftgibsversion, etc. - the actual first-run defaults), THEN layer the pinned bench
rem overrides from bench-home\autoexec.cfg on top. Absolute path, not the bare filename
rem "autoexec.cfg" - this file IS bench-home-run\autoexec.cfg, so a bare exec would just find
rem and re-run itself (the engine's homedir lookup always checks -q's directory first).
rem NOTE: no enabledelayedexpansion needed below - every SET is read on a later, separate
rem top-level line, never re-read within the same parenthesized block it was set in.
> "%BH%\autoexec.cfg" echo exec "%HERE%autoexec.cfg"
type "%HERE%bench-home\autoexec.cfg" >> "%BH%\autoexec.cfg"

> "%BH%\bench.cfg" echo sgbench "data/bench/workload-v1.dmo"

echo warmup pass...
"%HERE%bin64\sauerbraten.exe" -q"%BH%" "-xexec bench.cfg"

call :countrows "%BH%\benchresults.csv" BEFORE

for /l %%i in (1,1,%PASSES%) do (
  echo measured pass %%i/%PASSES%...
  "%HERE%bin64\sauerbraten.exe" -q"%BH%" "-xexec bench.cfg"
)

call :countrows "%BH%\benchresults.csv" AFTER

set /a NEEDED=%BEFORE%+%PASSES%
if %AFTER% LSS %NEEDED% (
  echo.
  echo BENCHMARK FAILED - no results were produced. See any BENCH ERROR above.
  pause
  exit /b 1
)

rem Invocation-unique timestamp for the archive copies below - PowerShell (ubiquitous on any
rem Windows this exe runs on) rather than %date%/%time%, whose format is locale-dependent and
rem not safe to parse the same way on every machine.
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set TS=%%T

copy /y "%BH%\benchresults.csv" "%HERE%benchresults.csv" >nul
rem Keep the latest results at the stable benchresults.csv name (above) for tools/scripts that
rem always read that path, but ALSO archive this invocation's full CSV under a timestamped name
rem so an earlier run's rows are never silently clobbered by a later one.
copy /y "%BH%\benchresults.csv" "%HERE%benchresults-%TS%.csv" >nul

rem benchframes-<row>.csv (per-pass raw frame-time dumps - see benchdumpframes in patch 22, on
rem by default) live inside bench-home-run, which the very next invocation's "rmdir /s /q"
rem above wipes unconditionally. Copy every dump out next to benchresults.csv, under this
rem invocation's timestamp, before it's lost. No-op (zero iterations, no error) if the profile
rem had benchdumpframes 0 and none exist.
for %%F in ("%BH%\benchframes-*.csv") do call :archiveframe "%%F"

echo == results ==
type "%HERE%benchresults.csv"
pause
exit /b 0

rem Sets %2 to the DATA row count of file %1 (0 if the file doesn't exist yet - happens before
rem the warmup pass has run) - the header line is excluded. benchreport() (patch 22) always
rem writes the header and that row's data together in one open-for-append call, so the CSV is
rem either absent (0 data rows) or has a header plus >=1 data row - never a bare header, so
rem "total lines - 1" is always safe when the file exists. Counting raw lines instead would
rem double-count the header as if it were a row of growth: on this invocation's very first
rem success (BEFORE captured right after the warmup pass, when the file has just been created
rem for the first time), that one extra line let PASSES-1 real measured successes still satisfy
rem the AFTER-vs-NEEDED check below - a silently-too-lenient gate. "find /c /v """ counts every
rem line (lines NOT matching the empty string); reading via stdin redirection (not passing the
rem filename as an argument) is what keeps the output a bare number instead of a
rem "---------- FILENAME: n" header line.
:countrows
if not exist "%~1" ( set "%~2=0" & goto :eof )
for /f %%c in ('find /c /v "" ^< "%~1"') do set /a "%~2=%%c-1"
goto :eof

rem Copies one bench-home-run\benchframes-<row>.csv (passed as %~1, full path) out to
rem <HERE>benchframes-<TS>-<row>.csv. %~n1 is the filename without extension
rem ("benchframes-<row>"); stripping the "benchframes-" prefix leaves just "<row>" so the
rem renamed file reads benchframes-<TS>-<row>.csv, matching the .sh runner's own naming.
rem Both SET lines below are separate top-level statements (not inside a parenthesized block),
rem so - same reasoning as :countrows above - plain expansion is safe without
rem enabledelayedexpansion.
:archiveframe
set "FRAMENAME=%~n1"
set "FRAMEROW=%FRAMENAME:benchframes-=%"
copy /y "%~1" "%HERE%benchframes-%TS%-%FRAMEROW%.csv" >nul
goto :eof
