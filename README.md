# Wallpaper

Set any image (or animated GIF) as your desktop wallpaper from a PowerShell
script. Works on Windows 11 24H2+, where the classic WorkerW/Progman window
trick no longer displays anything.

## Usage

- `start_wallpaper.bat` — double-click, pick an image, done.
- Or with a path: `powershell -NoProfile -ExecutionPolicy Bypass -File wall.ps1 -Image "C:\pics\me.jpg"`
- Stop: `stop_wallpaper.bat`, or the global hotkey **Shift+3**.
- Autostart: put a shortcut to `start_wallpaper.bat` in `shell:startup`.

## How it works

`wall.ps1` draws the image off-screen (cover-fit to the virtual screen) and
pushes it into the real desktop wallpaper via `SPI_SETDESKWALLPAPER`.
No child windows are parented into Explorer, so there is nothing to break
when Windows changes how the desktop layers work.

- Static image: rendered once; a tiny hidden process stays resident only to
  handle the stop hotkey / restore.
- Animated GIF: frames are pushed continuously (each frame is a wallpaper
  swap; frame delays below 100 ms are clamped — keep GIFs modest).

Your previous wallpaper is remembered and restored whenever the script stops
(hotkey, stop script, or closing the console).

## Files

| File                  | Purpose                                   |
|-----------------------|-------------------------------------------|
| `start_wallpaper.bat` | Launcher (hidden console); asks for image |
| `wall.ps1`            | The renderer                               |
| `stop.ps1`            | Signals the running wallpaper to stop      |
| `stop_wallpaper.bat`  | Calls `stop.ps1`                           |
