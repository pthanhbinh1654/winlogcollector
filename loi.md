Đánh giá tổng quan

WinLogCollector hiện là một prototype khá tốt cho đồ án CT491, vì đã có:

Thu thập bằng Get-WinEvent.
Hai chế độ Limited/Continuous.
Tách bước thu thập, nén, gửi SFTP và GUI.
Có silent mode để chạy bằng Task Scheduler.
Có ý tưởng offline queue.

Tuy nhiên, dự án chưa đủ an toàn và tin cậy để gọi là agent thu thập log hoàn chỉnh. Tôi đánh giá:

Ý tưởng và phạm vi: 7/10
Tổ chức code: 6/10
Độ tin cậy dữ liệu: 4/10
Bảo mật: 3.5/10
Khả năng bảo trì và kiểm thử: 3/10

Nguyên nhân chính là một số cấu hình không được sử dụng, retry queue đang có lỗi logic, dữ liệu Event Log được parse bằng vị trí mảng không ổn định, GUI chạy toàn bộ tác vụ nặng trên UI thread và chưa có checkpoint chống mất/trùng log.

I. Các lỗi cần sửa ngay – P0
1. Retry queue đang dùng sai hàm

GUILOGCHOGUI tìm các file .zip, sau đó truyền file .zip vào GUILOGSSH. Nhưng GUILOGSSH luôn thực hiện:

$TenZip = [System.IO.Path]::ChangeExtension($TenFile, ".zip")
Compress-Archive -Path $DuongDanLog -DestinationPath $DuongDanZip -Force

Khi đầu vào đã là .zip, đường dẫn nguồn và đích có thể trở thành cùng một file. Kết quả là retry có thể lỗi khi nén, ghi đè hoặc không gửi được file đang chờ.

Cách sửa đúng

Tách thành bốn hàm độc lập:

New-WinLogArchive
Send-WinLogArchive
Move-WinLogArchiveToQueue
Retry-WinLogQueue

Luồng xử lý:

JSONL
  │
  ├── New-WinLogArchive
  ▼
ZIP
  │
  ├── Send-WinLogArchive thành công ──► xóa local
  │
  └── thất bại ──► Move-WinLogArchiveToQueue
                        │
                        └── Retry-WinLogQueue chỉ gửi, không nén lại

Send-WinLogArchive phải từ chối đầu vào không phải .zip:

function Send-WinLogArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            (Test-Path $_ -PathType Leaf) -and
            ([IO.Path]::GetExtension($_) -eq '.zip')
        })]
        [string]$ArchivePath
    )

    # Chỉ upload, tuyệt đối không Compress-Archive ở đây.
}
2. RemotePath trong config không được sử dụng

Config khai báo:

"RemotePath": "/home/sftp/uploads"

Nhưng trong GUILOGSSH, giá trị này bị bỏ qua và đường dẫn bị ghi đè:

$RemotePath = if ($Mode -eq "Limited") {
    "/limited"
} else {
    "/continuous"
}

Như vậy người dùng nhập /home/sftp/uploads trong GUI cũng không có tác dụng.

Cách sửa
$baseRemotePath = $DuongDanRemote.TrimEnd('/')
$modeFolder = $Mode.ToLowerInvariant()
$RemotePath = "$baseRemotePath/$modeFolder"

Ví dụ kết quả:

/home/sftp/uploads/limited
/home/sftp/uploads/continuous

Nên đổi tên biến từ $DuongDanRemote thành $RemoteBasePath để tránh nhầm.

3. Đang tắt xác thực danh tính máy chủ SFTP

Code sử dụng:

-o StrictHostKeyChecking=no

Điều này cho phép kết nối tới server mà không kiểm tra host key, làm mất khả năng phát hiện server giả mạo hoặc tấn công trung gian. README hiện còn đưa tùy chọn này vào phần “Bảo mật”, đây là mô tả không đúng. OpenSSH hỗ trợ cơ sở dữ liệu host key qua known_hosts và tùy chọn UserKnownHostsFile.

Cách sửa

Thêm vào config:

"Remote": {
  "Host": "192.168.1.2",
  "Port": 22,
  "User": "sftp",
  "SSHKeyPath": "C:\\ProgramData\\WinLogCollector\\keys\\collector_ed25519",
  "KnownHostsPath": "C:\\ProgramData\\WinLogCollector\\ssh\\known_hosts",
  "RemotePath": "/home/sftp/uploads"
}

