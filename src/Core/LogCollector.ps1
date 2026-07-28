# =====================================================
# LogCollector.ps1 - Core: Thu thap Windows Event Log
# =====================================================

# property map: Event ID -> cac truong can lay them
$global:propertyMap = @{
    4624 = @{ "AccountName" = 5; "LogonType" = 10 }
    4688 = @{ "ProcessName" = 5; "CommandLine" = 8 }
    4104 = @{ "ScriptBlockText" = 2 }
}

function THUTHAPLOG {
    param(
        [string]$DuongDanLog,
        [string]$Mode,
        [DateTime]$StartTime,
        [DateTime]$EndTime,
        [string]$LogName,
        [string[]]$EventChannels = @('Application', 'Security', 'System', 'Setup'),
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )

    try {
        if ($Mode -eq "Limited") {
            if ($StartTime -ge $EndTime) {
                AddLog "Loi: Thoi gian bat dau phai nho hon thoi gian ket thuc" "ERROR" $LogOutput
                return
            }
            AddLog "--------------------------------------------------" "INFO" $LogOutput
            AddLog "Bat dau thu thap log $LogName tu: $StartTime den $EndTime" "INFO" $LogOutput
            AddLog "--------------------------------------------------" "INFO" $LogOutput

            $Filter = @{ LogName = $LogName; StartTime = $StartTime; EndTime = $EndTime }
            $Logs = Get-WinEvent -FilterHashtable $Filter -ErrorAction Stop
        }
        else {
            AddLog "--------------------------------------------------" "INFO" $LogOutput
            AddLog "🟢 Bat dau thu thap log tu: $StartTime den $EndTime" "INFO" $LogOutput
            AddLog "--------------------------------------------------" "INFO" $LogOutput

            $Logs = @()
            foreach ($channel in $EventChannels) {
                try {
                    $Filter = @{ LogName = $channel; StartTime = $StartTime; EndTime = $EndTime }
                    $Logs += Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue
                }
                catch { continue }
            }
        }

        if ($Logs -ne $null -and $Logs.Count -gt 0) {
            $Logs = $Logs | Sort-Object -Property TimeCreated
            $writer = [System.IO.StreamWriter]::new($DuongDanLog, $true, [System.Text.Encoding]::UTF8)
            foreach ($log in $Logs) {
                $eventData = @{}
                if ($global:propertyMap.ContainsKey($log.Id)) {
                    $map = $global:propertyMap[$log.Id]
                    foreach ($field in $map.Keys) {
                        $index = $map[$field]
                        $eventData[$field] = if ($log.Properties.Count -gt $index) {
                            $log.Properties[$index].Value
                        }
                        else { $null }
                    }
                }
                $LogEntry = [PSCustomObject](@{
                        RecordID         = $log.RecordID
                        TimeCreated      = $log.TimeCreated.ToString("o")
                        Id               = $log.Id
                        Level            = $log.Level
                        LevelDisplayName = $log.LevelDisplayName
                        ProviderName     = $log.ProviderName
                        LogName          = $log.LogName
                        ProcessID        = if ($log.Properties.Count -gt 0) { $log.Properties[0].Value } else { $null }
                        UserID           = if ($log.UserId) { $log.UserId.Value } else { $null }
                        Message          = $log.Message
                    } + $eventData)
                $writer.WriteLine(($LogEntry | ConvertTo-Json -Depth 4 -Compress))
            }
            $writer.Close()
            AddLog "✅ Thu thap $($Logs.Count) ban ghi log thanh cong." "SUCCESS" $LogOutput
        }
        else {
            AddLog "Khong co log nao trong khoang thoi gian nay." "INFO" $LogOutput
        }
    }
    catch {
        AddLog "❌ Co loi xay ra khi thu thap Log: $_" "ERROR" $LogOutput
    }
}
