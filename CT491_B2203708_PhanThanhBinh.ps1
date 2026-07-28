function KTADMIN {
    param($DuongDan = $MyInvocation.MyCommand.Path)
    
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    
    if (-Not $IsAdmin) {
        Write-Host "`n❌ Script can quyen Admin de hoat dong. Dang khoi dong lai voi quyen Admin...`n"
        $Argument = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$DuongDan`""
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
            if ($ping) {
                $LogOutput.AppendText("✅ Ket noi thanh cong den $TenKN`r`n")
            }
            else {
                $LogOutput.AppendText("❌ Khong the ket noi den $TenKN`r`n")
            }
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



$global:propertyMap = @{
    4624 = @{
        "AccountName" = 5
        "LogonType"   = 10
    }
    4688 = @{
        "ProcessName" = 5
        "CommandLine" = 8
    }
    4104 = @{
        "ScriptBlockText" = 2
    }
}

function THUTHAPLOG {
    param(
        [string]$DuongDanLog,
        [string]$Mode,
        [DateTime]$StartTime,
        [DateTime]$EndTime,
        [string]$LogName,
        [string]$FolderLuuLog,
        [System.Windows.Forms.RichTextBox]$LogOutput = $null
    )
    
    
    
    <#if (-Not (Test-Path $FolderLuuLog)){
        New-Item -Path $FolderLuuLog -ItemType Directory | Out-Null
        (Get-Item $FolderLuuLog).Attributes += 'Hidden'
        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("✅ Da tao thu muc luu log: $FolderLuuLog`r`n")
            $LogOutput.ScrollToCaret()
        }
    }

    #>
    try {
        if ($Mode -eq "Limited") {
            if ($StartTime -ge $EndTime) {
                if ($LogOutput -ne $null) {
                    $LogOutput.AppendText("`r`n❌ Loi: Thoi gian bat dau phai nho hon thoi gian ket thuc`r`n")
                    $LogOutput.ScrollToCaret()
                }
                return
            }

            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("`r`n--------------------------------------------------`r`n")
                $LogOutput.AppendText("Bat dau thu thap log $LogName tu thoi gian: $StartTime den $EndTime`r`n")
                $LogOutput.AppendText("--------------------------------------------------`r`n")
                $LogOutput.ScrollToCaret()
            }
            
            $Filter = @{
                LogName   = $LogName
                StartTime = $StartTime
                EndTime   = $EndTime
            }
            
            $Logs = Get-WinEvent -FilterHashtable $Filter -ErrorAction Stop
        }
        else {
            $TGBD = $StartTime
            $TGKT = $EndTime
            #$global:LastLogTime = $TGKT.AddMilliseconds(1)
            
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("`r`n--------------------------------------------------`r`n")
                $LogOutput.AppendText("🟢 Bat dau thu thap log tu thoi gian: $TGBD`r`n")
                $LogOutput.AppendText("--------------------------------------------------`r`n")
                $LogOutput.ScrollToCaret()
            }
            
            $AllLogNames = @('Application', 'Security', 'System', 'Setup')
            $Logs = @()

            foreach ($logName in $AllLogNames) {
                try {
                    $Filter = @{
                        LogName   = $logName
                        StartTime = $TGBD
                        EndTime   = $TGKT
                    }

                    $Logs += Get-WinEvent -FilterHashtable $Filter -ErrorAction SilentlyContinue 

                }
                catch {
                    continue
                }
            }
        }
            
        if ($Logs -ne $null -and $Logs.Count -gt 0) {
            $Logs = $Logs | Sort-Object -Property TimeCreated
            $File = [System.IO.StreamWriter]::new($DuongDanLog, $true, [System.Text.Encoding]::UTF8)
            foreach ($log in $Logs) {
                $eventData = @{}  
                if ($global:propertyMap.ContainsKey($log.Id)) {  
                    $map = $global:propertyMap[$log.Id]  
                    foreach ($field in $map.Keys) {  
                        $index = $map[$field]  
                        if ($log.Properties.Count -gt $index) {  
                            $eventData[$field] = $log.Properties[$index].Value  
                        }
                        else {  
                            $eventData[$field] = $null  
                            if ($LogOutput -ne $null) {
                                $LogOutput.AppendText("⚠️ Khong du Properties cho $field (Event ID: $($log.Id))`r`n")
                                $LogOutput.ScrollToCaret()
                            }
                        }  
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

                $json = $LogEntry | ConvertTo-Json -Depth 4 -Compress
                $File.Writeline($json)
            }
            $File.Close()
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("`r`n✅ Thu thap Log thanh cong: tu ngay $StartTime den ngay $EndTime`r`n")
                $LogOutput.ScrollToCaret()
            }
        }
        else {
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("`r`n❌ Khong co Log nao de thu thap`r`n")
                $LogOutput.ScrollToCaret()
            }
        }
    }
    catch {
        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("`r`n❌ Co loi xay ra khi thu thap Log: $_`r`n")
            $LogOutput.ScrollToCaret()
        }
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
    if (-Not(KTKN -TenKN $RemoteHost -LogOutput $LogOutput)) {
        return $false
    }
    else {
        $files = Get-ChildItem -Path $ThuMucChoGui -Filter "*.json"
        if ($files) {
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("`r`nTien hanh gui lai cac Log da gui that bai...`r`n")
                $LogOutput.ScrollToCaret()
            }
            $guiThanhCong = $true
            foreach ($file in $files) {
                $DuongDanLog = $file.FullName
                $ketQua = GUILOGSSH -DuongDanLog $DuongDanLog -RemoteHost $RemoteHost -User $User -DuongDanRemote $DuongDanRemote -ThuMucChoGui $ThuMucChoGui -SSHFolders $SSHFolders -Mode $Mode -LogOutput $LogOutput
                if (-not $ketQua) {
                    $guiThanhCong = $false
                }
            }
            return $guiThanhCong
        }
        return $true
    }
}

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
        # Kiểm tra tồn tại của file log
        if (-not (Test-Path $DuongDanLog)) {
            throw "File log không tồn tại: $DuongDanLog"
        }
        
        # Chuẩn bị các biến cần thiết
        $TenFile = Split-Path $DuongDanLog -Leaf
        $DuongDanChoGui = Join-Path $ThuMucChoGui $TenFile
        
        # Kiểm tra SFTP đã được cài đặt chưa
        if (-not (Get-Command sftp -ErrorAction SilentlyContinue)) {
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("❌ Chua cai dat OpenSSH hoặc SFTP Client`r`n")
                $LogOutput.ScrollToCaret()
            }
            throw "Chưa cài đặt OpenSSH hoặc SFTP Client"
        }
        
        # Kiểm tra kết nối đến máy chủ SSH
        if (-not (KTKN -TenKN $RemoteHost -LogOutput $LogOutput)) {
            # Xử lý khi không kết nối được
            $thongBao = "Không thể kết nối đến máy chủ SSH"
            
            if ($DuongDanLog -ne $DuongDanChoGui) {
                if ($LogOutput -ne $null) {
                    $LogOutput.AppendText("`r`n❌ Khong noi ket duoc den SSH, Log $TenFile duoc luu vao thu muc cho.`r`n")
                    $LogOutput.ScrollToCaret()
                }
                Copy-Item -Path $DuongDanLog -Destination $DuongDanChoGui
                Remove-Item -Path $DuongDanLog
            }
            else {
                if ($LogOutput -ne $null) {
                    $LogOutput.AppendText("`r`n❌ Khong noi ket duoc den SSH, Log $TenFile duoc gui cho lan tiep theo.`r`n")
                    $LogOutput.ScrollToCaret()
                }
            }
            throw $thongBao
        }
        
        # Kết nối SSH thành công
        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("✅ Ket noi SSH thanh cong`r`n")
            $LogOutput.ScrollToCaret()
        }

        # Xác định đường dẫn remote dựa trên mode
        $DuongDanRemote = if ($Mode -eq "Limited") { "/limited" } else { "/continuous" }
        
        # Tạo file lệnh SFTP
        $sftpCommand = @"
cd $DuongDanRemote
put `"$DuongDanLog`"
bye
"@
        $sftpPath = Join-Path $env:TEMP "sftp_commands.txt"
        
        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("DEBUG: File SFTP command path: $sftpPath`r`n")
            $LogOutput.ScrollToCaret()
        }

        # Ghi file lệnh SFTP
        $sftpCommand | Out-File -Encoding ASCII -FilePath $sftpPath
        
        if (-not (Test-Path $sftpPath)) {
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("❌ ERROR: Không thể tạo file SFTP tại '$sftpPath'`r`n")
                $LogOutput.ScrollToCaret()
            }
            throw "Không thể tạo file lệnh SFTP"
        }

        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("✅ File SFTP đã tạo: $sftpPath`r`n")
            $LogOutput.ScrollToCaret()
        }

        # Chuẩn bị lệnh SFTP
        $sftpArgs = @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "BatchMode=yes",
            "-i", "`"$SSHFolders`"",
            "-b", "`"$sftpPath`"",
            "${User}@${RemoteHost}"
        )
        $sftpCommand = "sftp $($sftpArgs -join ' ')"
    
        if ($LogOutput -ne $null) {
            $LogOutput.AppendText("Dang gui Log den ${RemoteHost}...`r`n")
            $LogOutput.ScrollToCaret()
        }

        # Thực thi lệnh SFTP
        try {
            $result = Invoke-Expression $sftpCommand -ErrorAction Stop
            
            if ($LASTEXITCODE -ne 0) {
                throw "SFTP command failed with exit code $LASTEXITCODE"
            }
            
            # Gửi thành công
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("✅ Gui Log thanh cong`r`n")
                $LogOutput.ScrollToCaret()
            }
            
            # Dọn dẹp file
            Remove-Item -Path $DuongDanLog
            Remove-Item -Path $sftpPath
            return $true
        }
        catch {
            # Xử lý khi gửi thất bại
            if ($LogOutput -ne $null) {
                $LogOutput.AppendText("❌ Gui Log that bai: $_`r`n")
                $LogOutput.ScrollToCaret()
            }
            
            # Dọn dẹp file lệnh SFTP
            Remove-Item -Path $sftpPath
            
            # Xử lý file log khi gửi thất bại
            if ($DuongDanLog -ne $DuongDanChoGui) {
                if ($LogOutput -ne $null) {
                    $LogOutput.AppendText("`r`n❌ Gui Log that bai, Log $TenFile duoc luu vao thu muc cho.`r`n")
                    $LogOutput.ScrollToCaret()
                }
                Copy-Item -Path $DuongDanLog -Destination $DuongDanChoGui -Force
                Remove-Item -Path $DuongDanLog
            }
            else {
                if ($LogOutput -ne $null) {
                    $LogOutput.AppendText("`r`n❌ Gui Log that bai, Log $TenFile duoc gui cho lan tiep theo.`r`n")
                    $LogOutput.ScrollToCaret()
                }
            }
            throw
        }
    }
    catch {
        return $false
    }
}

