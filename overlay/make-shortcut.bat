@echo off
rem Creates a Desktop shortcut to SwiftGibs (proper icon, no console window).
powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $lnk = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\SwiftGibs.lnk'); $lnk.TargetPath = '%~dp0bin64\sauerbraten.exe'; $lnk.Arguments = '-q.'; $lnk.WorkingDirectory = '%~dp0'; $lnk.IconLocation = '%~dp0swiftgibs.ico'; $lnk.Save()"
echo Desktop shortcut created: SwiftGibs
pause
