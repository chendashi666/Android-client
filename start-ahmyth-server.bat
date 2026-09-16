@echo off
setlocal
title AhMyth Server Launcher (JDK 11)
cd /d "%~dp0"

if not exist "AhMyth-Server\node_modules\electron\dist\electron.exe" (
    echo [AhMyth] First run: installing dependencies for electron...
    cd /d "AhMyth-Server"
    set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
    call npm install --no-audit --no-fund
    if errorlevel 1 (
        echo [AhMyth] npm install failed. Check network or mirror.
        pause
        exit /b 1
    )
    cd /d "%~dp0"
)

rem Point the GUI (java-version check / apktool / sign.jar) at the ISOLATED JDK 11.
set "JAVA_HOME=C:\Users\MECHREVO\jdk11\jdk-11.0.32.1+1"
set "PATH=%JAVA_HOME%\bin;%PATH%"

echo [AhMyth] Starting server with JDK 11...
cd /d "AhMyth-Server"
"node_modules\electron\dist\electron.exe" ./app
if errorlevel 1 (
    echo [AhMyth] Server exited with an error.
    pause
)