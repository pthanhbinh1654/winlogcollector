# =====================================================
# LogCollector.ps1 - Core: Thu thap & Parse Event Log
# Fixes: #4 (EventIDs), #5 (Subscriptions + PS/Operational),
#         #6 (XML parser), #7 (checkpoint), #11 (stream not RAM),
#         #12 (.jsonl ext), #13 (atomic write), #14 (unique filename)
# =====================================================

# ---- Doc / Ghi checkpoint theo tung channel ----
function Read-CollectorState {
    param([string]$StateFile)
    if (Test-Path $StateFile) {
        try { return Get-Content $StateFile -Raw | ConvertFrom-Json }
        catch {}
    }
    return [pscustomobject]@{}
}

function Write-CollectorState {
    param([string]$StateFile, [hashtable]$State)
    $tmp = "$StateFile.tmp"
    $State | ConvertTo-Json | Set-Content $tmp -Encoding UTF8
    Move-Item -Path $tmp -Destination $StateFile -Force
}

# ---- Parse Event Record bang XML (ổn dinh hon Properties[]) ----
function ConvertFrom-WinEventRecord {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )
    process {
        [xml]$xml = $EventRecord.ToXml()
        $eventData = [ordered]@{}
        foreach ($node in @($xml.Event.EventData.Data)) {
            $name = $node.GetAttribute('Name')
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "Data$($eventData.Count)" }
            $eventData[$name] = [string]$node.'#text'
        }

        [pscustomobject]@{
            SchemaVersion     = '1.0'
            RecordId          = $EventRecord.RecordId
            TimeCreatedUtc    = $EventRecord.TimeCreated.ToUniversalTime().ToString('o')
            EventId           = $EventRecord.Id
            Version           = $EventRecord.Version
            Level             = $EventRecord.Level
            LevelDisplayName  = $EventRecord.LevelDisplayName
            ProviderName      = $EventRecord.ProviderName
            ProviderId        = if ($EventRecord.ProviderId) { $EventRecord.ProviderId.ToString() } else { $null }
            Channel           = $EventRecord.LogName
            Computer          = [string]$xml.Event.System.Computer
            ProviderProcessId = $EventRecord.ProcessId
            SystemUserSid     = if ($EventRecord.UserId) { $EventRecord.UserId.Value } else { $null }
            ActivityId        = if ($EventRecord.ActivityId) { $EventRecord.ActivityId.ToString() } else { $null }
            EventData         = $eventData
            Message           = $EventRecord.Message
        }
    }
}

