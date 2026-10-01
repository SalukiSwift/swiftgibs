@echo off
rem Thin wrapper: all logic is in run-server.ps1, because batch quoting mangles
rem nested quotes and pipes inside for /f (it silently broke IP detection).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-server.ps1"
