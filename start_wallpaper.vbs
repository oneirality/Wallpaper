' Launches wall.ps1 with no console window at all (nothing in Alt+Tab).
' Double-click this file, or put a shortcut to it in shell:startup.
' Optional: pass an image path as the first argument to skip the file picker.
Set args = WScript.Arguments
Set fso = CreateObject("Scripting.FileSystemObject")
dir_ = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir_ & "\wall.ps1"""
If args.Count > 0 Then cmd = cmd & " -Image """ & args(0) & """"
CreateObject("Wscript.Shell").Run cmd, 0, False
