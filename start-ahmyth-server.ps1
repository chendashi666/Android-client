# AhMyth Server launcher (PowerShell) - uses isolated JDK 11 for the GUI toolchain
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $root 'AhMyth-Server')

$jdk = 'C:\Users\MECHREVO\jdk11\jdk-11.0.32.1+1'
$env:JAVA_HOME = $jdk
$env:PATH = "$jdk\bin;$env:PATH"

$exe = Join-Path $root 'AhMyth-Server\node_modules\electron\dist\electron.exe'
if (-not (Test-Path $exe)) {
    Write-Host '[AhMyth] First run: installing dependencies (electron)...'
    $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
    npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { Write-Host '[AhMyth] npm install failed. Check network or mirror.'; exit 1 }
}

Write-Host '[AhMyth] Starting server with JDK 11...'
& $exe './app'
if ($LASTEXITCODE -ne 0) { Write-Host '[AhMyth] Server exited with an error.' }