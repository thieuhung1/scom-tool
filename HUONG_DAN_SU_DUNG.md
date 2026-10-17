# 🛡️ SCOM CyberShield v3.0 — Computer Protection, Virus Scanner & System Cleaner

Công cụ bảo vệ máy tính, quét mã độc đa lớp, săn lùng tiến trình đào coin ngầm và dọn dẹp tối ưu hóa hệ thống chuyên sâu dành cho Windows. Hỗ trợ song song cả **Giao diện Đồ họa (Desktop GUI)** và **Giao diện Dòng lệnh (Terminal CLI Pro)**.

![Platform](https://img.shields.io/badge/Platform-Windows_10%2F11-0078D6?style=flat-square)
![Engine](https://img.shields.io/badge/Engine-PowerShell_Core-5391FE?style=flat-square)
![UI](https://img.shields.io/badge/Interface-GUI_%26_Terminal_Pro-00dc82?style=flat-square)
![License](https://img.shields.io/badge/Status-Production_Ready-success?style=flat-square)

---

## 🔥 Tính Năng Cốt Lõi

### 1. Bộ Máy Quét Mã Độc 5 Lớp (5-Layer Heuristic & Signature Engine)
* **Lớp 1 — Phát hiện Đuôi tệp kép giả mạo (`Double Extension`):** Chặn đứng các tệp thực thi ẩn dưới định dạng tài liệu/hình ảnh (`.pdf.exe`, `.docx.exe`, `.jpg.scr`, `.png.exe`, ...).
* **Lớp 2 — Phát hiện Giả mạo Tiến trình Hệ thống (`System Masquerading`):** Nhận diện các tệp mạo danh tiến trình cốt lõi của Windows (`svchost.exe`, `lsass.exe`, `csrss.exe`, `services.exe`, ...) nằm ngoài vùng an toàn (`System32`, `SysWOW64`, `WinSxS`).
* **Lớp 3 — Phân tích Cấu trúc Nhị phân (`MZ Magic Bytes Inspection`):** Đọc trực tiếp header nhị phân (`0x4D 0x5A`) để vạch trần các tệp thực thi PE (`.exe`/`.dll`) cố tình đổi đuôi thành `.jpg`, `.png`, `.pdf`, `.txt`.
* **Lớp 4 — Đối chiếu Chữ ký Mã băm (`MD5/SHA256 Signature Match`):** Nhận diện chính xác các mẫu mã độc đã biết (WannaCry, mẫu kiểm thử quốc tế EICAR, ...).
* **Lớp 5 — Phân tích Hành vi Kịch bản Độc hại (`Malicious Script Heuristics`):** Quét nội dung các tệp `.ps1`, `.bat`, `.cmd`, `.vbs`, `.hta` để phát hiện kỹ thuật tải mã độc ngầm (`DownloadString`, `certutil -urlcache`, `-enc`) hoặc hành vi xóa bản sao lưu (`vssadmin delete shadows`) của Ransomware.

### 2. Thợ Săn Tiến Trình & Diệt Đào Coin Ngầm (Process Hunter)
* Quét toàn bộ tiến trình đang hoạt động trên bộ nhớ RAM theo thời gian thực.
* Tự động gắn cờ cảnh báo đỏ đối với các trình đào tiền ảo trái phép (`xmrig`, `cpuminer`, `ccminer`, `nicehash`, `minerd`, ...), tiến trình giả mạo `System32` hoặc chạy lén từ thư mục tạm (`%TEMP%`).
* Hỗ trợ cưỡng chế tiêu diệt tiến trình độc hại tức thì theo mã `PID`.

### 3. Lá Chắn Khởi Động & Bảo Vệ File Hosts (Startup & DNS Shield)
* **Startup Inspector:** Rà soát toàn bộ danh sách ứng dụng tự khởi động cùng Windows (Registry & Startup Folders), phát hiện sớm các lệnh gọi `.vbs`, `.bat`, `powershell -enc` bất thường.
* **Hosts Shield:** Kiểm tra các dòng chuyển hướng IP/DNS trái phép trong tệp `C:\Windows\System32\drivers\etc\hosts` và khôi phục về trạng thái mặc định chuẩn của Microsoft chỉ với 1 phím bấm.

### 4. Dọn Dẹp Rác Chuyên Sâu & Tăng Tốc Hệ Thống (Deep System Cleaner)
* Giải phóng dung lượng ổ đĩa bằng cách làm sạch toàn diện: `User Temp (%TEMP%)`, `Windows Temp`, `Windows Prefetch`, `Crash Dumps & Windows Error Reporting (WER)`, `Recycle Bin` và làm mới bộ nhớ đệm `DNS Cache`.

### 5. Khu Vực Cách Ly An Toàn & Trình Tạo Mẫu Thử EICAR
* Cô lập tệp tin nguy hiểm vào khu vực an toàn (`%LOCALAPPDATA%\SCOM_Quarantine`) kèm khả năng khôi phục hoặc xóa vĩnh viễn.
* Tích hợp tính năng tạo tệp kiểm thử chuẩn quốc tế **EICAR** (an toàn 100%) để người dùng kiểm chứng trực tiếp khả năng phát hiện và cách ly của công cụ bất cứ lúc nào.

---

## 🛠️ Hướng Dẫn Cài Đặt & Sử Dụng Nhanh

### Cách 1: Chạy trực tiếp giao diện Terminal Pro (Không cần cài đặt)
1. Tải hoặc Clone mã nguồn dự án về máy:
   `git clone [https://github.com/thieuhung1/scom-tool.git](https://github.com/thieuhung1/scom-tool.git)`
2. Mở thư mục dự án, nhấp đúp chuột vào tệp **`run.bat`** (hoặc **`SCOM_AntiVirus.bat`**).
3. Nhấn **Yes** khi hộp thoại **UAC (User Account Control)** xuất hiện để cấp quyền Administrator giúp công cụ quét sâu toàn hệ thống.
4. Nhập phím tương ứng trên Menu (`[1]` đến `[9]`, `[T]`, `[0]`) để sử dụng các tính năng.

### Cách 2: Chạy trực tiếp Engine bằng lệnh PowerShell (Dành cho Quản trị viên / Tích hợp UI)
Bạn có thể gọi trực tiếp `core_scanner.ps1` với các chế độ linh hoạt:

    # 1. Quét nhanh các khu vực trọng yếu (Temp, Downloads, Startup)
    powershell -NoProfile -ExecutionPolicy Bypass -File .\core_scanner.ps1 -Mode "Quick"

    # 2. Quét một thư mục hoặc tệp tin bất kỳ
    powershell -NoProfile -ExecutionPolicy Bypass -File .\core_scanner.ps1 -Mode "Custom" -TargetPath "D:\Downloads"

    # 3. Săn lùng tiến trình độc hại / đào coin trên RAM
    powershell -NoProfile -ExecutionPolicy Bypass -File .\core_scanner.ps1 -Mode "ProcessHunter"

    # 4. Kiểm tra các mục khởi động cùng Windows
    powershell -NoProfile -ExecutionPolicy Bypass -File .\core_scanner.ps1 -Mode "Startup"

---

## 🔒 Cam Kết An Toàn
* **Không xóa tệp tin tự động khi chưa được phép:** Mọi tệp tin bị phát hiện nghi ngờ đều hỏi ý kiến người dùng trước khi di chuyển vào Khu Cách Ly (`SCOM_Quarantine`).
* **Tương thích song song với Windows Defender:** Tích hợp lệnh cập nhật cơ sở dữ liệu chữ ký mới nhất và kích hoạt quét phối hợp cùng Microsoft Defender API.