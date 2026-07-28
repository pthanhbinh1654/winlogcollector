# =====================================================
# Collector.Tests.ps1 - Pester Unit Tests for WinLogCollector (Pester v3/v4/v5 compatible)
# =====================================================

$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
. (Join-Path $ProjectRoot "src\Utils\Logger.ps1")
. (Join-Path $ProjectRoot "src\Utils\Security.ps1")
. (Join-Path $ProjectRoot "src\Core\LogCollector.ps1")
. (Join-Path $ProjectRoot "src\Core\LogUploader.ps1")

Describe "WinLogCollector State Management" {
    It "Should write and read state checkpoint correctly" {
        $testStateFile = Join-Path $env:TEMP "test_state_$([System.Guid]::NewGuid().ToString('N')).json"
        $stateData = @{
            Security = @{ LastRecordId = 12345; LastEventTimeUtc = "2026-07-28T12:00:00Z" }
        }

        Write-CollectorState -StateFile $testStateFile -State $stateData
        (Test-Path $testStateFile) | Should Be $true

        $readState = Read-CollectorState -StateFile $testStateFile
        $readState.Security.LastRecordId | Should Be 12345

        Remove-Item $testStateFile -ErrorAction SilentlyContinue
    }
}

Describe "WinLogCollector Preflight Checks" {
    It "Should return boolean from Admin check" {
        $isAdmin = Test-IsAdmin
        ($isAdmin -is [bool]) | Should Be $true
    }
}

Describe "WinLogCollector Log Archive Creation" {
    It "Should create a valid ZIP archive from JSONL file" {
        $tempDir = Join-Path $env:TEMP "collector_test_$([System.Guid]::NewGuid().ToString('N'))"
        New-Item $tempDir -ItemType Directory | Out-Null
        $jsonlFile = Join-Path $tempDir "sample.jsonl"
        @'
{"RecordId":1,"EventId":4624,"Channel":"Security"}
{"RecordId":2,"EventId":4625,"Channel":"Security"}
'@ | Set-Content $jsonlFile -Encoding UTF8

        $archiveResult = New-WinLogArchive -JsonlPath $jsonlFile -DestDir $tempDir -HostId "TESTHOST"
        (Test-Path $archiveResult.ZipPath) | Should Be $true
        $archiveResult.RecordCount | Should Be 2

        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