KTADMIN $MyInvocation.MyCommand.Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
#form chinh
$form = New-Object System.Windows.Forms.Form
$form.Text = 'He thong Thu thap Log'
$form.Size = New-Object System.Drawing.Size(850, 900)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Icon = [System.Drawing.SystemIcons]::Application

#chia form thanh hang va cot de sap xep cac control
$tlayout = New-Object System.Windows.Forms.TableLayoutPanel
$tlayout.Dock = 'Fill'
$tlayout.ColumnCount = 1
$tlayout.RowCount = 2
$tlayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 50)))
$tlayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$form.Controls.Add($tlayout)

#panel phia tren
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 70
$header.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$header.Margin = New-Object System.Windows.Forms.Padding(0)
$tlayout.Controls.Add($header, 0, 0)

#title phia tren
$title = New-Object System.Windows.Forms.Label
$title.Text = 'HE THONG THU THAP LOG TREN WINDOWS'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(10, 10)
$title.AutoSize = $true
$header.Controls.Add($title)

#panel chinh phia duoi
$main = New-Object System.Windows.Forms.Panel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(20)
$main.AutoScroll = $false
$tlayout.Controls.Add($main, 0, 1)

#flow de sap xep cac control theo chieu doc
$flow = New-Object System.Windows.Forms.FlowLayoutPanel
$flow.Dock = 'Fill'
$flow.FlowDirection = 'TopDown'
$flow.WrapContents = $false
$flow.AutoScroll = $false
$main.Controls.Add($flow)

