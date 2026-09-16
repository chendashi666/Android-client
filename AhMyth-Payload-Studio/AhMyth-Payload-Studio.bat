@echo off
setlocal
title AhMyth Payload Studio
cd /d "%~dp0"
set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PS_EXE%" set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0AhMyth-Payload-Studio.ps1"
endlocal
