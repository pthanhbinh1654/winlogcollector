# =====================================================
# LogUploader.ps1 - Core: Archive, Queue & SFTP Upload
# Fix P0.5: Zero WinForms dependency in parameters
# Fix P0.6: Return QueueFull status when size >= MaxSizeMB
# Fix P0.8: MaxAgeDays retention (quarantine expired archives)
# =====================================================

function New-WinLogArchive {
    param(
        [Parameter(Mandatory)][string]$JsonlPath,
        [Parameter(Mandatory)][string]$DestDir,
        [string]$HostId = $env:COMPUTERNAME,
        [DateTime]$StartUtc = [DateTime]::UtcNow,
        [DateTime]$EndUtc = [DateTime]::UtcNow
    )
    if (-not (Test-Path $JsonlPath)) { throw "Khong tim thay file JSONL: $JsonlPath" }

    $batchId = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $startStr = $StartUtc.ToString('yyyyMMddTHHmmssZ')
    $endStr = $EndUtc.ToString('yyyyMMddTHHmmssZ')
    $baseName = "${HostId}_${startStr}_${endStr}_${batchId}"
    $zipPath = Join-Path $DestDir "$baseName.zip"

    # SHA-256 cua file JSONL
    $sha256 = (Get-FileHash -Path $JsonlPath -Algorithm SHA256).Hash

    # Dem record count qua ReadLines (streaming)
    $recordCount = 0
    $reader = [System.IO.File]::ReadLines($JsonlPath)
    foreach ($line in $reader) { if (-not [string]::IsNullOrWhiteSpace($line)) { $recordCount++ } }

    # Manifest.json
    $manifestPath = Join-Path $env:TEMP "manifest_${batchId}.json"
    @{
        schemaVersion    = "1.0"
        collectorVersion = "0.3.1"
        batchId          = $batchId
        host             = $HostId
        startUtc         = $StartUtc.ToString("o")
        endUtc           = $EndUtc.ToString("o")
        recordCount      = $recordCount
        eventFileSha256  = $sha256
        contentType      = "application/x-ndjson"
    } | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8

    Compress-Archive -Path @($JsonlPath, $manifestPath) -DestinationPath $zipPath -Force
    Remove-Item $manifestPath -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        ZipPath     = $zipPath
        BatchId     = $batchId
        RecordCount = $recordCount
    }
}

function Test-SftpConnectivity {
    param(
        [string]$RemoteHost,
        [int]$Port = 22
    )
    try {
        return Test-NetConnection -ComputerName $RemoteHost -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
    }
    catch {
        return $false
    }
}

function Send-WinLogArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ (Test-Path $_ -PathType Leaf) -and ([IO.Path]::GetExtension($_) -eq '.zip') })]
        [string]$ArchivePath,
        [Parameter(Mandatory)][string]$RemoteHost,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$RemoteBasePath,
        [Parameter(Mandatory)][string]$SSHKeyPath,
        [Parameter(Mandatory)][string]$KnownHostsPath,
        [int]$Port = 22,
        [string]$Mode = "continuous"
    )

    $fileName = Split-Path $ArchivePath -Leaf
    $partName = "$fileName.part"
    $remotePath = "$($RemoteBasePath.TrimEnd('/'))/$($Mode.ToLowerInvariant())"
    $sftpPath = Join-Path $env:TEMP "sftp_$([System.Guid]::NewGuid().ToString('N').Substring(0,6)).txt"

    @"
