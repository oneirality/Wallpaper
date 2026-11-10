# wall.ps1 - Wallpaper Engine-style wallpaper using the WorkerW trick.
# Per-user only, no admin. The window is parented behind the desktop icons:
# cannot be focused, alt-tabbed, or closed from the taskbar.
#
# Stop it with Shift+3 (global hotkey) or stop_wallpaper.bat.
#
# Content: swap the PictureBox block for anything WinForms can host
# (animated GIF works in PictureBox out of the box).

param(
    [string]$Image = "",
    [string]$Title = "MyWallPS"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Native {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string win);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string win);
    [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int idx);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int idx, int val);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}

// exits the message loop when the Shift+3 hotkey (WM_HOTKEY = 0x0312) arrives
public class HotkeyFilter : System.Windows.Forms.IMessageFilter {
    public bool PreFilterMessage(ref System.Windows.Forms.Message m) {
        if (m.Msg == 0x0312) { System.Windows.Forms.Application.Exit(); return true; }
        return false;
    }
}
"@

# Per-monitor-DPI systems report logical sizes without this -> the window
# would land smaller than the physical screen. Call before reading VirtualScreen.
[void][Native]::SetProcessDPIAware()

# Re-run guard via named mutex. (FindWindow cannot be used: after adoption the
# wallpaper is a WS_CHILD of WorkerW, and FindWindow only sees top-level windows.)
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\MyWallPS_Instance", [ref]$createdNew)
if (-not $createdNew) { Write-Host "Wallpaper is already running."; exit }

# Stop channel: stop.ps1 sets this event; the timer below closes the form.
$stopEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Local\MyWallPS_Stop")

# No path given? Ask for one with a file picker (topmost so it is not behind other windows).
if ($Image -eq "") {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Pick a wallpaper image"
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp;*.gif|All files|*.*"
    if ($dlg.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true})) -ne [System.Windows.Forms.DialogResult]::OK) { exit }
    $Image = $dlg.FileName
}
if (-not (Test-Path $Image)) { throw "Image not found: $Image" }

# --- 1. Ask Progman to spawn the second WorkerW (behind the icons) ---
$progman = [Native]::FindWindow("Progman", $null)
if ($progman -eq [IntPtr]::Zero) { throw "Progman not found - Explorer not running?" }
$result = [IntPtr]::Zero
[Native]::SendMessageTimeout($progman, 0x052C, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result) | Out-Null

# --- 2. Build the content window (no taskbar entry, no border) ---
$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.ShowInTaskbar = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$form.Bounds = New-Object System.Drawing.Rectangle($vs.X, $vs.Y, $vs.Width, $vs.Height)
$form.BackColor = [System.Drawing.Color]::Black

# Load via MemoryStream so the image file is not locked while the script runs.
$bytes = [System.IO.File]::ReadAllBytes($Image)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$pict = New-Object System.Windows.Forms.PictureBox
$pict.Dock = [System.Windows.Forms.DockStyle]::Fill
$pict.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$pict.Image = [System.Drawing.Image]::FromStream($ms)
$form.Controls.Add($pict)

# WS_EX_TOOLWINDOW before Show() -> no taskbar/alt-tab flash while adopting.
$hwnd = $form.Handle
$exStyle = [Native]::GetWindowLong($hwnd, -20)
[Native]::SetWindowLong($hwnd, -20, ($exStyle -bor 0x00000080)) | Out-Null

$form.Show()
[void]$form.Handle

# --- 3. Find the right WorkerW, adopt the window ---
# the WorkerW we want is the sibling AFTER the one holding SHELLDLL_DefView (the icons)
$script:worker = [IntPtr]::Zero
$enum = [Native+EnumProc]{
    param($h, $l)
    if ([Native]::FindWindowEx($h, [IntPtr]::Zero, "SHELLDLL_DefView", $null) -ne [IntPtr]::Zero) {
        $c = [Native]::FindWindowEx([IntPtr]::Zero, $h, "WorkerW", $null)
        if ($c -ne [IntPtr]::Zero) { $script:worker = $c; return $false }
    }
    return $true
}
[Native]::EnumWindows($enum, [IntPtr]::Zero) | Out-Null
if ($script:worker -eq [IntPtr]::Zero) {
    # fallback: WorkerW directly under Progman
    $script:worker = [Native]::FindWindowEx($progman, [IntPtr]::Zero, "WorkerW", $null)
}
if ($script:worker -eq [IntPtr]::Zero) { throw "WorkerW not found" }

# drop caption bits, add WS_CHILD
$style = [Native]::GetWindowLong($hwnd, -16)
[Native]::SetWindowLong($hwnd, -16, ($style -band (-bnot 0x00C00000)) -bor 0x40000000) | Out-Null
[Native]::SetParent($hwnd, $script:worker) | Out-Null
[Native]::SetWindowPos($hwnd, [IntPtr]::Zero, $vs.X, $vs.Y, $vs.Width, $vs.Height, 0x0040) | Out-Null # SWP_FRAMECHANGED

# --- 4. Shift+3 stops the wallpaper (global hotkey, works without focus) ---
# MOD_SHIFT = 4, VK '3' = 0x33. Virtual key: on non-US layouts Shift+3 may
# be another character; change 0x33 to e.g. 0x42 ('B') if it does not fire.
if (-not [Native]::RegisterHotKey($form.Handle, 1, 4, 0x33)) {
    Write-Warning "Shift+3 is taken by another app - use stop_wallpaper.bat instead."
}
[System.Windows.Forms.Application]::AddMessageFilter((New-Object HotkeyFilter))

# Stop signal from stop.ps1 (works although the window is no longer top-level).
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({ if ($stopEvent.WaitOne(0)) { $form.Close() } })
$timer.Start()

# --- 5. Cleanup on close: release hotkey, detach from WorkerW so the desktop recovers ---
$form.Add_FormClosing({
    param($s, $e)
    try {
        [Native]::UnregisterHotKey($s.Handle, 1) | Out-Null
        [Native]::SetParent($s.Handle, [IntPtr]::Zero) | Out-Null
    } catch {}
})

[System.Windows.Forms.Application]::Run($form)

$timer.Stop(); $timer.Dispose()
$mutex.Dispose()