Và dùng:

$sftpArgs = @(
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$KnownHostsPath",
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=15',
    '-i', $SSHKeyPath,
    '-b', $batchFile,
    "$User@$RemoteHost"
)

Host key cần được thêm trong bước cài đặt và kiểm tra fingerprint bằng kênh độc lập, không tự động tin mọi key mới.

4. EventIDs có trong config nhưng collector không dùng

Config chứa:

"EventIDs": [4624, 4688, 4104]

Nhưng THUTHAPLOG chỉ lọc theo LogName, StartTime, EndTime. Vì vậy chương trình đang lấy toàn bộ sự kiện trong các channel, làm tăng dữ liệu, RAM, dung lượng và thời gian upload. Get-WinEvent -FilterHashtable hỗ trợ trực tiếp khóa Id dạng mảng.

Cách sửa

Thêm parameter:

[int[]]$EventIDs

Sau đó:

$filter = @{
    LogName   = $channel
    StartTime = $StartTime
    EndTime   = $EndTime
}

if ($EventIDs.Count -gt 0) {
    $filter.Id = $EventIDs
}

Đồng thời truyền từ Main.ps1:

THUTHAPLOG `
    -EventChannels $ConfigHT.Collection.EventChannels `
    -EventIDs $ConfigHT.Collection.EventIDs
5. Dự án tuyên bố hỗ trợ Event ID 4104 nhưng không thu thập đúng channel

Event 4104 nằm trong:

Microsoft-Windows-PowerShell/Operational

và cần bật Script Block Logging. Trong khi project chỉ đọc:

Application
Security
System
Setup

Do đó Continuous Mode hiện không thể lấy 4104 như README mô tả.

Config đúng hơn
"Collection": {
  "Subscriptions": [
    {
      "Channel": "Security",
      "EventIDs": [4624, 4625, 4634, 4647, 4688, 1102]
    },
    {
      "Channel": "Microsoft-Windows-PowerShell/Operational",
      "EventIDs": [4103, 4104]
    },
    {
      "Channel": "System",
      "EventIDs": [6005, 6006, 6008, 7045]
    }
  ]
}

Mô hình Subscription tốt hơn một mảng Event ID dùng chung vì mỗi Event ID thuộc một channel khác nhau.

6. Parse Event Log bằng chỉ số Properties[] rất dễ sai

Hiện tại project dùng:

4624 = @{
    "AccountName" = 5
    "LogonType"   = 10
}

và gán:

ProcessID = $log.Properties[0].Value

Có hai vấn đề:

Thứ tự Properties[] phụ thuộc schema và version của event.
Properties[0] không mặc định là Process ID. EventLogRecord đã có property ProcessId, còn toàn bộ dữ liệu đầy đủ có thể lấy bằng ToXml().

Ví dụ với 4624, LogonType không nên được lấy bằng index cố định 10. Hãy đọc theo tên trường trong XML.

Parser ổn định hơn
function ConvertFrom-WinEventRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$EventRecord
    )

    [xml]$xml = $EventRecord.ToXml()
    $eventData = [ordered]@{}

    foreach ($node in @($xml.Event.EventData.Data)) {
        $name = $node.GetAttribute('Name')

        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "Data$($eventData.Count)"
        }

        $eventData[$name] = [string]$node.'#text'
    }

    [pscustomobject]@{
        SchemaVersion     = '1.0'
        RecordId          = $EventRecord.RecordId
        TimeCreatedUtc    = $EventRecord.TimeCreated.ToUniversalTime().ToString('o')
        EventId           = $EventRecord.Id
        Version           = $EventRecord.Version
        Level             = $EventRecord.Level
        LevelDisplayName  = $EventRecord.LevelDisplayName
        ProviderName      = $EventRecord.ProviderName
        ProviderId        = $EventRecord.ProviderId
        Channel           = $EventRecord.LogName
        Computer          = $xml.Event.System.Computer
        ProviderProcessId = $EventRecord.ProcessId
        SystemUserSid     = if ($EventRecord.UserId) {
            $EventRecord.UserId.Value
        } else {
            $null
        }
        ActivityId        = $EventRecord.ActivityId
        RelatedActivityId = $EventRecord.RelatedActivityId
        EventData         = $eventData
        Message           = $EventRecord.Message
        RawXml            = $EventRecord.ToXml()
    }
}

