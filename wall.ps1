# wall.ps1 - wallpaper renderer that works on Windows 11 24H2+.
#
# Why not the classic WorkerW trick? This build ignores the Progman message
# (0x052C) that spawns the drawable WorkerW, so windows parented into any
# WorkerW/Progman layer never appear (verified by pixel sampling). Instead we
# render off-screen and push the result into the REAL desktop wallpaper via
# SPI_SETDESKWALLPAPER. No window z-order games -> immune to that regression.
#
# - Static image: drawn once, then the process stays resident but idle
#   (only so stop.ps1 can restore the original wallpaper).
# - Animated GIF: frames pushed continuously; each frame is a wallpaper swap,
#   so keep delays >= ~100 ms/frame.
#
# Stop: stop_wallpaper.bat (or kill the process).
# On stop the original wallpaper is restored.

param(
    [string]$Image = ""
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Native {
    // both wrap the same export SystemParametersInfoW under different .NET names
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SystemParametersInfoW")]
    public static extern bool SpiSet(uint action, uint uiParam, string pvParam, uint fWinIni);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SystemParametersInfoW")]
    public static extern bool SpiGet(uint action, uint uiParam, System.Text.StringBuilder pvParam, uint fWinIni);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# Hide the console window (covers direct powershell.exe launches; the .bat
# launcher already avoids creating one). SW_HIDE = 0.
$hwndConsole = [Native]::GetConsoleWindow()
if ($hwndConsole -ne [IntPtr]::Zero) { [void][Native]::ShowWindow($hwndConsole, 0) }

# --- Re-run guard -----------------------------------------------------------
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\MyWallPS_Instance", [ref]$createdNew)
if (-not $createdNew) { Write-Host "Wallpaper is already running."; exit }

# Stop channel: stop.ps1 sets this event.
$stopEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Local\MyWallPS_Stop")

# --- Backup current wallpaper (restored on exit) ----------------------------
$SPI_GETDESKWALLPAPER = 0x0073
$SPI_SETDESKWALLPAPER = 0x0014
$UPDATE_INI = 0x01
$SEND_CHANGE = 0x02

$origBackup = Join-Path $env:TEMP "orig_wallpaper_path.txt"
$firstRun = -not (Test-Path $origBackup)
if ($firstRun) {
    $sb = New-Object System.Text.StringBuilder 260
    [void][Native]::SpiGet($SPI_GETDESKWALLPAPER, 260, $sb, 0)
    $orig = $sb.ToString()
    if (-not $orig -or -not (Test-Path $orig)) {
        # fall back to registry value
        $orig = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
    }
    if ($orig -and (Test-Path $orig)) {
        Set-Content -Path $origBackup -Value $orig -Encoding Unicode
    } else {
        Remove-Item $origBackup -ErrorAction SilentlyContinue
        Write-Warning "Could not determine current wallpaper; nothing will be restored on exit."
        $origBackup = ""
    }
}

function Restore-Wallpaper {
    if ($script:origBackup -and (Test-Path $script:origBackup)) {
        $orig = (Get-Content $script:origBackup -Encoding Unicode | Select-Object -First 1)
        if ($orig -and (Test-Path $orig)) {
            [void][Native]::SpiSet($SPI_SETDESKWALLPAPER, 0, $orig, $UPDATE_INI -bor $SEND_CHANGE)
        }
        Remove-Item $script:origBackup -ErrorAction SilentlyContinue
    }
}

# --- Pick / validate the image ----------------------------------------------
if ($Image -eq "") {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Pick a wallpaper image"
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif|All files|*.*"
    if ($dlg.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true})) -ne [System.Windows.Forms.DialogResult]::OK) {
        Restore-Wallpaper; exit
    }
    $Image = $dlg.FileName
}
if (-not (Test-Path $Image)) { Restore-Wallpaper; throw "Image not found: $Image" }

# --- Render ------------------------------------------------------------------
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$canvas = New-Object System.Drawing.Bitmap($vs.Width, $vs.Height)
$gfx = [System.Drawing.Graphics]::FromImage($canvas)

# cover-fit: fill, keep aspect ratio, crop overflow (same as desktop style)
$img = [System.Drawing.Image]::FromFile($Image)
$scale = [Math]::Max($vs.Width / $img.Width, $vs.Height / $img.Height)
$dw = $img.Width * $scale; $dh = $img.Height * $scale
$dx = ($vs.Width - $dw) / 2; $dy = ($vs.Height - $dh) / 2
$gfx.Clear([System.Drawing.Color]::Black)
$gfx.DrawImage($img, [float]$dx, [float]$dy, [float]$dw, [float]$dh)

# scratch file for SPI_SETDESKWALLPAPER (must be a real file path)
$scratch = Join-Path $env:TEMP "wall_render.bmp"

function Push-Frame {
    $canvas.Save($scratch, [System.Drawing.Imaging.ImageFormat]::Bmp)
    [void][Native]::SpiSet($SPI_SETDESKWALLPAPER, 0, $scratch, $UPDATE_INI -bor $SEND_CHANGE)
}

# --- GIF loop vs static ------------------------------------------------------
$fd = New-Object System.Drawing.Imaging.FrameDimension($img.FrameDimensionsList[0])
$frameCount = $img.GetFrameCount($fd)
$isAnimated = $frameCount -gt 1

if (-not $isAnimated) {
    Push-Frame
    $img.Dispose(); $gfx.Dispose(); $canvas.Dispose()
} else {
    $delays = New-Object int[] $frameCount
    for ($i = 0; $i -lt $frameCount; $i++) {
        $d = $img.GetPropertyItem(0x5100).Value   # PropertyTagFrameDelay
        $delays[$i] = [BitConverter]::ToInt32($d, $i * 4)
        if ($delays[$i] -lt 100) { $delays[$i] = 100 }
    }
}

# --- Main loop ---------------------------------------------------------------
# No window at all -> nothing shows in Alt+Tab or the taskbar. Stop via
# stop_wallpaper.bat (sets the stop event) or by killing the process.
try {
    if ($isAnimated) {
        $frame = 0
        while (-not $stopEvent.WaitOne([TimeSpan]::FromMilliseconds($delays[$frame]))) {
            $img.SelectActiveFrame($fd, $frame)
            $gfx.Clear([System.Drawing.Color]::Black)
            $gfx.DrawImage($img, [float]$dx, [float]$dy, [float]$dw, [float]$dh)
            Push-Frame
            $frame = ($frame + 1) % $frameCount
        }
    } else {
        # static: just wait for the stop signal
        [void]$stopEvent.WaitOne()
    }
} finally {
    Restore-Wallpaper
    if (Test-Path $scratch) { Remove-Item $scratch -ErrorAction SilentlyContinue }
    $img.Dispose(); $gfx.Dispose(); $canvas.Dispose()
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
