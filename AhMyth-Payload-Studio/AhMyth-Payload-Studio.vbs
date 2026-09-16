' AhMyth Payload Studio - launcher (no console window)
' Prefers PowerShell 7 (pwsh.exe) and falls back to Windows PowerShell 5.1.
' wscript.exe is a GUI host, so double-clicking this file never opens a black window.
Option Explicit
Dim sh, fso, here, psExe, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)

psExe = sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\PowerShell\7\pwsh.exe"
If Not fso.FileExists(psExe) Then
    psExe = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
End If

cmd = """" & psExe & """ -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden " & _
      "-File """ & here & "\AhMyth-Payload-Studio.ps1"""
sh.Run cmd, 0, False