Lưu ý: ProviderProcessId là process đã ghi sự kiện. Với Event 4688, PID của tiến trình mới phải lấy từ trường XML có tên như NewProcessId.

7. Chưa có checkpoint đáng tin cậy, có thể mất hoặc trùng log

Continuous Mode dùng thời gian cuối:

$global:LastLogtime = $TGKT.AddMilliseconds(1)

Cách này có các rủi ro:

Nhiều event có cùng timestamp ở biên.
Event được ghi trễ nhưng có thời gian cũ hơn checkpoint.
Chương trình crash trước khi cập nhật trạng thái.
Hai Task Scheduler instance chạy chồng nhau.
Log bị clear làm Record ID thay đổi.

Project đã lưu RecordID, nhưng chưa dùng nó để checkpoint.

Giải pháp

Lưu state riêng cho từng channel:

{
  "Security": {
    "LastRecordId": 182733,
    "LastEventTimeUtc": "2026-07-28T08:30:00.0000000Z"
  },
  "System": {
    "LastRecordId": 55210,
    "LastEventTimeUtc": "2026-07-28T08:30:01.0000000Z"
  }
}

Nguyên tắc:

Thu thập sau LastRecordId.
Ghi file tạm.
Flush và đóng file.
Tạo checksum.
Đưa file vào queue.
Chỉ sau đó mới cập nhật checkpoint bằng thao tác atomic.

Nên phát hiện:

CurrentRecordId < LastRecordId

để xử lý trường hợp log đã bị clear hoặc rollover.

8. GUI có thể bị treo và nút Stop không dừng được tác vụ đang chạy

Các lệnh sau đều được gọi trực tiếp trong Click hoặc Windows.Forms.Timer.Tick:

Get-WinEvent
Compress-Archive
sftp.exe
Đọc và sort toàn bộ events

System.Windows.Forms.Timer thực thi trên UI thread. Khi một lần thu thập kéo dài, cửa sổ không phản hồi và người dùng không thể bấm Stop. Nút Stop hiện chỉ ngừng các tick kế tiếp, không hủy được lần thu thập/upload đang chạy.

Kiến trúc phù hợp hơn
GUI
 └── chỉ sửa config, xem trạng thái và gửi lệnh

Collector Agent
 ├── chạy bằng Scheduled Task hoặc Windows Service
 ├── checkpoint
 ├── queue
 └── persistent operational log

Core Module
 ├── event query
 ├── normalization
 ├── archive
 └── SFTP transport

Trong bản PowerShell GUI, có thể dùng runspace hoặc BackgroundWorker. Tuy nhiên, hướng tốt nhất là không để GUI sở hữu vòng đời collector.

9. Silent Mode chưa thật sự đáng tin cậy

Silent Mode hiện:

Chỉ thu thập một khoảng bằng DefaultIntervalMinutes.
Không gửi lại toàn bộ queue cũ.
Không dùng DefaultDurationMinutes.
Không kiểm tra kết quả trả về từ upload.
Có thể kết thúc với exit code 0 dù upload thất bại.
Khi thiếu quyền, nó cố mở UAC thay vì fail rõ ràng cho Task Scheduler.
Cách sửa

Silent Mode nên trả exit code rõ ràng:

0  = thành công
10 = config không hợp lệ
20 = không đọc được Event Log
30 = tạo archive thất bại
40 = upload thất bại nhưng đã queue an toàn
50 = mất dữ liệu hoặc queue thất bại

Luồng đúng:

Retry-WinLogQueue
Invoke-WinLogCollection
Retry-WinLogQueue
exit $result.ExitCode

Trong Silent Mode, thiếu quyền phải:

Write-Error 'Administrator privilege is required.'
exit 11

Không nên mở hộp thoại UAC trong tiến trình unattended.

10. Kiểm tra bằng ping không phải kiểm tra SFTP

KTKN chỉ dùng Test-Connection. Ping thành công không chứng minh port 22 hoặc SFTP đang hoạt động; ngược lại, server có thể chặn ICMP nhưng SFTP vẫn hoạt động.

