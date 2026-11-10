@echo off
rem Launches the wallpaper renderer without a visible console window.
rem No path given -> asks for an image with a file picker.
rem For autostart: Win+R -> shell:startup -> put a shortcut to this bat there,
rem or edit the line below to pass -Image "C:\path\to\picture.jpg".
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0wall.ps1"
