# =====================================================
# Security.ps1 - Utility: Kiem tra quyen & Preflight Check
# Fix P0.5: Zero WinForms dependency
# Fix P0.11: Preflight check Test-WinLogCollectorPrerequisite
# =====================================================

function global:Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator
    )
}

function global:Test-WinLogCollectorPrerequisite {
    param(
        [string]$RemoteHost,
        [int]$Port = 22,
        [string]$SSHKeyPath,
        [string]$KnownHostsPath,
        [string[]]$Channels = @("Security", "System", "Application", "Microsoft-Windows-PowerShell/Operational")
    )

    AddLog "--- Bat dau Preflight Check ---" "INFO"
    $passed = $true

    # 1. Admin check
    if (Test-IsAdmin) {
        AddLog "✅ [Quyen Admin]: Dang chay voi quyen Administrator." "SUCCESS"
    }
    else {
        AddLog "❌ [Quyen Admin]: Khong co quyen Administrator!" "ERROR"
        $passed = $false
    }

    # 2. Event Log Channels readability
    foreach ($ch in $Channels) {
        try {
            $testEv = Get-WinEvent -ListLog $ch -ErrorAction Stop
            if ($testEv.IsEnabled) {
                AddLog "✅ [Channel $ch]: Hoat dong va co the doc." "SUCCESS"
            }
            else {
                AddLog "⚠ [Channel $ch]: Bi vo hieu hoa (Disabled)." "WARNING"
            }
        }
        catch {
            AddLog "❌ [Channel $ch]: Khong the truy cap ($_.Exception.Message)" "ERROR"
            $passed = $false
        }
    }

    # 3. SFTP client executable check
    $sftpExe = Get-Command "sftp.exe" -ErrorAction SilentlyContinue
    if ($sftpExe) {
        AddLog "✅ [OpenSSH SFTP]: sftp.exe da duoc cai dat ($($sftpExe.Source))." "SUCCESS"
    }
    else {
        AddLog "❌ [OpenSSH SFTP]: sftp.exe khong tim thấy trong PATH!" "ERROR"
        $passed = $false
    }

    # 4. SSH Private Key file & ACL
    if ($SSHKeyPath -and (Test-Path $SSHKeyPath)) {
        AddLog "✅ [SSH Key]: Tim thay file key tai $SSHKeyPath." "SUCCESS"
    }
    else {
        AddLog "❌ [SSH Key]: Khong tim thay file key tai '$SSHKeyPath'." "ERROR"
        $passed = $false
    }

    # 5. KnownHosts file
    if ($KnownHostsPath -and (Test-Path $KnownHostsPath)) {
        AddLog "✅ [KnownHosts]: Tim thay file known_hosts tai $KnownHostsPath." "SUCCESS"
    }
    else {
        AddLog "⚠ [KnownHosts]: Khong tim thấy file known_hosts tai '$KnownHostsPath'. SFTP co thể từ chối kết nối." "WARNING"
    }

    # 6. TCP Port 22 connectivity
    if ($RemoteHost) {
        try {
            $tcpOk = Test-NetConnection -ComputerName $RemoteHost -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($tcpOk) {
                AddLog "✅ [SFTP Port $Port]: Ket noi TCP toi ${RemoteHost}:$Port thanh cong." "SUCCESS"
            }
            else {
                AddLog "❌ [SFTP Port $Port]: Khong the ket noi TCP toi ${RemoteHost}:$Port." "ERROR"
                $passed = $false
            }
        }
        catch {
            AddLog "❌ [SFTP Port $Port]: Loi kiem tra TCP ($_.Exception.Message)" "ERROR"
            $passed = $false
        }
    }

    AddLog "--- Ket thuc Preflight Check (Ket qua: $(if($passed){'DAT'}else{'KHONG DAT'})) ---" (if ($passed) { "SUCCESS" }else { "ERROR" })
    return $passed
}