Thay bằng:

Test-NetConnection `
    -ComputerName $RemoteHost `
    -Port $Port `
    -InformationLevel Quiet

Tốt hơn nữa: bỏ pre-check và thử chính lệnh SFTP, vì đó mới là phép kiểm tra end-to-end về DNS, TCP, host key và authentication.

II. Các cải tiến về độ tin cậy dữ liệu – P1
11. Không nên giữ toàn bộ logs trong RAM rồi mới sort

Code đang:

$Logs = @()
$Logs += Get-WinEvent ...
$Logs = $Logs | Sort-Object TimeCreated

+= với mảng tạo lại mảng nhiều lần, còn sort toàn bộ events có thể tiêu tốn nhiều RAM khi người dùng chọn khoảng thời gian dài. Collector cũng chưa có MaxEvents, giới hạn kích thước hay chia lô. Get-WinEvent hỗ trợ MaxEvents và lọc từ phía Event Log service.

Nên:

Truy vấn từng channel.
Stream từng event trực tiếp ra JSONL.
Chia file theo số record hoặc kích thước.
Ví dụ: tối đa 50.000 record hoặc 100 MB/archive.
Không global sort nếu không thật sự cần; SIEM có thể sắp theo timestamp.
12. File hiện là JSON Lines nhưng dùng đuôi .json

Mỗi event được ghi bằng một dòng JSON độc lập:

$writer.WriteLine($LogEntry | ConvertTo-Json -Compress)

Đây là NDJSON/JSONL, không phải một JSON document dạng array. Nhiều hệ thống đọc JSON thông thường sẽ báo lỗi khi gặp nhiều object liên tiếp.

Nên đổi thành:

*.jsonl

và ghi rõ trong README:

Content-Type: application/x-ndjson
Encoding: UTF-8
One event per line
13. Cần ghi file theo kiểu atomic

Hiện writer mở trực tiếp file đích ở append mode. Nếu process crash, file một phần vẫn tồn tại và có thể được upload. Writer cũng không nằm trong finally, nên exception giữa vòng lặp có thể để file chưa được đóng đúng cách.

Cách an toàn:

events.jsonl.tmp
   │
   ├── ghi dữ liệu
   ├── flush
   ├── close
   ├── validate record count
   └── rename atomic
        ▼
events.jsonl.ready

Uploader chỉ được lấy file có trạng thái .ready.

14. Tên file có thể trùng giữa nhiều máy

Tên hiện tại gần giống:

Continuous_2026-07-28_153000.zip

Hai máy gửi cùng thời điểm vào cùng folder SFTP có thể tạo cùng tên và ghi đè lẫn nhau.

Nên dùng:

<HostId>_<Channel>_<StartUtc>_<EndUtc>_<BatchId>.jsonl.zip

Ví dụ:

PC-BINH_Security_20260728T080000Z_20260728T080300Z_8f4d2b.zip

BatchId dùng GUID hoặc ULID.

15. Cần manifest và checksum

Mỗi archive nên chứa:

events.jsonl
manifest.json

Ví dụ manifest:

{
  "schemaVersion": "1.0",
  "collectorVersion": "0.3.0",
  "batchId": "8f4d2b90-29b0-44b9-baca-ae3af37c7875",
  "host": "PC-BINH",
  "channel": "Security",
  "startUtc": "2026-07-28T08:00:00Z",
  "endUtc": "2026-07-28T08:03:00Z",
  "firstRecordId": 180001,
  "lastRecordId": 180594,
  "recordCount": 594,
  "eventFileSha256": "..."
}

Server dùng BatchId để deduplicate và SHA-256 để kiểm tra toàn vẹn.

16. Upload cần giao thức “temporary then rename”

Không nên upload trực tiếp tên cuối. Nếu đường truyền ngắt, server có thể giữ file chưa hoàn chỉnh.

Luồng nên là:

put batch.zip batch.zip.part
verify
rename batch.zip.part batch.zip

Chỉ file không có .part mới được ingestion worker xử lý.

17. Queue cần metadata, backoff và giới hạn dung lượng

Hiện queue chỉ là một thư mục chứa .zip. Chưa có:

Số lần thử.
Lỗi gần nhất.
Thời điểm thử tiếp theo.
Giới hạn dung lượng.
Retention.
Dead-letter/quarantine.

Nên có sidecar:

batch.zip
batch.queue.json
{
  "attempt": 4,
  "createdUtc": "2026-07-28T08:00:00Z",
  "nextAttemptUtc": "2026-07-28T08:31:00Z",
  "lastError": "Connection timeout",
  "state": "Pending"
}

Backoff:

1 phút → 2 → 5 → 15 → 30 → 60 phút

Thêm:

"Queue": {
  "MaxSizeMB": 2048,
  "MaxAgeDays": 14,
  "MaxAttempts": 20
}

Sau quá số lần thử, chuyển sang Quarantine/, không xóa âm thầm.

III. Bảo mật và forensic
18. “HiddenLogs” không phải cơ chế bảo mật

Đặt thuộc tính Hidden chỉ làm thư mục ít xuất hiện trong Explorer; người dùng có quyền vẫn có thể đọc dữ liệu. Trong log có thể chứa username, command line và toàn bộ PowerShell script block. Đặc biệt Microsoft lưu ý command line của Event 4688 có thể chứa dữ liệu riêng tư hoặc credential ở dạng rõ.

Nên lưu tại:

C:\ProgramData\WinLogCollector\

với ACL chỉ cho:

SYSTEM
Administrators
WinLogCollector service account

Có thể bổ sung:

Mã hóa queue bằng CMS hoặc certificate của server.
Xóa file plaintext ngay sau khi tạo archive mã hóa.
Không lưu tại C:\HiddenLogs.
Không hiển thị toàn bộ command line hoặc script content trên GUI mặc định.
19. Chạy toàn bộ chương trình với Administrator là quá rộng

Main.ps1 luôn yêu cầu elevation trước khi biết người dùng muốn đọc channel nào. Trong thực tế, không phải mọi channel đều cần quyền Administrator.

Nên:

Chạy GUI bằng quyền thường.
Preflight từng subscription.
Chỉ agent/service account có quyền Event Log Readers hoặc quyền cụ thể.
Chỉ yêu cầu Administrator trong bước cài đặt service, ACL và audit policy.
20. Không nên dùng ExecutionPolicy Bypass như hướng dẫn mặc định

README và code tự elevation đều dùng -ExecutionPolicy Bypass. Microsoft nêu rõ execution policy chỉ là safety feature, không phải security boundary; Bypass làm mất toàn bộ cảnh báo và kiểm tra trong session đó.

Cho bản release nên:

Ký script bằng code-signing certificate.
Dùng RemoteSigned hoặc AllSigned tùy môi trường.
Phát hành checksum cho release.
Không tự động thêm Bypass trong Start-Process.
Task Scheduler chạy script đã được cài đặt và xác minh.
21. Cần preflight audit policy

Có Event ID trong code không có nghĩa Windows sẽ sinh event đó.

Ví dụ:

4688 cần bật Audit Process Creation.
Trường Command Line của 4688 cần bật Include command line in process creation events; mặc định trường này rỗng.
4104 cần Script Block Logging và đúng Operational channel.

Thêm lệnh:

Test-WinLogCollectorPrerequisite

Nó nên kiểm tra:

[OK] Security channel readable
[OK] Audit Process Creation enabled
[WARN] 4688 CommandLine policy disabled
[WARN] PowerShell Script Block Logging disabled
[OK] Microsoft-Windows-PowerShell/Operational enabled
[OK] SFTP client exists
[OK] SSH private key ACL
[OK] Server host key trusted
[OK] Queue has sufficient free disk
IV. Chất lượng code và cấu trúc project
22. Loại bỏ file script cũ gần 1.000 dòng

Repo đang giữ đồng thời:

CT491_B2203708_PhanThanhBinh.ps1
Main.ps1 + src/*

Script cũ chứa logic trùng với bản modular, bao gồm collector, uploader, GUI và các biến global. Người sửa dễ chỉnh một bản nhưng chạy bản còn lại. Repo hiện chỉ có một commit nên chưa có lịch sử rõ ràng để phân biệt phiên bản.

Giải pháp:

Xóa file cũ khỏi main.
Gắn tag trước khi xóa, ví dụ legacy-v1.
Hoặc chuyển sang archive/legacy/ và ghi rõ “DO NOT USE”.
README chỉ để một entry point duy nhất.
23. Chuyển từ dot-source sang PowerShell module

Hiện tại Main.ps1 dot-source bốn file. Nên tạo:

WinLogCollector.psd1
WinLogCollector.psm1

Tên hàm theo chuẩn Verb-Noun:

Get-WinLogBatch
Convert-WinEventRecord
New-WinLogArchive
Send-WinLogArchive
Retry-WinLogQueue
Test-WinLogCollectorConfiguration
Get-WinLogCollectorStatus

Thay cho:

THUTHAPLOG
GUILOGSSH
GUILOGCHOGUI
KTKN

Thêm:

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    ...
)

Tránh $global:; truyền context hoặc state object giữa các hàm.

24. Hàm hiện nuốt lỗi quá nhiều

Ví dụ:

catch {
    return $false
}

và:

-ErrorAction SilentlyContinue
catch { continue }

làm mất thông tin channel nào thất bại và nguyên nhân gì. Với SilentlyContinue, lỗi không terminating thường còn không đi vào catch.

Nên trả kết quả có cấu trúc:

[pscustomobject]@{
    Success    = $false
    Operation  = 'Upload'
    BatchId    = $BatchId
    ErrorCode  = 'SFTP_AUTH_FAILED'
    Error      = $_.Exception.Message
    Timestamp  = [DateTime]::UtcNow
}

Và dùng:

-ErrorAction Stop

sau đó log rõ channel hoặc file bị lỗi.

25. Logger cần ghi persistent log

Silent Mode hiện chỉ ghi stdout. Khi Task Scheduler chạy nền, việc truy vết lỗi rất khó.

Nên ghi:

C:\ProgramData\WinLogCollector\Logs\collector-2026-07-28.log

Với:

Rotation theo ngày.
Giới hạn số ngày.
JSON structured logging.
Correlation/Batch ID.
Không ghi private key hoặc toàn bộ command line nhạy cảm.

Ví dụ:

{
  "timestampUtc": "2026-07-28T08:15:00Z",
  "level": "Error",
  "operation": "Upload",
  "batchId": "8f4d2b",
  "errorCode": "SFTP_TIMEOUT",
  "message": "Connection timed out"
}
26. Config cần schema và file example

config.json hiện chứa đường dẫn riêng của máy cá nhân:

C:\Users\Binh\.ssh\sftp_id_rsa

và không có validation. .gitignore lại bỏ qua toàn bộ *.json, ngoại trừ config.json, nên sau này khó commit JSON Schema hoặc fixtures test.

Nên dùng:

config/config.example.json
config/config.local.json
config/config.schema.json

.gitignore:

config/config.local.json
runtime/
queue/
logs/
*.zip
*.jsonl
*.tmp

Không nên ignore toàn bộ *.json.

V. Những thiếu sót ở cấp độ dự án
27. Chưa có test và CI

Repo chưa có tests/ hoặc workflow GitHub Actions; trang Actions chưa có workflow chạy. PSScriptAnalyzer có thể phát hiện parser error, biến chưa khởi tạo, Invoke-Expression và nhiều lỗi PowerShell phổ biến.

Nên bổ sung:

tests/
├── Unit/
│   ├── LogCollector.Tests.ps1
│   ├── EventParser.Tests.ps1
│   ├── LogUploader.Tests.ps1
│   ├── Queue.Tests.ps1
│   └── Config.Tests.ps1
├── Integration/
│   ├── WindowsEventLog.Tests.ps1
│   └── Sftp.Tests.ps1
└── Fixtures/
    ├── event-4624-v2.xml
    ├── event-4688-v2.xml
    └── event-4104.xml

CI tối thiểu:

name: PowerShell CI

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: windows-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install tooling
        shell: powershell
        run: |
          Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
          Install-Module Pester -Force -Scope CurrentUser

      - name: Static analysis
        shell: powershell
        run: |
          $issues = Invoke-ScriptAnalyzer -Path . -Recurse
          $issues | Format-Table
          if ($issues.Where({ $_.Severity -eq 'Error' })) {
              exit 1
          }

      - name: Unit tests
        shell: powershell
        run: |
          Invoke-Pester -Path tests -CI
28. README đang có nhiều thông tin chưa khớp code

Các điểm cần sửa:

Clone URL vẫn là github.com/<username>/WinLogCollector.git.
Giao diện ghi github.com/B2203708, không phải repo hiện tại.
Tuyên bố hỗ trợ 4104 nhưng không có channel tương ứng.
Tuyên bố RemotePath cấu hình được nhưng code bỏ qua.
Gọi StrictHostKeyChecking=no là bảo mật.
Tuyên bố giảm băng thông khoảng 70% nhưng không có benchmark.
Tuyên bố MIT nhưng file LICENSE không tồn tại; link LICENSE hiện trả 404.

Cần thêm:

docs/
├── architecture.md
├── event-schema.md
├── configuration.md
├── deployment.md
├── troubleshooting.md
├── threat-model.md
└── benchmarks.md
29. Thiếu các file quản trị dự án

GitHub hiện báo chưa có SECURITY.md; repo cũng chưa có LICENSE thực tế, tests, CI hoặc release.

Nên bổ sung:

LICENSE
SECURITY.md
CONTRIBUTING.md
CHANGELOG.md
CODE_OF_CONDUCT.md
.github/workflows/ci.yml
.github/ISSUE_TEMPLATE/
VI. Kiến trúc thư mục nên chuyển tới
WinLogCollector/
├── src/
│   └── WinLogCollector/
│       ├── WinLogCollector.psd1
│       ├── WinLogCollector.psm1
│       ├── Public/
│       │   ├── Invoke-WinLogCollection.ps1
│       │   ├── Send-WinLogArchive.ps1
│       │   ├── Retry-WinLogQueue.ps1
│       │   └── Test-WinLogCollector.ps1
│       └── Private/
│           ├── ConvertFrom-WinEventRecord.ps1
│           ├── Read-CollectorState.ps1
│           ├── Write-CollectorState.ps1
│           ├── New-WinLogArchive.ps1
│           ├── Write-CollectorLog.ps1
│           └── Test-SftpHostKey.ps1
├── apps/
│   └── Gui/
│       ├── MainWindow.ps1
│       └── ViewModels.ps1
├── scripts/
│   ├── Install-WinLogCollector.ps1
│   ├── Uninstall-WinLogCollector.ps1
│   ├── Register-CollectorTask.ps1
│   └── Set-AuditPrerequisites.ps1
├── server/
│   ├── ingest/
│   ├── schemas/
│   └── examples/
├── config/
│   ├── config.example.json
│   └── config.schema.json
├── tests/
│   ├── Unit/
│   ├── Integration/
│   └── Fixtures/
├── docs/
├── .github/workflows/
├── Main.ps1
├── LICENSE
├── SECURITY.md
└── README.md
VII. Thứ tự triển khai hợp lý
Giai đoạn 1 – Khắc phục lỗi có thể gây sai hoặc mất dữ liệu
Tách Archive và Upload, sửa retry .zip.
Sử dụng đúng RemotePath.
Bỏ StrictHostKeyChecking=no.
Áp dụng EventIDs và thêm channel 4104.
Parse XML theo tên trường.
Ghi file atomic và dùng tên file có Host ID + Batch ID.
Silent Mode trả exit code và retry queue.
Thêm mutex để ngăn hai instance chạy đồng thời.
Giai đoạn 2 – Làm agent đáng tin cậy
Checkpoint theo channel và Record ID.
Queue metadata, backoff, retention và quarantine.
Manifest + SHA-256.
Persistent structured logging.
Preflight audit policies.
Tách agent khỏi GUI.
Giai đoạn 3 – Nâng thành dự án portfolio mạnh
PowerShell module chuẩn.
Pester unit/integration tests.
PSScriptAnalyzer và GitHub Actions.
Server-side ingestion worker.
Elasticsearch/OpenSearch mapping.
Dashboard và truy vấn forensic.
Threat model, benchmark và tài liệu triển khai.

Việc nên làm đầu tiên là sửa LogUploader.ps1, vì retry queue và xác thực host SFTP hiện là hai điểm có khả năng làm hỏng luồng vận hành hoặc tạo rủi ro bảo mật lớn nhất.