#group de chua cac control
$group1 = New-Object System.Windows.Forms.GroupBox
$group1.Text = 'Thu thap Log'
$group1.Size = New-Object System.Drawing.Size(800, 100)
$group1.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flow.Controls.Add($group1)

$g1mode1 = New-Object System.Windows.Forms.Label
$g1mode1.Text = "Che do thu thap:"
$g1mode1.Location = New-Object System.Drawing.Point(20, 25)
$g1mode1.Size = New-Object System.Drawing.Size(100, 20)
$g1mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group1.Controls.Add($g1mode1)

$g1mode1 = New-Object System.Windows.Forms.ComboBox
$g1mode1.Location = New-Object System.Drawing.Point(120, 25)
$g1mode1.Size = New-Object System.Drawing.Size(150, 20)
$g1mode1.DropDownStyle = 'DropDownList'
$g1mode1.Items.AddRange(@('Limited', 'Continuous'))
$g1mode1.SelectedIndex = 0
$g1mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group1.Controls.Add($g1mode1)

$g1mode2 = New-Object System.Windows.Forms.Label
$g1mode2.Text = 'Loai Log:'
$g1mode2.Location = New-Object System.Drawing.Point(400, 25)
$g1mode2.Size = New-Object System.Drawing.Size(60, 20)
$g1mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group1.Controls.Add($g1mode2)

$g1mode2 = New-Object System.Windows.Forms.ComboBox
$g1mode2.Location = New-Object System.Drawing.Point(460, 25)
$g1mode2.Size = New-Object System.Drawing.Size(150, 20)
$g1mode2.DropDownStyle = 'DropDownList'
$g1mode2.Items.AddRange(@('Application', 'Security', 'System', 'Setup'))
$g1mode2.SelectedIndex = 0
$g1mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group1.Controls.Add($g1mode2)

$g1mode3 = New-Object System.Windows.Forms.Label
$g1mode3.Text = 'Thu muc luu Log:'
$g1mode3.Location = New-Object System.Drawing.Point(20, 55)
$g1mode3.Size = New-Object System.Drawing.Size(100, 20)
$g1mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group1.Controls.Add($g1mode3)

$g1mode3 = New-Object System.Windows.Forms.TextBox
$g1mode3.Location = New-Object System.Drawing.Point(120, 55)
$g1mode3.Size = New-Object System.Drawing.Size(550, 20)
$g1mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g1mode3.Text = "C:\"
$group1.Controls.Add($g1mode3)

$g1mode4 = New-Object System.Windows.Forms.Button
$g1mode4.Text = '...'
$g1mode4.Location = New-Object System.Drawing.Point(680, 55)
$g1mode4.Size = New-Object System.Drawing.Size(50, 25)
$g1mode4.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$g1mode4.Add_Click({
        $folder = New-Object System.Windows.Forms.FolderBrowserDialog
        $folder.Description = "Chon thu muc luu Log"
        $folder.SelectedPath = $g1mode3.Text
        if ($folder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $g1mode3.Text = $folder.SelectedPath
        }
    })
$group1.Controls.Add($g1mode4)

