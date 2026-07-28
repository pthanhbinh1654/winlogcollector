# =====================================================
# Main.ps1 - Diem khoi chay chinh
# Su dung: .\Main.ps1 [-ConfigPath <path>] [-Silent]
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
    Write-Host "`n❌ Can quyen Admin. Dang khoi dong lai voi quyen Admin...`n"
    $argStr = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    if ($Silent) { $argStr += " -Silent" }
    if ($ConfigPath -ne "$PSScriptRoot\config.json") { $argStr += " -ConfigPath `"$ConfigPath`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $argStr
    exit
}
Write-Host "`n✅ Dang chay voi quyen Admin.`n"

# ---- Doc cau hinh tu config.json ----
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Khong tim thay file cau hinh: $ConfigPath"
    exit 1
}
$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Chuyen doi sang hashtable de de truyen vao modules
$ConfigHT = @{
    Remote     = @{
        Host       = $Config.Remote.Host
        User       = $Config.Remote.User
        SSHKeyPath = $Config.Remote.SSHKeyPath
        RemotePath = $Config.Remote.RemotePath
    }
    Local      = @{
        FolderLuuLog = $Config.Local.FolderLuuLog
    }
    Collection = @{
        EventChannels          = @($Config.Collection.EventChannels)
        EventIDs               = @($Config.Collection.EventIDs)
        DefaultIntervalMinutes = $Config.Collection.DefaultIntervalMinutes
        DefaultDurationMinutes = $Config.Collection.DefaultDurationMinutes
    }
}

# ---- Dot-source cac module ----
$SrcBase = Join-Path $PSScriptRoot "src"
. (Join-Path $SrcBase "Utils\Logger.ps1")
. (Join-Path $SrcBase "Utils\Security.ps1")
. (Join-Path $SrcBase "Core\LogCollector.ps1")
. (Join-Path $SrcBase "Core\LogUploader.ps1")

# ---- Khoi chay ----
if ($Silent) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] [INFO] Chay o che do Silent (khong co GUI)"
    # Thu thap 1 lan ngay tu thoi gian config
    $StartTime = (Get-Date).AddMinutes(-$ConfigHT.Collection.DefaultIntervalMinutes)
    $EndTime = Get-Date
    $FolderLuuLog = Join-Path $ConfigHT.Local.FolderLuuLog "HiddenLogs"
    if (-not (Test-Path $FolderLuuLog)) {
        New-Item -Path $FolderLuuLog -ItemType Directory -Force | Out-Null
        (Get-Item $FolderLuuLog).Attributes += 'Hidden'
    }
    $ThuMucChoGui = Join-Path $FolderLuuLog "Gui\Continuous"
    if (-not (Test-Path $ThuMucChoGui)) { New-Item -Path $ThuMucChoGui -ItemType Directory -Force | Out-Null }

    $TenLog = "Silent_$($StartTime.ToString('yyyy-MM-dd_HHmmss')).json"
    $DuongDanLog = Join-Path $FolderLuuLog $TenLog
    THUTHAPLOG -DuongDanLog $DuongDanLog -Mode "Continuous" -StartTime $StartTime -EndTime $EndTime `
        -LogName "" -EventChannels $ConfigHT.Collection.EventChannels

    if (Test-Path $DuongDanLog) {
        GUILOGSSH -DuongDanLog $DuongDanLog -RemoteHost $ConfigHT.Remote.Host `
            -User $ConfigHT.Remote.User -DuongDanRemote $ConfigHT.Remote.RemotePath `
            -ThuMucChoGui $ThuMucChoGui -SSHFolders $ConfigHT.Remote.SSHKeyPath `
            -Mode "Continuous"
    }
}
else {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    . (Join-Path $SrcBase "Gui\MainWindow.ps1")
    Show-MainWindow -Config $ConfigHT
}