cd $remotePath
put "$ArchivePath" "$partName"
rename "$partName" "$fileName"
bye
"@ | Out-File -Encoding ASCII -FilePath $sftpPath

    $sftpArgs = @(
        '-o', 'StrictHostKeyChecking=yes',
        '-o', "UserKnownHostsFile=`"$KnownHostsPath`"",
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=15',
        '-P', $Port,
        '-i', "`"$SSHKeyPath`"",
        '-b', "`"$sftpPath`"",
        "${User}@${RemoteHost}"
    )

    try {
        $output = & sftp @sftpArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw "SFTP exit code $LASTEXITCODE : $($output -join ' ')" }
        Remove-Item $sftpPath -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Success = $true; Error = $null }
    }
    catch {
        Remove-Item $sftpPath -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message }
    }
}

function Move-WinLogArchiveToQueue {
    param(
        [string]$ArchivePath,
        [string]$QueueDir,
        [string]$LastError = ""
    )
    if (-not (Test-Path $QueueDir)) { New-Item $QueueDir -ItemType Directory -Force | Out-Null }
    $dest = Join-Path $QueueDir (Split-Path $ArchivePath -Leaf)
    Move-Item -Path $ArchivePath -Destination $dest -Force

    $sidecarPath = [IO.Path]::ChangeExtension($dest, ".queue.json")
    $sidecarTmp = "$sidecarPath.tmp"
    @{
        attempt        = 0
        createdUtc     = [DateTime]::UtcNow.ToString("o")
        nextAttemptUtc = [DateTime]::UtcNow.ToString("o")
        lastError      = $LastError
        state          = "Pending"
    } | ConvertTo-Json | Set-Content $sidecarTmp -Encoding UTF8
    Move-Item $sidecarTmp $sidecarPath -Force

    return $dest
}

function Retry-WinLogQueue {
    param(
        [string]$QueueDir,
        [string]$QuarantineDir,
        [string]$RemoteHost,
        [string]$User,
        [string]$RemoteBasePath,
        [string]$SSHKeyPath,
        [string]$KnownHostsPath,
        [int]$Port = 22,
        [string]$Mode = "continuous",
        [int]$MaxSizeMB = 2048,
        [int]$MaxAttempts = 20,
        [int]$MaxAgeDays = 14
    )

    if (-not (Test-Path $QueueDir)) { return @{ Success = $true; QueueFull = $false; Sent = 0; Failed = 0 } }

    $zips = Get-ChildItem $QueueDir -Filter "*.zip" -ErrorAction SilentlyContinue
    if (-not $zips) { return @{ Success = $true; QueueFull = $false; Sent = 0; Failed = 0 } }

    $queueSizeMB = [math]::Round(($zips | Measure-Object Length -Sum).Sum / 1MB, 2)
    $isQueueFull = ($queueSizeMB -ge $MaxSizeMB)
    if ($isQueueFull) {
        AddLog "⚠ Queue dat $queueSizeMB MB (gioi han $MaxSizeMB MB). Queue da day!" "WARNING"
    }

    AddLog "Queue co $($zips.Count) file can gui lai..." "INFO"
    $sent = 0; $failed = 0

    if (-not (Test-SftpConnectivity -RemoteHost $RemoteHost -Port $Port)) {
        AddLog "Khong ket noi duoc TCP port $Port. Bo qua retry." "WARNING"
        return @{ Success = $false; QueueFull = $isQueueFull; Sent = 0; Failed = $zips.Count }
    }

    foreach ($zip in $zips) {
        $sidecarPath = [IO.Path]::ChangeExtension($zip.FullName, ".queue.json")
        $meta = if (Test-Path $sidecarPath) {
            try { Get-Content $sidecarPath -Raw | ConvertFrom-Json } catch { $null }
        }
        else { $null }

        # Fix P0.8: Kiem tra MaxAgeDays retention
        if ($meta -and $meta.createdUtc) {
            try {
                $created = [DateTime]::Parse($meta.createdUtc)
                if ([DateTime]::UtcNow -gt $created.AddDays($MaxAgeDays)) {
                    AddLog "File $($zip.Name) da vuot qua MaxAgeDays ($MaxAgeDays ngay). Chuyen Quarantine." "WARNING"
                    if (-not (Test-Path $QuarantineDir)) { New-Item $QuarantineDir -ItemType Directory -Force | Out-Null }
                    Move-Item $zip.FullName $QuarantineDir -Force
                    Move-Item $sidecarPath $QuarantineDir -Force -ErrorAction SilentlyContinue
                    continue
                }
            }
            catch {}
        }

        # Kiem tra nextAttemptUtc
        if ($meta -and $meta.nextAttemptUtc) {
            try {
                $nextTime = [DateTime]::Parse($meta.nextAttemptUtc)
                if ([DateTime]::UtcNow -lt $nextTime) {
                    AddLog "Bo qua $($zip.Name) - cho den $($nextTime.ToString('HH:mm:ss')) UTC" "INFO"
                    continue
                }
            }
            catch {}
        }

        $result = Send-WinLogArchive -ArchivePath $zip.FullName -RemoteHost $RemoteHost `
            -User $User -RemoteBasePath $RemoteBasePath -SSHKeyPath $SSHKeyPath `
            -KnownHostsPath $KnownHostsPath -Port $Port -Mode $Mode

        if ($result.Success) {
            AddLog "Gui lai thanh cong: $($zip.Name)" "SUCCESS"
            Remove-Item $zip.FullName -ErrorAction SilentlyContinue
            Remove-Item $sidecarPath  -ErrorAction SilentlyContinue
            $sent++
        }
        else {
            $attempt = if ($meta -and $meta.attempt) { [int]$meta.attempt + 1 } else { 1 }
            AddLog "Gui lai that bai lan $($attempt): $($zip.Name) - $($result.Error)" "WARNING"

            if ($attempt -ge $MaxAttempts) {
                if (-not (Test-Path $QuarantineDir)) { New-Item $QuarantineDir -ItemType Directory -Force | Out-Null }
                Move-Item $zip.FullName $QuarantineDir -Force
                Move-Item $sidecarPath $QuarantineDir -Force -ErrorAction SilentlyContinue
                AddLog "Chuyen $($zip.Name) vao Quarantine sau $MaxAttempts lan that bai." "ERROR"
            }
            else {
                $backoffTable = @(1, 2, 5, 15, 30, 60)
                $backoffMin = if ($attempt -le $backoffTable.Count) { $backoffTable[$attempt - 1] } else { 60 }
                $nextAttempt = [DateTime]::UtcNow.AddMinutes($backoffMin)
                $tmpSide = "$sidecarPath.tmp"
                @{
                    attempt        = $attempt
                    createdUtc     = if ($meta -and $meta.createdUtc) { $meta.createdUtc } else { [DateTime]::UtcNow.ToString("o") }
                    nextAttemptUtc = $nextAttempt.ToString("o")
                    lastError      = $result.Error
                    state          = "Pending"
                } | ConvertTo-Json | Set-Content $tmpSide -Encoding UTF8
                Move-Item $tmpSide $sidecarPath -Force
            }
            $failed++
        }
    }
    return @{ Success = ($failed -eq 0); QueueFull = $isQueueFull; Sent = $sent; Failed = $failed }
}

function KTKN {
    param(
        [string]$TenKN,
        [int]$Port = 22
    )
    $ok = Test-SftpConnectivity -RemoteHost $TenKN -Port $Port
    $msg = if ($ok) { "✅ [${TenKN}]:$Port co the ket noi." } else { "❌ [${TenKN}]:$Port khong ket noi duoc." }
    AddLog $msg (if ($ok) { "SUCCESS" } else { "WARNING" })
    return $ok
}
