# ELK Stack & SFTP Pipeline Setup Guide

Tài liệu hướng dẫn triển khai hệ thống **ELK Stack (Elasticsearch, Logstash, Kibana)** kết hợp với **SFTP Server (OpenSSH)** và **Auto-Extractor Sidecar** để thu thập, đồng bộ và trực quan hóa dữ liệu log từ Windows Log Collector.

---

## 🏗️ Kiến trúc Hệ thống (Pipeline Architecture)

```
[Windows Host Agent]
    │  (Powershell EventLog Collector)
    ▼
[Local DataDir] ──► (Zipped Log Archives: *.zip)
    │
    │  (SFTP Transfer via OpenSSH, Port 2222)
    ▼
[WSL2 / Docker Host]
 ├── [sftp01 Container] ──► Uploads land in /home/winlog/incoming (Volume: sftp_incoming)
 ├── [extractor01 Container] ──► Auto-extracts *.zip -> *.jsonl.ready (Background Sidecar)
 ├── [logstash01 Container] ──► Watches /input/**/*.ready, parses JSON, indexes to ES
 ├── [es01 Container] ──► Stores & indexes logs (Elasticsearch:9200)
 └── [kibana01 Container] ──► Visualizes logs (http://localhost:5601)
```

---

## 📖 Quy Chuẩn Kỹ Thuật Truy Vấn Log (Microsoft Get-WinEvent Standards)

Tài liệu tham chiếu chính thức từ Microsoft Learn: [Get-WinEvent (Microsoft.PowerShell.Diagnostics)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent).

Hệ thống **WinLogCollector** tuân thủ nghiêm ngặt các quy chuẩn hiệu năng của Microsoft đối với cmdlet `Get-WinEvent`:

1. **Truy vấn Tầng Hệ Điều Hành (`-FilterXPath` & `-FilterHashtable`)**: Không sử dụng `Where-Object` để tránh nạp dữ liệu thô vào RAM. Mọi bộ lọc được đẩy trực tiếp xuống tầng Windows Event Log Subsystem (C/C++ API layer).
2. **Thứ Tự Tuyến Tính (`-Oldest`)**: Bắt buộc truy vấn theo chiều thời gian từ cũ nhất đến mới nhất (*Oldest-First*) để đảm bảo checkpoint `EventRecordID` (số nguyên 64-bit tự tăng) tăng dần chính xác, chống lặp log.
3. **Giới Hạn Bộ Nhớ Đệm (`-MaxEvents`)**: Giới hạn `BatchSize = 5000` cho mỗi chu kỳ đọc để bảo vệ bộ nhớ RAM.
4. **Tiền Kiểm Tra Trạng Thái Log (`-ListLog` / `EventLogConfiguration`)**: Kiểm tra sự tồn tại và trạng thái kích hoạt của kênh log trước khi đọc.

## ⚡ PHƯƠNG PHÁP 1: Cài Đặt Nhanh 1-Click (Quick Automation)

Phương pháp này tự động hóa 100% việc sinh SSH Key, bật Docker WSL2, inject Public Key, cập nhật `known_hosts` và `config.json`.

### Các bước thực hiện:
Mở **PowerShell (Run as Administrator)** tại thư mục gốc của dự án và chạy:

```powershell
powershell -ExecutionPolicy Bypass -File ".\setup-elk.ps1"
```

### Kết quả thu được:
- ✅ SSH Key được sinh tự động tại `C:\ProgramData\WinLogCollector\keys\id_rsa`.
- ✅ Các container Docker (`es01`, `logstash01`, `kibana01`, `sftp01`, `extractor01`) khởi động thành công.
- ✅ File `config.json` tự động được cấu hình khớp 100% với container.

---

## 🛠️ PHƯƠNG PHÁP 2: Cài Đặt Thủ Công Từng Bước (Manual Setup Step-by-Step)

Dành cho quản trị viên muốn tự tùy chỉnh môi trường hoặc khắc phục sự cố.

### Yêu cầu mở 2 Terminal:
- `[Win-Admin]`: PowerShell (Run as Administrator) trên Windows.
- `[WSL2]`: Terminal Ubuntu trên WSL2.

---

### Bước 1: Tạo SSH Keys trên Windows `[Win-Admin]`

```powershell
# 1. Tạo thư mục chứa key
New-Item -ItemType Directory -Path "C:\ProgramData\WinLogCollector\keys" -Force | Out-Null

# 2. Tạo SSH Key Pair (Nhấn Enter 2 lần khi hỏi Passphrase)
ssh-keygen -t rsa -b 4096 -f "C:\ProgramData\WinLogCollector\keys\id_rsa"
```

---

### Bước 2: Tạo cấu trúc thư mục trên WSL2 `[WSL2]`

```bash
mkdir -p ~/elk-winlog/logstash/pipeline
mkdir -p ~/elk-winlog/logstash/config
mkdir -p ~/elk-winlog/sftp
```

---

### Bước 3: Copy các file Cấu hình `[WSL2]`