# ---- Ham thu thap chinh: stream tung channel, ghi atomic, checkpoint ----
function Invoke-WinLogCollection {
    param(
        [Parameter(Mandatory)][array]$Subscriptions,   # [{Channel, EventIDs}]
        [Parameter(Mandatory)][string]$OutputDir,       # Thu muc luu .jsonl.ready
        [Parameter(Mandatory)][string]$StateFile,       # Path den checkpoint JSON
        [DateTime]$StartTime = [DateTime]::UtcNow.AddMinutes(-3),
        [DateTime]$EndTime = [DateTime]::UtcNow,
        [string]$HostId = $env:COMPUTERNAME,
        [int]$MaxEvents = 50000,
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )

    $state = Read-CollectorState -StateFile $StateFile
    $stateUpdates = @{}
    $producedFiles = @()

    foreach ($sub in $Subscriptions) {
        $channel = $sub.Channel
        $eventIds = @($sub.EventIDs)

        AddLog "Trat viet channel: $channel (EventIDs: $(if($eventIds.Count -gt 0){$eventIds -join ','}else{'tat ca'}))" "INFO" $LogOutput

        # Lay checkpoint
        $lastRecordId = 0
        if ($state.$channel) { $lastRecordId = [long]$state.$channel.LastRecordId }

        # Build filter
        $filter = @{ LogName = $channel; StartTime = $StartTime; EndTime = $EndTime }
        if ($eventIds.Count -gt 0) { $filter.Id = $eventIds }

        try {
            $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop
        }
        catch [System.Exception] {
            if ($_.Exception.Message -match 'No events') {
                AddLog "Khong co event trong $channel" "INFO" $LogOutput
            }
            else {
                AddLog "Loi doc channel $channel : $($_.Exception.Message)" "WARNING" $LogOutput
            }
            continue
        }

        if (-not $events -or $events.Count -eq 0) {
            AddLog "Khong co event trong $channel" "INFO" $LogOutput
            continue
        }

        # Phat hien log roll-over: neu RecordId nho hon checkpoint
        $maxId = ($events | Measure-Object RecordId -Maximum).Maximum
        if ($lastRecordId -gt 0 -and $maxId -lt $lastRecordId) {
            AddLog "[WARN] Log bi xoa hoac rollover o $channel (lastRecordId=$lastRecordId, maxId=$maxId). Reset checkpoint." "WARNING" $LogOutput
            $lastRecordId = 0
        }

        # Loc theo RecordId de tranh trung lap
        if ($lastRecordId -gt 0) {
            $events = $events | Where-Object { $_.RecordId -gt $lastRecordId }
        }

        if (-not $events -or $events.Count -eq 0) {
            AddLog "Khong co event moi sau checkpoint ($lastRecordId) trong $channel" "INFO" $LogOutput
            continue
        }

        AddLog "Co $($events.Count) event moi tu $channel" "INFO" $LogOutput

        # Tao ten file unique
        $batchId = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
        $chanSafe = $channel -replace '[/\\:]', '_'
        $startStr = $StartTime.ToString('yyyyMMddTHHmmssZ')
        $endStr = $EndTime.ToString('yyyyMMddTHHmmssZ')
        $tmpFile = Join-Path $OutputDir "${HostId}_${chanSafe}_${startStr}_${endStr}_${batchId}.jsonl.tmp"
        $readyFile = [IO.Path]::ChangeExtension($tmpFile, ".ready")

        # Ghi file ATOM: viet .tmp -> rename .ready
        $writer = $null
        $firstId = $null; $lastId = $null; $count = 0
        try {
            $writer = [System.IO.StreamWriter]::new($tmpFile, $false, [System.Text.Encoding]::UTF8)
            foreach ($ev in $events | Sort-Object RecordId) {
                $parsed = ConvertFrom-WinEventRecord -EventRecord $ev
                $writer.WriteLine(($parsed | ConvertTo-Json -Depth 6 -Compress))
                if ($null -eq $firstId) { $firstId = $ev.RecordId }
                $lastId = $ev.RecordId
                $count++
            }
        }
        finally {
            if ($writer) { $writer.Flush(); $writer.Close(); $writer.Dispose() }
        }

        # Rename atomic
        Move-Item -Path $tmpFile -Destination $readyFile -Force
        AddLog "Da ghi $count events -> $(Split-Path $readyFile -Leaf)" "SUCCESS" $LogOutput

        $producedFiles += $readyFile

        # Cap nhat state (chi sau khi file .ready da xac nhan)
        $stateUpdates[$channel] = @{
            LastRecordId     = $lastId
            LastEventTimeUtc = [DateTime]::UtcNow.ToString('o')
        }
    }

    # Ghi checkpoint atomic
    if ($stateUpdates.Count -gt 0) {
        $newState = @{}
        ($state.PSObject.Properties | ForEach-Object { $newState[$_.Name] = $_.Value })
        $stateUpdates.Keys | ForEach-Object { $newState[$_] = $stateUpdates[$_] }
        Write-CollectorState -StateFile $StateFile -State $newState
        AddLog "Da cap nhat checkpoint: $($stateUpdates.Keys -join ', ')" "INFO" $LogOutput
    }

    return $producedFiles
}

# ---- Wrapper thu thap theo kieu Limited (giu tuong thich) ----
function THUTHAPLOG {
    param(
        [string]$DuongDanLog,
        [string]$Mode,
        [DateTime]$StartTime,
        [DateTime]$EndTime,
        [string]$LogName,
        [array]$Subscriptions = $null,
        [string[]]$EventChannels = @('Application', 'Security', 'System', 'Setup'),
        [int[]]$EventIDs = @(),
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )

    # Limited: giu loi goi cu, dung Subscriptions neu co
    $useSubs = if ($Subscriptions) { $Subscriptions } else {
        @{ Channel = $LogName; EventIDs = @($EventIDs) }
    }

    $outputDir = Split-Path $DuongDanLog -Parent
    $stateFile = Join-Path $outputDir "state.json"
    $results = Invoke-WinLogCollection -Subscriptions @($useSubs) -OutputDir $outputDir `
        -StateFile $stateFile -StartTime $StartTime -EndTime $EndTime -LogOutput $LogOutput

    # Doi ten file dau ra thanh ten chinh xac (tuong thich voi phian cua)
    if ($results.Count -gt 0) {
        Move-Item -Path $results[0] -Destination ([IO.Path]::ChangeExtension($DuongDanLog, ".jsonl.ready")) -Force
        return $true
    }
    return $false
}
