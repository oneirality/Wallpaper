# Gracefully stops the wallpaper by signalling its stop event.
try {
    $evt = [System.Threading.EventWaitHandle]::OpenExisting("Local\MyWallPS_Stop")
    [void]$evt.Set()
    Write-Host "Wallpaper stopped."
} catch {
    Write-Host "Wallpaper not running."
}
