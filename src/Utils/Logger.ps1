# =====================================================
# Logger.ps1 - Utility: Ghi log ra GUI console + File
# Fix #25: Persistent JSON log file tai ProgramData
# =====================================================

$global:LogFile = $null

function Initialize-Logger {
    param([string]$DataDir = "C:\ProgramData\WinLogCollector")
    $logDir = Join-Path $DataDir "Logs"
    if (-not (Test-Path $logDir)) { New-Item $logDir -ItemType Directory -Force | Out-Null }
    $global:LogFile = Join-Path $logDir "collector-$(Get-Date -Format 'yyyy-MM-dd').log"
}

function AddLog {
    param(
        [string]$Message,
        [string]$Type = "INFO",
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $utcNow = [DateTime]::UtcNow.ToString("o")

    $color = switch ($Type) {
        "ERROR" { [System.Drawing.Color]::FromArgb(255, 80, 80) }
        "WARNING" { [System.Drawing.Color]::DarkOrange }
        "SUCCESS" { [System.Drawing.Color]::FromArgb(0, 200, 100) }
        default { [System.Drawing.Color]::White }
    }

    $target = if ($LogOutput -ne $null) { $LogOutput } else { $global:LogOutputControl }

    if ($target -ne $null) {
        $entry = "[$timestamp] [$Type] $Message`r`n"
        if ($target.InvokeRequired) {
            $target.Invoke([Action] {
                    $target.SelectionStart = $target.TextLength
                    $target.SelectionLength = 0
                    $target.SelectionColor = $color
                    $target.AppendText($entry)
                    $target.ScrollToCaret()
                })
        }
        else {
            $target.SelectionStart = $target.TextLength
            $target.SelectionLength = 0
            $target.SelectionColor = $color
            $target.AppendText($entry)
            $target.ScrollToCaret()
        }
    }
    else {
        $levelColor = switch ($Type) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $levelColor
    }

    # Ghi persistent log file (JSON structured)
    if ($global:LogFile) {
        try {
            $entry = [ordered]@{
                timestampUtc = $utcNow
                level        = $Type
                message      = $Message
            } | ConvertTo-Json -Compress
            Add-Content -Path $global:LogFile -Value $entry -Encoding UTF8
        }
        catch {}
    }
}
