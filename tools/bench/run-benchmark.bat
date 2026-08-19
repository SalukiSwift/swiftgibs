@echo off
rem SwiftGibs benchmark: 1 warmup + %1 measured passes (default 3).
rem Results: benchresults.csv next to this file. Safe: uses its own bench-home-run
rem profile dir, never touches your real SwiftGibs config.
setlocal enabledelayedexpansion
set PASSES=%1
if "%PASSES%"=="" set PASSES=3
set HERE=%~dp0
cd /d "%HERE%"
set BH=%HERE%bench-home-run
if exist "%BH%" rmdir /s /q "%BH%"
mkdir "%BH%"
copy /y "%HERE%bench-home\autoexec.cfg" "%BH%\" >nul 2>nul
> "%BH%\bench.cfg" echo sgbench "data/bench/workload-v1.dmo"
echo warmup pass...
"%HERE%bin64\sauerbraten.exe" -q"%BH%" "-xexec bench.cfg"
for /l %%i in (1,1,%PASSES%) do (
  echo measured pass %%i/%PASSES%...
  "%HERE%bin64\sauerbraten.exe" -q"%BH%" "-xexec bench.cfg"
)
copy /y "%BH%\benchresults.csv" "%HERE%benchresults.csv" >nul
echo == results ==
type "%HERE%benchresults.csv"
pause