1. Copy file `deploy/elk/docker-compose.elk.yml` vào `~/elk-winlog/docker-compose.elk.yml`.
2. Copy file `deploy/elk/logstash/pipeline/winlog.conf` vào `~/elk-winlog/logstash/pipeline/winlog.conf`.
3. Tạo file `~/elk-winlog/logstash/config/logstash.yml`:
   ```bash
   cat > ~/elk-winlog/logstash/config/logstash.yml << 'EOF'
   http.host: "0.0.0.0"
   xpack.monitoring.enabled: false
   EOF
   ```

---

### Bước 4: Tạo SSH Host Keys cho SFTP Container `[WSL2]`

```bash
cd ~/elk-winlog/sftp
ssh-keygen -t ed25519 -f ssh_host_ed25519_key -N ""
ssh-keygen -t rsa -b 4096 -f ssh_host_rsa_key -N ""
```

---

### Bước 5: Khởi động Docker Stack `[WSL2]`

```bash
sudo service docker start
cd ~/elk-winlog
docker compose -f docker-compose.elk.yml up -d
```

---

### Bước 6: Nạp Public Key vào SFTP Container `[WSL2]`

> ⚠️ **Lưu ý quan trọng**: Container `atmoz/sftp` chroot user `winlog` và sử dụng UID `1001:1001`.

```bash
PUBKEY=$(cat /mnt/c/ProgramData/WinLogCollector/keys/id_rsa.pub)
docker exec sftp01 bash -c "
  mkdir -p /home/winlog/.ssh /home/winlog/incoming/continuous /home/winlog/incoming/limited
  echo '$PUBKEY' > /home/winlog/.ssh/authorized_keys
  chown -R 1001:1001 /home/winlog/.ssh /home/winlog/incoming
  chmod 700 /home/winlog/.ssh
  chmod 600 /home/winlog/.ssh/authorized_keys
"
```

---

### Bước 7: Cập nhật known_hosts trên Windows `[Win-Admin]`

```powershell
ssh-keyscan -p 2222 127.0.0.1 | Out-File -Encoding ASCII "C:\ProgramData\WinLogCollector\keys\known_hosts"
```

---

### Bước 8: Kiểm tra kết nối SFTP `[Win-Admin]`

```powershell
sftp -P 2222 -i "C:\ProgramData\WinLogCollector\keys\id_rsa" -o "StrictHostKeyChecking=no" winlog@127.0.0.1
```
✅ **Thành công** nếu xuất hiện prompt `sftp>` mà không hỏi mật khẩu. Gõ `bye` để thoát.

---

### Bước 9: Cấu hình `config.json` `[Win-Admin]`

Sửa thông tin trong file `config.json` của Agent:

```json
"Remote": {
    "Host": "127.0.0.1",
    "Port": 2222,
    "User": "winlog",
    "SSHKeyPath": "C:\\ProgramData\\WinLogCollector\\keys\\id_rsa",
    "KnownHostsPath": "C:\\ProgramData\\WinLogCollector\\keys\\known_hosts",
    "RemotePath": "/incoming"
}
```

> 📌 **Tại sao "RemotePath" lại là `/incoming` mà không phải `/home/winlog/incoming`?**
> Container `atmoz/sftp` tự động chroot user `winlog` vào `/home/winlog`. Vì thế đối với SFTP Client, gốc `/` chính là `/home/winlog`. Do đó `/home/winlog/incoming` trên SFTP Client tương ứng là `/incoming`.

---

## 📊 Trực Quan Hóa Trên Kibana UI

1. Mở trình duyệt web: **`http://localhost:5601`**
2. Vào **Management** ➔ **Stack Management** ➔ **Index Patterns** ➔ Chọn **Create index pattern**.
3. Điền Index Pattern Name: **`winlogs-*`**
4. Chọn Timestamp field: **`@timestamp`** ➔ Bấm **Create index pattern**.
5. Mở tab **Discover** (biểu tượng kính lúp) để xem dữ liệu Windows Event Logs theo thời gian thực.

---

## 🔍 Bảng Xử Lý Lỗi Thường Gặp (Troubleshooting)

| Nguyên nhân | Hiện tượng | Cách khắc phục |
|---|---|---|
| Chroot Path bị sai | Log: `realpath /home/winlog/incoming...: No such file` | Đổi `"RemotePath": "/incoming"` trong `config.json` |
| Key chưa nạp / Sai permission | SFTP hỏi mật khẩu | Làm lại Bước 6 (Gán đúng UID `1001:1001`) |
| Host Key thay đổi | `REMOTE HOST IDENTIFICATION CHANGED` | Xóa `known_hosts` cũ và chạy lại `ssh-keyscan` |
| Quá trình nén ZIP | Logstash không đọc được `.zip` | Đảm bảo container `extractor01` đang `Up` |
| Syntax `winlog.conf` | Logstash crash loop | Đảm bảo các chuỗi Ruby filter dùng nháy đơn `'` |
