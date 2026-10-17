#Requires -Version 5.1
<#
.SYNOPSIS
    QuickLock-USB - locks your Windows PC the moment your USB key is removed.

.DESCRIPTION
    Turns any USB drive into a physical "key" for your PC.
    While the key is plugged in, you work normally. Pull it out and Windows
    locks instantly. Plug it back in, sign in, and protection re-arms.

    The key is identified by a random secret file stored on the USB drive
    (only its SHA-256 hash is saved on the PC) plus the drive's volume serial
    number - not by drive letter, so another USB stick on the same letter
    will NOT be accepted.

.PARAMETER Register
    Make a USB drive your key (creates a hidden secret key file on it).

.PARAMETER Drive
    Used with -Register to pick a drive letter directly, e.g. -Drive E:

.PARAMETER Install
    Start QuickLock-USB automatically every time you sign in (Task Scheduler).

.PARAMETER Uninstall
    Remove the auto-start task and stop QuickLock-USB.

.PARAMETER Status
    Show configuration, whether the key is detected, and whether it is running.

.PARAMETER NoTray
    Run without the system-tray icon (console / background loop only).

.EXAMPLE
    .\QuickLock.ps1 -Register
.EXAMPLE
    .\QuickLock.ps1 -Install
.EXAMPLE
    .\QuickLock.ps1 -Status

.LINK
    https://github.com/aparthasaradhireddy897-hash/QuickLock-USB
#>
[CmdletBinding()]
param(
    [switch]$Register,
    [string]$Drive,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$NoTray
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Constants & state
# --------------------------------------------------------------------------
$script:Version    = '2.0.0'
$script:AppName    = 'QuickLock-USB'
$script:AppDir     = Join-Path $env:LOCALAPPDATA 'QuickLock'
$script:BinDir     = Join-Path $script:AppDir 'bin'
$script:ConfigPath = Join-Path $script:AppDir 'config.json'
$script:LogPath    = Join-Path $script:AppDir 'quicklock.log'
$script:KeyDirName = '.quicklock'
$script:KeyRelPath = '.quicklock\key.bin'
$script:TaskName   = 'QuickLock-USB'
$script:MutexName  = 'Local\QuickLockUSB'

$script:Defaults = [ordered]@{
    KeyHash             = ''          # SHA-256 of the secret key file (set by -Register)
    VolumeSerial        = ''          # serial of the registered USB drive (set by -Register)
    CheckIntervalMs     = 1000        # how often to check for the key (min 250)
    GraceSeconds        = 0           # wait this long after removal before locking
    Action              = 'Lock'      # Lock | LockAndScreenOff
    StrictMode          = $false      # re-lock if someone signs in without the key
    StrictRelockSeconds = 15          # how often strict mode re-locks (min 5)
    ShowTray            = $true       # show the system-tray icon
    Notifications       = $true       # show tray balloon notifications
    LogMaxKB            = 512         # rotate the log file above this size
}

$script:Config      = $null
$script:ConfigStamp = $null
$script:State       = 'WaitingForKey'   # WaitingForKey | Armed | Locked
$script:KeyRoot     = $null             # e.g. 'E:\' while the key is present
$script:RemovedAt   = $null
$script:LastLockAt  = $null
$script:Paused      = $false
$script:Tray        = $null
$script:StatusItem  = $null
$script:Timer       = $null

# --------------------------------------------------------------------------
# Logging & configuration
# --------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    try {
        if (-not (Test-Path $script:AppDir)) {
            New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null
        }
        $maxKB = 512
        if ($script:Config) { $maxKB = [int]$script:Config.LogMaxKB }
        if ((Test-Path $script:LogPath) -and ((Get-Item $script:LogPath).Length -gt ($maxKB * 1KB))) {
            Move-Item -Path $script:LogPath -Destination "$($script:LogPath).old" -Force
        }
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never crash the protection loop.
    }
}

