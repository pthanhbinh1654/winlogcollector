# WinLogCollector 🪟📋

> **Enterprise-grade Windows Log Collector Agent (v0.3.1)** – Đồ án CT491 - Niên Luận Cơ Sở

[🇬🇧 English Version](README.md) | [🇻🇳 Tiếng Việt](README_VN.md)

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey?logo=windows)](https://www.microsoft.com/windows)
[![Pester](https://img.shields.io/badge/Tests-Pester-green?logo=powershell)](tests/Unit/Collector.Tests.ps1)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 📌 Giới thiệu

**WinLogCollector** là một Windows Event Log Collector agent chuyên nghiệp, tin cậy và đạt chuẩn bảo mật, được thiết kế cho các môi trường doanh nghiệp:
- Thu thập Windows Event Logs theo **oldest-first paginated XPath query** dựa trên checkpoint `RecordID` (đảm bảo không trùng, không mất dữ liệu).
- Tách biệt cấu hình theo mảng **Subscriptions** cho từng Event Log Channel riêng biệt.
- **Tự động khôi phục sau crash (Durable Outbox)**: Xử lý cả file `.ready` và `.zip` còn tồn tại ở đầu mỗi chu kỳ.
- **Nén log & bảo mật truyền tải**: Nén ZIP và gửi lên máy chủ SFTP qua SSH Key với **`StrictHostKeyChecking=yes`** & host key verification.
- **Tích hợp ELK Pipeline Tự Động**: Đi kèm toàn bộ hạ tầng ELK Stack (Elasticsearch, Logstash, Kibana), container **Sidecar Auto-ZIP Extractor** và **Script Setup 1-Click**.
- **Hàng chờ offline (Queue with Exponential Backoff & Quarantine)**: Giới hạn dung lượng Queue (`MaxSizeMB`), giới hạn số lần thử (`MaxAttempts`) và tự động đưa file quá hạn (`MaxAgeDays`) vào `Quarantine`.
- **Hoàn toàn tách biệt WinForms khỏi Core**: Core chạy headless 100%, GUI & Silent mode gọi chung một hàm duy nhất `Invoke-WinLogCollectorCycle`.

---

## 🏗️ Kiến trúc hệ thống

```mermaid
flowchart TD
    A[Windows Event Logs\nSecurity / System / Operational] -->|XPath EventRecordID > LastId| B[LogCollector Engine]
    B -->|Atomic Write JSONL| C[Ready/*.jsonl.ready]
    C -->|Compress-Archive| D[Ready/*.zip]
    D -->|Truyền SFTP Port 2222| E[WSL2 / SFTP Container]
    D -.->|Failed Upload| F[Queue/*.zip + Sidecar JSON]
    F -->|Exponential Backoff Retry| E
    F -.->|Expired / Exceeded MaxAttempts| G[Quarantine/]

    subgraph Tích hợp ELK Stack
        E -->|Volume sftp_incoming| H[Auto-Extractor Container]
        H -->|Auto Unzip *.jsonl.ready| I[Logstash Engine]
        I -->|Parse & Index| J[Elasticsearch]
        J -->|Trực quan hóa| K[Kibana UI http://localhost:5601]
    end

    style A fill:#0078D4,color:#fff
    style B fill:#1565c0,color:#fff
    style E fill:#2e7d32,color:#fff
    style J fill:#f57c00,color:#fff
```

---

## 📂 Cấu trúc dự án

```
WinLogCollector/
├── Main.ps1                    # Orchestrator & Single Entry Point
├── setup-elk.ps1               # Script 1-Click Tự động hóa Setup ELK & SFTP
├── config.json                 # File cấu hình JSON (Host, Keys, Subscriptions...)
├── README.md                   # Hướng dẫn sử dụng (Tiếng Anh)
├── README_VN.md                # Hướng dẫn sử dụng (Tiếng Việt)
├── LICENSE                     # Mã nguồn mở MIT License
├── config/
│   ├── config.example.json     # File cấu hình mẫu
│   └── config.schema.json      # JSON Schema validation
├── deploy/
│   └── elk/                    # File cấu hình hạ tầng ELK Stack & SFTP
│       ├── docker-compose.elk.yml
│       └── logstash/
│           ├── config/logstash.yml
│           └── pipeline/winlog.conf
├── docs/
│   └── ELK_SETUP.md            # Hướng dẫn chi tiết ELK (1-Click & Thủ công)
├── src/
│   ├── Core/
│   │   ├── LogCollector.ps1    # Incremental oldest-first Event Log collector
│   │   └── LogUploader.ps1     # Compression, SFTP upload & Queue management
│   ├── Gui/
│   │   └── MainWindow.ps1      # WinForms UI (nhận Context hashtable)
│   └── Utils/
│       ├── Logger.ps1          # Thread-safe persistent JSON logger & UI callback sink
│       └── Security.ps1        # Admin check & Preflight check (Test-WinLogCollectorPrerequisite)
└── tests/
    └── Unit/
        └── Collector.Tests.ps1 # Pester Unit Tests suite
```

---

## ⚙️ Cấu hình `config.json` (v0.3.1 Schema)

```json
{
  "Remote": {
    "Host": "127.0.0.1",
    "Port": 2222,
    "User": "winlog",
    "SSHKeyPath": "C:\\ProgramData\\WinLogCollector\\keys\\id_rsa",
    "KnownHostsPath": "C:\\ProgramData\\WinLogCollector\\keys\\known_hosts",
    "RemotePath": "/incoming"
  },
  "Local": {
    "DataDir": "C:\\ProgramData\\WinLogCollector"
  },
  "Collection": {
    "DefaultIntervalMinutes": 3,
    "DefaultDurationMinutes": 9,
    "Subscriptions": [
      {
        "Channel": "Security",
        "EventIDs": [4624, 4625, 4688]
      },
      {
        "Channel": "System",
        "EventIDs": []
      },
      {
        "Channel": "Microsoft-Windows-PowerShell/Operational",
        "EventIDs": [4103, 4104]
      }
    ]
  },
  "Queue": {
    "MaxSizeMB": 2048,
    "MaxAttempts": 20,
    "MaxAgeDays": 14
  }
}
```

---

## 🚀 Hướng Dẫn Cài Đặt & Chạy Hệ Thống

### 1. Cài đặt ELK Stack & SFTP Server (Chọn Phương pháp A hoặc B)

> 📖 **Xem Tài Liệu Đầy Đủ**: File **[docs/ELK_SETUP.md](docs/ELK_SETUP.md)** hướng dẫn chi tiết từ A đến Z.

- **Phương pháp A — ⚡ Cài đặt Nhanh 1-Click**:
  Mở PowerShell (Run as Administrator) và chạy:
  ```powershell
  powershell -ExecutionPolicy Bypass -File ".\setup-elk.ps1"
  ```
  *(Tự động sinh SSH Key, bật Docker WSL2, inject Public Key, cập nhật `known_hosts` và file `config.json` trong 1 lệnh).*

- **Phương pháp B — 🛠️ Cài đặt Thủ công Từng Bước**:
  Xem hướng dẫn chi tiết từng bước tại [docs/ELK_SETUP.md](docs/ELK_SETUP.md#️-phương-pháp-2-cài-đặt-thủ-công-từng-bước-manual-setup-step-by-step).

---

### 2. Chạy Agent Thu Thập Log

- **Chạy Giao diện Quản trị GUI WinForms (Mặc định)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File ".\Main.ps1"
  ```

- **Chạy Chế độ Silent (Headless Mode - Dùng cho Task Scheduler)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File ".\Main.ps1" -Silent
  ```

- **Chạy Unit Tests (Pester)**:
  ```powershell
  Invoke-Pester -Path ".\tests\Unit\Collector.Tests.ps1"
  ```

---

## 🖥️ Giao diện Quản trị WinForms (6 Tab)

| Tab | Chức năng | Chi tiết |
|---|---|---|
| **1. 📊 Tổng quan** | KPI Stat Cards & Điều khiển nhanh | Xem tổng số Event đã lấy, dung lượng Queue, trạng thái SFTP; nút Thu thập ngay, Bắt đầu/Dừng tự động, Preflight. |
| **2. 📥 Thu thập log** | Quản lý Subscriptions & Mode | Đổi giữa Checkpoint (incremental) và Lookback (phút); DataGridView chỉnh sửa trực tiếp danh sách Event Log Channels & Event IDs. |
| **3. ⚡ Tự động (Timer)** | Lịch chạy định kỳ Continuous Mode | Chỉnh chu kỳ Timer (phút), đếm ngược thời gian lần chạy kế tiếp, tự động retry queue đệm offline. |
| **4. 🌐 Cấu hình SFTP** | Cấu hình & Thử nghiệm kết nối | Thay đổi Host, Port, Username, RemotePath, SSH Key, KnownHosts; thử cổng TCP 22 & lưu cấu hình trực tiếp vào `config.json`. |
| **5. 📦 Hàng chờ Queue** | Quản lý đệm Offline & Quarantine | DataGridView danh sách file `.zip` đang chờ retry (Dung lượng, Số lần thử, Lần thử kế tiếp); nút Retry ngay & Mở thư mục. |
| **6. 🔍 Preflight Check** | Bảng kiểm tra tiền điều kiện | DataGridView kiểm tra 8 tiêu chí hệ thống (Admin, sftp.exe, SSH Key, KnownHosts, Event Channels, Cổng TCP 22). |

---

## 🔒 Tính năng Bảo mật & Độ tin cậy (Security & Invariants)

1. **Strict Host Key Verification**: Ép buộc kiểm tra fingerprint máy chủ qua file `known_hosts` (ngăn ngừa Man-in-the-Middle).
2. **Atomic Operations**: Ghi file tạm (`.tmp`) rồi đổi tên sang `.ready`/`.queue.json` để tránh race-conditions.
3. **Single Instance Mutex**: Sử dụng `Local\WinLogCollector` Named Mutex ngăn chạy nhiều tiến trình cùng lúc.
4. **Oldest-First RecordID Pagination**: Query log theo thứ tự từ cũ tới mới dựa trên EventRecordID, đảm bảo thu thập đầy đủ sau khi máy tắt hoặc gián đoạn.
5. **Disk Protection**: Tự động ngừng thu thập khi Queue vượt quá ngưỡng `MaxSizeMB` cấu hình.

---

## 📝 License

Dự án phát hành theo mã nguồn mở **MIT License**. Xem chi tiết tại [LICENSE](LICENSE).

---
*Đồ án CT491 – Niên Luận Cơ Sở \| B2203708 – Phan Thanh Bình*
