@echo off
rem FALLBACK: right-click this file and choose "Run as administrator".
rem Use it if the automatic admin prompt from run-server.bat gets missed.
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   This needs admin rights.
  echo   Right-click allow-firewall.bat and choose "Run as administrator".
  echo.
  pause
  exit /b 1
)
netsh advfirewall firewall delete rule name=SwiftGibsLocalServer >nul 2>&1
netsh advfirewall firewall add rule name=SwiftGibsLocalServer dir=in action=allow protocol=UDP localport=28785-28786 profile=any
echo.
echo   Done. Friends can now reach the server. You can close this window.
echo.
pause
