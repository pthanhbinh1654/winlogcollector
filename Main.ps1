# =====================================================
# Main.ps1 - Single Entry Point & Orchestrator v0.3.1
# Fix P0.10: Named Mutex (Global\WinLogCollector)
# Fix P0.3: Single unified cycle function (Invoke-WinLogCollectorCycle)
# Fix P0.1: Pass Context hashtable to GUI
# =====================================================
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$Silent
)

# ---- 1. Named Mutex (Prevent Concurrent Instances - P0.10) ----
$createdNew = $false
$mutex = [System.Threading.Mutex]::new($true, "Global\WinLogCollector", [ref]$createdNew)
if (-not $createdNew) {
    Write-Host "⚠ Single instance enforced. Another instance of WinLogCollector is already running." -ForegroundColor Yellow
    exit 12   # Exit code 12 = Already Running
}

# ---- 2. Admin Check ----
$ScriptPath = $MyInvocation.MyCommand.Path
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator
)
if (-not $IsAdmin) {
    if ($Silent) {
        Write-Error 'Administrator privilege is required. Run this script as Administrator.'
        $mutex.ReleaseMutex() | Out-Null
        exit 11   # Exit code 11 = Insufficient privileges
    }
    $argStr = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$ScriptPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $argStr
    $mutex.ReleaseMutex() | Out-Null
    exit
}

# ---- 3. Load & Validate Config ----
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Khong tim thay file cau hinh: $ConfigPath"
    $mutex.ReleaseMutex() | Out-Null
    exit 10
}
try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Config JSON khong hop le: $_"
    $mutex.ReleaseMutex() | Out-Null
    exit 10
}

# Convert Config to Hashtable Context
$ConfigHT = @{
    Remote     = @{
        Host           = $Config.Remote.Host
        Port           = if ($Config.Remote.Port) { [int]$Config.Remote.Port } else { 22 }
        User           = $Config.Remote.User
        SSHKeyPath     = $Config.Remote.SSHKeyPath
        KnownHostsPath = $Config.Remote.KnownHostsPath
        RemotePath     = $Config.Remote.RemotePath
    }
    Local      = @{
        DataDir = if ($Config.Local.DataDir) { $Config.Local.DataDir } else { "C:\ProgramData\WinLogCollector" }
    }
    Collection = @{
        Subscriptions          = @($Config.Collection.Subscriptions)
        DefaultIntervalMinutes = [int]$Config.Collection.DefaultIntervalMinutes
        DefaultDurationMinutes = [int]$Config.Collection.DefaultDurationMinutes
    }
    Queue      = @{
        MaxSizeMB   = if ($Config.Queue.MaxSizeMB) { [int]$Config.Queue.MaxSizeMB }   else { 2048 }
        MaxAttempts = if ($Config.Queue.MaxAttempts) { [int]$Config.Queue.MaxAttempts }  else { 20 }
        MaxAgeDays  = if ($Config.Queue.MaxAgeDays) { [int]$Config.Queue.MaxAgeDays }   else { 14 }
    }
}

# ---- 4. Dot-source Core Modules ----
$SrcBase = Join-Path $PSScriptRoot "src"
. (Join-Path $SrcBase "Utils\Logger.ps1")
. (Join-Path $SrcBase "Utils\Security.ps1")
. (Join-Path $SrcBase "Core\LogCollector.ps1")
. (Join-Path $SrcBase "Core\LogUploader.ps1")

# Initialize Logger
Initialize-Logger -DataDir $ConfigHT.Local.DataDir

# Directories
$DataDir = $ConfigHT.Local.DataDir
$ReadyDir = Join-Path $DataDir "Ready"
$QueueDir = Join-Path $DataDir "Queue"
$QuarantineDir = Join-Path $DataDir "Quarantine"
$StateFile = Join-Path $DataDir "state.json"
@($DataDir, $ReadyDir, $QueueDir, $QuarantineDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item $_ -ItemType Directory -Force | Out-Null }
}

$Context = @{
    Config        = $ConfigHT
    DataDir       = $DataDir
    ReadyDir      = $ReadyDir
    QueueDir      = $QueueDir
    QuarantineDir = $QuarantineDir
    StateFile     = $StateFile
}

