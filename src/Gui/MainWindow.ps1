# =====================================================
# MainWindow.ps1 - Professional 6-Tab WinForms GUI Agent (v0.3.1)
# Fully interactive, UTF-8 clean, feature-rich control panel
# =====================================================

function Show-MainWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $Config = $Context.Config

    # ---- Helper: Save Config back to config.json & memory ----
    function Save-GuiConfig {
        param([hashtable]$NewConfig)
        $configPath = Join-Path $PSScriptRoot "..\..\config.json"
        if (-not (Test-Path $configPath)) { $configPath = "config.json" }

        try {
            $jsonStr = $NewConfig | ConvertTo-Json -Depth 10
            $jsonStr | Set-Content $configPath -Encoding UTF8 -Force
            AddLog "Đã lưu cấu hình mới vào file config.json" "SUCCESS"
            return $true
        }
        catch {
            AddLog "Lỗi khi lưu config.json: $_" "ERROR"
            return $false
        }
    }

    # ---- Register Logger Sink ----
    $script:LogBox = $null
    Initialize-Logger -DataDir $Context.DataDir -Sink {
        param($Message, $Type)
        if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
            $color = switch ($Type) {
                "ERROR" { [System.Drawing.Color]::FromArgb(255, 80, 80) }
                "WARNING" { [System.Drawing.Color]::FromArgb(255, 180, 50) }
                "SUCCESS" { [System.Drawing.Color]::FromArgb(40, 210, 120) }
                default { [System.Drawing.Color]::FromArgb(220, 220, 220) }
            }
            $entry = "[$(Get-Date -Format 'HH:mm:ss')] [$Type] $Message`r`n"
            if ($script:LogBox.InvokeRequired) {
                $script:LogBox.Invoke([Action] {
                        $script:LogBox.SelectionStart = $script:LogBox.TextLength
                        $script:LogBox.SelectionLength = 0
                        $script:LogBox.SelectionColor = $color
                        $script:LogBox.AppendText($entry)
                        $script:LogBox.ScrollToCaret()
                    })
            }
            else {
                $script:LogBox.SelectionStart = $script:LogBox.TextLength
                $script:LogBox.SelectionLength = 0
                $script:LogBox.SelectionColor = $color
                $script:LogBox.AppendText($entry)
                $script:LogBox.ScrollToCaret()
            }
        }
    }

    # ---- Form Initialization ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Windows Log Collector Agent v0.3.1 - B2203708"
    $form.Size = New-Object System.Drawing.Size(1150, 780)
    $form.MinimumSize = New-Object System.Drawing.Size(1050, 700)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    # Styles
    $fontHeader = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $fontSub = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $fontSection = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $fontBold = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $fontConsole = New-Object System.Drawing.Font("Consolas", 10)

    $bgCard = [System.Drawing.Color]::FromArgb(40, 40, 45)
    $bgInput = [System.Drawing.Color]::FromArgb(45, 45, 50)
    $accentBlue = [System.Drawing.Color]::FromArgb(0, 122, 204)
    $accentGreen = [System.Drawing.Color]::FromArgb(40, 167, 69)
    $accentRed = [System.Drawing.Color]::FromArgb(220, 53, 69)
    $accentOrange = [System.Drawing.Color]::FromArgb(255, 152, 0)
    $accentGray = [System.Drawing.Color]::FromArgb(70, 70, 85)
    $accentDark = [System.Drawing.Color]::FromArgb(70, 70, 90)

    # ---- Top Header Panel ----
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlHeader.Height = 60
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
    $form.Controls.Add($pnlHeader)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "WINDOWS LOG COLLECTOR AGENT"
    $lblTitle.Font = $fontHeader
    $lblTitle.ForeColor = $accentBlue
    $lblTitle.Location = New-Object System.Drawing.Point(15, 10)
    $lblTitle.AutoSize = $true
    $pnlHeader.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = "Máy: $env:COMPUTERNAME  |  Phiên bản: 0.3.1  |  Quyền: $(if(Test-IsAdmin){'Administrator'}else{'User'})"
    $lblSubtitle.Font = $fontSub
    $lblSubtitle.ForeColor = [System.Drawing.Color]::LightGray
    $lblSubtitle.Location = New-Object System.Drawing.Point(17, 36)
    $lblSubtitle.AutoSize = $true
    $pnlHeader.Controls.Add($lblSubtitle)

    # Status Badge (Top Right)
    $lblAgentBadge = New-Object System.Windows.Forms.Label
    $lblAgentBadge.Text = "● ĐANG SẴN SÀNG"
    $lblAgentBadge.Font = $fontBold
    $lblAgentBadge.ForeColor = [System.Drawing.Color]::LimeGreen
    $lblAgentBadge.Location = New-Object System.Drawing.Point(920, 18)
    $lblAgentBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $lblAgentBadge.AutoSize = $true
    $pnlHeader.Controls.Add($lblAgentBadge)

    # ---- Bottom Console Panel ----
    $pnlConsole = New-Object System.Windows.Forms.Panel
    $pnlConsole.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $pnlConsole.Height = 220
    $pnlConsole.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 22)
    $form.Controls.Add($pnlConsole)

    $pnlConsoleBar = New-Object System.Windows.Forms.Panel
    $pnlConsoleBar.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlConsoleBar.Height = 30
    $pnlConsoleBar.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
    $pnlConsole.Controls.Add($pnlConsoleBar)

    $lblConsoleTitle = New-Object System.Windows.Forms.Label
    $lblConsoleTitle.Text = "NHẬT KÝ TIẾN TRÌNH (PROCESS LOG)"
    $lblConsoleTitle.Font = $fontBold
    $lblConsoleTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $lblConsoleTitle.Location = New-Object System.Drawing.Point(10, 5)
    $lblConsoleTitle.AutoSize = $true
    $pnlConsoleBar.Controls.Add($lblConsoleTitle)

    $btnClearLog = New-Object System.Windows.Forms.Button
    $btnClearLog.Text = "Xóa Log"
    $btnClearLog.Size = New-Object System.Drawing.Size(75, 24)
    $btnClearLog.Location = New-Object System.Drawing.Point(960, 3)
    $btnClearLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClearLog.FlatStyle = "Flat"
    $btnClearLog.BackColor = $bgCard
    $btnClearLog.ForeColor = [System.Drawing.Color]::White
    $pnlConsoleBar.Controls.Add($btnClearLog)

    $btnOpenDataDir = New-Object System.Windows.Forms.Button
    $btnOpenDataDir.Text = "Mở Thư Mục Data"
    $btnOpenDataDir.Size = New-Object System.Drawing.Size(120, 24)
    $btnOpenDataDir.Location = New-Object System.Drawing.Point(830, 3)
    $btnOpenDataDir.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnOpenDataDir.FlatStyle = "Flat"
    $btnOpenDataDir.BackColor = $bgCard
    $btnOpenDataDir.ForeColor = [System.Drawing.Color]::White
    $pnlConsoleBar.Controls.Add($btnOpenDataDir)

    $script:LogBox = New-Object System.Windows.Forms.RichTextBox
    $script:LogBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:LogBox.Font = $fontConsole
    $script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 18)
    $script:LogBox.ForeColor = [System.Drawing.Color]::White
    $script:LogBox.ReadOnly = $true
    $script:LogBox.BorderStyle = "None"
    $pnlConsole.Controls.Add($script:LogBox)
    $script:LogBox.BringToFront()

    # ---- Main TabControl (Center) ----
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tabControl.Font = $fontBold
    $form.Controls.Add($tabControl)
    $tabControl.BringToFront()

    # Create 6 Tabs
    $tabDashboard = New-Object System.Windows.Forms.TabPage "  📊 Tổng quan  "
    $tabCollection = New-Object System.Windows.Forms.TabPage "  📥 Thu thập log  "
    $tabAutomation = New-Object System.Windows.Forms.TabPage "  ⚡ Tự động (Timer)  "
    $tabSftp = New-Object System.Windows.Forms.TabPage "  🌐 Cấu hình SFTP  "
    $tabQueue = New-Object System.Windows.Forms.TabPage "  📦 Hàng chờ (Queue)  "
    $tabPreflight = New-Object System.Windows.Forms.TabPage "  🔍 Preflight Check  "

    @($tabDashboard, $tabCollection, $tabAutomation, $tabSftp, $tabQueue, $tabPreflight) | ForEach-Object {
        $_.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
        $tabControl.TabPages.Add($_)
    }

    # =====================================================
    # TAB 1: TỔNG QUAN (DASHBOARD)
    # =====================================================
    $pnlDashStats = New-Object System.Windows.Forms.TableLayoutPanel
    $pnlDashStats.Location = New-Object System.Drawing.Point(15, 15)
    $pnlDashStats.Size = New-Object System.Drawing.Size(1100, 110)
    $pnlDashStats.ColumnCount = 4
    $pnlDashStats.RowCount = 1
    $pnlDashStats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
    $pnlDashStats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
    $pnlDashStats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
    $pnlDashStats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
    $tabDashboard.Controls.Add($pnlDashStats)

    # Function create Stat Card
    function New-StatCard {
        param($Title, $Value, $Subtext, $Color)
        $box = New-Object System.Windows.Forms.GroupBox
        $box.Dock = [System.Windows.Forms.DockStyle]::Fill
        $box.BackColor = $bgCard
        $box.ForeColor = [System.Drawing.Color]::LightGray
        $box.Margin = New-Object System.Windows.Forms.Padding(5)

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = $Title
        $lblTitle.Font = $fontSub
        $lblTitle.ForeColor = [System.Drawing.Color]::LightGray
        $lblTitle.Location = New-Object System.Drawing.Point(10, 15)
        $lblTitle.AutoSize = $true
        $box.Controls.Add($lblTitle)

        $lblVal = New-Object System.Windows.Forms.Label
        $lblVal.Text = $Value
        $lblVal.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
        $lblVal.ForeColor = $Color
        $lblVal.Location = New-Object System.Drawing.Point(10, 35)
        $lblVal.AutoSize = $true
        $box.Controls.Add($lblVal)

        $lblSub = New-Object System.Windows.Forms.Label
        $lblSub.Text = $Subtext
        $lblSub.Font = $fontSub
        $lblSub.ForeColor = [System.Drawing.Color]::Gray
        $lblSub.Location = New-Object System.Drawing.Point(10, 75)
        $lblSub.AutoSize = $true
        $box.Controls.Add($lblSub)

        return @{ Box = $box; ValLabel = $lblVal; SubLabel = $lblSub }
    }

    $accentCyan = [System.Drawing.Color]::Cyan
    $card1 = New-StatCard -Title "EVENT ĐÃ THU THẬP" -Value "0" -Subtext "Trong chu kỳ này" -Color $accentBlue
    $card2 = New-StatCard -Title "FILE TỒN TRONG QUEUE" -Value "0 File" -Subtext "Dung lượng: 0 MB" -Color $accentOrange
    $card3 = New-StatCard -Title "SFTP SERVER" -Value "CHƯA THỬ" -Subtext "$($Config.Remote.Host):$($Config.Remote.Port)" -Color $accentCyan
    $card4 = New-StatCard -Title "KÊNH THẤT BẠI" -Value "0 Channel" -Subtext "Trạng thái: Tốt" -Color $accentGreen

    $pnlDashStats.Controls.Add($card1.Box, 0, 0)
    $pnlDashStats.Controls.Add($card2.Box, 1, 0)
    $pnlDashStats.Controls.Add($card3.Box, 2, 0)
    $pnlDashStats.Controls.Add($card4.Box, 3, 0)

    # Overview Info GroupBox
    $grpDashInfo = New-Object System.Windows.Forms.GroupBox
    $grpDashInfo.Text = " THÔNG TIN VẬN HÀNH "
    $grpDashInfo.Location = New-Object System.Drawing.Point(20, 135)
    $grpDashInfo.Size = New-Object System.Drawing.Size(1090, 140)
    $grpDashInfo.ForeColor = [System.Drawing.Color]::LightGray
    $tabDashboard.Controls.Add($grpDashInfo)

    $lblInfoServer = New-Object System.Windows.Forms.Label
    $lblInfoServer.Text = "Máy chủ SFTP từ xa: $($Config.Remote.User)@$($Config.Remote.Host):$($Config.Remote.Port)"
    $lblInfoServer.Location = New-Object System.Drawing.Point(20, 25)
    $lblInfoServer.AutoSize = $true
    $grpDashInfo.Controls.Add($lblInfoServer)

    $lblInfoChannels = New-Object System.Windows.Forms.Label
    $channelsText = ($Config.Collection.Subscriptions | ForEach-Object { $_.Channel }) -join ", "
    $lblInfoChannels.Text = "Danh sách Channels: $channelsText"
    $lblInfoChannels.Location = New-Object System.Drawing.Point(20, 52)
    $lblInfoChannels.AutoSize = $true
    $grpDashInfo.Controls.Add($lblInfoChannels)

    $lblInfoTimer = New-Object System.Windows.Forms.Label
    $lblInfoTimer.Text = "Chu kỳ chạy tự động: Mỗi $($Config.Collection.DefaultIntervalMinutes) phút  |  Lần chạy kế tiếp: Chưa bật"
    $lblInfoTimer.Location = New-Object System.Drawing.Point(20, 80)
    $lblInfoTimer.AutoSize = $true
    $grpDashInfo.Controls.Add($lblInfoTimer)

    $lblInfoDataDir = New-Object System.Windows.Forms.Label
    $lblInfoDataDir.Text = "Thư mục lưu dữ liệu DataDir: $($Context.DataDir)"
    $lblInfoDataDir.Location = New-Object System.Drawing.Point(20, 107)
    $lblInfoDataDir.AutoSize = $true
    $grpDashInfo.Controls.Add($lblInfoDataDir)

    # Action Buttons Panel (Dashboard)
    $pnlDashActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlDashActions.Location = New-Object System.Drawing.Point(20, 285)
    $pnlDashActions.Size = New-Object System.Drawing.Size(1090, 60)
    $tabDashboard.Controls.Add($pnlDashActions)

    function New-ActionButton {
        param($Text, $Color, $Width = 180)
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.Font = $fontBold
        $btn.BackColor = $Color
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.FlatStyle = "Flat"
        $btn.Size = New-Object System.Drawing.Size($Width, 42)
        $btn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 15, 0)
        return $btn
    }

    $btnDashRunOnce = New-ActionButton -Text "[►] Thu Thập Ngay" -Color $accentBlue -Width 190
    $btnDashStartAuto = New-ActionButton -Text "[⚡] Bắt Đầu Tự Động" -Color $accentGreen -Width 200
    $btnDashStopAuto = New-ActionButton -Text "[⏹] Dừng Tự Động" -Color $accentRed -Width 180
    $btnDashStopAuto.Enabled = $false
    $btnDashPreflight = New-ActionButton -Text "[🔍] Kiểm Tra Preflight" -Color $accentGray -Width 200

    $pnlDashActions.Controls.Add($btnDashRunOnce)
    $pnlDashActions.Controls.Add($btnDashStartAuto)
    $pnlDashActions.Controls.Add($btnDashStopAuto)
    $pnlDashActions.Controls.Add($btnDashPreflight)

    # =====================================================
    # TAB 2: THU THẬP LOG (COLLECTION SETTINGS)
    # =====================================================
    $grpCollMode = New-Object System.Windows.Forms.GroupBox
    $grpCollMode.Text = " Chế Độ & Phạm Vi Thu Thập "
    $grpCollMode.Location = New-Object System.Drawing.Point(20, 15)
    $grpCollMode.Size = New-Object System.Drawing.Size(1090, 115)
    $grpCollMode.ForeColor = [System.Drawing.Color]::LightGray
    $tabCollection.Controls.Add($grpCollMode)

    $rbModeCheckpoint = New-Object System.Windows.Forms.RadioButton
    $rbModeCheckpoint.Text = "Theo Checkpoint tự động (RecordID Incremental - Khuyên dùng)"
    $rbModeCheckpoint.Checked = $true
    $rbModeCheckpoint.Location = New-Object System.Drawing.Point(20, 22)
    $rbModeCheckpoint.AutoSize = $true
    $grpCollMode.Controls.Add($rbModeCheckpoint)

    $rbModeLookback = New-Object System.Windows.Forms.RadioButton
    $rbModeLookback.Text = "Theo N phút gần nhất (Lookback):"
    $rbModeLookback.Location = New-Object System.Drawing.Point(20, 50)
    $rbModeLookback.AutoSize = $true
    $grpCollMode.Controls.Add($rbModeLookback)

    $numLookbackMin = New-Object System.Windows.Forms.NumericUpDown
    $numLookbackMin.Minimum = 1
    $numLookbackMin.Maximum = 10080
    $numLookbackMin.Value = $Config.Collection.DefaultIntervalMinutes
    $numLookbackMin.Location = New-Object System.Drawing.Point(285, 48)
    $numLookbackMin.Size = New-Object System.Drawing.Size(70, 25)
    $numLookbackMin.BackColor = $bgInput
    $numLookbackMin.ForeColor = [System.Drawing.Color]::White
    $grpCollMode.Controls.Add($numLookbackMin)

    $lblLookbackUnit = New-Object System.Windows.Forms.Label
    $lblLookbackUnit.Text = "phút"
    $lblLookbackUnit.Location = New-Object System.Drawing.Point(362, 50)
    $lblLookbackUnit.AutoSize = $true
    $grpCollMode.Controls.Add($lblLookbackUnit)

    # Che do Date Range custom (Tu ngay -> Den ngay)
    $rbModeCustomRange = New-Object System.Windows.Forms.RadioButton
    $rbModeCustomRange.Text = "Khoảng thời gian chọn lọc:"
    $rbModeCustomRange.Location = New-Object System.Drawing.Point(20, 78)
    $rbModeCustomRange.AutoSize = $true
    $grpCollMode.Controls.Add($rbModeCustomRange)

    $lblFromDate = New-Object System.Windows.Forms.Label
    $lblFromDate.Text = "Từ:"
    $lblFromDate.Location = New-Object System.Drawing.Point(240, 80)
    $lblFromDate.AutoSize = $true
    $grpCollMode.Controls.Add($lblFromDate)

    $dtpFromDate = New-Object System.Windows.Forms.DateTimePicker
    $dtpFromDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtpFromDate.CustomFormat = "yyyy-MM-dd HH:mm"
    $dtpFromDate.Value = (Get-Date).AddDays(-1)
    $dtpFromDate.Location = New-Object System.Drawing.Point(270, 76)
    $dtpFromDate.Size = New-Object System.Drawing.Size(150, 25)
    $grpCollMode.Controls.Add($dtpFromDate)

    $lblToDate = New-Object System.Windows.Forms.Label
    $lblToDate.Text = "Đến:"
    $lblToDate.Location = New-Object System.Drawing.Point(435, 80)
    $lblToDate.AutoSize = $true
    $grpCollMode.Controls.Add($lblToDate)

    $dtpToDate = New-Object System.Windows.Forms.DateTimePicker
    $dtpToDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtpToDate.CustomFormat = "yyyy-MM-dd HH:mm"
    $dtpToDate.Value = Get-Date
    $dtpToDate.Location = New-Object System.Drawing.Point(475, 76)
    $dtpToDate.Size = New-Object System.Drawing.Size(150, 25)
    $grpCollMode.Controls.Add($dtpToDate)

    # Subscriptions DataGridView
    $grpSubs = New-Object System.Windows.Forms.GroupBox
    $grpSubs.Text = " Danh Sách Event Log Subscriptions "
    $grpSubs.Location = New-Object System.Drawing.Point(20, 140)
    $grpSubs.Size = New-Object System.Drawing.Size(1090, 180)
    $grpSubs.ForeColor = [System.Drawing.Color]::LightGray
    $tabCollection.Controls.Add($grpSubs)

    $gridSubs = New-Object System.Windows.Forms.DataGridView
    $gridSubs.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridSubs.BackgroundColor = [System.Drawing.Color]::FromArgb(35, 35, 38)
    $gridSubs.ForeColor = [System.Drawing.Color]::Black
    $gridSubs.AutoSizeColumnsMode = "Fill"
    $gridSubs.AllowUserToAddRows = $true
    $grpSubs.Controls.Add($gridSubs)

    # Setup Grid Columns
    $colSubEnabled = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colSubEnabled.HeaderText = "Kích Hoạt"
    $colSubEnabled.Width = 80

    $colSubChan = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colSubChan.HeaderText = "Event Log Channel"

    $colSubIDs = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colSubIDs.HeaderText = "Event IDs (Cách nhau bởi dấu phẩy, để trống = Tất cả)"

    $gridSubs.Columns.Add($colSubEnabled) | Out-Null
    $gridSubs.Columns.Add($colSubChan) | Out-Null
    $gridSubs.Columns.Add($colSubIDs) | Out-Null

    # Populate Subscriptions Grid
    function Refresh-SubscriptionsGrid {
        $gridSubs.Rows.Clear()
        foreach ($sub in $Config.Collection.Subscriptions) {
            $idsStr = if ($sub.EventIDs) { ($sub.EventIDs -join ", ") } else { "" }
            $gridSubs.Rows.Add($true, $sub.Channel, $idsStr) | Out-Null
        }
    }
    Refresh-SubscriptionsGrid

    # Save Subscriptions Button
    $btnSaveSubs = New-ActionButton -Text "[💾] Lưu Cấu Hình Subscriptions" -Color $accentBlue -Width 260
    $btnSaveSubs.Location = New-Object System.Drawing.Point(20, 330)
    $tabCollection.Controls.Add($btnSaveSubs)

    $btnSaveSubs.Add_Click({
            $newSubs = @()
            foreach ($row in $gridSubs.Rows) {
                if ($row.IsNewRow) { continue }
                $enabled = [bool]$row.Cells[0].Value
                $chan = [string]$row.Cells[1].Value
                $idsText = [string]$row.Cells[2].Value

                if ($enabled -and -not [string]::IsNullOrWhiteSpace($chan)) {
                    $idList = @()
                    if (-not [string]::IsNullOrWhiteSpace($idsText)) {
                        $idList = @(($idsText -split ',') | ForEach-Object { [int]($_.Trim()) } | Where-Object { $_ -gt 0 })
                    }
                    $newSubs += @{ Channel = $chan.Trim(); EventIDs = $idList }
                }
            }
            $Config.Collection.Subscriptions = $newSubs
            Save-GuiConfig -NewConfig $Config
            $lblInfoChannels.Text = "Danh sách Channels: " + (($Config.Collection.Subscriptions | ForEach-Object { $_.Channel }) -join ", ")
        })

    # =====================================================
    # TAB 3: TỰ ĐỘNG (AUTOMATION / TIMER)
    # =====================================================
    $grpAutoSettings = New-Object System.Windows.Forms.GroupBox
    $grpAutoSettings.Text = " Cấu Hình Lịch Chạy Tự Động (Continuous Mode) "
    $grpAutoSettings.Location = New-Object System.Drawing.Point(20, 15)
    $grpAutoSettings.Size = New-Object System.Drawing.Size(1090, 160)
    $grpAutoSettings.ForeColor = [System.Drawing.Color]::LightGray
    $tabAutomation.Controls.Add($grpAutoSettings)

    $lblTimerInterval = New-Object System.Windows.Forms.Label
    $lblTimerInterval.Text = "Chu kỳ lặp lại thu thập (Interval):"
    $lblTimerInterval.Location = New-Object System.Drawing.Point(20, 30)
    $lblTimerInterval.AutoSize = $true
    $grpAutoSettings.Controls.Add($lblTimerInterval)

    $numTimerMin = New-Object System.Windows.Forms.NumericUpDown
    $numTimerMin.Minimum = 1
    $numTimerMin.Maximum = 1440
    $numTimerMin.Value = $Config.Collection.DefaultIntervalMinutes
    $numTimerMin.Location = New-Object System.Drawing.Point(260, 28)
    $numTimerMin.Size = New-Object System.Drawing.Size(80, 25)
    $numTimerMin.BackColor = $bgInput
    $numTimerMin.ForeColor = [System.Drawing.Color]::White
    $grpAutoSettings.Controls.Add($numTimerMin)

    $lblTimerMinUnit = New-Object System.Windows.Forms.Label
    $lblTimerMinUnit.Text = "phút (Mặc định: 3 phút)"
    $lblTimerMinUnit.Location = New-Object System.Drawing.Point(348, 30)
    $lblTimerMinUnit.AutoSize = $true
    $grpAutoSettings.Controls.Add($lblTimerMinUnit)

    $chkAutoStart = New-Object System.Windows.Forms.CheckBox
    $chkAutoStart.Text = "Tự động kích hoạt Timer ngay khi mở ứng dụng"
    $chkAutoStart.Location = New-Object System.Drawing.Point(20, 68)
    $chkAutoStart.AutoSize = $true
    $grpAutoSettings.Controls.Add($chkAutoStart)

    $chkRetryBefore = New-Object System.Windows.Forms.CheckBox
    $chkRetryBefore.Text = "Tự động Retry hàng chờ Queue trước mỗi chu kỳ thu thập"
    $chkRetryBefore.Checked = $true
    $chkRetryBefore.Location = New-Object System.Drawing.Point(20, 100)
    $chkRetryBefore.AutoSize = $true
    $grpAutoSettings.Controls.Add($chkRetryBefore)

    # Live Timer Status Card
    $grpTimerStatus = New-Object System.Windows.Forms.GroupBox
    $grpTimerStatus.Text = " Trạng Thái Timer Đang Chạy "
    $grpTimerStatus.Location = New-Object System.Drawing.Point(20, 185)
    $grpTimerStatus.Size = New-Object System.Drawing.Size(1090, 120)
    $grpTimerStatus.ForeColor = [System.Drawing.Color]::LightGray
    $tabAutomation.Controls.Add($grpTimerStatus)

    $lblLiveTimerState = New-Object System.Windows.Forms.Label
    $lblLiveTimerState.Text = "Trạng Thái: ĐÃ DỪNG"
    $lblLiveTimerState.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblLiveTimerState.ForeColor = [System.Drawing.Color]::LightGray
    $lblLiveTimerState.Location = New-Object System.Drawing.Point(20, 30)
    $lblLiveTimerState.AutoSize = $true
    $grpTimerStatus.Controls.Add($lblLiveTimerState)

    $lblLiveNextRun = New-Object System.Windows.Forms.Label
    $lblLiveNextRun.Text = "Lần chạy tiếp theo: N/A"
    $lblLiveNextRun.Location = New-Object System.Drawing.Point(20, 70)
    $lblLiveNextRun.AutoSize = $true
    $grpTimerStatus.Controls.Add($lblLiveNextRun)

    # Action Buttons (Automation)
    $btnAutoStart = New-ActionButton -Text "[⚡] Bắt Đầu Timer" -Color $accentGreen -Width 200
    $btnAutoStart.Location = New-Object System.Drawing.Point(20, 315)
    $tabAutomation.Controls.Add($btnAutoStart)

    $btnAutoStop = New-ActionButton -Text "[⏹] Dừng Timer" -Color $accentRed -Width 180
    $btnAutoStop.Location = New-Object System.Drawing.Point(235, 315)
    $btnAutoStop.Enabled = $false
    $tabAutomation.Controls.Add($btnAutoStop)

    # =====================================================
    # TAB 4: CẤU HÌNH SFTP (SFTP CONFIGURATION)
    # =====================================================
    $grpSftp = New-Object System.Windows.Forms.GroupBox
    $grpSftp.Text = " Thống Số Kết Nối SFTP Server "
    $grpSftp.Location = New-Object System.Drawing.Point(20, 15)
    $grpSftp.Size = New-Object System.Drawing.Size(1090, 240)
    $grpSftp.ForeColor = [System.Drawing.Color]::LightGray
    $tabSftp.Controls.Add($grpSftp)

    function Add-SftpField {
        param($Parent, $Label, $Value, $Top, $IsFile = $false)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Label
        $lbl.Location = New-Object System.Drawing.Point(20, $Top)
        $lbl.AutoSize = $true
        $Parent.Controls.Add($lbl)

        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Text = $Value
        $txt.Location = New-Object System.Drawing.Point(180, ($Top - 3))
        $txtWidth = if ($IsFile) { 750 } else { 350 }
        $txt.Size = New-Object System.Drawing.Size($txtWidth, 25)
        $txt.BackColor = $bgInput
        $txt.ForeColor = [System.Drawing.Color]::White
        $Parent.Controls.Add($txt)

        if ($IsFile) {
            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "..."
            $btnBrowse.Location = New-Object System.Drawing.Point(938, ($Top - 4))
            $btnBrowse.Size = New-Object System.Drawing.Size(40, 27)
            $btnBrowse.FlatStyle = "Flat"
            $btnBrowse.BackColor = $bgCard
            $btnBrowse.ForeColor = [System.Drawing.Color]::White
            $Parent.Controls.Add($btnBrowse)

            $btnBrowse.Add_Click({
                    $dlg = New-Object System.Windows.Forms.OpenFileDialog
                    if ($dlg.ShowDialog() -eq "OK") { $txt.Text = $dlg.FileName }
                })
        }
        return $txt
    }

    $txtSftpHost = Add-SftpField -Parent $grpSftp -Label "SFTP Host IP:" -Value $Config.Remote.Host -Top 30
    $txtSftpPort = Add-SftpField -Parent $grpSftp -Label "Port:" -Value $Config.Remote.Port -Top 65
    $txtSftpUser = Add-SftpField -Parent $grpSftp -Label "Username:" -Value $Config.Remote.User -Top 100
    $txtSftpRemote = Add-SftpField -Parent $grpSftp -Label "Remote Base Path:" -Value $Config.Remote.RemotePath -Top 135
    $txtSftpKey = Add-SftpField -Parent $grpSftp -Label "SSH Key Path:" -Value $Config.Remote.SSHKeyPath -Top 170 -IsFile $true
    $txtSftpKnown = Add-SftpField -Parent $grpSftp -Label "Known Hosts Path:" -Value $Config.Remote.KnownHostsPath -Top 205 -IsFile $true

    # Action Buttons (SFTP)
    $pnlSftpActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlSftpActions.Location = New-Object System.Drawing.Point(20, 265)
    $pnlSftpActions.Size = New-Object System.Drawing.Size(1090, 60)
    $tabSftp.Controls.Add($pnlSftpActions)

    $btnSftpTestTcp = New-ActionButton -Text "[🔌] Kiểm Tra TCP Port" -Color $accentBlue -Width 210
    $btnSftpTestAuth = New-ActionButton -Text "[🔑] Thử Đăng Nhập SFTP" -Color $accentDark -Width 220
    $btnSftpSave = New-ActionButton -Text "[💾] Lưu Cấu Hình SFTP" -Color $accentGreen -Width 220

    $pnlSftpActions.Controls.Add($btnSftpTestTcp)
    $pnlSftpActions.Controls.Add($btnSftpTestAuth)
    $pnlSftpActions.Controls.Add($btnSftpSave)

    $btnSftpTestTcp.Add_Click({
            AddLog "Kiểm tra kết nối TCP tới $($txtSftpHost.Text):$($txtSftpPort.Text)..." "INFO"
            $ok = Test-NetConnection -ComputerName $txtSftpHost.Text -Port ([int]$txtSftpPort.Text) -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($ok) {
                AddLog "✅ [TCP OK]: Cổng $($txtSftpPort.Text) của server $($txtSftpHost.Text) đang mở!" "SUCCESS"
                $card3.ValLabel.Text = "ONLINE"
                $card3.ValLabel.ForeColor = [System.Drawing.Color]::LimeGreen
            }
            else {
                AddLog "❌ [TCP FAIL]: Không thể kết nối tới cổng $($txtSftpPort.Text) của $($txtSftpHost.Text)" "ERROR"
                $card3.ValLabel.Text = "OFFLINE"
                $card3.ValLabel.ForeColor = $accentRed
            }
        })

    $btnSftpSave.Add_Click({
            $Config.Remote.Host = $txtSftpHost.Text.Trim()
            $Config.Remote.Port = [int]$txtSftpPort.Text.Trim()
            $Config.Remote.User = $txtSftpUser.Text.Trim()
            $Config.Remote.RemotePath = $txtSftpRemote.Text.Trim()
            $Config.Remote.SSHKeyPath = $txtSftpKey.Text.Trim()
            $Config.Remote.KnownHostsPath = $txtSftpKnown.Text.Trim()

            if (Save-GuiConfig -NewConfig $Config) {
                $lblInfoServer.Text = "Máy chủ SFTP từ xa: $($Config.Remote.User)@$($Config.Remote.Host):$($Config.Remote.Port)"
                $card3.SubLabel.Text = "$($Config.Remote.Host):$($Config.Remote.Port)"
            }
        })

    # =====================================================
    # TAB 5: HÀNG CHỜ QUEUE & QUARANTINE
    # =====================================================
    $grpQueueGrid = New-Object System.Windows.Forms.GroupBox
    $grpQueueGrid.Text = " Danh Sách Archive Đang Lưu Trong Queue (" + $Context.QueueDir + ") "
    $grpQueueGrid.Location = New-Object System.Drawing.Point(20, 15)
    $grpQueueGrid.Size = New-Object System.Drawing.Size(1090, 240)
    $grpQueueGrid.ForeColor = [System.Drawing.Color]::LightGray
    $tabQueue.Controls.Add($grpQueueGrid)

    $gridQueue = New-Object System.Windows.Forms.DataGridView
    $gridQueue.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridQueue.BackgroundColor = [System.Drawing.Color]::FromArgb(35, 35, 38)
    $gridQueue.ForeColor = [System.Drawing.Color]::Black
    $gridQueue.AutoSizeColumnsMode = "Fill"
    $gridQueue.ReadOnly = $true
    $grpQueueGrid.Controls.Add($gridQueue)

    $gridQueue.Columns.Add("FileName", "Tên File Archive (.zip)") | Out-Null
    $gridQueue.Columns.Add("SizeMB", "Kích Thước (MB)") | Out-Null
    $gridQueue.Columns.Add("Attempt", "Số Lần Thử") | Out-Null
    $gridQueue.Columns.Add("CreatedUtc", "Thời Gian Tạo (UTC)") | Out-Null
    $gridQueue.Columns.Add("NextRetry", "Lần Thử Kế Tiếp") | Out-Null

    function Refresh-QueueGrid {
        $gridQueue.Rows.Clear()
        if (Test-Path $Context.QueueDir) {
            $zips = Get-ChildItem $Context.QueueDir -Filter "*.zip" -ErrorAction SilentlyContinue
            $totalMB = 0
            foreach ($z in $zips) {
                $mb = [math]::Round($z.Length / 1MB, 2)
                $totalMB += $mb
                $sidecar = [IO.Path]::ChangeExtension($z.FullName, ".queue.json")
                $meta = if (Test-Path $sidecar) { try { Get-Content $sidecar -Raw | ConvertFrom-Json } catch { $null } } else { $null }

                $attempt = if ($meta -and $meta.attempt) { $meta.attempt } else { 0 }
                $created = if ($meta -and $meta.createdUtc) { $meta.createdUtc } else { $z.CreationTimeUtc.ToString("HH:mm:ss") }
                $next = if ($meta -and $meta.nextAttemptUtc) { $meta.nextAttemptUtc } else { "Ngay lập tức" }

                $gridQueue.Rows.Add($z.Name, "$mb MB", $attempt, $created, $next) | Out-Null
            }
            $card2.ValLabel.Text = "$($zips.Count) File"
            $card2.SubLabel.Text = "Dung lượng: $totalMB MB"
        }
    }
    Refresh-QueueGrid

    # Action Buttons (Queue)
    $pnlQueueActions = New-Object System.Windows.Forms.FlowLayoutPanel
    $pnlQueueActions.Location = New-Object System.Drawing.Point(20, 265)
    $pnlQueueActions.Size = New-Object System.Drawing.Size(1090, 60)
    $tabQueue.Controls.Add($pnlQueueActions)

    $btnQueueRetry = New-ActionButton -Text "[🔄] Retry Tất Cả Ngay" -Color $accentBlue -Width 220
    $btnQueueRefresh = New-ActionButton -Text "[🔃] Làm Mới Danh Sách" -Color $accentDark -Width 210
    $btnQueueOpenDir = New-ActionButton -Text "[📁] Mở Thư Mục Queue" -Color $accentDark -Width 220

    $pnlQueueActions.Controls.Add($btnQueueRetry)
    $pnlQueueActions.Controls.Add($btnQueueRefresh)
    $pnlQueueActions.Controls.Add($btnQueueOpenDir)

    $btnQueueRefresh.Add_Click({ Refresh-QueueGrid })
    $btnQueueOpenDir.Add_Click({ Invoke-Item $Context.QueueDir })
    $btnQueueRetry.Add_Click({
            AddLog "Bắt đầu Retry hàng chờ Queue thủ công..." "INFO"
            $res = Retry-WinLogQueue `
                -QueueDir $Context.QueueDir -QuarantineDir $Context.QuarantineDir `
                -RemoteHost $Config.Remote.Host -User $Config.Remote.User `
                -RemoteBasePath $Config.Remote.RemotePath -SSHKeyPath $Config.Remote.SSHKeyPath `
                -KnownHostsPath $Config.Remote.KnownHostsPath -Port $Config.Remote.Port `
                -MaxSizeMB $Config.Queue.MaxSizeMB -MaxAttempts $Config.Queue.MaxAttempts -MaxAgeDays $Config.Queue.MaxAgeDays
            Refresh-QueueGrid
        })

    # =====================================================
    # TAB 6: PREFLIGHT CHECK
    # =====================================================
    $grpPreGrid = New-Object System.Windows.Forms.GroupBox
    $grpPreGrid.Text = " Kết Quả Kiểm Tra Tiền Điều Kiện (Preflight Checks) "
    $grpPreGrid.Location = New-Object System.Drawing.Point(20, 15)
    $grpPreGrid.Size = New-Object System.Drawing.Size(1090, 240)
    $grpPreGrid.ForeColor = [System.Drawing.Color]::LightGray
    $tabPreflight.Controls.Add($grpPreGrid)

    $gridPreflight = New-Object System.Windows.Forms.DataGridView
    $gridPreflight.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridPreflight.BackgroundColor = [System.Drawing.Color]::FromArgb(35, 35, 38)
    $gridPreflight.ForeColor = [System.Drawing.Color]::Black
    $gridPreflight.AutoSizeColumnsMode = "Fill"
    $gridPreflight.ReadOnly = $true
    $grpPreGrid.Controls.Add($gridPreflight)

    $gridPreflight.Columns.Add("CheckItem", "Hạng Mục Kiểm Tra") | Out-Null
    $gridPreflight.Columns.Add("Status", "Trạng Thái") | Out-Null
    $gridPreflight.Columns.Add("Details", "Chi Tiết") | Out-Null

    function Run-PreflightGui {
        $gridPreflight.Rows.Clear()
        AddLog "--- Bắt đầu Preflight Check toàn diện ---" "INFO"

        $passCount = 0; $failCount = 0

        # Check Admin
        $isAdmin = Test-IsAdmin
        $gridPreflight.Rows.Add("Quyền Administrator", (if ($isAdmin) { "ĐẠT" }else { "THẤT BẠI" }), (if ($isAdmin) { "Đang chạy với quyền Administrator" }else { "Cần chạy dưới quyền Administrator!" })) | Out-Null
        if ($isAdmin) { $passCount++ } else { $failCount++ }

        # Check sftp.exe
        $sftp = Get-Command "sftp.exe" -ErrorAction SilentlyContinue
        $sftpOk = ($null -ne $sftp)
        $gridPreflight.Rows.Add("OpenSSH Client (sftp.exe)", (if ($sftpOk) { "ĐẠT" }else { "THẤT BẠI" }), (if ($sftpOk) { "Đã cài đặt: $($sftp.Source)" }else { "Không tìm thấy sftp.exe trong PATH!" })) | Out-Null

        # Check SSH Key
        $keyOk = Test-Path $Config.Remote.SSHKeyPath
        $gridPreflight.Rows.Add("SSH Private Key", (if ($keyOk) { "ĐẠT" }else { "THẤT BẠI" }), (if ($keyOk) { "Tìm thấy file: $($Config.Remote.SSHKeyPath)" }else { "File key không tồn tại!" })) | Out-Null

        # Check KnownHosts
        $khOk = Test-Path $Config.Remote.KnownHostsPath
        $gridPreflight.Rows.Add("File KnownHosts", (if ($khOk) { "ĐẠT" }else { "CẢNH BÁO" }), (if ($khOk) { "Tìm thấy: $($Config.Remote.KnownHostsPath)" }else { "Khuyên dùng file known_hosts để bật StrictHostKeyChecking" })) | Out-Null

        # Check Channels
        foreach ($sub in $Config.Collection.Subscriptions) {
            $ch = $sub.Channel
            $chOk = $false; $chMsg = ""
            try {
                $l = Get-WinEvent -ListLog $ch -ErrorAction Stop
                if ($l.IsEnabled) { $chOk = $true; $chMsg = "Kênh đang mở và có thể đọc" }
                else { $chMsg = "Kênh bị vô hiệu hóa (Disabled)" }
            }
            catch { $chMsg = $_.Exception.Message }

            $gridPreflight.Rows.Add("Channel [$ch]", (if ($chOk) { "ĐẠT" }else { "THẤT BẠI" }), $chMsg) | Out-Null
        }

        # Check TCP Port 22
        $tcpOk = Test-NetConnection -ComputerName $Config.Remote.Host -Port $Config.Remote.Port -InformationLevel Quiet -WarningAction SilentlyContinue
        $gridPreflight.Rows.Add("Kết Nối SFTP Server", (if ($tcpOk) { "ĐẠT" }else { "THẤT BẠI" }), (if ($tcpOk) { "Kết nối TCP tới $($Config.Remote.Host):$($Config.Remote.Port) THÀNH CÔNG" }else { "Không thể mở cổng TCP $($Config.Remote.Port) tới $($Config.Remote.Host)" })) | Out-Null

        if ($tcpOk) {
            $card3.ValLabel.Text = "ONLINE"
            $card3.ValLabel.ForeColor = [System.Drawing.Color]::LimeGreen
        }
        else {
            $card3.ValLabel.Text = "OFFLINE"
            $card3.ValLabel.ForeColor = $accentRed
        }
    }

    $btnRunPreflightTab = New-ActionButton -Text "[🔍] Chạy Lại Preflight Check" -Color $accentBlue -Width 260
    $btnRunPreflightTab.Location = New-Object System.Drawing.Point(20, 265)
    $tabPreflight.Controls.Add($btnRunPreflightTab)

    $btnRunPreflightTab.Add_Click({ Run-PreflightGui })

    # =====================================================
    # TIMER & GLOBAL ACTION HANDLERS
    # =====================================================
    $timer = New-Object System.Windows.Forms.Timer
    $intervalMs = [math]::Max(10000, $Config.Collection.DefaultIntervalMinutes * 60 * 1000)
    $timer.Interval = $intervalMs

    $script:nextRunTime = $null

    # Function update Timer Status UI
    function Update-TimerUI {
        param([bool]$Running)
        if ($Running) {
            $lblAgentBadge.Text = "● ĐANG TỰ ĐỘNG (TIMER)"
            $lblAgentBadge.ForeColor = [System.Drawing.Color]::Cyan
            $lblLiveTimerState.Text = "Trạng Thái: ĐANG CHẠY TỰ ĐỘNG"
            $lblLiveTimerState.ForeColor = [System.Drawing.Color]::LimeGreen
            $lblLiveNextRun.Text = "Lần chạy tiếp theo: " + (Get-Date).AddMilliseconds($timer.Interval).ToString("HH:mm:ss")
            $lblInfoTimer.Text = "Chu kỳ chạy tự động: Mỗi " + [math]::Round($timer.Interval / 60000, 1) + " phút  |  Lần chạy kế tiếp: " + (Get-Date).AddMilliseconds($timer.Interval).ToString("HH:mm:ss")

            $btnDashStartAuto.Enabled = $false
            $btnDashStopAuto.Enabled = $true
            $btnAutoStart.Enabled = $false
            $btnAutoStop.Enabled = $true
        }
        else {
            $lblAgentBadge.Text = "● ĐANG SẴN SÀNG"
            $lblAgentBadge.ForeColor = [System.Drawing.Color]::LimeGreen
            $lblLiveTimerState.Text = "Trạng Thái: ĐÃ DỪNG"
            $lblLiveTimerState.ForeColor = [System.Drawing.Color]::LightGray
            $lblLiveNextRun.Text = "Lần chạy tiếp theo: Chưa bật"
            $lblInfoTimer.Text = "Chu kỳ chạy tự động: Chưa bật"

            $btnDashStartAuto.Enabled = $true
            $btnDashStopAuto.Enabled = $false
            $btnAutoStart.Enabled = $true
            $btnAutoStop.Enabled = $false
        }
    }

    # Timer Tick Event Handler
    $timer.Add_Tick({
            AddLog "--- Timer Tick: Bắt đầu chu kỳ thu thập tự động ---" "INFO"
            $lblAgentBadge.Text = "● ĐANG THU THẬP LOG..."
            $lblAgentBadge.ForeColor = [System.Drawing.Color]::Yellow
            try {
                $res = Invoke-WinLogCollectorCycle -Context $Context -Mode "continuous"
                if ($res) {
                    $card1.ValLabel.Text = [string]$res.Collected
                    Refresh-QueueGrid
                }
            }
            finally {
                Update-TimerUI -Running $true
            }
        })

    # Start Auto Action
    $actionStartAuto = {
        $intervalMs = [math]::Max(10000, [int]$numTimerMin.Value * 60 * 1000)
        $timer.Interval = $intervalMs
        $timer.Start()
        Update-TimerUI -Running $true
        AddLog "Đã kích hoạt thu thập tự động mỗi $($numTimerMin.Value) phút." "SUCCESS"
    }

    # Stop Auto Action
    $actionStopAuto = {
        $timer.Stop()
        Update-TimerUI -Running $false
        AddLog "Đã dừng thu thập tự động." "WARNING"
    }

    # Run Once Action
    $actionRunOnce = {
        $btnDashRunOnce.Enabled = $false
        $lblAgentBadge.Text = "● ĐANG THU THẬP LOG..."
        $lblAgentBadge.ForeColor = [System.Drawing.Color]::Yellow
        try {
            $sTime = $null; $eTime = $null
            if ($rbModeCustomRange.Checked) {
                $sTime = $dtpFromDate.Value.ToUniversalTime()
                $eTime = $dtpToDate.Value.ToUniversalTime()
                AddLog "Chế độ: Thu thập theo khoảng thời gian ($($sTime.ToString('yyyy-MM-dd HH:mm UTC')) -> $($eTime.ToString('yyyy-MM-dd HH:mm UTC')))" "INFO"
            }
            elseif ($rbModeLookback.Checked) {
                $mins = [int]$numLookbackMin.Value
                $sTime = (Get-Date).ToUniversalTime().AddMinutes(-$mins)
                $eTime = (Get-Date).ToUniversalTime()
                AddLog "Chế độ: Thu thập Lookback $mins phút gần nhất" "INFO"
            }
            $res = Invoke-WinLogCollectorCycle -Context $Context -Mode "limited" -StartTime $sTime -EndTime $eTime
            if ($res.Success) {
                $card1.ValLabel.Text = [string]$res.Collected
                AddLog "Chu kỳ thu thập hoàn tất thành công. Số log: $($res.Collected)" "SUCCESS"
            }
            else {
                AddLog "Chu kỳ thu thập kết thúc với mã lỗi $($res.ExitCode)" "WARNING"
            }
            Refresh-QueueGrid
        }
        finally {
            $btnDashRunOnce.Enabled = $true
            if ($timer.Enabled) { Update-TimerUI -Running $true }
            else { Update-TimerUI -Running $false }
        }
    }

    # Wire Button Handlers
    $btnDashRunOnce.Add_Click($actionRunOnce)
    $btnDashStartAuto.Add_Click($actionStartAuto)
    $btnDashStopAuto.Add_Click($actionStopAuto)
    $btnAutoStart.Add_Click($actionStartAuto)
    $btnAutoStop.Add_Click($actionStopAuto)
    $btnDashPreflight.Add_Click({
            $tabControl.SelectedTab = $tabPreflight
            Run-PreflightGui
        })

    $btnClearLog.Add_Click({ $script:LogBox.Clear() })
    $btnOpenDataDir.Add_Click({ Invoke-Item $Context.DataDir })

    # Initial Welcome & Checks
    AddLog "WinLogCollector Agent v0.3.1 - Khởi động thành công." "SUCCESS"
    AddLog "SFTP Remote: $($Config.Remote.User)@$($Config.Remote.Host):$($Config.Remote.Port)" "INFO"

    $form.Add_FormClosing({
            $timer.Stop()
            $timer.Dispose()
        })

    # Show Form
    $form.ShowDialog() | Out-Null
}
