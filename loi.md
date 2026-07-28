Commit này đã sửa lớn Main.ps1, collector, uploader, GUI và logger. Đây là static code review; tôi chưa thể chạy integration test thật với Windows Event Log, Task Scheduler và SFTP server trong môi trường hiện tại.

1. Kết luận tổng quan mới

Phiên bản này đã tốt hơn rõ rệt:

GUI và Silent Mode dùng chung một orchestration function.
GUI đã dùng schema config mới.
Có checkpoint theo EventRecordID.
Có phân trang oldest-first sau khi đã có checkpoint.
Có .ready recovery.
Có mutex chống chạy song song.
Có queue sidecar, exponential backoff và quarantine.
SFTP đã bật host-key verification.
Logger không còn phụ thuộc trực tiếp vào RichTextBox.

Tuy nhiên, dự án vẫn chưa đạt bảo đảm at-least-once hoàn chỉnh. Tôi còn thấy ba đường có thể mất hoặc bỏ quên dữ liệu:

Lần chạy đầu có hơn 5.000 event.
Một event bị lỗi khi ghi JSONL nhưng vòng lặp nuốt exception.
Crash sau khi tạo ZIP nhưng trước khi upload hoặc đưa ZIP vào queue.

Ngoài ra, nút Preflight Check hiện gọi một function không tồn tại, nên chức năng này chắc chắn chưa chạy được.

Đánh giá hiện tại:

Hạng mục	Điểm
Kiến trúc Core	7/10
Độ tin cậy dữ liệu	5.5/10
Bảo mật	6.5/10
GUI	5/10
Queue/SFTP	6/10
Testing	3/10
Tài liệu	3.5/10
Tổng thể	6.1/10

Trạng thái phù hợp: prototype/đồ án kỹ thuật tốt, chưa nên gọi là production-ready collector.

2. Những lỗi cũ đã được sửa đúng
2.1. GUI đã dùng đúng Context

Lỗi trước đây Main.ps1 truyền nhiều parameter nhưng Show-MainWindow chỉ nhận Config đã được sửa. Hiện cả hai dùng:

Show-MainWindow -Context $Context

GUI đọc Context.Config, Context.DataDir và schema Collection.Subscriptions.

2.2. GUI và Silent Mode đã dùng chung một chu kỳ

Invoke-WinLogCollectorCycle hiện điều phối:

Retry Queue
→ Collect
→ Archive
→ Upload hoặc Queue
→ Retry Queue lần cuối

Đây là cải tiến kiến trúc đúng, tránh việc GUI dùng code cũ còn Silent Mode dùng code mới.

2.3. Sau khi có checkpoint, downtime không còn cắt mất log theo thời gian

Khi LastRecordId > 0, collector dùng XPath:

EventRecordID > LastRecordId

và không áp dụng time window. Điều này khắc phục trường hợp Task Scheduler ngừng nhiều giờ rồi chỉ đọc vài phút gần nhất.

2.4. Có khôi phục file .ready

Collector quét các file *.ready còn lại từ lần chạy trước và đưa chúng trở lại danh sách xử lý. Đây là durable-outbox recovery bước đầu.

2.5. Lỗi channel được phân biệt với “không có event”

Collector trả về:

Success
ReadyFiles
RecordCount
FailedChannels

Main chuyển channel failure thành exit code 20, thay vì coi nó như một lần chạy bình thường không có log.

2.6. Queue retry đã được tách đúng

Archive, gửi SFTP, đưa vào queue và retry là các function riêng. Retry không còn nén lại file ZIP. Sidecar cũng được ghi qua .tmp rồi rename.

2.7. Host-key verification đã được bật

Uploader hiện dùng:

StrictHostKeyChecking=yes
UserKnownHostsFile=...
BatchMode=yes

Đây là sửa đổi bảo mật đúng so với việc tự động tin mọi server.

2.8. Có mutex chống hai instance

Global\WinLogCollector ngăn hai tiến trình collector đồng thời đọc cùng checkpoint hoặc retry cùng file queue.

3. Các lỗi P0 còn tồn tại
P0.1. Nút Preflight gọi function không tồn tại

GUI gọi:

Test-WinLogCollectorPrerequisite `
    -RemoteHost ...
    -Port ...
    -SSHKeyPath ...
    -KnownHostsPath ...

Nhưng function này không tồn tại trong Main.ps1, Security.ps1, LogCollector.ps1 hay LogUploader.ps1. Security.ps1 hiện chỉ có KTADMIN và KTKN. Vì vậy bấm Preflight Check sẽ gặp lỗi “term is not recognized”.

Cần triển khai
function Test-WinLogCollectorPrerequisite {
    [CmdletBinding()]
    param(
        [hashtable]$Context
    )

    $checks = [System.Collections.Generic.List[object]]::new()

    # Config fields
    # sftp.exe
    # SSH key
    # known_hosts
    # TCP port
    # quyền ghi DataDir
    # quyền đọc từng Event Log channel
    # channel enabled
    # audit policy
    # dung lượng đĩa

    [pscustomobject]@{
        Success = -not ($checks | Where-Object Status -eq 'Failed')
        Checks  = $checks
    }
}

Function này phải được gọi cả trong GUI lẫn Silent Mode, không chỉ đặt sau một nút.

P0.2. Lần chạy đầu vẫn có thể mất event nếu vượt 5.000 bản ghi

Khi chưa có checkpoint, code hiện dùng:

Get-WinEvent `
    -FilterHashtable $filter `
    -MaxEvents $BatchSize |
    Sort-Object RecordId

Get-WinEvent mặc định trả event từ mới nhất tới cũ nhất. Vì vậy nếu khoảng fallback có 20.000 event, collector chỉ lấy 5.000 event mới nhất, sau đó sort riêng 5.000 event này và checkpoint tới Record ID cao nhất. 15.000 event cũ hơn sẽ không bao giờ được lấy lại. Microsoft cũng xác nhận Get-WinEvent mặc định trả newest-first.

Bản sửa tối thiểu
$events = Get-WinEvent `
    -FilterHashtable $filter `
    -MaxEvents $BatchSize `
    -Oldest `
    -ErrorAction Stop

Sau batch đầu tiên, vòng lặp tiếp tục bằng:

EventRecordID > lastWritten
Bản sửa tốt hơn

Dùng EventLogQuery/EventLogReader cho cả lần đầu và các lần tiếp theo, với XPath kết hợp:

TimeCreated >= InitialLookback
EventID thuộc subscription
EventRecordID > checkpoint

Như vậy chỉ có một cơ chế query, tránh hai nhánh có hành vi khác nhau.

P0.3. ZIP có thể bị bỏ quên vĩnh viễn sau crash

Luồng hiện tại:

.ready
→ New-WinLogArchive tạo ZIP
→ xóa .ready
→ Send-WinLogArchive
→ thành công: xóa ZIP
→ thất bại: chuyển ZIP vào Queue

Nếu process crash sau khi xóa .ready nhưng trước khi upload hoặc queue, file ZIP vẫn nằm trong Ready. Lần chạy sau collector chỉ quét *.ready, không quét *.zip, nên ZIP đó không bao giờ được xử lý tiếp.

Cách sửa

Đầu mỗi chu kỳ phải drain cả hai loại:

$pendingJsonl = Get-ChildItem $Context.ReadyDir -Filter '*.ready'
$pendingZips  = Get-ChildItem $Context.ReadyDir -Filter '*.zip'

Thứ tự:

1. Upload hoặc queue toàn bộ ZIP cũ
2. Archive toàn bộ JSONL ready
3. Upload ZIP mới
4. Collect batch mới
5. Drain outbox lần nữa

Tốt hơn nữa, đổi tên thư mục:

Outbox\Jsonl
Outbox\Archive
Queue
Quarantine

Mỗi file phải luôn nằm trong một trạng thái rõ ràng.

P0.4. catch {} có thể làm mất riêng một event

Trong vòng lặp ghi event:

foreach ($ev in $batch) {
    try {
        $parsed = ConvertFrom-WinEventRecord $ev
        $writer.WriteLine(...)
        $lastWritten = $ev.RecordId
    }
    catch {}
}

Giả sử event Record ID 1002 ghi lỗi, nhưng 1003 ghi thành công:

1001 → ghi được
1002 → bị bỏ qua
1003 → ghi được
checkpoint → 1003

Event 1002 sau đó bị checkpoint vượt qua và mất vĩnh viễn.

Nguyên tắc sửa

Không được tiếp tục sang Record ID cao hơn nếu một record chưa được durable-write.

foreach ($ev in $batch) {
    try {
        $parsed = ConvertFrom-WinEventRecord -EventRecord $ev
        $json = $parsed | ConvertTo-Json -Depth 10 -Compress
        $writer.WriteLine($json)

        $lastWritten = $ev.RecordId
        $count++
    }
    catch {
        $channelError = "RecordId $($ev.RecordId): $($_.Exception.Message)"
        break
    }
    finally {
        $ev.Dispose()
    }
}

if ($channelError) {
    break
}

Parser đã có fallback object khi parse XML lỗi, nên lỗi lọt tới outer catch thường là lỗi serialization, writer hoặc tài nguyên. Khi đó nên dừng batch thay vì bỏ qua.

P0.5. EventRecord không được dispose

Code dispose EventLogReader, nhưng từng object $ev được giữ trong list và không được Dispose(). EventRecord triển khai IDisposable và Microsoft mô tả Dispose() dùng để giải phóng tài nguyên của object. Với backlog lớn, điều này có thể tạo áp lực native handles và bộ nhớ.

Giải pháp tốt hơn là không trả nguyên EventRecord ra list. Đọc, parse, serialize và dispose từng event ngay trong vòng lặp streaming.

P0.6. Queue đầy chỉ được cảnh báo, không thực sự “đóng băng”

Code ghi:

if ($queueSizeMB -gt $MaxSizeMB) {
    AddLog "... Dinh hoa quy trinh thu thap moi."
}

Nhưng sau cảnh báo, Main vẫn tiếp tục thu thập và tạo thêm log. Vì vậy nhận xét trong comment “Queue policy enforcement” chưa đúng với hành vi thực tế.

Cần trả trạng thái rõ ràng
return @{
    Success    = $false
    QueueFull  = $true
    QueueSizeMB = $queueSizeMB
    Sent       = 0
    Failed     = $zips.Count
}

Main:

$retry1 = Retry-WinLogQueue ...

if ($retry1.QueueFull) {
    AddLog 'Queue đầy. Tạm dừng thu thập để bảo vệ ổ đĩa.' 'ERROR'

    return [pscustomobject]@{
        Success  = $false
        ExitCode = 50
    }
}
P0.7. Kết quả retry bị Main bỏ qua

Main lưu:

$retry1 = Retry-WinLogQueue ...
$retry2 = Retry-WinLogQueue ...

nhưng không dùng Success, Failed hoặc Sent để tính exitCode. Hệ quả:

Queue cũ gửi thất bại nhưng task vẫn có thể trả exit code 0.
Upload mới thất bại, được retry thành công ngay sau đó, nhưng exit code vẫn giữ 40.
Trạng thái GUI/Scheduler không phản ánh trạng thái queue thật.

Kết quả chu kỳ cần chứa:

Queued
PendingQueue
SentFromQueue
Quarantined
QueueFull
FailedChannels

Success nên dựa trên health policy, không chỉ dựa trên upload vừa tạo trong chu kỳ hiện tại.

P0.8. MaxAgeDays có trong config nhưng hoàn toàn chưa được dùng

Config khai báo:

"MaxAgeDays": 14

Main cũng đọc giá trị này, nhưng Retry-WinLogQueue không có parameter MaxAgeDays và không kiểm tra tuổi archive.

Cần chọn policy rõ ràng:

Quá MaxAgeDays
→ chuyển Quarantine
→ ghi operational alert
→ tuyệt đối không xóa im lặng
4. Những vấn đề P1 cần cải tiến
4.1. GUI vẫn bị block

System.Windows.Forms.Timer.Tick và button click gọi trực tiếp toàn bộ chu kỳ collector, nén và SFTP ngay trên UI thread. Khi Get-WinEvent, Compress-Archive hoặc SFTP chậm, cửa sổ sẽ “Not Responding”. Nút Stop chỉ dừng timer kế tiếp, không hủy chu kỳ đang chạy.

Nên dùng background runspace hoặc tách GUI khỏi agent:

GUI
  → đọc config và trạng thái
  → gửi lệnh chạy

Agent/Scheduled Task
  → collect
  → checkpoint
  → outbox
  → SFTP
4.2. Security.ps1 vẫn là legacy code

File này còn:

KTADMIN.
ExecutionPolicy Bypass.
Ping thay vì SFTP preflight.
Parameter kiểu System.Windows.Forms.RichTextBox.
Function KTKN trùng tên với function trong LogUploader.ps1.

Main dot-source Security.ps1 trước khi nạp WinForms, nên Silent Mode vẫn còn dependency GUI không cần thiết; function KTKN sau đó còn bị uploader định nghĩa đè.

Nên xóa file cũ và thay bằng:

Test-WinLogCollectorPrivilege
Test-WinLogCollectorPrerequisite
Test-WinLogChannelAccess
Test-SftpConfiguration

Tất cả phải độc lập WinForms.

4.3. State hỏng bị âm thầm coi như chưa từng chạy
try {
    ConvertFrom-Json
}
catch {}

return @{}

Nếu state.json bị hỏng, collector reset checkpoint và có thể thu thập trùng dữ liệu mà không phát cảnh báo.

Nên:

state.json parse lỗi
→ copy sang state.corrupt.<timestamp>.json
→ không ghi đè ngay
→ trả trạng thái Degraded hoặc Failed
4.4. Chưa phát hiện Event Log clear hoặc rollover

Nếu Windows Event Log bị clear và Record ID bắt đầu lại thấp hơn checkpoint, query:

EventRecordID > checkpoint-cũ

có thể không trả event mới trong thời gian dài.

Cần lưu thêm:

LogCreationTime
OldestRecordNumber
NewestRecordNumber
LogFileId/generation

Khi currentNewestRecordId < checkpoint, phải:

Ghi cảnh báo log reset.
Tạo generation mới.
Khởi tạo lại checkpoint theo policy.
Không âm thầm coi là “không có event”.
4.5. Một backlog lớn bị ghi vào duy nhất một file

Mặc dù mỗi query lấy 5.000 event, vòng while tiếp tục ghi mọi page vào cùng một .jsonl.tmp. Nếu backlog có hàng triệu event, file có thể rất lớn và một chu kỳ chạy quá lâu.

Nên rotate theo điều kiện:

50.000 record
hoặc 100 MB
hoặc 5 phút collection

Mỗi phần có checkpoint/manifest riêng.

4.6. Manifest chưa phản ánh batch thực tế

Collector tạo một batchId trong tên JSONL, nhưng archive tạo batchId mới. Main không truyền StartUtc/EndUtc, nên hai giá trị mặc định gần như là thời điểm nén, không phải thời gian event đầu và cuối. Manifest cũng chưa có channel, first/last Record ID hoặc collector batch ID.

Nên truyền metadata xuyên suốt:

{
  "batchId": "...",
  "agentId": "...",
  "channel": "Security",
  "firstRecordId": 1001,
  "lastRecordId": 1500,
  "firstEventTimeUtc": "...",
  "lastEventTimeUtc": "...",
  "recordCount": 500,
  "sha256": "..."
}
4.7. Lệnh SFTP cần được kiểm thử lại cách quote argument

Mảng $sftpArgs tự chèn dấu nháy vào SSHKeyPath, KnownHostsPath và batch-file path:

'-i', "`"$SSHKeyPath`""
'-b', "`"$sftpPath`""

Khi gọi native executable bằng argument array, việc tự chèn dấu nháy như vậy dễ tạo khác biệt giữa Windows PowerShell 5.1 và PowerShell 7, đặc biệt với đường dẫn có dấu cách.

Nên truyền giá trị thô:

$sftpArgs = @(
    '-o', 'StrictHostKeyChecking=yes'
    '-o', "UserKnownHostsFile=$KnownHostsPath"
    '-o', 'BatchMode=yes'
    '-o', 'ConnectTimeout=15'
    '-P', $Port
    '-i', $SSHKeyPath
    '-b', $sftpPath
    "$User@$RemoteHost"
)

Sau đó viết integration test với đường dẫn chứa khoảng trắng.

4.8. SFTP chưa thật sự idempotent

Nếu server đã rename .part thành file cuối nhưng client mất kết nối trước khi nhận exit code thành công, client có thể đưa archive vào queue. Retry sau đó gặp file cuối đã tồn tại và có thể thất bại liên tục dù server đã nhận đủ dữ liệu.

Cần một trong các giải pháp:

Tên archive immutable bằng Batch ID và server deduplicate.
Server trả acknowledgement theo Batch ID.
Trước retry, kiểm tra file đích và checksum.
Ingestion server lưu batchId unique.
4.9. Sidecar hỏng chưa được xử lý rõ

Nếu .queue.json không parse được, code coi metadata là $null và bắt đầu lại từ attempt 1. Lịch sử retry và tuổi file bị mất.

Nên chuyển cả ZIP và sidecar lỗi sang Quarantine, hoặc reconstruct metadata dựa trên file creation time và ghi cảnh báo rõ ràng.

4.10. Kiểm tra “No events” phụ thuộc ngôn ngữ hệ điều hành

Code kiểm tra:

$_.Exception.Message -match 'No events'

Trên Windows dùng locale khác tiếng Anh, message có thể không chứa chuỗi này và một channel không có event sẽ bị đánh dấu lỗi.

Nên kiểm tra exception type, native error code hoặc dùng query API trả $null, không parse nội dung message.

4.11. Mutex có race nhỏ khi elevation

Process thường đang giữ mutex, gọi Start-Process -Verb RunAs, rồi mới release mutex. Elevated process có thể khởi động nhanh hơn và thấy mutex đang tồn tại, sau đó exit code 12.

Nên kiểm tra elevation trước khi acquire mutex, hoặc release mutex trước Start-Process.

Ngoài ra Silent Mode release mutex trước exit, rồi finally lại release lần nữa. Exception đang bị nuốt nên chưa gây crash, nhưng logic lifecycle không sạch.

5. Testing và CI hiện chưa bảo vệ project

Repo hiện không có thư mục tests/, nhưng CI chỉ in:

No tests directory found.

và vẫn thành công. Vì vậy badge CI, nếu xanh, chưa chứng minh collector hoạt động đúng.

CI phải fail khi không có test:

if (-not (Test-Path tests)) {
    throw 'tests directory is required.'
}

$result = Invoke-Pester -Path tests -PassThru

if ($result.TotalCount -eq 0 -or $result.FailedCount -gt 0) {
    exit 1
}
Bộ test bắt buộc
Collector invariant
Lần đầu có 12.000 event → thu đủ 12.000
Checkpoint 5.000 → chỉ lấy Record ID > 5.000
Một event serialize lỗi → không checkpoint vượt qua event đó
Channel không có event → Success, count 0
Channel không có quyền → FailedChannels chứa channel
Crash recovery
Crash sau .tmp
Crash sau .ready
Crash sau tạo ZIP
Crash sau xóa .ready
Crash sau upload .part
Crash sau remote rename

Sau mỗi tình huống phải chứng minh:

Không mất batch
Không bỏ quên file
Duplicate có thể nhận biết bằng Batch ID
Queue
Queue vượt MaxSizeMB
File quá MaxAgeDays
Sidecar hỏng
Quá MaxAttempts
SFTP offline rồi online lại
Remote file đã tồn tại
6. README hiện vẫn mô tả phiên bản cũ

README còn hướng dẫn:

FolderLuuLog.
EventChannels.
HiddenLogs.
Ping kiểm tra SFTP.
StrictHostKeyChecking=no.
ExecutionPolicy Bypass.
Clone URL chứa <username>.
Limited Mode chọn chính xác khoảng A–B, trong khi GUI hiện chỉ có “Thu thập ngay”.

Những mô tả này mâu thuẫn trực tiếp với config và code hiện tại. Đặc biệt README vẫn giới thiệu StrictHostKeyChecking=no, trong khi uploader mới đã chuyển sang yes.

README cần viết lại hoàn toàn cho v0.3.1, không nên tiếp tục vá vài dòng trên tài liệu cũ.

7. Cấu trúc repo vẫn còn source cũ ở root

Mặc dù đã có thư mục archive, file monolithic:

CT491_B2203708_PhanThanhBinh.ps1

vẫn nằm ngay root cạnh Main.ps1. Điều này tiếp tục tạo hai ứng viên “entry point” và có thể làm người review hoặc người dùng chạy nhầm phiên bản.

Nên:

archive/legacy/CT491_B2203708_PhanThanhBinh.ps1

và root chỉ còn một entry point:

Main.ps1
8. Thứ tự sửa hợp lý tiếp theo
Nhóm 1 — Chống lỗi chạy và mất dữ liệu
Viết Test-WinLogCollectorPrerequisite.
Thêm -Oldest cho lần chạy đầu.
Drain cả *.ready và *.zip.
Xóa toàn bộ catch {} trong đường dữ liệu.
Dispose từng EventRecord.
Dừng collection khi queue đầy.
Dùng kết quả retry để tính health và exit code.
Nhóm 2 — Hoàn thiện transaction pipeline
Một Batch ID xuyên suốt.
Rotate file theo count/size.
Detect Event Log clear/rollover.
State corruption recovery.
MaxAgeDays và corrupt-sidecar policy.
SFTP idempotency.
Accurate manifest.
Nhóm 3 — Vận hành và chất lượng dự án
Tách GUI khỏi UI thread.
Xóa Security.ps1 legacy.
Config JSON Schema.
Pester unit và integration tests.
CI fail khi không có test.
Viết lại README.
Chuyển script monolithic khỏi root.