$group2 = New-Object System.Windows.Forms.GroupBox
$group2.Text = 'Cau hinh thu thap log trong 1 khoang thoi gian (Limited)'
$group2.Size = New-Object System.Drawing.Size(800, 100)
$group2.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flow.Controls.Add($group2)


$g2mode1 = New-Object System.Windows.Forms.Label
$g2mode1.Text = 'Thoi gian bat dau:'
$g2mode1.Location = New-Object System.Drawing.Point(20, 25)
$g2mode1.Size = New-Object System.Drawing.Size(120, 20)
$g2mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group2.Controls.Add($g2mode1)

$g2mode1 = New-Object System.Windows.Forms.DateTimePicker
$g2mode1.Location = New-Object System.Drawing.Point(140, 25)
$g2mode1.Size = New-Object System.Drawing.Size(150, 20)
$g2mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g2mode1.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$g2mode1.CustomFormat = "dd/MM/yyyy HH:mm:ss"
$g2mode1.Value = (Get-Date).AddDays(-1)

$group2.Controls.Add($g2mode1)


$g2mode2 = New-Object System.Windows.Forms.Label
$g2mode2.Text = 'Thoi gian ket thuc:'
$g2mode2.Location = New-Object System.Drawing.Point(400, 25)
$g2mode2.Size = New-Object System.Drawing.Size(120, 20)
$g2mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group2.Controls.Add($g2mode2)

$g2mode2 = New-Object System.Windows.Forms.DateTimePicker
$g2mode2.Location = New-Object System.Drawing.Point(520, 25)
$g2mode2.Size = New-Object System.Drawing.Size(150, 20)
$g2mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g2mode2.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$g2mode2.CustomFormat = "dd/MM/yyyy HH:mm:ss"
$g2mode2.Value = (Get-Date)
$group2.Controls.Add($g2mode2)

$g2mode3 = New-Object System.Windows.Forms.Label
$g2mode3.Text = 'Thong bao : thoi gian bat dau phai nho hon thoi gian ket thuc'
$g2mode3.Location = New-Object System.Drawing.Point(20, 55)
$g2mode3.Size = New-Object System.Drawing.Size(500, 20)
$g2mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$g2mode3.ForeColor = [System.Drawing.Color]::DarkBlue
$group2.Controls.Add($g2mode3)


$group3 = New-Object System.Windows.Forms.GroupBox
$group3.Text = 'Cau hinh thu thap log lien tuc (Continuous)'
$group3.Size = New-Object System.Drawing.Size(800, 100)
$group3.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flow.Controls.Add($group3)

$g3mode1 = New-Object System.Windows.Forms.Label
$g3mode1.Text = 'Thoi gian thu thap:'
$g3mode1.Location = New-Object System.Drawing.Point(20, 25)
$g3mode1.Size = New-Object System.Drawing.Size(120, 20)
$g3mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group3.Controls.Add($g3mode1)

$g3mode1 = New-Object System.Windows.Forms.NumericUpDown
$g3mode1.Location = New-Object System.Drawing.Point(140, 25)
$g3mode1.Size = New-Object System.Drawing.Size(150, 20)
$g3mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g3mode1.Minimum = 1
$g3mode1.Maximum = 1440
$g3mode1.Value = 9
$group3.Controls.Add($g3mode1)

$g3mode2 = New-Object System.Windows.Forms.CheckBox
$g3mode2.Text = 'Lien tuc (khong gioi han thoi gian)'
$g3mode2.Location = New-Object System.Drawing.Point(320, 25)
$g3mode2.Size = New-Object System.Drawing.Size(250, 20)
$g3mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g3mode2.Add_Click({
        $g3mode1.Enabled = -not $g3mode2.Checked
    })
$group3.Controls.Add($g3mode2)


$g3mode3 = New-Object System.Windows.Forms.Label
$g3mode3.Text = 'Khoang thoi gian giua cac lan (phut):'
$g3mode3.Location = New-Object System.Drawing.Point(20, 55)
$g3mode3.Size = New-Object System.Drawing.Size(200, 20)
$g3mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group3.Controls.Add($g3mode3)

$g3mode3 = New-Object System.Windows.Forms.NumericUpDown
$g3mode3.Location = New-Object System.Drawing.Point(220, 55)
$g3mode3.Size = New-Object System.Drawing.Size(100, 20)
$g3mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g3mode3.Minimum = 1
$g3mode3.Maximum = 1440
$g3mode3.Value = 3
$g3mode3.Increment = 1
$group3.Controls.Add($g3mode3)


$group4 = New-Object System.Windows.Forms.GroupBox
$group4.Text = 'Cau hinh gui log'
$group4.Size = New-Object System.Drawing.Size(800, 160)
$group4.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flow.Controls.Add($group4)



$g4mode1 = New-Object System.Windows.Forms.Label
$g4mode1.Text = 'Dia chi may chu:'
$g4mode1.Location = New-Object System.Drawing.Point(20, 25)
$g4mode1.Size = New-Object System.Drawing.Size(120, 20)
$g4mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group4.Controls.Add($g4mode1)

$g4mode1 = New-Object System.Windows.Forms.TextBox
$g4mode1.Location = New-Object System.Drawing.Point(140, 25)
$g4mode1.Size = New-Object System.Drawing.Size(150, 20)
$g4mode1.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g4mode1.Text = "192.168.1.2"
$group4.Controls.Add($g4mode1)


