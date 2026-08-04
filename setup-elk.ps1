# =====================================================
# setup-elk.ps1 — Automated 1-Click ELK & SFTP Setup
# =====================================================

$ErrorActionPreference = "Stop"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " 🚀 WINLOGCOLLECTOR — 1-CLICK ELK SETUP AUTOMATION " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

$KeyDir = "C:\ProgramData\WinLogCollector\keys"
$PrivateKeyPath = "$KeyDir\id_rsa"
$PublicKeyPath = "$KeyDir\id_rsa.pub"
$KnownHostsPath = "$KeyDir\known_hosts"
$ConfigFile = Join-Path $PSScriptRoot "config.json"

# 1. SSH Keys Setup
if (-not (Test-Path $KeyDir)) {
    New-Item -ItemType Directory -Path $KeyDir -Force | Out-Null
    Write-Host "[1/6] Đã tạo thư mục lưu SSH Keys: $KeyDir" -ForegroundColor Green
}

if (-not (Test-Path $PrivateKeyPath)) {
    Write-Host "[1/6] Đang tạo SSH Key Pair..." -ForegroundColor Yellow
    & ssh-keygen -t rsa -b 4096 -f "$PrivateKeyPath" -N '""'
    Write-Host "[1/6] SSH Key Pair đã được tạo thành công." -ForegroundColor Green
}
else {
    Write-Host "[1/6] Đã tìm thấy SSH Key sẵn có." -ForegroundColor Green
}

# 2. Copy Pub Key to User Temp for WSL access
$UserPubCopy = "$env:USERPROFILE\id_rsa.pub"
Copy-Item $PublicKeyPath $UserPubCopy -Force

# 3. Deploy ELK Stack on WSL2
Write-Host "[2/6] Đang kiểm tra và khởi động Docker trên WSL2..." -ForegroundColor Yellow
wsl -u root service docker start 2>$null

Write-Host "[3/6] Đang đồng bộ file cấu hình sang WSL2 (~/elk-winlog)..." -ForegroundColor Yellow
wsl -e bash -c "mkdir -p ~/elk-winlog/logstash/pipeline ~/elk-winlog/logstash/config ~/elk-winlog/sftp"

# Copy compose & pipeline from artifacts/local
$ArtifactDir = "$env:USERPROFILE\.gemini\antigravity\brain\e24209ad-ef3c-434d-90dc-7ff5b204f3f8\elk-setup"
if (Test-Path $ArtifactDir) {
    wsl -e bash -c "cp /mnt/c/Users/$env:USERNAME/.gemini/antigravity/brain/e24209ad-ef3c-434d-90dc-7ff5b204f3f8/elk-setup/docker-compose.elk.yml ~/elk-winlog/docker-compose.elk.yml"
    wsl -e bash -c "cp /mnt/c/Users/$env:USERNAME/.gemini/antigravity/brain/e24209ad-ef3c-434d-90dc-7ff5b204f3f8/elk-setup/logstash/pipeline/winlog.conf ~/elk-winlog/logstash/pipeline/winlog.conf"
    wsl -e bash -c "echo 'http.host: \"0.0.0.0\"' > ~/elk-winlog/logstash/config/logstash.yml"
    wsl -e bash -c "echo 'xpack.monitoring.enabled: false' >> ~/elk-winlog/logstash/config/logstash.yml"
}

# Generate SFTP host keys if not exist
wsl -e bash -c "cd ~/elk-winlog/sftp && [ ! -f ssh_host_ed25519_key ] && ssh-keygen -t ed25519 -f ssh_host_ed25519_key -N ''"
wsl -e bash -c "cd ~/elk-winlog/sftp && [ ! -f ssh_host_rsa_key ] && ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key -N ''"

Write-Host "[4/6] Đang khởi động các container ELK Stack (Elasticsearch, Logstash, Kibana, SFTP, Extractor)..." -ForegroundColor Yellow
wsl -e bash -c "cd ~/elk-winlog && docker compose -f docker-compose.elk.yml up -d"

# 4. Inject Public Key into SFTP Container & create directories via shell script
Write-Host "[5/6] Đang nạp Public Key và phân quyền trong container SFTP..." -ForegroundColor Yellow
$pubKeyContent = Get-Content "$env:USERPROFILE\id_rsa.pub" -Raw
$shScript = @"
#!/bin/bash
docker exec sftp01 bash -c "
  mkdir -p /home/winlog/.ssh /home/winlog/incoming/continuous /home/winlog/incoming/limited
  echo '$pubKeyContent' > /home/winlog/.ssh/authorized_keys
  chown -R 1001:1001 /home/winlog/.ssh /home/winlog/incoming
  chmod 700 /home/winlog/.ssh
  chmod 600 /home/winlog/.ssh/authorized_keys
"
"@
$shScript | Out-File -Encoding ASCII "$env:TEMP\inject_keys.sh"
wsl -e bash -c "tr -d '\r' < /mnt/c/Users/$env:USERNAME/AppData/Local/Temp/inject_keys.sh > /tmp/inject.sh && bash /tmp/inject.sh"

# 5. Update Windows known_hosts
Write-Host "[6/6] Đang cập nhật known_hosts trên Windows..." -ForegroundColor Yellow
$origEA = $ErrorActionPreference
$ErrorActionPreference = "Continue"
ssh-keygen -R "[127.0.0.1]:2222" 2>$null | Out-Null
Start-Sleep -Seconds 1
$keys = & ssh-keyscan -p 2222 127.0.0.1 2>$null
$ErrorActionPreference = $origEA

if ($keys) {
    try {
        & cmd.exe /c "del /f /q `"$KnownHostsPath`"" 2>$null
        [System.IO.File]::WriteAllText($KnownHostsPath, (($keys -join "`n") + "`n"), [System.Text.Encoding]::ASCII)
    }
    catch {
        $KnownHostsPath = "$env:USERPROFILE\.ssh\known_hosts"
        if (-not (Test-Path "$env:USERPROFILE\.ssh")) { New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" -Force | Out-Null }
        [System.IO.File]::WriteAllText($KnownHostsPath, (($keys -join "`n") + "`n"), [System.Text.Encoding]::ASCII)
    }
    Write-Host "   -> File known_hosts đã được cập nhật thành công ($KnownHostsPath)." -ForegroundColor Green
}

# 6. Update config.json
if (Test-Path $ConfigFile) {
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $cfg.Remote.Host = "127.0.0.1"
    $cfg.Remote.Port = 2222
    $cfg.Remote.User = "winlog"
    $cfg.Remote.SSHKeyPath = $PrivateKeyPath
    $cfg.Remote.KnownHostsPath = $KnownHostsPath
    $cfg.Remote.RemotePath = "/incoming"
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $ConfigFile -Encoding UTF8
    Write-Host "   -> File config.json đã được cập nhật chuẩn sang SFTP Container." -ForegroundColor Green
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " 🎉 HOÀN THÀNH SETUP HỆ THỐNG ELK TỰ ĐỘNG! " -ForegroundColor Green
Write-Host " -> SFTP Port: 2222 (User: winlog)" -ForegroundColor White
Write-Host " -> Kibana Web UI: http://localhost:5601" -ForegroundColor White
Write-Host " -> Tự động giải nén ZIP: Container 'extractor01' đang chạy background" -ForegroundColor White
Write-Host "=====================================================" -ForegroundColor Cyan
