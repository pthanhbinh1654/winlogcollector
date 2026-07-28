# =====================================================
# MainWindow.ps1 - GUI WinForms Interface v0.3.1
# Fix P0.1: Signature matches Show-MainWindow -Context $Context
# Fix P0.2: Uses new config schema (DataDir, Subscriptions)
# Fix P0.3: Calls Invoke-WinLogCollectorCycle instead of legacy functions
# Fix P0.4: Checks .ready and .zip files instead of .json
# Fix P0.5: Registers Logger scriptblock sink
# =====================================================

function Show-MainWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $Config = $Context.Config

    # ---- Register Logger Sink ----
    $script:LogBox = $null
    Initialize-Logger -DataDir $Context.DataDir -Sink {
        param($Message, $Type)
        if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
            $color = switch ($Type) {
                "ERROR" { [System.Drawing.Color]::FromArgb(255, 80, 80) }
                "WARNING" { [System.Drawing.Color]::DarkOrange }
                "SUCCESS" { [System.Drawing.Color]::FromArgb(0, 200, 100) }
                default { [System.Drawing.Color]::White }
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

    # ---- Form Design ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Windows Log Collector Agent v0.3.1"
    $form.Size = New-Object System.Drawing.Size(950, 700)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    $fontHeader = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $fontLabel = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $fontBtn = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $fontLog = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)

    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "WINDOWS LOG COLLECTOR AGENT"
    $lblTitle.Font = $fontHeader
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 150, 255)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 15)
    $lblTitle.AutoSize = $true
    $form.Controls.Add($lblTitle)

    # ---- Panel Config ----
    $grpConfig = New-Object System.Windows.Forms.GroupBox
    $grpConfig.Text = " Thong tin Cấu hình "
    $grpConfig.Font = $fontLabel
    $grpConfig.ForeColor = [System.Drawing.Color]::LightGray
    $grpConfig.Location = New-Object System.Drawing.Point(20, 50)
    $grpConfig.Size = New-Object System.Drawing.Size(895, 140)
    $form.Controls.Add($grpConfig)

    # Remote Server
    $lblServer = New-Object System.Windows.Forms.Label
    $lblServer.Text = "SFTP Server: $($Config.Remote.User)@$($Config.Remote.Host):$($Config.Remote.Port)"
    $lblServer.Location = New-Object System.Drawing.Point(20, 30)
    $lblServer.AutoSize = $true
    $grpConfig.Controls.Add($lblServer)

    # Channels (Fix P0.2: get from Subscriptions)
    $channelsStr = ($Config.Collection.Subscriptions | ForEach-Object { $_.Channel }) -join ", "
    $lblChannels = New-Object System.Windows.Forms.Label
    $lblChannels.Text = "Channels: $channelsStr"
    $lblChannels.Location = New-Object System.Drawing.Point(20, 60)
    $lblChannels.AutoSize = $true
    $grpConfig.Controls.Add($lblChannels)

    # Directories
    $lblDirs = New-Object System.Windows.Forms.Label
    $lblDirs.Text = "DataDir: $($Context.DataDir)  |  RemotePath: $($Config.Remote.RemotePath)"
    $lblDirs.Location = New-Object System.Drawing.Point(20, 95)
    $lblDirs.AutoSize = $true
    $grpConfig.Controls.Add($lblDirs)

    # ---- Panel Actions ----
    $btnPreflight = New-Object System.Windows.Forms.Button
    $btnPreflight.Text = "🔍 Preflight Check"
    $btnPreflight.Font = $fontBtn
    $btnPreflight.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnPreflight.ForeColor = [System.Drawing.Color]::White
    $btnPreflight.FlatStyle = "Flat"
    $btnPreflight.Location = New-Object System.Drawing.Point(20, 205)
    $btnPreflight.Size = New-Object System.Drawing.Size(160, 40)
    $form.Controls.Add($btnPreflight)

    $btnRunOnce = New-Object System.Windows.Forms.Button
    $btnRunOnce.Text = "▶ Thu thap Ngay"
    $btnRunOnce.Font = $fontBtn
    $btnRunOnce.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnRunOnce.ForeColor = [System.Drawing.Color]::White
    $btnRunOnce.FlatStyle = "Flat"
    $btnRunOnce.Location = New-Object System.Drawing.Point(195, 205)
    $btnRunOnce.Size = New-Object System.Drawing.Size(160, 40)
    $form.Controls.Add($btnRunOnce)

    $btnStartAuto = New-Object System.Windows.Forms.Button
    $btnStartAuto.Text = "⚡ Tu dong (Timer)"
    $btnStartAuto.Font = $fontBtn
    $btnStartAuto.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 80)
    $btnStartAuto.ForeColor = [System.Drawing.Color]::White
    $btnStartAuto.FlatStyle = "Flat"
    $btnStartAuto.Location = New-Object System.Drawing.Point(370, 205)
    $btnStartAuto.Size = New-Object System.Drawing.Size(160, 40)
    $form.Controls.Add($btnStartAuto)

    $btnStopAuto = New-Object System.Windows.Forms.Button
    $btnStopAuto.Text = "⏹ Dung Tu dong"
    $btnStopAuto.Font = $fontBtn
    $btnStopAuto.BackColor = [System.Drawing.Color]::FromArgb(180, 40, 40)
    $btnStopAuto.ForeColor = [System.Drawing.Color]::White
    $btnStopAuto.FlatStyle = "Flat"
    $btnStopAuto.Enabled = $false
    $btnStopAuto.Location = New-Object System.Drawing.Point(545, 205)
    $btnStopAuto.Size = New-Object System.Drawing.Size(160, 40)
    $form.Controls.Add($btnStopAuto)

    # Status Label
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Trang thai: San sang"
    $lblStatus.Font = $fontLabel
    $lblStatus.ForeColor = [System.Drawing.Color]::LimeGreen
    $lblStatus.Location = New-Object System.Drawing.Point(720, 215)
    $lblStatus.AutoSize = $true
    $form.Controls.Add($lblStatus)

    # ---- RichTextBox Log Output ----
    $script:LogBox = New-Object System.Windows.Forms.RichTextBox
    $script:LogBox.Font = $fontLog
    $script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)
    $script:LogBox.ForeColor = [System.Drawing.Color]::White
    $script:LogBox.Location = New-Object System.Drawing.Point(20, 260)
    $script:LogBox.Size = New-Object System.Drawing.Size(895, 380)
    $script:LogBox.ReadOnly = $true
    $form.Controls.Add($script:LogBox)

    # ---- Timer for Continuous Collection ----
    $timer = New-Object System.Windows.Forms.Timer
    $intervalMs = [math]::Max(10000, $Config.Collection.DefaultIntervalMinutes * 60 * 1000)
    $timer.Interval = $intervalMs

    # ---- Event Handlers ----

    # Preflight Check
    $btnPreflight.Add_Click({
            $script:LogBox.Clear()
            AddLog "--- Kiem tra Preflight Prerequisite ---" "INFO"
            Test-WinLogCollectorPrerequisite `
                -RemoteHost $Config.Remote.Host -Port $Config.Remote.Port `
                -SSHKeyPath $Config.Remote.SSHKeyPath -KnownHostsPath $Config.Remote.KnownHostsPath
        })

    # Run Once (P0.3: calls Invoke-WinLogCollectorCycle)
    $btnRunOnce.Add_Click({
            $btnRunOnce.Enabled = $false
            $lblStatus.Text = "Trang thai: Dang chay..."
            $lblStatus.ForeColor = [System.Drawing.Color]::Yellow
            try {
                $res = Invoke-WinLogCollectorCycle -Context $Context -Mode "limited"
                if ($res.Success) {
                    $lblStatus.Text = "Trang thai: Thanh cong"
                    $lblStatus.ForeColor = [System.Drawing.Color]::LimeGreen
                }
                else {
                    $lblStatus.Text = "Trang thai: Co loi (Code $($res.ExitCode))"
                    $lblStatus.ForeColor = [System.Drawing.Color]::OrangeRed
                }
            }
            finally {
                $btnRunOnce.Enabled = $true
            }
        })

    # Timer Tick (P0.3: calls Invoke-WinLogCollectorCycle)
    $timer.Add_Tick({
            AddLog "--- Timer Tick: Chu ky tu dong ---" "INFO"
            Invoke-WinLogCollectorCycle -Context $Context -Mode "continuous" | Out-Null
        })

    # Start Auto
    $btnStartAuto.Add_Click({
            $timer.Start()
            $btnStartAuto.Enabled = $false
            $btnStopAuto.Enabled = $true
            $btnRunOnce.Enabled = $false
            $lblStatus.Text = "Trang thai: Chay tu dong ($($Config.Collection.DefaultIntervalMinutes) phut)"
            $lblStatus.ForeColor = [System.Drawing.Color]::Cyan
            AddLog "Da bat thu thap tu dong moi $($Config.Collection.DefaultIntervalMinutes) phut." "SUCCESS"
        })

    # Stop Auto
    $btnStopAuto.Add_Click({
            $timer.Stop()
            $btnStartAuto.Enabled = $true
            $btnStopAuto.Enabled = $false
            $btnRunOnce.Enabled = $true
            $lblStatus.Text = "Trang thai: Da dung"
            $lblStatus.ForeColor = [System.Drawing.Color]::LightGray
            AddLog "Da dung thu thap tu dong." "WARNING"
        })

    # Welcome log
    AddLog "WinLogCollector Agent v0.3.1 khoi dong thanh cong." "SUCCESS"
    AddLog "SFTP Remote: $($Config.Remote.User)@$($Config.Remote.Host):$($Config.Remote.Port)" "INFO"

    # Show Dialog
    $form.Add_FormClosing({
            $timer.Stop()
            $timer.Dispose()
        })
    $form.ShowDialog() | Out-Null
}
