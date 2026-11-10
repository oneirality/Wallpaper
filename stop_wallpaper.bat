@echo off
rem Signals the wallpaper's stop event (FormClosing cleanup detaches it from the desktop).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop.ps1"