$g4mode2 = New-Object System.Windows.Forms.Label
$g4mode2.Text = 'Username:'
$g4mode2.Location = New-Object System.Drawing.Point(400, 25)
$g4mode2.Size = New-Object System.Drawing.Size(80, 20)
$g4mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group4.Controls.Add($g4mode2)

$g4mode2 = New-Object System.Windows.Forms.TextBox
$g4mode2.Location = New-Object System.Drawing.Point(480, 25)
$g4mode2.Size = New-Object System.Drawing.Size(150, 20)
$g4mode2.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g4mode2.Text = "sftp"
$group4.Controls.Add($g4mode2)


$g4mode3 = New-Object System.Windows.Forms.Label
$g4mode3.Text = "Duong da luu log o may chu:"
$g4mode3.Location = New-Object System.Drawing.Point(20, 55)
$g4mode3.Size = New-Object System.Drawing.Size(200, 20)
$g4mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group4.Controls.Add($g4mode3)

$g4mode3 = New-Object System.Windows.Forms.TextBox
$g4mode3.Location = New-Object System.Drawing.Point(220, 55)
$g4mode3.Size = New-Object System.Drawing.Size(550, 20)
$g4mode3.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g4mode3.Text = "/home/sftp/uploads"
$group4.Controls.Add($g4mode3)


$g4mode4 = New-Object System.Windows.Forms.Label
$g4mode4.Text = 'Duong dan SSH key:'
$g4mode4.Location = New-Object System.Drawing.Point(20, 85)
$g4mode4.Size = New-Object System.Drawing.Size(200, 20)
$g4mode4.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$group4.Controls.Add($g4mode4)

$g4mode4 = New-Object System.Windows.Forms.TextBox
$g4mode4.Location = New-Object System.Drawing.Point(220, 85)
$g4mode4.Size = New-Object System.Drawing.Size(490, 20)
$g4mode4.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$g4mode4.Text = "C:\Users\Binh\.ssh\sftp_id_rsa"
$group4.Controls.Add($g4mode4)

$g4mode5 = New-Object System.Windows.Forms.Button
$g4mode5.Text = '...'
$g4mode5.Location = New-Object System.Drawing.Point(720, 85)
$g4mode5.Size = New-Object System.Drawing.Size(50, 25)
$g4mode5.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$g4mode5.Add_Click({
        $file = New-Object System.Windows.Forms.OpenFileDialog
        $file.Title = "Chon file SSH key"
        $file.InitialDirectory = [System.IO.Path]::GetDirectoryName($g4mode4.Text)
        if ($file.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $g4mode4.Text = $file.FileName
        }
    })
$group4.Controls.Add($g4mode5)

