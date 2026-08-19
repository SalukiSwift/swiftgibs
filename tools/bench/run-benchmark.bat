@echo off
rem SwiftGibs benchmark: 1 warmup + %1 measured passes (default 3).
rem Results: benchresults.csv next to this file. Safe: uses its own bench-home-run
rem profile dir, never touches your real SwiftGibs config.
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

copy /y "%BH%\benchresults.csv" "%HERE%benchresults.csv" >nul
echo == results ==
type "%HERE%benchresults.csv"
pause
exit /b 0

rem Sets %2 to the line count of file %1 (0 if the file doesn't exist yet - happens before the
rem warmup pass has run). "find /c /v """ counts every line (lines NOT matching the empty
rem string); reading via stdin redirection (not passing the filename as an argument) is what
rem keeps the output a bare number instead of a "---------- FILENAME: n" header line.
:countrows
if not exist "%~1" ( set "%~2=0" & goto :eof )
for /f %%c in ('find /c /v "" ^< "%~1"') do set "%~2=%%c"
goto :eof
