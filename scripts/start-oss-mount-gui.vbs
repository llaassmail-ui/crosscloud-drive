Option Explicit

Dim shell, fso, scriptDir, guiScript, command

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
guiScript = fso.BuildPath(scriptDir, "oss-mount-gui.ps1")
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & guiScript & Chr(34)

shell.Run command, 0, False
