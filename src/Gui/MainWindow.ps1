# =====================================================
# MainWindow.ps1 - GUI: Windows Forms Interface
# =====================================================

function Show-MainWindow {
    param([hashtable]$Config)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # --- Form chinh ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'WinLogCollector – He thong Thu thap Log'
    $form.Size = New-Object System.Drawing.Size(860, 920)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false

    # --- Header ---
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 70
    $header.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $form.Controls.Add($header)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = 'WinLogCollector – Thu thap & Gui Log Windows'
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point(15, 10)
    $lblTitle.AutoSize = $true
    $header.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "v2.0 – Modular Edition | github.com/B2203708"
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(200, 230, 255)
    $lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblSub.Location = New-Object System.Drawing.Point(17, 45)
    $lblSub.AutoSize = $true
    $header.Controls.Add($lblSub)

    # --- Main panel + FlowLayout ---
    $main = New-Object System.Windows.Forms.Panel
    $main.Location = New-Object System.Drawing.Point(0, 70)
    $main.Size = New-Object System.Drawing.Size(860, 850)
    $main.Padding = New-Object System.Windows.Forms.Padding(15)
    $main.AutoScroll = $true
    $form.Controls.Add($main)

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'
    $flow.FlowDirection = 'TopDown'
    $flow.WrapContents = $false
    $flow.AutoScroll = $false
    $main.Controls.Add($flow)

    # ---- Helper: tao GroupBox nhanh ----
    function New-Group { param($text, $h) $g = New-Object System.Windows.Forms.GroupBox; $g.Text = $text; $g.Size = New-Object System.Drawing.Size(810, $h); $g.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $g }
    function New-Lbl { param($t, $x, $y, $w = 120) $l = New-Object System.Windows.Forms.Label; $l.Text = $t; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, 20); $l.Font = New-Object System.Drawing.Font("Segoe UI", 9); $l }
    function New-Txt { param($t, $x, $y, $w = 150) $tb = New-Object System.Windows.Forms.TextBox; $tb.Text = $t; $tb.Location = New-Object System.Drawing.Point($x, $y); $tb.Size = New-Object System.Drawing.Size($w, 22); $tb.Font = New-Object System.Drawing.Font("Segoe UI", 9); $tb }

    # ==================== GROUP 1: Thu thap ====================
    $group1 = New-Group "Thu thap Log" 105
    $flow.Controls.Add($group1)

    $group1.Controls.Add((New-Lbl "Che do:" 15 28 80))
    $cboMode = New-Object System.Windows.Forms.ComboBox
    $cboMode.Location = New-Object System.Drawing.Point(100, 25); $cboMode.Size = New-Object System.Drawing.Size(140, 22)
    $cboMode.DropDownStyle = 'DropDownList'; $cboMode.Items.AddRange(@('Limited', 'Continuous')); $cboMode.SelectedIndex = 0
    $cboMode.Font = New-Object System.Drawing.Font("Segoe UI", 9); $group1.Controls.Add($cboMode)

    $group1.Controls.Add((New-Lbl "Loai Log:" 370 28 70))
    $cboLogType = New-Object System.Windows.Forms.ComboBox
    $cboLogType.Location = New-Object System.Drawing.Point(445, 25); $cboLogType.Size = New-Object System.Drawing.Size(160, 22)
    $cboLogType.DropDownStyle = 'DropDownList'; $cboLogType.Items.AddRange(@('Application', 'Security', 'System', 'Setup')); $cboLogType.SelectedIndex = 0
    $cboLogType.Font = New-Object System.Drawing.Font("Segoe UI", 9); $group1.Controls.Add($cboLogType)

    $group1.Controls.Add((New-Lbl "Thu muc luu:" 15 60 100))
    $txtFolder = New-Txt $Config.Local.FolderLuuLog 120 58 570
    $group1.Controls.Add($txtFolder)
    $btnBrowse = New-Object System.Windows.Forms.Button; $btnBrowse.Text = '...'; $btnBrowse.Location = New-Object System.Drawing.Point(698, 57); $btnBrowse.Size = New-Object System.Drawing.Size(45, 24)
    $btnBrowse.Add_Click({ $fd = New-Object System.Windows.Forms.FolderBrowserDialog; $fd.SelectedPath = $txtFolder.Text; if ($fd.ShowDialog() -eq 'OK') { $txtFolder.Text = $fd.SelectedPath } })
    $group1.Controls.Add($btnBrowse)

    # ==================== GROUP 2: Limited ====================
    $group2 = New-Group "Cau hinh thu thap 1 khoang thoi gian (Limited)" 105
    $flow.Controls.Add($group2)

    $group2.Controls.Add((New-Lbl "Tu ngay:" 15 28 80))
    $dtpStart = New-Object System.Windows.Forms.DateTimePicker; $dtpStart.Location = New-Object System.Drawing.Point(100, 25); $dtpStart.Size = New-Object System.Drawing.Size(180, 22)
    $dtpStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom; $dtpStart.CustomFormat = "dd/MM/yyyy HH:mm:ss"; $dtpStart.Value = (Get-Date).AddDays(-1); $group2.Controls.Add($dtpStart)

    $group2.Controls.Add((New-Lbl "Den ngay:" 320 28 80))
    $dtpEnd = New-Object System.Windows.Forms.DateTimePicker; $dtpEnd.Location = New-Object System.Drawing.Point(405, 25); $dtpEnd.Size = New-Object System.Drawing.Size(180, 22)
    $dtpEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom; $dtpEnd.CustomFormat = "dd/MM/yyyy HH:mm:ss"; $dtpEnd.Value = (Get-Date); $group2.Controls.Add($dtpEnd)

    $lblNote2 = New-Lbl "⚠ Thoi gian bat dau phai nho hon thoi gian ket thuc" 15 62 500
    $lblNote2.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic); $lblNote2.ForeColor = [System.Drawing.Color]::DarkBlue; $group2.Controls.Add($lblNote2)

    # ==================== GROUP 3: Continuous ====================
    $group3 = New-Group "Cau hinh thu thap lien tuc (Continuous)" 105
    $flow.Controls.Add($group3)

    $group3.Controls.Add((New-Lbl "Tong thoi gian (phut):" 15 28 145))
    $numDuration = New-Object System.Windows.Forms.NumericUpDown; $numDuration.Location = New-Object System.Drawing.Point(165, 25); $numDuration.Size = New-Object System.Drawing.Size(100, 22); $numDuration.Minimum = 1; $numDuration.Maximum = 1440; $numDuration.Value = $Config.Collection.DefaultDurationMinutes; $group3.Controls.Add($numDuration)

    $chkForever = New-Object System.Windows.Forms.CheckBox; $chkForever.Text = 'Lien tuc khong gioi han'; $chkForever.Location = New-Object System.Drawing.Point(295, 27); $chkForever.Size = New-Object System.Drawing.Size(200, 20); $chkForever.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkForever.Add_Click({ $numDuration.Enabled = -not $chkForever.Checked }); $group3.Controls.Add($chkForever)

    $group3.Controls.Add((New-Lbl "Khoang cach (phut):" 15 62 140))
    $numInterval = New-Object System.Windows.Forms.NumericUpDown; $numInterval.Location = New-Object System.Drawing.Point(160, 60); $numInterval.Size = New-Object System.Drawing.Size(100, 22); $numInterval.Minimum = 1; $numInterval.Maximum = 1440; $numInterval.Value = $Config.Collection.DefaultIntervalMinutes; $group3.Controls.Add($numInterval)

    # ==================== GROUP 4: GUI Log ====================
    $group4 = New-Group "Cau hinh gui Log qua SFTP" 170
    $flow.Controls.Add($group4)

    $group4.Controls.Add((New-Lbl "Dia chi may chu:" 15 28 120))
    $txtHost = New-Txt $Config.Remote.Host 140 25 180; $group4.Controls.Add($txtHost)
    $group4.Controls.Add((New-Lbl "Username:" 370 28 80))
    $txtUser = New-Txt $Config.Remote.User 455 25 150; $group4.Controls.Add($txtUser)

    $group4.Controls.Add((New-Lbl "Duong dan tren server:" 15 62 150))
    $txtRemote = New-Txt $Config.Remote.RemotePath 170 60 545; $group4.Controls.Add($txtRemote)

    $group4.Controls.Add((New-Lbl "SSH Private Key:" 15 96 120))
    $txtKey = New-Txt $Config.Remote.SSHKeyPath 140 94 530; $group4.Controls.Add($txtKey)
    $btnKey = New-Object System.Windows.Forms.Button; $btnKey.Text = '...'; $btnKey.Location = New-Object System.Drawing.Point(678, 93); $btnKey.Size = New-Object System.Drawing.Size(45, 24)
    $btnKey.Add_Click({ $ofd = New-Object System.Windows.Forms.OpenFileDialog; if ($ofd.ShowDialog() -eq 'OK') { $txtKey.Text = $ofd.FileName } }); $group4.Controls.Add($btnKey)

    $btnTest = New-Object System.Windows.Forms.Button; $btnTest.Text = 'Kiem tra ket noi'; $btnTest.Location = New-Object System.Drawing.Point(140, 128); $btnTest.Size = New-Object System.Drawing.Size(150, 26); $btnTest.FlatStyle = 'Flat'
    $btnTest.Add_Click({
            $ok = KTKN -TenKN $txtHost.Text
            $msg = if ($ok) { "✅ Ket noi thanh cong den $($txtHost.Text)" } else { "❌ Khong the ket noi den $($txtHost.Text)" }
            $icon = if ($ok) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Error }
            [System.Windows.Forms.MessageBox]::Show($msg, "Ket qua", [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
        }); $group4.Controls.Add($btnTest)

    # ==================== GROUP 5: Progress ====================
    $group5 = New-Group "Trang thai" 70
    $flow.Controls.Add($group5)
    $progress = New-Object System.Windows.Forms.ProgressBar; $progress.Location = New-Object System.Drawing.Point(15, 28); $progress.Size = New-Object System.Drawing.Size(775, 28); $progress.Style = 'Continuous'
    $group5.Controls.Add($progress)

    # ==================== Buttons ====================
    $btnPanel = New-Object System.Windows.Forms.Panel; $btnPanel.Size = New-Object System.Drawing.Size(810, 55); $flow.Controls.Add($btnPanel)

    $btnStart = New-Object System.Windows.Forms.Button; $btnStart.Text = "▶  Bat dau thu thap"; $btnStart.Location = New-Object System.Drawing.Point(250, 7); $btnStart.Size = New-Object System.Drawing.Size(160, 40)
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215); $btnStart.ForeColor = [System.Drawing.Color]::White; $btnStart.FlatStyle = 'Flat'; $btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnPanel.Controls.Add($btnStart)

    $btnStop = New-Object System.Windows.Forms.Button; $btnStop.Text = "⏹  Dung thu thap"; $btnStop.Location = New-Object System.Drawing.Point(250, 7); $btnStop.Size = New-Object System.Drawing.Size(160, 40)
    $btnStop.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50); $btnStop.ForeColor = [System.Drawing.Color]::White; $btnStop.FlatStyle = 'Flat'; $btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold); $btnStop.Visible = $false
    $btnPanel.Controls.Add($btnStop)

    # ==================== GROUP 6: Console ====================
    $group6 = New-Group "Console Output" 160
    $flow.Controls.Add($group6)
    $richLog = New-Object System.Windows.Forms.RichTextBox; $richLog.Location = New-Object System.Drawing.Point(10, 22); $richLog.Size = New-Object System.Drawing.Size(788, 128)
    $richLog.Font = New-Object System.Drawing.Font("Consolas", 9); $richLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30); $richLog.ForeColor = [System.Drawing.Color]::White
    $richLog.ReadOnly = $true; $richLog.ScrollBars = 'Both'; $richLog.WordWrap = $false
    $group6.Controls.Add($richLog)
    $global:LogOutputControl = $richLog

    # ==================== Lappy initial state ====================
    $cboMode.Add_SelectedIndexChanged({
            $isLimited = ($cboMode.SelectedItem -eq 'Limited')
            $cboLogType.Enabled = $isLimited
            $dtpStart.Enabled = $isLimited
            $dtpEnd.Enabled = $isLimited
            $numDuration.Enabled = (-not $isLimited) -and (-not $chkForever.Checked)
            $chkForever.Enabled = -not $isLimited
            $numInterval.Enabled = -not $isLimited
        })
    # Apply initial state
    $cboMode.SelectedIndex = 0
    $numDuration.Enabled = $false; $chkForever.Enabled = $false; $numInterval.Enabled = $false

    $global:StopCollection = $false
    $global:ContinuousTimer = $null

    # ==================== Stop button ====================
    $btnStop.Add_Click({
            $global:StopCollection = $true
            if ($global:ContinuousTimer) { $global:ContinuousTimer.Stop() }
            AddLog "Dang dung qua trinh thu thap..." "WARNING"
            $progress.Style = 'Continuous'; $progress.MarqueeAnimationSpeed = 0; $progress.Value = 100
            $btnStop.Visible = $false; $btnStart.Visible = $true
        })

    # ==================== Start button ====================
    $btnStart.Add_Click({
            try {
                $richLog.Clear()
                AddLog "=== BAT DAU QUA TRINH THU THAP LOG ===" "INFO"

                $Mode = $cboMode.SelectedItem
                $LogName = $cboLogType.SelectedItem
                $StartTime = $dtpStart.Value
                $EndTime = $dtpEnd.Value
                $FolderBase = $txtFolder.Text
                $RemoteHost = $txtHost.Text
                $User = $txtUser.Text
                $RemotePath = $txtRemote.Text
                $SSHKey = $txtKey.Text
                $Channels = $Config.Collection.EventChannels
                $KhoangPhut = [int]$numInterval.Value

                AddLog "Che do: $Mode" "INFO"

                # Tao thu muc an
                $FolderLuuLog = Join-Path $FolderBase "HiddenLogs"
                if (-not (Test-Path $FolderLuuLog)) {
                    New-Item -Path $FolderLuuLog -ItemType Directory -Force | Out-Null
                    (Get-Item $FolderLuuLog).Attributes += 'Hidden'
                    AddLog "Da tao thu muc an: $FolderLuuLog" "SUCCESS"
                }
                $ThuMucGui = Join-Path $FolderLuuLog "Gui"
                $ThuMucChoGui = Join-Path $ThuMucGui $Mode
                @($ThuMucGui, $ThuMucChoGui) | ForEach-Object {
                    if (-not (Test-Path $_)) {
                        New-Item -Path $_ -ItemType Directory -Force | Out-Null
                        (Get-Item $_).Attributes += 'Hidden'
                    }
                }

                if ($Mode -eq "Limited") {
                    if ($StartTime -ge $EndTime) {
                        [System.Windows.Forms.MessageBox]::Show("Loi: Thoi gian bat dau phai nho hon thoi gian ket thuc", "Loi", 'OK', 'Error')
                        return
                    }
                    $progress.Value = 30
                    $TenLog = "${LogName}_$($StartTime.ToString('yyyy-MM-dd_HHmmss'))-$($EndTime.ToString('yyyy-MM-dd_HHmmss')).json"
                    $DuongDanLog = Join-Path $FolderLuuLog $TenLog
                    AddLog "Thu thap log $LogName tu $($StartTime.ToString('dd/MM/yyyy HH:mm:ss')) den $($EndTime.ToString('dd/MM/yyyy HH:mm:ss'))..." "INFO"
                    THUTHAPLOG -DuongDanLog $DuongDanLog -Mode $Mode -StartTime $StartTime -EndTime $EndTime -LogName $LogName -EventChannels $Channels -LogOutput $richLog
                    if (Test-Path $DuongDanLog) {
                        $progress.Value = 60
                        $ok = GUILOGSSH -DuongDanLog $DuongDanLog -RemoteHost $RemoteHost -User $User -DuongDanRemote $RemotePath -ThuMucChoGui $ThuMucChoGui -SSHFolders $SSHKey -Mode $Mode -LogOutput $richLog
                        $progress.Value = 80
                        $guiLai = GUILOGCHOGUI -ThuMucChoGui $ThuMucChoGui -RemoteHost $RemoteHost -User $User -DuongDanRemote $RemotePath -Mode $Mode -SSHFolders $SSHKey -LogOutput $richLog
                        $progress.Value = 100
                        $msg = if ($guiLai) { "Thu thap va gui log hoan thanh!" } else { "Hoan thanh! Mot so file cho chua gui duoc." }
                        $icon = if ($guiLai) { 'Information' } else { 'Warning' }
                        [System.Windows.Forms.MessageBox]::Show($msg, "Thong bao", 'OK', $icon)
                    }
                    else {
                        AddLog "Khong tim thay file log sau khi thu thap." "ERROR"
                    }
                }
                else {
                    # --- Continuous Mode ---
                    $btnStart.Visible = $false; $btnStop.Visible = $true
                    $global:StopCollection = $false
                    $IntervalMs = [math]::Max(5000, $KhoangPhut * 60 * 1000)
                    $global:RemainingCycles = if ($chkForever.Checked) { -1 } else { [math]::Max(1, [math]::Ceiling(([int]$numDuration.Value) / $KhoangPhut)) }
                    $global:DemGuiLai = 0
                    $global:LastLogtime = (Get-Date).AddMinutes(-$KhoangPhut)

                    AddLog "Bat dau Continuous mode: moi $KhoangPhut phut | Tong: $(if($global:RemainingCycles -eq -1){'Khong gioi han'} else {$global:RemainingCycles} ) lan" "INFO"
                    $progress.Style = 'Marquee'; $progress.MarqueeAnimationSpeed = 30

                    if ($global:ContinuousTimer) { $global:ContinuousTimer.Stop(); $global:ContinuousTimer.Dispose() }
                    $global:ContinuousTimer = New-Object System.Windows.Forms.Timer
                    $global:ContinuousTimer.Interval = $IntervalMs

                    $Script:DoStep = {
                        if ($global:StopCollection) { $global:ContinuousTimer.Stop(); return }
                        $global:DemGuiLai++
                        if ($global:DemGuiLai -ge 5) {
                            $global:DemGuiLai = 0
                            AddLog "Kiem tra gui lai thu muc cho..." "INFO"
                            GUILOGCHOGUI -ThuMucChoGui $ThuMucChoGui -RemoteHost $RemoteHost -User $User -DuongDanRemote $RemotePath -Mode $Mode -SSHFolders $SSHKey -LogOutput $richLog | Out-Null
                        }
                        $TGKT = Get-Date
                        $TenLog = "Continuous_$($global:LastLogtime.ToString('yyyy-MM-dd_HHmmss')).json"
                        $DuongDanLog = Join-Path $FolderLuuLog $TenLog
                        AddLog "Thu thap tu $($global:LastLogtime.ToString('HH:mm:ss')) den $($TGKT.ToString('HH:mm:ss'))" "INFO"
                        THUTHAPLOG -DuongDanLog $DuongDanLog -Mode $Mode -StartTime $global:LastLogtime -EndTime $TGKT -LogName "" -EventChannels $Channels -LogOutput $richLog
                        $global:LastLogtime = $TGKT.AddMilliseconds(1)
                        if (Test-Path $DuongDanLog) {
                            GUILOGSSH -DuongDanLog $DuongDanLog -RemoteHost $RemoteHost -User $User -DuongDanRemote $RemotePath -ThuMucChoGui $ThuMucChoGui -SSHFolders $SSHKey -Mode $Mode -LogOutput $richLog | Out-Null
                        }
                        else {
                            AddLog "Khong co log moi." "INFO"
                        }
                        if ($global:RemainingCycles -gt 0) {
                            $global:RemainingCycles--
                            if ($global:RemainingCycles -eq 0) {
                                $global:ContinuousTimer.Stop()
                                $progress.Style = 'Continuous'; $progress.Value = 100
                                $btnStop.Visible = $false; $btnStart.Visible = $true
                                AddLog "Da hoan thanh tat ca cac chu ky thu thap." "SUCCESS"
                                [System.Windows.Forms.MessageBox]::Show("Thu thap log lien tuc hoan thanh!", "Thong bao", 'OK', 'Information')
                                return
                            }
                            else {
                                AddLog "Con lai: $($global:RemainingCycles) lan" "INFO"
                            }
                        }
                    }
                    $global:ContinuousTimer.Add_Tick({ & $Script:DoStep })
                    & $Script:DoStep   # Chay lan dau tien ngay lap tuc
                    if (-not $global:StopCollection -and ($global:RemainingCycles -ne 0)) {
                        $global:ContinuousTimer.Start()
                    }
                }
            }
            catch {
                AddLog "❌ Loi: $_" "ERROR"
                $btnStop.Visible = $false; $btnStart.Visible = $true
            }
        })

    [void]$form.ShowDialog()
}
