@echo off
setlocal
title AhMyth Payload Builder
cd /d "%~dp0"
set "JAVA_HOME=C:\Users\MECHREVO\jdk11\jdk-11.0.32.1+1"
set "PATH=%JAVA_HOME%\bin;%PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-payload-gui.ps1" %*
if errorlevel 1 ( echo [x] Build failed. See output above. & pause & exit /b 1 )
echo.
echo [OK] Done.
pause