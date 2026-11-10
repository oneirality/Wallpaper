@echo off
rem Launches the animated wallpaper without a visible console window.
rem For autostart: Win+R -> shell:startup -> put a shortcut to this bat there.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0wall.ps1"
