# =====================================================
# Logger.ps1 - Utility: Logging khong phu thuoc GUI
# Fix P0.5: Khong dung WinForms type trong Core
#           Dung scriptblock callback de truyen sink
# =====================================================

$global:LogFile = $null
$global:LogSink = $null    # [scriptblock]{ param($msg, $level) ... }

function global:Initialize-Logger {
    param(
        [string]$DataDir = "C:\ProgramData\WinLogCollector",
        [scriptblock]$Sink = $null
    )
    $logDir = Join-Path $DataDir "Logs"
    if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory -Force | Out-Null }
    $global:LogFile = Join-Path $logDir "collector-$(Get-Date -Format 'yyyy-MM-dd').log"
    $global:LogSink = $Sink
}

function global:AddLog {
    param(
        [string]$Message,
        [string]$Type = "INFO",
        $LogOutput = $null   # Tuong thich nguoc - co the truyen bat ki gia tri gi
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $utcNow = [DateTime]::UtcNow.ToString("o")

    # Ghi persistent log file
    if ($global:LogFile) {
        try {
            $entry = "{""timestampUtc"":""$utcNow"",""level"":""$Type"",""message"":$(($Message | ConvertTo-Json -Compress))}"
            Add-Content -Path $global:LogFile -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {}
    }

    # GUI sink (scriptblock duoc truyen tu Show-MainWindow)
    if ($global:LogSink) {
        try { & $global:LogSink $Message $Type } catch {}
        return
    }

    # Fallback: stdout cho Silent mode
    $levelColor = switch ($Type) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $levelColor
}
