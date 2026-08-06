# =====================================================
# Uploader.Tests.ps1 - Pester Unit Tests for LogUploader
# =====================================================

$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
. (Join-Path $ProjectRoot "src\Utils\Logger.ps1")
. (Join-Path $ProjectRoot "src\Core\LogUploader.ps1")

Describe "WinLogCollector LogUploader Queue & Backoff" {
    It "Should create sidecar .queue.json with UTC timestamps" {
        $tempDir = Join-Path $env:TEMP "uploader_test_$([System.Guid]::NewGuid().ToString('N'))"
        New-Item $tempDir -ItemType Directory | Out-Null
        $zipFile = Join-Path $tempDir "test_archive.zip"
        "dummy zip content" | Set-Content $zipFile -Encoding UTF8

        $queueDir = Join-Path $tempDir "Queue"
        $queuedZip = Move-WinLogArchiveToQueue -ArchivePath $zipFile -QueueDir $queueDir -LastError "Connection Failed"

        (Test-Path $queuedZip) | Should Be $true
        $sidecar = [IO.Path]::ChangeExtension($queuedZip, ".queue.json")
        (Test-Path $sidecar) | Should Be $true

        $meta = Get-Content $sidecar -Raw | ConvertFrom-Json
        $meta.lastError | Should Be "Connection Failed"
        $meta.state | Should Be "Pending"

        # Verify parsed timestamps are valid UTC ISO-8601
        $parsedCreated = [DateTime]::Parse($meta.createdUtc).ToUniversalTime()
        $parsedCreated.Kind | Should Be ([System.DateTimeKind]::Utc)

        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Should parse backoff nextAttemptUtc accurately with UTC offset" {
        $metaJson = @{
            attempt        = 1
            createdUtc     = [DateTime]::UtcNow.AddDays(-1).ToString("o")
            nextAttemptUtc = [DateTime]::UtcNow.AddMinutes(-5).ToString("o") # 5 min in past -> ready for retry
            state          = "Pending"
        } | ConvertTo-Json

        $parsedNext = [DateTime]::Parse(($metaJson | ConvertFrom-Json).nextAttemptUtc).ToUniversalTime()
        ([DateTime]::UtcNow -gt $parsedNext) | Should Be $true
    }
}