function Get-Config {
    $cfg = [pscustomobject]$script:Defaults
    if (Test-Path $script:ConfigPath) {
        try {
            $saved = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
            foreach ($p in $saved.PSObject.Properties) {
                if ($cfg.PSObject.Properties.Name -contains $p.Name) { $cfg.($p.Name) = $p.Value }
            }
        }
        catch {
            Write-Warning "Config file is invalid, using defaults: $_"
        }
    }
    # Keep values in a safe range.
    if ([int]$cfg.CheckIntervalMs -lt 250)    { $cfg.CheckIntervalMs = 250 }
    if ([int]$cfg.GraceSeconds -lt 0)         { $cfg.GraceSeconds = 0 }
    if ([int]$cfg.StrictRelockSeconds -lt 5)  { $cfg.StrictRelockSeconds = 5 }
    if (@('Lock', 'LockAndScreenOff') -notcontains $cfg.Action) { $cfg.Action = 'Lock' }
    return $cfg
}

function Save-Config {
    param([Parameter(Mandatory)]$Config)
    New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null
    $Config | ConvertTo-Json | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

function Sync-Config {
    # Hot-reload config.json when it changes (no restart needed).
    try {
        if (-not (Test-Path $script:ConfigPath)) { return }
        $stamp = (Get-Item $script:ConfigPath).LastWriteTimeUtc
        if ($script:ConfigStamp -and $stamp -ne $script:ConfigStamp) {
            $script:Config  = Get-Config
            $script:KeyRoot = $null
            $script:RemovedAt = $null
            if ($script:Timer) { $script:Timer.Interval = [int]$script:Config.CheckIntervalMs }
            Set-State 'WaitingForKey'   # never lock just because the key was re-registered
            Write-Log 'Configuration reloaded.'
        }
        $script:ConfigStamp = $stamp
    }
    catch {
        Write-Log "Could not reload config: $_" 'WARN'
    }
}

# --------------------------------------------------------------------------
# Key detection
# --------------------------------------------------------------------------
function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-VolumeSerial {
    param([string]$Letter)   # 'E:'
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$Letter'" -ErrorAction Stop
        if ($disk) { return [string]$disk.VolumeSerialNumber }
    }
    catch { }
    return ''
}

