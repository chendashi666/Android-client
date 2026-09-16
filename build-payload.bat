@echo off
setlocal
cd /d "%~dp0AhMyth-Client"
set "JAVA_HOME=C:\Users\MECHREVO\jdk11\jdk-11.0.32.1+1"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "GRADLE_USER_HOME=C:\Users\MECHREVO\.gradle-ahmyth"
echo [AhMyth] Building APK payload with Gradle 6.5 / JDK 11...
call gradlew.bat assembleRelease --stacktrace
if errorlevel 1 (
    echo [AhMyth] BUILD FAILED.
    pause
    exit /b 1
)
echo [AhMyth] BUILD OK. APK is at app\build\outputs\apk\release\
pause