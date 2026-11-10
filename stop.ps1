# Gracefully stops the wallpaper by signalling its stop event.
# (FindWindow cannot be used: the wallpaper window is a WS_CHILD of WorkerW
# after adoption, and FindWindow only sees top-level windows.)
try {
    $evt = [System.Threading.EventWaitHandle]::OpenExisting("Local\MyWallPS_Stop")
    [void]$evt.Set()
    Write-Host "Wallpaper stopped."
} catch {
    Write-Host "Wallpaper not running."
}
