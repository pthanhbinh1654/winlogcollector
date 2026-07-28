# =====================================================
# LogCollector.ps1 - Core: Thu thap & Parse Event Log
# Fix P0.6: Query oldest-first theo RecordID, paginate
# Fix P0.7: Sau khi co checkpoint, bo time-window
# Fix P0.8: Drain Ready/ o dau chu ky
# Fix P0.9: Tach FailedChannels khoi "no event"
# =====================================================

function Read-CollectorState {
    param([string]$StateFile)
    if (Test-Path $StateFile) {
        try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{}
}

function Write-CollectorState {
    param([string]$StateFile, [hashtable]$State)
    $tmp = "$StateFile.tmp"
    $State | ConvertTo-Json | Set-Content $tmp -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $StateFile -Force
}

# ---- XML parser: doc theo ten truong, khong dung index ----
function ConvertFrom-WinEventRecord {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )
    process {
        try {
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
                Channel           = $EventRecord.LogName
                Computer          = [string]$xml.Event.System.Computer
                ProviderProcessId = $EventRecord.ProcessId
                SystemUserSid     = if ($EventRecord.UserId) { $EventRecord.UserId.Value } else { $null }
                ActivityId        = if ($EventRecord.ActivityId) { $EventRecord.ActivityId.ToString() } else { $null }
                Keywords          = $EventRecord.Keywords
                EventData         = $eventData
                RawXml            = $EventRecord.ToXml()
            }
        }
        catch {
            # Dead-letter: event hong - ghi lai de khong mat RecordId
            [pscustomobject]@{
                SchemaVersion = '1.0'
                RecordId      = $EventRecord.RecordId
                EventId       = $EventRecord.Id
                Channel       = $EventRecord.LogName
                ParseError    = $_.Exception.Message
                RawXml        = try { $EventRecord.ToXml() } catch { $null }
            }
        }
    }
}

# ---- Query page theo XPath RecordID (oldest-first) ----
function Get-WinEventBatch {
    param(
        [string]$Channel,
        [long]$AfterRecordId = 0,
        [DateTime]$FallbackStartTime,       # Dung khi chua co checkpoint
        [int[]]$EventIDs = @(),
        [int]$BatchSize = 5000
    )

    if ($AfterRecordId -gt 0) {
        # Co checkpoint: dung XPath theo RecordID, khong gioi han thoi gian
        $idFilter = if ($EventIDs.Count -gt 0) {
            $idOr = ($EventIDs | ForEach-Object { "EventID=$_" }) -join " or "
            "*[System[(EventRecordID > $AfterRecordId) and ($idOr)]]"
        }
        else {
            "*[System[EventRecordID > $AfterRecordId]]"
        }
        try {
            # ReverseDirection = false => oldest first
            $query = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new($Channel, [System.Diagnostics.Eventing.Reader.PathType]::LogName, $idFilter)
            $query.ReverseDirection = $false
            $reader = [System.Diagnostics.Eventing.Reader.EventLogReader]::new($query)
            $events = [System.Collections.Generic.List[object]]::new()
            $count = 0
            while ($count -lt $BatchSize) {
                $ev = $reader.ReadEvent()
                if ($null -eq $ev) { break }
                $events.Add($ev)
                $count++
            }
            $reader.Dispose()
            return @{ Events = $events; HasMore = ($count -eq $BatchSize) }
        }
        catch {
            return @{ Events = @(); HasMore = $false; Error = $_.Exception.Message }
        }
    }
    else {
        # Chua co checkpoint: dung FilterHashtable voi FallbackStartTime
        $filter = @{ LogName = $Channel; StartTime = $FallbackStartTime }
        if ($EventIDs.Count -gt 0) { $filter.Id = $EventIDs }
        try {
            $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $BatchSize -ErrorAction Stop |
            Sort-Object RecordId
            return @{ Events = $events; HasMore = ($events.Count -eq $BatchSize) }
        }
        catch {
            if ($_.Exception.Message -match 'No events') { return @{ Events = @(); HasMore = $false } }
            return @{ Events = @(); HasMore = $false; Error = $_.Exception.Message }
        }
    }
}

