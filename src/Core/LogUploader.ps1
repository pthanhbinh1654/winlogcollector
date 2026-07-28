# =====================================================
# LogUploader.ps1 - Core: Nen + Gui Log qua SFTP
# =====================================================

function GUILOGSSH {
    param(
        [string]$DuongDanLog,
        [string]$RemoteHost,
        [string]$User,
        [string]$DuongDanRemote,
        [string]$ThuMucChoGui,
        [string]$SSHFolders,
        [string]$Mode,
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )
    try {
        if (-not (Test-Path $DuongDanLog)) {
            throw "File log khong ton tai: $DuongDanLog"
        }

        $TenFile = Split-Path $DuongDanLog -Leaf
        $TenZip = [System.IO.Path]::ChangeExtension($TenFile, ".zip")
        $DuongDanZip = Join-Path (Split-Path $DuongDanLog -Parent) $TenZip
        $DuongDanChoGui = Join-Path $ThuMucChoGui $TenZip

        # Kiem tra SFTP
        if (-not (Get-Command sftp -ErrorAction SilentlyContinue)) {
            throw "Chua cai dat OpenSSH / SFTP Client"
        }

        # Nen file JSON thanh ZIP truoc khi gui
        Compress-Archive -Path $DuongDanLog -DestinationPath $DuongDanZip -Force
        AddLog "✅ Da nen log: $TenZip ($('{0:N1}' -f ((Get-Item $DuongDanZip).Length / 1KB)) KB)" "SUCCESS" $LogOutput
        Remove-Item -Path $DuongDanLog   # Xoa ban goc sau khi nen

        # Kiem tra ket noi
        if (-not (KTKN -TenKN $RemoteHost -LogOutput $LogOutput)) {
            if ($DuongDanZip -ne $DuongDanChoGui) {
                Copy-Item -Path $DuongDanZip -Destination $DuongDanChoGui
                Remove-Item -Path $DuongDanZip
                AddLog "❌ Khong ket noi duoc SSH, $TenZip da luu vao thu muc cho." "WARNING" $LogOutput
            }
            throw "Khong the ket noi den may chu SSH"
        }
        AddLog "✅ Ket noi SSH thanh cong" "SUCCESS" $LogOutput

        # Xac dinh duong dan remote
        $RemotePath = if ($Mode -eq "Limited") { "/limited" } else { "/continuous" }

        # Tao file lenh SFTP
        $sftpCmdContent = "cd $RemotePath`nput `"$DuongDanZip`"`nbye"
        $sftpPath = Join-Path $env:TEMP "sftp_cmd_$(Get-Date -Format 'HHmmssff').txt"
        $sftpCmdContent | Out-File -Encoding ASCII -FilePath $sftpPath

        $sftpArgs = @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=15",
            "-i", "`"$SSHFolders`"",
            "-b", "`"$sftpPath`"",
            "${User}@${RemoteHost}"
        )
        AddLog "Dang gui $TenZip den ${RemoteHost}${RemotePath}..." "INFO" $LogOutput

        try {
            $result = & sftp @sftpArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "SFTP that bai (exit code $LASTEXITCODE): $result"
            }
            AddLog "✅ Gui Log thanh cong: $TenZip" "SUCCESS" $LogOutput
            Remove-Item -Path $DuongDanZip -ErrorAction SilentlyContinue
            Remove-Item -Path $sftpPath    -ErrorAction SilentlyContinue
            return $true
        }
        catch {
            AddLog "❌ Gui Log that bai: $_" "ERROR" $LogOutput
            Remove-Item -Path $sftpPath -ErrorAction SilentlyContinue
            if ($DuongDanZip -ne $DuongDanChoGui) {
                Copy-Item -Path $DuongDanZip -Destination $DuongDanChoGui -Force
                Remove-Item -Path $DuongDanZip -ErrorAction SilentlyContinue
                AddLog "$TenZip duoc luu vao thu muc cho." "WARNING" $LogOutput
            }
            throw
        }
    }
    catch {
        return $false
    }
}

function GUILOGCHOGUI {
    param(
        [string]$ThuMucChoGui,
        [string]$RemoteHost,
        [string]$User,
        [string]$DuongDanRemote,
        [string]$Mode,
        [string]$SSHFolders,
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )

    if (-Not (KTKN -TenKN $RemoteHost -LogOutput $LogOutput)) {
        return $false
    }

    # Tim tat ca file .zip trong thu muc cho
    $files = Get-ChildItem -Path $ThuMucChoGui -Filter "*.zip" -ErrorAction SilentlyContinue
    if (-not $files) { return $true }   # Khong co file cho, coi la thanh cong

    AddLog "Tim thay $($files.Count) file trong thu muc cho. Tien hanh gui lai..." "INFO" $LogOutput
    $guiThanhCong = $true
    foreach ($file in $files) {
        $ok = GUILOGSSH -DuongDanLog $file.FullName -RemoteHost $RemoteHost `
            -User $User -DuongDanRemote $DuongDanRemote `
            -ThuMucChoGui $ThuMucChoGui -SSHFolders $SSHFolders `
            -Mode $Mode -LogOutput $LogOutput
        if (-not $ok) { $guiThanhCong = $false }
    }
    return $guiThanhCong
}