function Get-CandidateDrives {
    # USB sticks are 'Removable'; many USB SSDs/HDDs report as 'Fixed'.
    $sys = $env:SystemDrive.TrimEnd('\')
    [System.IO.DriveInfo]::GetDrives() | Where-Object {
        ($_.DriveType -eq 'Removable' -or $_.DriveType -eq 'Fixed') -and
        $_.Name.TrimEnd('\') -ne $sys -and
        $_.IsReady
    }
}

function Test-KeyOnDrive {
    param([string]$Root, [switch]$CheckSerial)
    try {
        $path = Join-Path $Root $script:KeyRelPath
        if (-not [System.IO.File]::Exists($path)) { return $false }
        $hash = Get-Sha256Hex ([System.IO.File]::ReadAllBytes($path))
        if ($hash -ne $script:Config.KeyHash) { return $false }
        if ($CheckSerial -and $script:Config.VolumeSerial) {
            if ((Get-VolumeSerial $Root.Substring(0, 2)) -ne $script:Config.VolumeSerial) { return $false }
        }
        return $true
    }
    catch {
        return $false   # drive vanished mid-read, access denied, etc.
    }
}

function Test-KeyPresent {
    # Fast path: re-check the drive the key was last seen on.
    if ($script:KeyRoot -and (Test-KeyOnDrive $script:KeyRoot)) { return $true }
    $script:KeyRoot = $null
    # Slow path: scan drives (also verifies the volume serial).
    foreach ($d in Get-CandidateDrives) {
        $root = $d.RootDirectory.FullName
        if (Test-KeyOnDrive $root -CheckSerial) {
            $script:KeyRoot = $root
            return $true
        }
    }
    return $false
}

# --------------------------------------------------------------------------
# Lock actions
# --------------------------------------------------------------------------
function Initialize-Native {
    if (-not ('QuickLock.Native' -as [type])) {
        Add-Type -Namespace QuickLock -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool LockWorkStation();
[DllImport("user32.dll")]
public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
'@
    }
}

function Test-SessionLocked {
    # LogonUI.exe runs while the lock screen is shown.
    return [bool](Get-Process -Name LogonUI -ErrorAction SilentlyContinue)
}

function Invoke-LockAction {
    param([string]$Reason)
    Initialize-Native
    if (-not [QuickLock.Native]::LockWorkStation()) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Log "LockWorkStation failed (Win32 error $err)." 'ERROR'
        return
    }
    if ($script:Config.Action -eq 'LockAndScreenOff') {
        Start-Sleep -Milliseconds 500
        # HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, 2 = off
        [void][QuickLock.Native]::PostMessage([IntPtr]0xFFFF, 0x0112, [IntPtr]0xF170, [IntPtr]2)
    }
    Write-Log "Workstation locked ($Reason)."
}

# --------------------------------------------------------------------------
# Monitor (state machine)
# --------------------------------------------------------------------------
function Show-Notice {
    param([string]$Text, [string]$Icon = 'Info')
    if ($script:Tray -and $script:Config.Notifications) {
        $script:Tray.ShowBalloonTip(3000, $script:AppName, $Text, [System.Windows.Forms.ToolTipIcon]::$Icon)
    }
}

function Update-TrayText {
    if (-not $script:Tray) { return }
    $label = switch ($script:State) {
        'WaitingForKey' { 'waiting for key' }
        'Armed'         { 'protecting' }
        'Locked'        { 'key removed' }
    }
    if ($script:Paused) { $label = 'paused' }
    $script:Tray.Text = "QuickLock: $label"
    if ($script:StatusItem) { $script:StatusItem.Text = "Status: $label" }
}

function Set-State {
    param([string]$New)
    if ($script:State -ne $New) {
        Write-Log "State: $($script:State) -> $New"
        $script:State = $New
        Update-TrayText
    }
}

function Invoke-Tick {
    Sync-Config
    $present = Test-KeyPresent
    $now = Get-Date

    switch ($script:State) {
        'WaitingForKey' {
            # Never lock at start-up: we only arm once the key has been seen.
            if ($present) {
                Set-State 'Armed'
                Show-Notice "Key detected on $($script:KeyRoot). Protection is ON."
            }
        }
        'Armed' {
            if ($present) { $script:RemovedAt = $null; break }
            if (-not $script:RemovedAt) { $script:RemovedAt = $now }
            if (($now - $script:RemovedAt).TotalSeconds -ge [double]$script:Config.GraceSeconds) {
                $script:RemovedAt = $null
                if ($script:Paused) {
                    Write-Log 'Key removed while paused - not locking.'
                    Set-State 'WaitingForKey'
                }
                else {
                    Invoke-LockAction 'key removed'
                    $script:LastLockAt = $now
                    Set-State 'Locked'
                }
            }
        }
        'Locked' {
            if ($present) {
                Set-State 'Armed'
                Show-Notice 'Welcome back - key detected.'
            }
            elseif ($script:Config.StrictMode -and -not $script:Paused -and
                    ($now - $script:LastLockAt).TotalSeconds -ge [double]$script:Config.StrictRelockSeconds -and
                    -not (Test-SessionLocked)) {
                # Someone signed in without the key: lock again.
                Invoke-LockAction 'strict mode - signed in without key'
                $script:LastLockAt = $now
            }
        }
    }
}

function Start-PlainLoop {
    while ($true) {
        try { Invoke-Tick } catch { Write-Log "Tick error: $_" 'ERROR' }
        Start-Sleep -Milliseconds ([int]$script:Config.CheckIntervalMs)
    }
}

function Start-TrayLoop {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:StatusItem = $menu.Items.Add('Status: starting')
    $script:StatusItem.Enabled = $false
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $pauseItem = $menu.Items.Add('Pause protection')
    $pauseItem.add_Click({
        $script:Paused = -not $script:Paused
        if ($script:Paused) { $this.Text = 'Resume protection'; Write-Log 'Protection paused from tray.' }
        else                { $this.Text = 'Pause protection';  Write-Log 'Protection resumed from tray.' }
        Update-TrayText
    })

    $lockItem = $menu.Items.Add('Lock now')
    $lockItem.add_Click({ Invoke-LockAction 'tray: lock now' })

    $logItem = $menu.Items.Add('Open log')
    $logItem.add_Click({ if (Test-Path $script:LogPath) { Start-Process notepad.exe $script:LogPath } })

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $exitItem = $menu.Items.Add('Exit')
    $exitItem.add_Click({ [System.Windows.Forms.Application]::Exit() })

    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.Icon = [System.Drawing.SystemIcons]::Shield
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.Visible = $true
    Update-TrayText

    $script:Timer = New-Object System.Windows.Forms.Timer
    $script:Timer.Interval = [int]$script:Config.CheckIntervalMs
    $script:Timer.add_Tick({ try { Invoke-Tick } catch { Write-Log "Tick error: $_" 'ERROR' } })

    try {
        Invoke-Tick
        $script:Timer.Start()
        [System.Windows.Forms.Application]::Run()
    }
    finally {
        $script:Timer.Stop()
        $script:Tray.Visible = $false
        $script:Tray.Dispose()
    }
}

function Start-Monitor {
    if (-not $script:Config.KeyHash) {
        $msg = "No USB key registered yet.`n`nRun Setup.cmd (or: QuickLock.ps1 -Register) first."
        if ($script:Config.ShowTray -and -not $NoTray) {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($msg, $script:AppName, 'OK', 'Warning')
        }
        throw $msg
    }

    $mutex = New-Object System.Threading.Mutex($false, $script:MutexName)
    $owned = $false
    try { $owned = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) {
        Write-Host 'QuickLock-USB is already running.'
        $mutex.Dispose()
        return
    }

    try {
        Initialize-Native
        $script:ConfigStamp = if (Test-Path $script:ConfigPath) { (Get-Item $script:ConfigPath).LastWriteTimeUtc } else { $null }
        Write-Log ("QuickLock-USB {0} started (interval {1} ms, action {2}, grace {3}s, strict {4})." -f `
            $script:Version, $script:Config.CheckIntervalMs, $script:Config.Action, $script:Config.GraceSeconds, $script:Config.StrictMode)
        if ($script:Config.ShowTray -and -not $NoTray) { Start-TrayLoop } else { Start-PlainLoop }
    }
    finally {
        Write-Log 'QuickLock-USB stopped.'
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

# --------------------------------------------------------------------------
# Commands: Register / Install / Uninstall / Status
# --------------------------------------------------------------------------
function Invoke-Register {
    if ($Drive) {
        $letter = $Drive.Trim().TrimEnd('\').TrimEnd(':').ToUpper() + ':'
        if ($letter -eq $env:SystemDrive.TrimEnd('\').ToUpper()) { throw 'The Windows system drive cannot be used as a key.' }
        $target = [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.Name.TrimEnd('\').ToUpper() -eq $letter -and $_.IsReady } |
            Select-Object -First 1
        if (-not $target) { throw "Drive $letter was not found or is not ready." }
    }
    else {
        $drives = @(Get-CandidateDrives | Where-Object { $_.DriveType -eq 'Removable' })
        if ($drives.Count -eq 0) {
            throw 'No removable USB drive found. Plug in your USB drive. (USB SSDs that show as a normal disk: use -Drive X:)'
        }
        Write-Host ''
        Write-Host 'Removable drives found:'
        for ($i = 0; $i -lt $drives.Count; $i++) {
            $d = $drives[$i]
            $label = if ($d.VolumeLabel) { $d.VolumeLabel } else { '(no label)' }
            Write-Host ('  [{0}] {1}  {2}  {3:N1} GB' -f ($i + 1), $d.Name, $label, ($d.TotalSize / 1GB))
        }
        $choice = Read-Host "Choose the drive to use as your key (1-$($drives.Count))"
        $n = 0
        if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $drives.Count) { throw 'Invalid choice.' }
        $target = $drives[$n - 1]
    }

    $root = $target.RootDirectory.FullName
    $dir  = Join-Path $root $script:KeyDirName
    if (-not (Test-Path $dir)) {
        $item = New-Item -ItemType Directory -Path $dir
        $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
    }

    # 64 random bytes = the secret. Only its hash is stored on the PC.
    $bytes = New-Object byte[] 64
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }

    $keyPath = Join-Path $root $script:KeyRelPath
    if (Test-Path $keyPath) { (Get-Item $keyPath -Force).Attributes = 'Normal' }
    [System.IO.File]::WriteAllBytes($keyPath, $bytes)
    (Get-Item $keyPath -Force).Attributes = 'Hidden, ReadOnly'

    $script:Config.KeyHash      = Get-Sha256Hex $bytes
    $script:Config.VolumeSerial = Get-VolumeSerial $root.Substring(0, 2)
    Save-Config $script:Config
    Write-Log "New key registered on $root (volume serial $($script:Config.VolumeSerial))."

    Write-Host ''
    Write-Host "Done! $root is now your QuickLock key." -ForegroundColor Green
    Write-Host 'Any previously registered key no longer works.'
    Write-Host 'Do not delete the hidden .quicklock folder on the drive. Formatting the drive also erases the key.'
}

function Get-RunningInstances {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
        Where-Object { $_.CommandLine -like '*QuickLock.ps1*' -and $_.ProcessId -ne $PID }
}

function Invoke-Install {
    if (-not $script:Config.KeyHash) { throw 'Register a USB key first:  .\QuickLock.ps1 -Register' }

    # Copy the program to %LOCALAPPDATA%\QuickLock\bin so it works even if
    # this download folder is moved or deleted.
    New-Item -ItemType Directory -Path $script:BinDir -Force | Out-Null
    $ps1 = Join-Path $script:BinDir 'QuickLock.ps1'
    if ($PSCommandPath -ne $ps1) {
        Copy-Item -Path $PSCommandPath -Destination $ps1 -Force
        $vbsSrc = Join-Path $PSScriptRoot 'QuickLock.vbs'
        if (Test-Path $vbsSrc) { Copy-Item -Path $vbsSrc -Destination (Join-Path $script:BinDir 'QuickLock.vbs') -Force }
    }
    Get-ChildItem -Path $script:BinDir -File | Unblock-File

    $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
    if ([Environment]::OSVersion.Version.Build -ge 22000) {
        # Windows 11: start fully hidden without VBScript (which Microsoft is phasing out).
        $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe $psArgs"
    }
    else {
        $vbs = Join-Path $script:BinDir 'QuickLock.vbs'
        $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbs`""
    }

    $user      = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
                    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force `
        -Description 'Locks Windows when the QuickLock USB key is removed.' | Out-Null

    # Restart so the freshly installed copy is the one running.
    Get-RunningInstances | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-ScheduledTask -TaskName $script:TaskName
    Write-Log 'Installed auto-start task.'

    Write-Host ''
    Write-Host 'Installed! QuickLock-USB now starts automatically when you sign in.' -ForegroundColor Green
    Write-Host 'It is running now - look for the shield icon in the system tray.'
}

function Invoke-Uninstall {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
    }
    Get-RunningInstances | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path $script:BinDir) { Remove-Item -Path $script:BinDir -Recurse -Force }
    Write-Log 'Uninstalled.'

    Write-Host ''
    Write-Host 'QuickLock-USB was removed and stopped.' -ForegroundColor Green
    Write-Host "Your settings and log are kept in $($script:AppDir) - delete that folder to remove everything."
}

function Show-Status {
    $taskState = 'not installed'
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($task) { $taskState = "installed ($($task.State))" }

    $keyState = 'not registered'
    if ($script:Config.KeyHash) {
        $keyState = if (Test-KeyPresent) { "plugged in ($($script:KeyRoot))" } else { 'registered, not plugged in' }
    }

    $running = @(Get-RunningInstances).Count

    Write-Host ''
    Write-Host "QuickLock-USB $($script:Version)" -ForegroundColor Cyan
    Write-Host ('  USB key        : {0}' -f $keyState)
    Write-Host ('  Running now    : {0}' -f $(if ($running -gt 0) { 'yes' } else { 'no' }))
    Write-Host ('  Auto-start     : {0}' -f $taskState)
    Write-Host ('  Action         : {0}' -f $script:Config.Action)
    Write-Host ('  Check interval : {0} ms' -f $script:Config.CheckIntervalMs)
    Write-Host ('  Grace period   : {0} s' -f $script:Config.GraceSeconds)
    Write-Host ('  Strict mode    : {0}' -f $script:Config.StrictMode)
    Write-Host ('  Config file    : {0}' -f $script:ConfigPath)
    Write-Host ('  Log file       : {0}' -f $script:LogPath)
}

# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------
$script:Config = Get-Config
try {
    if     ($Register)  { Invoke-Register }
    elseif ($Install)   { Invoke-Install }
    elseif ($Uninstall) { Invoke-Uninstall }
    elseif ($Status)    { Show-Status }
    else                { Start-Monitor }
}
catch {
    Write-Log "$_" 'ERROR'
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}