# ---- Ham thu thap chinh ----
function Invoke-WinLogCollection {
    param(
        [Parameter(Mandatory)][array]$Subscriptions,
        [Parameter(Mandatory)][string]$OutputDir,
        [Parameter(Mandatory)][string]$StateFile,
        [DateTime]$FallbackStartTime = (Get-Date).ToUniversalTime().AddMinutes(-60),
        [string]$HostId = $env:COMPUTERNAME,
        [int]$BatchSize = 5000
    )

    if (-not (Test-Path $OutputDir)) { New-Item $OutputDir -ItemType Directory -Force | Out-Null }
    $state = Read-CollectorState -StateFile $StateFile
    $stateUpdates = @{}
    $readyFiles = [System.Collections.Generic.List[string]]::new()
    $failedChs = [System.Collections.Generic.List[string]]::new()
    $totalCount = 0

    # Fix P0.8: Drain existing .ready files truoc
    $existingReady = Get-ChildItem $OutputDir -Filter "*.ready" -ErrorAction SilentlyContinue
    if ($existingReady) {
        AddLog "Phuc hoi $($existingReady.Count) file .ready tu chu ky truoc." "WARNING"
        foreach ($f in $existingReady) { $readyFiles.Add($f.FullName) }
    }

    foreach ($sub in $Subscriptions) {
        $channel = $sub.Channel
        $eventIds = @($sub.EventIDs)
        $lastId = if ($state.$channel) { [long]$state.$channel.LastRecordId } else { 0 }

        AddLog "Thu thap channel: $channel (RecordID > $lastId, IDs: $(if($eventIds.Count -gt 0){$eventIds -join ','}else{'tat ca'}))" "INFO"

        $batchId = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
        $chanSafe = $channel -replace '[/\\: ]', '_'
        $batchFile = Join-Path $OutputDir "${HostId}_${chanSafe}_${batchId}.jsonl.tmp"
        $readyFile = [IO.Path]::ChangeExtension($batchFile, ".ready")

        $writer = $null
        $firstId = $null
        $lastWritten = $lastId
        $count = 0
        $channelError = $null
        $hasMore = $true

        while ($hasMore) {
            $result = Get-WinEventBatch -Channel $channel -AfterRecordId $lastWritten `
                -FallbackStartTime $FallbackStartTime -EventIDs $eventIds -BatchSize $BatchSize

            if ($result.Error) { $channelError = $result.Error; break }

            $batch = $result.Events
            $hasMore = $result.HasMore

            if (-not $batch -or $batch.Count -eq 0) { break }

            if ($null -eq $writer) {
                $writer = [System.IO.StreamWriter]::new($batchFile, $false, [System.Text.Encoding]::UTF8)
            }

            foreach ($ev in $batch) {
                try {
                    $parsed = ConvertFrom-WinEventRecord -EventRecord $ev
                    $writer.WriteLine(($parsed | ConvertTo-Json -Depth 6 -Compress))
                    if ($null -eq $firstId) { $firstId = $ev.RecordId }
                    $lastWritten = $ev.RecordId
                    $count++
                }
                catch {}
            }
        }

        if ($null -ne $writer) { $writer.Flush(); $writer.Close(); $writer.Dispose() }

        if ($channelError) {
            AddLog "Loi channel ${channel}: $channelError" "ERROR"
            $failedChs.Add($channel)
            if (Test-Path $batchFile) { Remove-Item $batchFile -ErrorAction SilentlyContinue }
            continue
        }

        if ($count -eq 0) {
            AddLog "Khong co event moi trong $channel" "INFO"
            if (Test-Path $batchFile) { Remove-Item $batchFile -ErrorAction SilentlyContinue }
            continue
        }

        # Atomic rename
        Move-Item -Path $batchFile -Destination $readyFile -Force
        AddLog "Da ghi $count events -> $(Split-Path $readyFile -Leaf)" "SUCCESS"
        $readyFiles.Add($readyFile)
        $totalCount += $count
        $stateUpdates[$channel] = @{ LastRecordId = $lastWritten; LastEventTimeUtc = [DateTime]::UtcNow.ToString('o') }
    }

    # Ghi checkpoint chi sau khi file .ready da xac nhan
    if ($stateUpdates.Count -gt 0) {
        $newState = @{}
        $state.PSObject.Properties | ForEach-Object { $newState[$_.Name] = $_.Value }
        $stateUpdates.Keys | ForEach-Object { $newState[$_] = $stateUpdates[$_] }
        Write-CollectorState -StateFile $StateFile -State $newState
    }

    return [pscustomobject]@{
        Success        = ($failedChs.Count -eq 0)
        ReadyFiles     = $readyFiles.ToArray()
        RecordCount    = $totalCount
        FailedChannels = $failedChs.ToArray()
    }
}
