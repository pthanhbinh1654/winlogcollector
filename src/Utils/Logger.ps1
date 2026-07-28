# =====================================================
# Logger.ps1 - Utility: Ghi log ra console GUI
# =====================================================

function AddLog {
    param(
        [string]$Message,
        [string]$Type = "INFO",
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Type) {
        "ERROR" { [System.Drawing.Color]::Red }
        "WARNING" { [System.Drawing.Color]::DarkOrange }
        "SUCCESS" { [System.Drawing.Color]::DarkGreen }
        default { [System.Drawing.Color]::Black }
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
        # Fallback: ghi ra stdout khi chay Silent mode
        Write-Host "[$timestamp] [$Type] $Message"
    }
}
