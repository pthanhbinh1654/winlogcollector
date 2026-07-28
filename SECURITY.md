# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.3.x   | ✅         |
| < 0.3   | ❌         |

## Reporting a Vulnerability

Nếu bạn phát hiện lỗ hổng bảo mật nghiêm trọng trong WinLogCollector, vui lòng **KHÔNG** tạo Issue công khai.

Thay vào đó, hãy liên hệ qua:
- **Email**: pthanhbinh1654@github.com  
- **Subject**: `[SECURITY] WinLogCollector – <mô tả ngắn>`

### Thông tin cần cung cấp:
1. Phiên bản bị ảnh hưởng
2. Mô tả chi tiết lỗ hổng
3. Bước tái hiện (PoC nếu có)
4. Đánh giá tác động (CVSS nếu biết)

### Cam kết:
- Phản hồi trong vòng **48 giờ**
- Cập nhật bản vá trong vòng **14 ngày** với lỗ hổng nghiêm trọng

## Lưu ý bảo mật khi triển khai

> **Quan trọng**: SSH private key KHÔNG được commit vào repository.

1. **SSH Key**: Lưu tại `C:\ProgramData\WinLogCollector\keys\` với ACL chỉ cho Administrators và SYSTEM.
2. **Known Hosts**: Phải được thiết lập qua `ssh-keyscan` trước khi deploy.
3. **data directory**: `C:\ProgramData\WinLogCollector\` nên có ACL hạn chế.
4. **Log nhạy cảm**: Event 4688 có thể chứa command line với credential – không chia sẻ logs thô.
