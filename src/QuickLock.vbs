' QuickLock-USB launcher - starts QuickLock.ps1 with no console window.
' Double-click this file to start QuickLock-USB manually.
Option Explicit
Dim fso, shell, dir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\QuickLock.ps1"""
shell.Run cmd, 0, False