$g4mode6 = New-Object System.Windows.Forms.Button
$g4mode6.Text = "Kiem tra ket noi"
$g4mode6.Location = New-Object System.Drawing.Point(220, 115)
$g4mode6.Size = New-Object System.Drawing.Size(150, 25)
$g4mode6.FlatStyle = [System.Windows.Forms.FlatStyle]::System
$g4mode6.Add_Click({
        $result = KTKN -TenKN $g4mode1.Text
        if ($result) {
            [System.Windows.Forms.MessageBox]::Show("Ket noi thanh cong den dia chi $($g4mode1.Text)", "Thong bao", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Khong the ket noi den dia chi $($g4mode1.Text)", "Loi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
$group4.Controls.Add($g4mode6)


$group5 = New-Object System.Windows.Forms.GroupBox
$group5.Text = "Trang thai thu thap"
$group5.Size = New-Object System.Drawing.Size(800, 70)
$group5.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flow.Controls.Add($group5)

$g5mode1 = New-Object System.Windows.Forms.ProgressBar
$g5mode1.Location = New-Object System.Drawing.Point(20, 25)
$g5mode1.Size = New-Object System.Drawing.Size(760, 25)
$g5mode1.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$g5mode1.Value = 0

$group5.Controls.Add($g5mode1)

$button = New-Object System.Windows.Forms.Panel
$button.Size = New-Object System.Drawing.Size(800, 50)
$flow.Controls.Add($button)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Bat dau thu thap"
$btnStart.Location = New-Object System.Drawing.Point(300, 5)
$btnStart.Size = New-Object System.Drawing.Size(150, 40)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$button.Controls.Add($btnStart)

# Thêm nút dừng
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Dung thu thap"
$btnStop.Location = New-Object System.Drawing.Point(300, 5)
$btnStop.Size = New-Object System.Drawing.Size(150, 40)
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(215, 0, 0)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnStop.Visible = $false
$button.Controls.Add($btnStop)

# Biến toàn cục để kiểm soát vòng lặp
$global:StopCollection = $false

$btnStop.Add_Click({
        $global:StopCollection = $true
        if ($global:ContinuousTimer -ne $null) {
            $global:ContinuousTimer.Stop()
        }
        AddLog "Dang dung qua trinh thu thap log..." "INFO"
        $g5mode1.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $g5mode1.MarqueeAnimationSpeed = 0
        $g5mode1.Value = 100
        $btnStop.Visible = $false
        $btnStart.Visible = $true
    })

$group6 = New-Object System.Windows.Forms.GroupBox
$group6.Text = "Console Output"
$group6.Size = New-Object System.Drawing.Size(800, 150)
$group6.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$flow.Controls.Add($group6)

$g6mode1 = New-Object System.Windows.Forms.RichTextBox
$g6mode1.Location = New-Object System.Drawing.Point(10, 20)
$g6mode1.Size = New-Object System.Drawing.Size(780, 120) # Giảm kích thước để phù hợp với GroupBox
$g6mode1.Font = New-Object System.Drawing.Font("Consolas", 9)
$g6mode1.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$g6mode1.ForeColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$g6mode1.ReadOnly = $true
$g6mode1.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Both
$g6mode1.HideSelection = $false # Đảm bảo văn bản được chọn luôn hiển thị
$g6mode1.WordWrap = $false # Tắt ngắt dòng để hiển thị đầy đủ nội dung
$g6mode1.Add_TextChanged({ $g6mode1.SelectionStart = $g6mode1.Text.Length; $g6mode1.ScrollToCaret() }) # Tự động cuộn xuống khi có nội dung mới
$group6.Controls.Add($g6mode1)


$g1mode1.Add_SelectedIndexChanged({
        if ($g1mode1.SelectedItem -eq "Limited") {
            $g1mode2.Enabled = $true
            $g2mode1.Enabled = $true
            $g2mode2.Enabled = $true
            $g3mode1.Enabled = $false
            $g3mode2.Enabled = $false
            $g3mode3.Enabled = $false
        }
        else {
            $g2mode1.Enabled = $false
            $g2mode2.Enabled = $false
            $g1mode2.Enabled = $false
            $g3mode3.Enabled = $true
            $g3mode1.Enabled = $true
            $g3mode2.Enabled = $true
        }
    })
# Kích hoạt cấu hình mặc định ban đầu dựa trên giá trị đã chọn
if ($g1mode1.SelectedItem -eq "Limited") {
    $g2mode1.Enabled = $true
    $g2mode2.Enabled = $true
    $g2mode3.Enabled = $true
    $g3mode1.Enabled = $false
    $g3mode2.Enabled = $false
    $g3mode3.Enabled = $false
}

function AddLog {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Type) {
        "ERROR" { [System.Drawing.Color]::Red }
        "WARNING" { [System.Drawing.Color]::Yellow }
        "SUCCESS" { [System.Drawing.Color]::Green }
        default { [System.Drawing.Color]::Black }
    }
    
    # Ensure we're on the UI thread
    if ($g6mode1.InvokeRequired) {
        $g6mode1.Invoke([Action] {
                $g6mode1.SelectionStart = $g6mode1.TextLength
                $g6mode1.SelectionLength = 0
                $g6mode1.SelectionColor = $color
                $g6mode1.AppendText("[$timestamp] [$Type] $Message`r`n")
                $g6mode1.ScrollToCaret()
            })
    }
    else {
        $g6mode1.SelectionStart = $g6mode1.TextLength
        $g6mode1.SelectionLength = 0
        $g6mode1.SelectionColor = $color
        $g6mode1.AppendText("[$timestamp] [$Type] $Message`r`n")
        $g6mode1.ScrollToCaret()
    }
}

$btnStart.Add_Click({
    
    
        try {      
            $g6mode1.Clear()
            AddLog "Bat dau qua trinh thu thap log..."  "INFO"  
            $Mode = $g1mode1.SelectedItem
            $StartTime = $g2mode1.Value
            $EndTime = $g2mode2.Value
            $LogName = if ($Mode -eq "Limited") { $g1mode2.SelectedItem } else { "All" }
            $FolderLuuLog = $g1mode3.Text
            $TGThuThapLienTiep = if ($g3mode2.Checked) { $true } else { [int]$g3mode1.Value * 60 }
            $global:LastLogtime = (Get-Date).AddMinutes( - [int]$g3mode3.Value)
            $KhoangThoiGian = [int]$g3mode3.Value * 60
            $RemoteHost = $g4mode1.Text
            $User = $g4mode2.Text
            $DuongDanRemote = $g4mode3.Text
            $SSHFolders = $g4mode4.Text
         
            # Ẩn nút Start, hiện nút Stop nếu ở chế độ Continuous
            if ($Mode -eq "Continuous") {
                $btnStart.Visible = $false
                $btnStop.Visible = $true
                $global:StopCollection = $false
            }
        
            AddLog "Chế độ thu thập: $Mode" "INFO"
            if ($Mode -eq "Limited") {
                AddLog "Loại log: $LogName" "INFO"
                AddLog "Thời gian bắt đầu: $($StartTime.ToString('dd/MM/yyyy HH:mm:ss'))" "INFO"
                AddLog "Thời gian kết thúc: $($EndTime.ToString('dd/MM/yyyy HH:mm:ss'))" "INFO"
            }
            else {
                if ($g3mode2.Checked) {
                    AddLog "Thời gian thu thập: Lien tuc" "INFO"
                }
                else {
                    AddLog "Thời gian thu thập: $($g3mode1.Value) phút" "INFO"
                }
                AddLog "Khoảng thời gian giữa các lần: $($g3mode3.Value) phút" "INFO"
            }


        
            $FolderLuuLog = Join-Path $FolderLuuLog "HiddenLogs"
            if (-Not (Test-Path $FolderLuuLog)) {
                New-Item -Path $FolderLuuLog -ItemType Directory -Force | Out-Null
                (Get-Item $FolderLuuLog).Attributes += 'Hidden'
                AddLog "Da tao thu muc an: $FolderLuuLog" "SUCCESS"
            }

        
            $ThuMucGui = Join-Path $FolderLuuLog "Gui"
            $ThuMucChoGui = Join-Path $ThuMucGui $Mode
            
            # Tạo và ẩn thư mục Gui nếu chưa tồn tại
            if (-Not (Test-Path $ThuMucGui)) {
                New-Item -Path $ThuMucGui -ItemType Directory -Force | Out-Null
                (Get-Item $ThuMucGui).Attributes += 'Hidden'
                AddLog "Da tao thu muc gui log: $ThuMucGui" "SUCCESS"
            }
            
            # Tạo và ẩn thư mục Mode trong Gui nếu chưa tồn tại
            if (-Not (Test-Path $ThuMucChoGui)) {
                New-Item -Path $ThuMucChoGui -ItemType Directory -Force | Out-Null
                (Get-Item $ThuMucChoGui).Attributes += 'Hidden'
                AddLog "Da tao thu muc luu log: $ThuMucChoGui" "SUCCESS"
            }

            if ($Mode -eq "Limited") {
                if ($StartTime -ge $EndTime) {
                    AddLog "Loi: Thoi gian bat dau phai nho hon thoi gian ket thuc" "ERROR"
                    [System.Windows.Forms.MessageBox]::Show("Loi:Thoi gian bat dau phai nho hon thoi gian ket thuc", "Loi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
                $g5mode1.Value = 30
                $TenLog = "${LogName}_$($StartTime.ToString('yyyy-MM-dd_HHmmss'))-$($EndTime.ToString('yyyy-MM-dd_HHmmss')).json"
                $DuongDanLog = Join-Path $FolderLuuLog $TenLog
                       
                AddLog "Thu thap log tu $($StartTime.ToString('dd/MM/yyyy HH:mm:ss')) den $($EndTime.ToString('dd/MM/yyyy HH:mm:ss'))" "INFO"
                THUTHAPLOG -DuongDanLog $DuongDanLog -Mode $Mode -StartTime $StartTime -EndTime $EndTime -LogName $LogName -FolderLuuLog $FolderLuuLog -LogOutput $g6mode1
                if (Test-Path $DuongDanLog) {
                    AddLog "Thu thap log thanh cong" "SUCCESS"
                    $g5mode1.Value = 60
                    AddLog "Dang gui log den may chu..." "INFO"
                    $guiThanhCong = GUILOGSSH -DuongDanLog $DuongDanLog -RemoteHost $RemoteHost -User $User -DuongDanRemote $DuongDanRemote -ThuMucChoGui $ThuMucChoGui -SSHFolders $SSHFolders -Mode $Mode -LogOutput $g6mode1
                    if ($guiThanhCong) {
                        AddLog "Dang kiem tra va gui lai cac file trong thu muc cho..." "INFO"
                        $g5mode1.Value = 90
                
                        $guiLaiThanhCong = GUILOGCHOGUI -ThuMucChoGui $ThuMucChoGui -RemoteHost $RemoteHost -User $User -DuongDanRemote $DuongDanRemote -Mode $Mode -SSHFolders $SSHFolders -LogOutput $g6mode1
                        if ($guiLaiThanhCong) {
                            AddLog "Thu thap va gui log hoan thanh" "SUCCESS"
                            $g5mode1.Value = 100
                            [System.Windows.Forms.MessageBox]::Show("Thu thap va gui log hoan thanh", "Thong bao", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                        }
                        else {
                            AddLog "Thu thap va gui log hoan thanh! Một số file trong thu mục chờ chưa gửi được" "WARNING"
                            [System.Windows.Forms.MessageBox]::Show("Thu thap va gui log hoan thanh! Một số file trong thu mục chờ chưa gửi được", "Thong bao", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        }
                    }
                    else {
                        Move-Item -Path $DuongDanLog -Destination $ThuMucChoGui -Force
                        $g5mode1.Value = 100
                        AddLog "Log duoc luu tai thu muc cho do khong the gui di" "WARNING"
                        [System.Windows.Forms.MessageBox]::Show("Log duoc luu tai thu muc cho do khong the gui di", "Thong bao", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    }
                }
                else {
                    AddLog "Khong tim thay file log sau khi thu thap" "ERROR"
                    [System.Windows.Forms.MessageBox]::Show("Khong tim thay file log sau khi thu thap", "Loi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
            else {
                $g5mode1.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
                $g5mode1.MarqueeAnimationSpeed = 30
                
                $KhoangThoiGianPhut = [int]$g3mode3.Value
                $IntervalMs = [math]::Max(1000, $KhoangThoiGianPhut * 60 * 1000)
                
                if ($g3mode2.Checked) {
                    $global:RemainingCycles = -1
                    AddLog "Thu thap log lien tuc khong gioi han thoi gian (moi $KhoangThoiGianPhut phut)" "INFO"
                }
                else {
                    $TongThoiGianPhut = [int]$g3mode1.Value
                    $global:RemainingCycles = [math]::Max(1, [math]::Ceiling($TongThoiGianPhut / $KhoangThoiGianPhut))
                    AddLog "Thu thap log lien tuc trong $TongThoiGianPhut phut (tong cong $global:RemainingCycles lan, moi $KhoangThoiGianPhut phut)" "INFO"
                }

                $global:DemGuiLai = 0

                if ($global:ContinuousTimer -ne $null) {
                    $global:ContinuousTimer.Stop()
                    $global:ContinuousTimer.Dispose()
                    $global:ContinuousTimer = $null
                }

                $global:ContinuousTimer = New-Object System.Windows.Forms.Timer
                $global:ContinuousTimer.Interval = $IntervalMs

                # Function thuc hien 1 chu ky thu thap log
                $Script:ExecuteContinuousStep = {
                    if ($global:StopCollection) {
                        if ($global:ContinuousTimer -ne $null) { $global:ContinuousTimer.Stop() }
                        AddLog "Da dung qua trinh thu thap log." "INFO"
                        $g5mode1.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                        $g5mode1.MarqueeAnimationSpeed = 0
                        $g5mode1.Value = 100
                        $btnStop.Visible = $false
                        $btnStart.Visible = $true
                        return
                    }

                    $global:DemGuiLai++
                    if ($global:DemGuiLai -ge 5) {
                        $global:DemGuiLai = 0
                        AddLog "Dang kiem tra va thu gui lai cac log trong thu muc cho..." "INFO"
                        $guiLaiThanhCong = GUILOGCHOGUI -ThuMucChoGui $ThuMucChoGui -RemoteHost $RemoteHost -User $User -DuongDanRemote $DuongDanRemote -Mode $Mode -SSHFolders $SSHFolders -LogOutput $g6mode1
                        if ($guiLaiThanhCong) {
                            AddLog "Da gui thanh cong cac log trong thu muc cho" "SUCCESS"
                        }
                        else {
                            AddLog "Van con mot so log trong thu muc cho chua gui duoc" "WARNING"
                        }
                    }

                    $TenLog = "Continuous_$($global:LastLogtime.ToString('yyyy-MM-dd_HHmmss')).json"
                    $DuongDanLog = Join-Path $FolderLuuLog $TenLog
                    $TGKT = Get-Date
                    AddLog "Bat dau thu thap log tu $($global:LastLogtime.ToString('dd/MM/yyyy HH:mm:ss')) den $($TGKT.ToString('dd/MM/yyyy HH:mm:ss'))" "INFO"
                    THUTHAPLOG -DuongDanLog $DuongDanLog -Mode $Mode -StartTime $global:LastLogtime -EndTime $TGKT -LogName $LogName -FolderLuuLog $FolderLuuLog -LogOutput $g6mode1
                    $global:LastLogtime = $TGKT.AddMilliseconds(1)

                    if (Test-Path $DuongDanLog) {
                        AddLog "Thu thap log thanh cong, dang gui den may chu..." "SUCCESS"
                        $guiThanhCong = GUILOGSSH -DuongDanLog $DuongDanLog -RemoteHost $RemoteHost -User $User -DuongDanRemote $DuongDanRemote -ThuMucChoGui $ThuMucChoGui -SSHFolders $SSHFolders -Mode $Mode -LogOutput $g6mode1
                        if (-not $guiThanhCong) {
                            AddLog "Khong the gui log, luu vao thu muc cho" "WARNING"
                            Move-Item -Path $DuongDanLog -Destination $ThuMucChoGui -Force
                        }
                    }
                    else {
                        AddLog "Khong co log moi trong khoang thoi gian nay" "INFO"
                    }

                    if ($global:RemainingCycles -gt 0) {
                        $global:RemainingCycles--
                        if ($global:RemainingCycles -eq 0) {
                            if ($global:ContinuousTimer -ne $null) { $global:ContinuousTimer.Stop() }
                            AddLog "Da hoan thanh so lan thu thap quy dinh." "SUCCESS"
                            $g5mode1.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                            $g5mode1.MarqueeAnimationSpeed = 0
                            $g5mode1.Value = 100
                            $btnStop.Visible = $false
                            $btnStart.Visible = $true
                            [System.Windows.Forms.MessageBox]::Show("Thu thap log lien tuc hoan thanh", "Thong bao", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                            return
                        }
                        else {
                            AddLog "So lan thu thap con lai: $($global:RemainingCycles)" "INFO"
                        }
                    }
                }

                $global:ContinuousTimer.Add_Tick({
                        & $Script:ExecuteContinuousStep
                    })

                # Chay chu ky dau tien ngay lap tuc
                & $Script:ExecuteContinuousStep
                
                # Sau do kich hoat Timer cho cac chu ky tiep theo (neu chua bi dung)
                if (-not $global:StopCollection -and ($global:RemainingCycles -ne 0)) {
                    $global:ContinuousTimer.Start()
                }
            }
        }
        catch {
            AddLog "Lỗi: $_" "ERROR"
            # Đảm bảo nút Start luôn hiển thị khi có lỗi
            $btnStop.Visible = $false
            $btnStart.Visible = $true
        }
    })


$form.ShowDialog()