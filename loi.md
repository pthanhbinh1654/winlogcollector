Đánh giá lại toàn bộ phiên bản hiện tại

Tôi đã bỏ các kết luận dựa trên bản cũ và đọc lại phiên bản mới tại commit:

ff44edf4a821718779a7c7cc1d775632661ff374
fix(P0): Fully address 17 critical issues from loi.md audit
Ngày cập nhật: 28/07/2026

Commit này thực sự đã thay đổi lớn collector, uploader, config, logging, CI và tài liệu bảo mật. Tuy nhiên, đây là đánh giá tĩnh trên source code hiện tại; tôi chưa chạy được integration test thật trên Windows Event Log và SFTP trong môi trường này.

Kết luận mới

Phiên bản mới đã tiến bộ rõ rệt về kiến trúc lõi. Nhiều lỗi P0 trước đây đã được sửa đúng. Nhưng sau khi tích hợp code mới, dự án xuất hiện một số lỗi kết nối giữa Core – Main – GUI, trong đó có lỗi khiến GUI có khả năng không khởi động được.

Ngoài ra, checkpoint mới chưa đủ bảo đảm không mất log trong các tình huống:

Số event vượt quá MaxEvents.
Task Scheduler ngừng chạy lâu hơn chu kỳ.
Chương trình crash sau khi cập nhật checkpoint nhưng trước khi archive/upload.
Hai instance chạy đồng thời.

Vì vậy, trạng thái hiện tại phù hợp với:

Prototype kỹ thuật khá tốt, nhưng chưa phải collector có bảo đảm at-least-once và chưa sẵn sàng triển khai production.

1. Những phần đã được sửa tốt
1.1. Retry không còn nén lại file ZIP

Uploader mới đã tách rõ:

New-WinLogArchive
Send-WinLogArchive
Move-WinLogArchiveToQueue
Retry-WinLogQueue

Đây là hướng sửa đúng. Queue giờ gửi lại archive có sẵn thay vì đưa .zip vào hàm nén lần nữa.

1.2. RemotePath đã được sử dụng

Đường dẫn remote hiện được xây dựng từ base path trong cấu hình, sau đó thêm thư mục theo mode. Điều này tốt hơn việc hard-code /limited và /continuous.

1.3. Xác minh SSH host key đã được bật

Code mới dùng:

StrictHostKeyChecking=yes
UserKnownHostsFile=<KnownHostsPath>

Đây là cải tiến bảo mật quan trọng so với StrictHostKeyChecking=no.

1.4. Upload bằng file tạm rồi rename

Uploader gửi:

batch.zip.part

sau đó mới rename thành tên cuối. Cách này giúp server không xử lý nhầm file upload chưa hoàn tất.

1.5. Config đã chuyển sang subscription theo channel

Cấu hình mới tách Event ID theo từng channel, gồm cả:

Microsoft-Windows-PowerShell/Operational

cho Event ID 4103 và 4104. Thiết kế này đúng hơn một mảng Event ID dùng chung cho tất cả channel.

1.6. Parser Event Log đã dùng XML field name

ConvertFrom-WinEventRecord mới không còn phụ thuộc chủ yếu vào vị trí Properties[index], mà đọc XML và ánh xạ theo tên trường. Điều này ổn định hơn giữa các version event.

1.7. Đã có file trạng thái và Record ID

Collector lưu checkpoint riêng theo channel với LastRecordId. Đây là nền tảng đúng để xây dựng cơ chế thu thập incremental.

1.8. Ghi .tmp rồi chuyển thành .ready

Việc ghi file tạm rồi rename sang .ready giảm nguy cơ uploader lấy file đang ghi dở.

1.9. Queue có sidecar, retry và quarantine

Queue mới đã có attempt count, thời gian retry và thư mục quarantine. Đây là bước nâng cấp đáng kể so với queue chỉ chứa file ZIP.

1.10. Có logging dạng JSON và GitHub Actions

Project đã bổ sung persistent logger, workflow PSScriptAnalyzer/Pester, SECURITY.md, config mẫu và license.

