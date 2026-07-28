# =====================================================
# Security.ps1 - Utility: Kiem tra quyen & ket noi
# =====================================================

function KTADMIN {
    param([string]$DuongDan = $MyInvocation.MyCommand.Path)
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator
    )
    if (-Not $IsAdmin) {
        Write-Host "`n❌ Script can quyen Admin de hoat dong. Dang khoi dong lai voi quyen Admin...`n"
        $Argument = "-NoProfile -ExecutionPolicy Bypass -File `"$DuongDan`""
        Start-Process powershell -Verb RunAs -ArgumentList $Argument
        exit
    }
    Write-Host "`n✅ Script dang chay voi quyen Admin.`n"
}

function KTKN {
    param(
        [string]$TenKN,
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )
    try {
        $ping = Test-Connection -ComputerName $TenKN -Count 1 -Quiet
        if ($LogOutput -ne $null) {
            $msg = if ($ping) { "✅ Ket noi thanh cong den $TenKN" } else { "❌ Khong the ket noi den $TenKN" }
            $LogOutput.AppendText("$msg`r`n")
            $LogOutput.ScrollToCaret()
        }
        return $ping
    }
    catch {
        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("❌ Loi kiem tra ket noi: $_`r`n")
            $LogOutput.ScrollToCaret()
        }
        return $false
    }
}