# ---- 5. Single Unified Orchestration Function (P0.3) ----
function Invoke-WinLogCollectorCycle {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [string]$Mode = "continuous"
    )

    $cfg = $Context.Config
    $exitCode = 0

    AddLog "=== Bat dau chu ky LogCollector ===" "INFO"

    # Step A: Drain Queue first
    AddLog "1/4. Retry cac file trong Queue..." "INFO"
    $retry1 = Retry-WinLogQueue `
        -QueueDir $Context.QueueDir -QuarantineDir $Context.QuarantineDir `
        -RemoteHost $cfg.Remote.Host -User $cfg.Remote.User `
        -RemoteBasePath $cfg.Remote.RemotePath -SSHKeyPath $cfg.Remote.SSHKeyPath `
        -KnownHostsPath $cfg.Remote.KnownHostsPath -Port $cfg.Remote.Port `
        -Mode $Mode -MaxSizeMB $cfg.Queue.MaxSizeMB -MaxAttempts $cfg.Queue.MaxAttempts

    # Step B: Collect Events
    AddLog "2/4. Thu thap cac Event Log moi..." "INFO"
    $collectResult = $null
    try {
        $collectResult = Invoke-WinLogCollection `
            -Subscriptions $cfg.Collection.Subscriptions `
            -OutputDir $Context.ReadyDir -StateFile $Context.StateFile `
            -FallbackStartTime (Get-Date).ToUniversalTime().AddMinutes(-$cfg.Collection.DefaultIntervalMinutes)
    }
    catch {
        AddLog "Loi ngoai le khi thu thap log: $_" "ERROR"
        return [pscustomobject]@{ Success = $false; ExitCode = 20; Collected = 0; Queued = 0 }
    }

    if (-not $collectResult.Success) {
        AddLog "Co channel thu thap thất bại: $($collectResult.FailedChannels -join ', ')" "WARNING"
        $exitCode = 20
    }

    # Step C: Process & Upload Ready files (JSONL -> ZIP -> SFTP)
    $readyFiles = $collectResult.ReadyFiles
    if ($readyFiles -and $readyFiles.Count -gt 0) {
        AddLog "3/4. Xuly va upload $($readyFiles.Count) file ready..." "INFO"
        foreach ($readyFile in $readyFiles) {
            if (-not (Test-Path $readyFile)) { continue }
            $archive = $null
            try {
                $archive = New-WinLogArchive -JsonlPath $readyFile -DestDir $Context.ReadyDir -HostId $env:COMPUTERNAME
                Remove-Item $readyFile -ErrorAction SilentlyContinue
            }
            catch {
                AddLog "Loi nen archive cho $readyFile : $_" "ERROR"
                $exitCode = [math]::Max($exitCode, 30)
                continue
            }

            $upload = Send-WinLogArchive `
                -ArchivePath $archive.ZipPath `
                -RemoteHost $cfg.Remote.Host -User $cfg.Remote.User `
                -RemoteBasePath $cfg.Remote.RemotePath -SSHKeyPath $cfg.Remote.SSHKeyPath `
                -KnownHostsPath $cfg.Remote.KnownHostsPath -Port $cfg.Remote.Port -Mode $Mode

            if ($upload.Success) {
                Remove-Item $archive.ZipPath -ErrorAction SilentlyContinue
                AddLog "Upload thanh cong: $(Split-Path $archive.ZipPath -Leaf)" "SUCCESS"
            }
            else {
                Move-WinLogArchiveToQueue -ArchivePath $archive.ZipPath -QueueDir $Context.QueueDir -LastError $upload.Error
                AddLog "Upload that bai, da luu vao Queue." "WARNING"
                $exitCode = [math]::Max($exitCode, 40)
            }
        }
    }
    else {
        AddLog "3/4. Khong co file ready moi." "INFO"
    }

    # Step D: Final Queue Retry (catch anything queued in Step C)
    AddLog "4/4. Drain Queue lan cuoi..." "INFO"
    $retry2 = Retry-WinLogQueue `
        -QueueDir $Context.QueueDir -QuarantineDir $Context.QuarantineDir `
        -RemoteHost $cfg.Remote.Host -User $cfg.Remote.User `
        -RemoteBasePath $cfg.Remote.RemotePath -SSHKeyPath $cfg.Remote.SSHKeyPath `
        -KnownHostsPath $cfg.Remote.KnownHostsPath -Port $cfg.Remote.Port `
        -Mode $Mode -MaxSizeMB $cfg.Queue.MaxSizeMB -MaxAttempts $cfg.Queue.MaxAttempts

    AddLog "=== Hoan thanh chu ky. ExitCode: $exitCode ===" "INFO"

    return [pscustomobject]@{
        Success    = ($exitCode -eq 0)
        ExitCode   = $exitCode
        Collected  = $collectResult.RecordCount
        ReadyFiles = $readyFiles.Count
    }
}

# ---- 6. Entry Point Execution ----
try {
    if ($Silent) {
        $result = Invoke-WinLogCollectorCycle -Context $Context -Mode "continuous"
        $mutex.ReleaseMutex() | Out-Null
        exit $result.ExitCode
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        . (Join-Path $SrcBase "Gui\MainWindow.ps1")
        # Pass Context hashtable to GUI (Fix P0.1)
        Show-MainWindow -Context $Context
    }
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
}