2. Lỗi P0 hiện tại: cần sửa trước khi tiếp tục thêm tính năng
P0.1. GUI đang được gọi sai số lượng tham số

Trong Main.ps1, GUI được gọi với nhiều tham số:

Show-MainWindow `
    -Config $ConfigHT `
    -ReadyDir $ReadyDir `
    -QueueDir $QueueDir `
    -QuarantineDir $QuarantineDir `
    -StateFile $StateFile

Nhưng Show-MainWindow hiện chỉ khai báo:

param(
    [hashtable]$Config
)

PowerShell sẽ báo không tìm thấy parameter như ReadyDir, khiến GUI có thể lỗi ngay khi khởi động.

Cách sửa

Không nên tiếp tục truyền năm đường dẫn riêng. Hãy truyền một runtime context:

$Context = @{
    Config        = $ConfigHT
    DataDir       = $DataDir
    ReadyDir      = $ReadyDir
    QueueDir      = $QueueDir
    QuarantineDir = $QuarantineDir
    StateFile     = $StateFile
}

Show-MainWindow -Context $Context

GUI:

function Show-MainWindow {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    $Config = $Context.Config
}
P0.2. GUI vẫn sử dụng schema config cũ

GUI hiện còn truy cập các field cũ như:

$Config.Local.FolderLuuLog
$Config.Collection.EventChannels

Trong khi config mới dùng:

Local.DataDir
Collection.Subscriptions

Do đó, dù sửa parameter mismatch, nhiều control GUI vẫn có thể nhận $null hoặc hiển thị sai cấu hình.

Cách sửa

Xóa toàn bộ logic đọc config cũ khỏi GUI. Danh sách channel phải được lấy từ:

$Config.Collection.Subscriptions |
    ForEach-Object { $_.Channel }
P0.3. GUI gọi các hàm không còn tồn tại

GUI vẫn gọi:

GUILOGSSH
GUILOGCHOGUI

Nhưng uploader mới đã thay bằng:

New-WinLogArchive
Send-WinLogArchive
Retry-WinLogQueue

Hai hàm cũ không còn được định nghĩa trong code mới.

Cách sửa tốt nhất

GUI không nên tự ghép từng bước collector và uploader. Cả GUI và Silent Mode phải gọi chung một orchestration function:

Invoke-WinLogCollectorCycle -Context $Context

Như vậy không xảy ra tình trạng Silent Mode dùng luồng mới còn GUI vẫn dùng luồng cũ.

P0.4. GUI kiểm tra sai tên file output

Collector mới tạo:

*.jsonl.tmp
*.jsonl.ready

Nhưng GUI vẫn kiểm tra một đường dẫn dạng .json. Vì vậy collector có thể thu thập thành công nhưng GUI cho rằng không có file output.

Không nên để GUI tự đoán tên file. Invoke-WinLogCollection cần trả về object:

[pscustomobject]@{
    Success       = $true
    ReadyFiles    = $readyFiles
    RecordCount   = $recordCount
    FailedChannels = @()
}
P0.5. Core vẫn phụ thuộc vào WinForms

Một số function trong Core hoặc Logger khai báo parameter kiểu:

[System.Windows.Forms.RichTextBox]

Trong khi Main.ps1 dot-source các file Core trước khi gọi Add-Type -AssemblyName System.Windows.Forms. Silent Mode không cần giao diện nhưng vẫn phải parse các type GUI này.

Trong Windows PowerShell 5.1, assembly chưa được nạp có thể cần Add-Type trước khi sử dụng type của assembly. Điều này tạo nguy cơ Silent Mode lỗi ngay ở bước dot-source, trước khi đi vào nhánh headless.

Cách sửa

Core không được biết RichTextBox.

Thay:

function AddLog {
    param(
        [System.Windows.Forms.RichTextBox]$LogBox
    )
}

bằng:

function Write-CollectorLog {
    param(
        [string]$Message,
        [string]$Level = 'Information',
        [scriptblock]$Sink
    )

    # Ghi file persistent trước.

    if ($Sink) {
        & $Sink $Message $Level
    }
}

GUI có thể truyền callback riêng để cập nhật RichTextBox.

P0.6. MaxEvents = 50000 có thể gây mất log vĩnh viễn

Collector giới hạn mỗi truy vấn ở một số lượng event cố định. Get-WinEvent -MaxEvents mặc định trả về event từ mới đến cũ. Nếu khoảng truy vấn có hơn 50.000 event:

Collector chỉ nhận 50.000 event mới nhất.
Sau đó cập nhật checkpoint tới Record ID lớn nhất.
Những event cũ hơn nhưng chưa được thu thập sẽ nằm dưới checkpoint.
Các lần sau không bao giờ lấy lại chúng.

Đây là lỗi mất dữ liệu thực sự, không chỉ là vấn đề hiệu năng.

Cách sửa

Đọc theo thứ tự cũ đến mới và phân trang theo Record ID:

EventRecordID > LastRecordId
ORDER BY oldest first
LIMIT BatchSize

Lặp đến khi batch trả về ít hơn BatchSize.

Với PowerShell, có thể dùng XPath:

$xpath = "*[System[EventRecordID > $LastRecordId]]"

hoặc dùng trực tiếp EventLogQuery/EventLogReader với ReverseDirection = $false.

Không được cập nhật checkpoint vượt qua event chưa ghi bền vững.

P0.7. Có checkpoint nhưng vẫn mất log sau downtime

Trong Silent Mode, khoảng thu thập vẫn được xác định từ thời gian hiện tại, ví dụ vài phút gần nhất. Dù state có LastRecordId, filter vẫn chứa StartTime và EndTime.

Giả sử task dự kiến chạy mỗi 3 phút nhưng máy tắt 2 giờ:

LastRecordId = 1000
Hiện tại       = 10:00
StartTime      = 09:57

Các event từ 08:00 đến 09:57 có Record ID lớn hơn 1000 nhưng vẫn bị loại bởi StartTime. Checkpoint không cứu được trường hợp này.

Nguyên tắc đúng
Lần đầu chạy: dùng InitialLookbackMinutes.
Đã có checkpoint: query theo EventRecordID > LastRecordId, không giới hạn bằng khoảng 3 phút.
Có thể thêm một ngưỡng thời gian rất rộng để bảo vệ, nhưng Record ID phải là điều kiện chính.
P0.8. File .ready cũ không được phục hồi sau crash

Collector thực hiện gần đúng thứ tự:

Ghi JSONL
Rename thành .ready
Cập nhật checkpoint
Trả danh sách ReadyFiles
Main archive/upload danh sách đó

Vấn đề xảy ra nếu chương trình crash sau khi cập nhật checkpoint nhưng trước khi archive:

Ready/batch.jsonl.ready vẫn còn
Checkpoint đã vượt qua batch

Lần chạy sau, Main.ps1 chỉ xử lý danh sách file vừa được collector trả về. Nó không quét tất cả file .ready tồn tại từ lần trước. File này sẽ bị bỏ quên vĩnh viễn.

Cách sửa

Mỗi chu kỳ phải bắt đầu bằng việc drain durable outbox:

1. Quét Ready/*.jsonl.ready
2. Tạo archive cho từng file
3. Quét Ready/*.zip
4. Upload hoặc chuyển Queue
5. Retry Queue
6. Sau đó mới thu thập batch mới
7. Drain Ready lần nữa

Việc checkpoint sau .ready là chấp nhận được chỉ khi .ready là durable outbox luôn được phục hồi ở lần chạy tiếp theo.

P0.9. Lỗi đọc channel bị coi là “không có event”

Trong collector, lỗi Get-WinEvent của từng channel được log rồi continue. Nếu tất cả channel đều lỗi, collector có thể trả về không có file. Main.ps1 sau đó ghi “không có event mới” và kết thúc như một lần chạy thành công.

Ví dụ:

Task không có quyền đọc Security.
Channel bị disable.
XPath không hợp lệ.
Event Log service gặp lỗi.

Tất cả có thể bị hiểu nhầm là không có dữ liệu.

Kết quả cần trả về
[pscustomobject]@{
    Success        = $FailedChannels.Count -eq 0
    CollectedCount = $TotalCount
    ReadyFiles     = $ReadyFiles
    FailedChannels = $FailedChannels
}

Nếu một subscription bắt buộc thất bại, Silent Mode phải trả exit code khác 0.

P0.10. Chưa có mutex chống hai instance chạy đồng thời

Nếu Task Scheduler bắt đầu instance mới khi instance cũ chưa kết thúc, hai process có thể đồng thời:

Đọc cùng checkpoint.
Thu thập trùng event.
Ghi state đè nhau.
Retry cùng một queue file.
Một process move file trong khi process khác upload.

Cần named mutex:

$mutex = [Threading.Mutex]::new(
    $false,
    'Global\WinLogCollector'
)

if (-not $mutex.WaitOne(0)) {
    Write-CollectorLog `
        -Level Warning `
        -Message 'Another collector instance is running.'

    exit 12
}

Task Scheduler cũng nên cấu hình:

If the task is already running:
Do not start a new instance
P0.11. Preflight được mô tả trong commit nhưng chưa được triển khai

Commit message đề cập việc bổ sung prerequisite/preflight. Tuy nhiên, Security.ps1 hiện vẫn chủ yếu chứa KTADMIN và kiểm tra kết nối kiểu cũ; không có function hoàn chỉnh như:

Test-WinLogCollectorPrerequisite

Main.ps1 cũng chưa gọi một preflight tương ứng. Ngoài ra còn có function KTKN trùng tên giữa các file, nên function được dot-source sau có thể ghi đè function trước.

Preflight cần kiểm tra ít nhất:

Config hợp lệ
Quyền đọc từng channel
Channel có tồn tại và đang enabled
SFTP executable
Private-key file
Known-hosts file
Quyền ACL của private key
Kết nối TCP port 22
Remote folder tồn tại
Audit Process Creation
Include command line in process creation events
PowerShell Script Block Logging
Dung lượng ổ đĩa
Quyền ghi state/queue/log

Event 4688 chỉ có command line khi policy tương ứng được bật; còn Event 4104 phụ thuộc Script Block Logging và được ghi trong PowerShell Operational channel.

P0.12. Queue policy mới chỉ được khai báo, chưa được cưỡng chế đầy đủ

Config có các field như:

MaxSizeMB
MaxAgeDays
MaxAttempts

Nhưng:

MaxAgeDays chưa được sử dụng đầy đủ trong luồng Main/retry.
Khi queue vượt MaxSizeMB, code chủ yếu log cảnh báo, chưa có chiến lược dừng thu thập hoặc bảo vệ ổ đĩa.
Kết quả của các lần retry được lưu nhưng chưa tác động rõ tới exit code.
Nếu sidecar JSON hỏng, ConvertFrom-Json hoặc parse ngày có thể làm hỏng toàn bộ vòng retry.
Chính sách hợp lý
Queue < 80% giới hạn: hoạt động bình thường
Queue 80–100%: Warning/Degraded
Queue >= 100%: dừng thu thập mới hoặc chuyển sang emergency retention
Sidecar hỏng: chuyển file + sidecar sang Quarantine
Quá MaxAttempts: Quarantine
Quá MaxAgeDays: Quarantine hoặc xóa theo policy rõ ràng

Không được xóa log im lặng.

3. Các vấn đề P1 về độ chính xác và khả năng bảo trì
3.1. Batch ID chưa được giữ xuyên suốt pipeline

Collector tạo file, archive lại tạo thêm metadata/batch ID khác. Điều này làm khó truy vết một batch từ:

collection → ready → archive → queue → SFTP → ingestion

Nên sinh BatchId ngay khi bắt đầu collection và dùng cùng ID trong:

Tên file.
JSON log.
Sidecar.
Manifest.
Checkpoint transaction.
Server ingestion.
3.2. Manifest chưa đủ dữ liệu forensic

Manifest nên có:

{
  "schemaVersion": "1.0",
  "collectorVersion": "0.3.1",
  "agentId": "...",
  "hostname": "...",
  "batchId": "...",
  "channel": "Security",
  "firstRecordId": 1001,
  "lastRecordId": 1500,
  "firstEventTimeUtc": "...",
  "lastEventTimeUtc": "...",
  "recordCount": 500,
  "eventSha256": "..."
}

Hiện một số thời gian trong manifest/state phản ánh collection window hoặc thời điểm hiện tại, không nhất thiết là thời gian event đầu/cuối thực tế.

3.3. Đếm record bằng cách đọc lại toàn bộ file

Uploader hiện có thao tác tương tự:

Get-Content file | Where-Object { ... }

để đếm dòng. Cách này đọc lại toàn bộ JSONL vào pipeline, làm giảm lợi ích của việc streaming collector.

Collector nên trả sẵn RecordCount, hoặc dùng:

[IO.File]::ReadLines($Path)

và đếm streaming.

3.4. Parser chưa bao phủ toàn bộ dạng Event XML

Parser hiện tập trung vào:

Event.EventData.Data

Nhưng Windows Event XML còn có thể chứa:

UserData
RenderingInfo
Correlation
RelatedActivityID

Nên lưu thêm:

RawXml
ActivityId
RelatedActivityId
Keywords
Opcode
Task
Version

Đối với dữ liệu không thể normalize, RawXml là fallback quan trọng phục vụ forensic.

3.5. Một event lỗi có thể ảnh hưởng cả channel

Các thao tác như:

$Event.Message
$Event.ToXml()
ConvertTo-Json

đều có khả năng lỗi với một record cụ thể. Không nên để một event hỏng làm dừng toàn bộ batch.

Luồng an toàn:

foreach event:
    try parse
    catch:
        ghi raw/dead-letter record
        tiếp tục

Dead-letter local nên chứa:

{
  "channel": "Security",
  "recordId": 12345,
  "error": "...",
  "rawXml": "..."
}
3.6. File .tmp lỗi chưa có lifecycle rõ ràng

Nếu process crash hoặc parser exception trước rename, .tmp có thể tồn tại lâu dài.

Khi khởi động:

.tmp mới và đang được process giữ → bỏ qua
.tmp cũ hơn ngưỡng → kiểm tra và recover/quarantine
.ready → tiếp tục archive
.zip → tiếp tục upload
3.7. GUI vẫn chạy công việc nặng trên UI thread

GUI dùng WinForms event handler/timer để chạy:

Get-WinEvent
Nén file
SFTP
Retry

Các tác vụ này có thể làm cửa sổ treo. Nút Stop chỉ chặn tick kế tiếp chứ không hủy thao tác đang chạy.

Giải pháp tốt hơn:

GUI = configuration + status
Agent = collection + queue + upload

GUI không nên sở hữu vòng đời collector.

3.8. Chưa thiết lập ACL cho dữ liệu local

SECURITY.md nói về việc bảo vệ thư mục dữ liệu, nhưng Main.ps1 hiện chủ yếu tạo directory, chưa có bước cài ACL rõ ràng. Log 4688 và 4104 có thể chứa command line hoặc script content nhạy cảm.

Nên có installer chạy một lần:

C:\ProgramData\WinLogCollector

với quyền chỉ dành cho:

SYSTEM
Administrators
WinLogCollector service account

Không nên để mỗi lần collector chạy lại tự thay đổi ACL.

3.9. README không còn đồng bộ với code

README hiện vẫn còn nhiều hướng dẫn thuộc phiên bản cũ, chẳng hạn:

Schema FolderLuuLog.
EventChannels.
Thư mục HiddenLogs.
Ping connectivity.
ExecutionPolicy Bypass.
Cấu hình SSH cũ.
URL clone placeholder hoặc thông tin GUI cũ.

Các hướng dẫn này hiện mâu thuẫn với config và uploader mới. Người dùng làm theo README có thể triển khai sai hoặc vô hiệu hóa các cải tiến bảo mật vừa thêm.

README cần được viết lại sau khi ổn định orchestration, không nên chỉnh từng đoạn nhỏ trên tài liệu cũ.

3.10. CI có thể thành công dù không có test

Workflow hiện chạy Pester nếu tìm thấy thư mục test, nhưng có thể chỉ thông báo không có test và tiếp tục. Commit hiện cũng chưa bổ sung bộ test thực tế tương ứng với các thay đổi lớn.

CI nên fail khi không có test:

if (-not (Test-Path tests)) {
    throw 'Tests directory is required.'
}

$result = Invoke-Pester -Path tests -PassThru

if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0) {
    exit 1
}
3.11. Chưa có JSON Schema validation

Code chủ yếu kiểm tra file config có parse được JSON hay không. Điều đó không phát hiện:

Thiếu KnownHostsPath.
Port sai kiểu.
Subscription không có channel.
EventIDs là chuỗi.
Queue limit âm.
Hai subscription trùng nhau.

Nên thêm:

config/config.schema.json

và function:

Test-WinLogCollectorConfiguration
3.12. Security.ps1 còn legacy code

Các function cũ như KTADMIN, KTKN và logic ping/elevation nên được:

Xóa nếu không dùng.
Hoặc đổi thành function chuẩn.
Không được trùng tên với uploader.
Không tự chạy ExecutionPolicy Bypass.
Không tự bật UAC trong Silent Mode.
4. Kiến trúc nên áp dụng cho bản tiếp theo

Điểm quan trọng nhất là không để Main, GUI và Silent Mode tự xây ba luồng xử lý khác nhau.

Một orchestration function duy nhất
function Invoke-WinLogCollectorCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [CollectorContext]$Context
    )

    # 1. Acquire mutex
    # 2. Validate config and prerequisites
    # 3. Recover stale temporary files
    # 4. Drain Ready JSONL files
    # 5. Drain Ready ZIP archives
    # 6. Retry Queue
    # 7. Collect events after checkpoint
    # 8. Commit durable ready files
    # 9. Drain Ready again
    # 10. Return structured health result
}

Cả hai entry point chỉ gọi function này:

Silent Mode
    └── Invoke-WinLogCollectorCycle

GUI
    └── background runspace
            └── Invoke-WinLogCollectorCycle
Kết quả trả về
[pscustomobject]@{
    Success         = $true
    ExitCode        = 0
    Collected       = 1250
    Archived        = 2
    Uploaded        = 2
    Queued          = 0
    Quarantined     = 0
    PendingReady    = 0
    PendingQueue    = 0
    FailedChannels  = @()
    StartedUtc      = $StartedUtc
    CompletedUtc    = [DateTime]::UtcNow
}

GUI hiển thị object này. Silent Mode chuyển ExitCode thành process exit code.

5. Cấu trúc source nên hướng tới
winlogcollector/
├── src/
│   └── WinLogCollector/
│       ├── WinLogCollector.psd1
│       ├── WinLogCollector.psm1
│       ├── Public/
│       │   ├── Invoke-WinLogCollectorCycle.ps1
│       │   ├── Test-WinLogCollectorConfiguration.ps1
│       │   ├── Test-WinLogCollectorPrerequisite.ps1
│       │   └── Get-WinLogCollectorStatus.ps1
│       └── Private/
│           ├── Get-WinEventBatch.ps1
│           ├── ConvertFrom-WinEventRecord.ps1
│           ├── Read-CollectorState.ps1
│           ├── Write-CollectorState.ps1
│           ├── New-WinLogArchive.ps1
│           ├── Send-WinLogArchive.ps1
│           ├── Retry-WinLogQueue.ps1
│           └── Write-CollectorLog.ps1
├── apps/
│   └── Gui/
│       └── MainWindow.ps1
├── scripts/
│   ├── Install-WinLogCollector.ps1
│   ├── Register-WinLogCollectorTask.ps1
│   └── Uninstall-WinLogCollector.ps1
├── config/
│   ├── config.example.json
│   └── config.schema.json
├── tests/
│   ├── Unit/
│   ├── Integration/
│   └── Fixtures/
├── docs/
├── Main.ps1
└── README.md
6. Bộ test tối thiểu cần có
Collector
Thu thập theo Record ID, không mất event khi > BatchSize
Không giới hạn bởi time window sau khi có checkpoint
Hai event cùng timestamp vẫn được thu thập
Channel lỗi được trả về FailedChannels
Checkpoint không cập nhật khi file ready chưa hoàn tất
Recovery
Crash sau .ready → lần sau vẫn archive
Crash sau .zip → lần sau vẫn upload
.tmp cũ → quarantine hoặc recover
State JSON hỏng → không ghi đè state mới âm thầm
Queue
Upload lỗi → queue
Retry thành công → xóa ZIP và sidecar
Sidecar lỗi → quarantine
Quá MaxAttempts → quarantine
Quá MaxAgeDays → áp dụng retention
Queue vượt giới hạn → trạng thái Degraded/Full
SFTP
Host key đúng → kết nối
Host key sai → từ chối
Remote folder thiếu → lỗi rõ ràng
Upload .part thành công → rename
Upload gián đoạn → không xuất hiện final file
GUI
Load config schema mới
Không gọi function legacy
Không block UI thread
Stop có cancellation token
Hiển thị đúng trạng thái queue/failed channel
7. Thứ tự sửa đề xuất cho phiên bản 0.3.1
Bước 1 – Khôi phục khả năng chạy
Sửa signature Show-MainWindow.
Xóa toàn bộ field config cũ trong GUI.
Xóa lời gọi GUILOGSSH và GUILOGCHOGUI.
Loại WinForms type khỏi Core.
Xóa hoặc viết lại Security.ps1.
Bước 2 – Chống mất dữ liệu
Query theo EventRecordID, oldest-first.
Phân trang thay vì lấy 50.000 event mới nhất.
Bỏ time filter sau khi đã có checkpoint.
Drain toàn bộ Ready/ ở đầu và cuối chu kỳ.
Thêm named mutex.
Trả lỗi nếu channel bắt buộc không đọc được.
Bước 3 – Hoàn thiện queue và vận hành
Thực thi thật MaxSizeMB, MaxAgeDays, MaxAttempts.
Sidecar ghi atomic.
Xử lý sidecar hỏng.
Dùng một Batch ID xuyên suốt.
Chuẩn hóa manifest.
Thêm ACL installer.
Bước 4 – Test và tài liệu
Viết Pester tests thật.
CI fail nếu không có test.
Thêm config schema.
Viết lại README theo code mới.
Thêm deployment, recovery và troubleshooting documentation.
8. Điểm đánh giá phiên bản hiện tại
Hạng mục	Điểm	Nhận xét
Ý tưởng và phạm vi	8/10	Bài toán rõ, đủ tốt cho portfolio security/data
Kiến trúc Core	6.5/10	Đã có checkpoint, queue, archive, SFTP
Độ đúng dữ liệu	5/10	Vẫn có đường mất log do MaxEvents, time window và recovery
Bảo mật	6/10	Host-key verification tốt hơn, nhưng ACL/preflight chưa hoàn chỉnh
GUI	3/10	Không đồng bộ với API và schema mới
Testing	3.5/10	Có CI nhưng chưa có test bảo vệ các invariant quan trọng
Tài liệu	4/10	README hiện mâu thuẫn với code mới
Khả năng production	4.5/10	Chưa có at-least-once bảo đảm và health reporting tin cậy
Đánh giá tổng thể: 5.8/10

Đây không còn là phiên bản sơ khai như trước; phần Core đã tiến bộ đáng kể. Tuy nhiên, ưu tiên hiện tại không nên là thêm Elasticsearch, dashboard hay nhiều Event ID hơn. Việc cần làm trước là hợp nhất luồng GUI/Silent, sửa query theo Record ID, bổ sung durable-outbox recovery và viết test chứng minh không mất/trùng log.