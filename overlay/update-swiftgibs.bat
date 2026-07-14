@echo off
rem Updates the SwiftGibs folder this .bat lives in to the latest GitHub
rem release. Your own files (config.cfg, friends.cfg, stats.cfg, screenshots)
rem are not in the release zip, so they are never touched.
rem
rem cmd executes batch files by file offset, so a script must never overwrite
rem itself mid-run - the update would corrupt it. First move: copy self to
rem %TEMP% and continue from there; the copy receives the game dir as %2.

if /i "%~1"=="run" goto main
copy /y "%~f0" "%TEMP%\swiftgibs-updater.bat" >nul
"%TEMP%\swiftgibs-updater.bat" run "%~dp0."
exit /b

:main
setlocal
title SwiftGibs updater
set "GAMEDIR=%~2"

echo.
echo  SwiftGibs updater
echo  -----------------
echo  This downloads the latest release (about 560 MB) and updates the
echo  game in:  %GAMEDIR%
echo  Your settings, friends and stats are kept.
echo.
pause

rem --- refuse to run while the game is open (the exe would be locked) ---
if exist "%GAMEDIR%\bin64\sauerbraten.exe" (
  ren "%GAMEDIR%\bin64\sauerbraten.exe" sauerbraten.exe.locktest >nul 2>&1
  if errorlevel 1 (
    echo.
    echo  SwiftGibs is running - close the game first, then run this again.
    goto end
  )
  ren "%GAMEDIR%\bin64\sauerbraten.exe.locktest" sauerbraten.exe >nul 2>&1
)

set "TMPD=%TEMP%\swiftgibs-update"
if exist "%TMPD%" rmdir /s /q "%TMPD%"
mkdir "%TMPD%"

echo.
echo  Downloading the latest release...
curl -L --fail --progress-bar -o "%TMPD%\swiftgibs-win64.zip" https://github.com/SalukiSwift/swiftgibs/releases/latest/download/swiftgibs-win64.zip
if errorlevel 1 (
  echo.
  echo  Download failed - check your internet connection and try again.
  goto end
)

echo.
echo  Unpacking...
tar -xf "%TMPD%\swiftgibs-win64.zip" -C "%TMPD%"
if errorlevel 1 (
  echo.
  echo  Unpack failed - the download may be corrupt. Try again.
  goto end
)

echo.
echo  Updating game files...
robocopy "%TMPD%\swiftgibs-win64" "%GAMEDIR%" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo.
  echo  Update failed while copying files. Make sure the game is closed
  echo  and run this again.
  goto end
)

rmdir /s /q "%TMPD%" >nul 2>&1
echo.
echo  Done! SwiftGibs is up to date - start the game and frag away.

:end
echo.
pause
endlocal
