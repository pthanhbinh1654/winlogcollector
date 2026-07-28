# =====================================================
# Main.ps1 - Diem khoi chay chinh v0.3.0
# Fix #9: Silent mode exit codes, no UAC
# Fix #22: Loai bo file cu (da push vao archive/)
# =====================================================
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$Silent
)

# ---- Kiem tra quyen Admin ----
$ScriptPath = $MyInvocation.MyCommand.Path
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator
)
if (-Not $IsAdmin) {
    if ($Silent) {
        Write-Error 'Administrator privilege is required. Run this script as Administrator.'
        exit 11
    }
    $argStr = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$ScriptPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $argStr
    exit
}

# ---- Doc cau hinh tu config.json (exit 10 neu sai) ----
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Khong tim thay file cau hinh: $ConfigPath"
    exit 10
}
try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Config JSON khong hop le: $_"
    exit 10
}

# Chuyen doi sang hashtable
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
        MaxSizeMB   = if ($Config.Queue.MaxSizeMB) { [int]$Config.Queue.MaxSizeMB }  else { 2048 }
        MaxAttempts = if ($Config.Queue.MaxAttempts) { [int]$Config.Queue.MaxAttempts } else { 20 }
    }
}

# ---- Dot-source cac module ----
$SrcBase = Join-Path $PSScriptRoot "src"
. (Join-Path $SrcBase "Utils\Logger.ps1")
. (Join-Path $SrcBase "Utils\Security.ps1")
. (Join-Path $SrcBase "Core\LogCollector.ps1")
. (Join-Path $SrcBase "Core\LogUploader.ps1")

# Khoi tao logger
Initialize-Logger -DataDir $ConfigHT.Local.DataDir

# ---- Tao thu muc can thiet ----
$DataDir = $ConfigHT.Local.DataDir
$ReadyDir = Join-Path $DataDir "Ready"
$QueueDir = Join-Path $DataDir "Queue"
$QuarantineDir = Join-Path $DataDir "Quarantine"
$StateFile = Join-Path $DataDir "state.json"
@($DataDir, $ReadyDir, $QueueDir, $QuarantineDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item $_ -ItemType Directory -Force | Out-Null }
}

# ---- Silent Mode ----
if ($Silent) {
    AddLog "=== WinLogCollector Silent Mode ===" "INFO"
    $exitCode = 0

    # 1. Retry queue truoc
    AddLog "Retry cac file trong queue..." "INFO"
    $retryResult = Retry-WinLogQueue `
        -QueueDir $QueueDir -QuarantineDir $QuarantineDir `
        -RemoteHost $ConfigHT.Remote.Host -User $ConfigHT.Remote.User `
        -RemoteBasePath $ConfigHT.Remote.RemotePath -SSHKeyPath $ConfigHT.Remote.SSHKeyPath `
        -KnownHostsPath $ConfigHT.Remote.KnownHostsPath -Port $ConfigHT.Remote.Port `
        -MaxSizeMB $ConfigHT.Queue.MaxSizeMB -MaxAttempts $ConfigHT.Queue.MaxAttempts

    # 2. Thu thap ky nay
    $StartTime = (Get-Date).ToUniversalTime().AddMinutes(-$ConfigHT.Collection.DefaultIntervalMinutes)
    $EndTime = (Get-Date).ToUniversalTime()
    AddLog "Thu thap tu $($StartTime.ToString('HH:mm:ss')) den $($EndTime.ToString('HH:mm:ss')) UTC" "INFO"

    try {
        $readyFiles = Invoke-WinLogCollection `
            -Subscriptions $ConfigHT.Collection.Subscriptions `
            -OutputDir $ReadyDir -StateFile $StateFile `
            -StartTime $StartTime -EndTime $EndTime
    }
    catch {
        AddLog "Loi thu thap: $_" "ERROR"
        exit 20
    }

    if (-not $readyFiles -or $readyFiles.Count -eq 0) {
        AddLog "Khong co event moi. Ket thuc." "INFO"
        exit 0
    }

    # 3. Archive va upload tung file
    foreach ($readyFile in $readyFiles) {
        $archiveResult = $null
        try {
            $archiveResult = New-WinLogArchive -JsonlPath $readyFile -DestDir $ReadyDir `
                -HostId $env:COMPUTERNAME -StartUtc $StartTime -EndUtc $EndTime
        }
        catch {
            AddLog "Loi tao archive: $_" "ERROR"
            $exitCode = [math]::Max($exitCode, 30)
            continue
        }
        Remove-Item $readyFile -ErrorAction SilentlyContinue

        $uploadResult = Send-WinLogArchive `
            -ArchivePath $archiveResult.ZipPath `
            -RemoteHost $ConfigHT.Remote.Host -User $ConfigHT.Remote.User `
            -RemoteBasePath $ConfigHT.Remote.RemotePath -SSHKeyPath $ConfigHT.Remote.SSHKeyPath `
            -KnownHostsPath $ConfigHT.Remote.KnownHostsPath -Port $ConfigHT.Remote.Port

        if ($uploadResult.Success) {
            Remove-Item $archiveResult.ZipPath -ErrorAction SilentlyContinue
            AddLog "Upload thanh cong: $(Split-Path $archiveResult.ZipPath -Leaf)" "SUCCESS"
        }
        else {
            Move-WinLogArchiveToQueue -ArchivePath $archiveResult.ZipPath -QueueDir $QueueDir -LastError $uploadResult.Error
            AddLog "Upload that bai, da luu vao queue." "WARNING"
            $exitCode = [math]::Max($exitCode, 40)
        }
    }

    # 4. Retry lai lan 2 voi cac file vua them vao queue
    $retryResult2 = Retry-WinLogQueue `
        -QueueDir $QueueDir -QuarantineDir $QuarantineDir `
        -RemoteHost $ConfigHT.Remote.Host -User $ConfigHT.Remote.User `
        -RemoteBasePath $ConfigHT.Remote.RemotePath -SSHKeyPath $ConfigHT.Remote.SSHKeyPath `
        -KnownHostsPath $ConfigHT.Remote.KnownHostsPath -Port $ConfigHT.Remote.Port `
        -MaxSizeMB $ConfigHT.Queue.MaxSizeMB -MaxAttempts $ConfigHT.Queue.MaxAttempts

    AddLog "Ket thuc. Exit code: $exitCode" "INFO"
    exit $exitCode

}
else {
    # ---- GUI Mode ----
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    . (Join-Path $SrcBase "Gui\MainWindow.ps1")
    Show-MainWindow -Config $ConfigHT -ReadyDir $ReadyDir -QueueDir $QueueDir -QuarantineDir $QuarantineDir -StateFile $StateFile
}
