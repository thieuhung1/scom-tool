# 🗺️ Kế Hoạch Xây Dựng & Đặc Tả Kỹ Thuật Chống Bug — SCOM CyberShield v3.0

Tài liệu này là **Bản Thiết Kế Kỹ Thuật (Technical Blueprint)** và lộ trình phát triển từ đầu cho dự án **SCOM CyberShield v3.0** (công cụ quét mã độc, săn tiến trình đào coin và dọn rác tối ưu hóa Windows), được thiết kế lại nhằm triệt tiêu 100% toàn bộ 11 lỗi (Bugs) của phiên bản cũ.

---

## 🏗️ PHẦN 1: KIẾN TRÚC PHÂN TẦNG & CẤU TRÚC THƯ MỤC CHUẨN

Hệ thống tách biệt hoàn toàn thành 3 tầng độc lập: **CLI Launcher (Batch)**, **Core Engine (PowerShell JSON API)** và **Desktop GUI (Node.js/Electron)** để không xảy ra xung đột luồng nhập/xuất (`stdin/stdout`).

    scom-cybershield-v3/
    ├── bin/                         # Bộ khởi chạy dòng lệnh cho người dùng cuối
    │   ├── run.bat                  # Entrypoint gọi trình điều khiển chính
    │   └── SCOM_CLI.bat             # Giao diện Terminal Pro 10 chức năng (Chuẩn UAC)
    ├── engine/                      # Lõi xử lý bảo mật & hệ thống Windows (PowerShell)
    │   ├── core_scanner.ps1         # Bộ máy quét 5 lớp (Hỗ trợ xuất Console & JSON)
    │   ├── cleaner.ps1              # Module dọn rác, tối ưu RAM, khôi phục Hosts an toàn
    │   └── signatures.json          # Cơ sở dữ liệu Hash MD5/SHA256, đuôi kép & tiến trình độc hại
    ├── src/                         # Tầng giao diện đồ họa Desktop (JS / HTML / CSS)
    │   ├── main.js                  # Tiến trình chính gọi PowerShell bất đồng bộ (Non-blocking)
    │   ├── preload.js               # Cầu nối IPC bảo mật giữa giao diện và hệ điều hành
    │   └── renderer/                # Giao diện người dùng Dark Mode Cyberpunk
    ├── tests/                       # Kiểm thử tự động (Pester cho PowerShell & Vitest cho JS)
    ├── README.md                    # Tài liệu giới thiệu và hướng dẫn sử dụng
    ├── plan.md                      # Kế hoạch phát triển và ma trận phòng chống Bug
    └── package.json                 # Cấu hình scripts và đóng gói ứng dụng (.exe)

---

## 🛑 PHẦN 2: MA TRẬN PHÒNG CHỐNG 11 BUG CỐT LÕI (ZERO-BUG PATTERN)

### 1. Nhóm Bug Tầng PowerShell Engine (`engine/core_scanner.ps1`)

| Mã Bug | Hiện tượng & Nguyên nhân gốc rễ | Giải pháp kỹ thuật bắt buộc trong v3.0 |
| :--- | :--- | :--- |
| **PS-BUG-01: Rò rỉ khóa file (File Handle Leak)** | Mở `FileStream` kiểm tra 2 byte `MZ Header` nhưng đặt `$stream.Close()` trong khối `try`. Khi gặp lỗi đọc file, luồng không được đóng gây khóa cứng file trên Windows. | Luôn khởi tạo `$stream = $null` và bọc trong cấu trúc `try { ... } finally { if ($null -ne $stream) { $stream.Dispose() } }` kèm cờ `FileShare.ReadWrite`. |
| **PS-BUG-02: Nghẽn cổ chai I/O khi băm MD5 toàn bộ file** | Gọi `Get-FileHash` trên mọi tệp tin `< 25MB` (bao gồm ảnh, video, tài liệu, cache), làm chế độ Quét Toàn Diện (`Full Scan`) chậm gấp 10–20 lần. | Chỉ tính mã băm MD5/SHA256 đối với các định dạng có khả năng thực thi (`.exe`, `.dll`, `.scr`, `.com`, `.bat`, `.cmd`, `.ps1`, `.vbs`, `.hta`) hoặc file nhỏ `< 100KB`. |
| **PS-BUG-03: Chế độ `Full` thiếu bước Cách ly (Quarantine)** | Quét toàn diện phát hiện mã độc nhưng kết thúc luôn mà không cho phép người dùng cách ly như chế độ `Quick` và `Custom`. | Đóng gói hàm dùng chung `Invoke-QuarantineAction` kèm file nhật ký `manifest.json` (hỗ trợ cả Cách ly & Khôi phục) và gọi thống nhất ở cả 3 chế độ `Quick`, `Custom`, `Full`. |
| **PS-BUG-04: Treo luồng (Hang) khi gọi từ giao diện GUI** | Lệnh `Read-Host` dừng tiến trình chờ nhập phím `Y/N` từ bàn phím, làm treo cứng tiến trình con khi gọi từ Node.js (`child_process.spawn`). | Bổ sung tham số `[switch]$NonInteractive` và `[ValidateSet('Text','JSON')][string]$OutputFormat = 'Text'`. Khi gọi từ GUI, trả kết quả JSON ngay mà không dừng ở `Read-Host`. |
| **PS-BUG-05: Báo động giả (False Positive) với `WinSxS`** | Chế độ `ProcessHunter` kiểm tra tiến trình hệ thống chỉ loại trừ `\system32\` và `\syswow64\`, bỏ sót thư mục hợp lệ `\windows\winsxs\`. | Đồng bộ danh sách đường dẫn hệ thống hợp lệ (`System32`, `SysWOW64`, `WinSxS`) vào một hàm kiểm tra duy nhất `Test-LegitSystemPath`. |
| **PS-BUG-06: Cảnh báo nhầm `localhost` trong file Hosts** | Chỉ lọc dòng bắt đầu bằng `#`, dẫn đến báo đỏ nhầm các dòng mặc định `127.0.0.1 localhost` và `::1 localhost`. | Bổ sung biểu thức chính quy loại trừ các cấu hình loopback chuẩn (`^\s*(127\.0\.0\.1|::1)\s+localhost\s*$`). |

### 2. Nhóm Bug Tầng Điều Khiển Batch (`bin/SCOM_CLI.bat`)

| Mã Bug | Hiện tượng & Nguyên nhân gốc rễ | Giải pháp kỹ thuật bắt buộc trong v3.0 |
| :--- | :--- | :--- |
| **BAT-BUG-01: Lỗi cú pháp comment dòng kiểm tra Admin** | Ghi `1. REMKiem tra quyen Administrator` làm CMD báo lỗi `'1.' is not recognized as an internal or external command`. | Tuân thủ chuẩn ghi chú `REM` hoặc `::` đứng đầu dòng, cách nội dung ít nhất 1 khoảng trắng. |
| **BAT-BUG-02: Mở trùng 2 cửa sổ CMD khi nâng quyền UAC** | Sau khi gọi `Start-Process -Verb RunAs`, cửa sổ CMD cũ (không có quyền Admin) không thoát mà chạy tiếp vào Menu chính. | Kiểm tra `if not errorlevel 1 exit /b` ngay sau lệnh gọi UAC để tự động đóng cửa sổ cũ khi người dùng nhấn **Yes**. |
| **BAT-BUG-03: Sập cửa sổ CMD khi nhập đường dẫn có ngoặc đơn** | Đặt lệnh `echo "%TARGET_PATH%"` bên trong khối ngoặc `( ... )`. Khi đường dẫn chứa `Program Files (x86)`, dấu `)` làm vỡ cú pháp khối lệnh Batch. | Kiểm tra biến rỗng `if not defined TARGET_PATH` trước và sử dụng nhãn `if exist "%TARGET_PATH%" goto RUN_SCAN` thay vì bọc `echo` trong ngoặc đơn. |
| **BAT-BUG-04: Báo "Thành công" giả khi thiếu quyền Admin** | Ghi đè file `hosts` hoặc cập nhật Defender thất bại do thiếu quyền Admin nhưng câu lệnh `echo [+] Thanh cong!` bên dưới vẫn luôn chạy. | Trả về mã thoát `exit 1` trong khối `catch` của PowerShell và kiểm tra `if errorlevel 1` bên Batch để hiển thị thông báo lỗi chuẩn xác. |
| **BAT-BUG-05: Vỡ ký tự chuỗi mẫu thử EICAR** | Ký tự `%` và `$EICAR` bị CMD/PowerShell hiểu nhầm là biến môi trường hoặc bị Defender xóa ngầm gây văng lỗi đỏ. | Escape `%%` trong Batch, ghép chuỗi `[char]36` trong PowerShell và bọc trong `try / catch` để thông báo rõ nếu Windows Defender chặn tức thì. |

---

## 📅 PHẦN 3: LỘ TRÌNH TRIỂN KHAI 4 GIAI ĐOẠN (SPRINT PLAN)

### ✅ Giai đoạn 1 (Tuần 1): Xây dựng Core Engine & Cơ sở dữ liệu Signature
- [x] Khởi tạo cấu trúc thư mục dự án và tệp `engine/signatures.json` lưu trữ danh sách đuôi tệp nguy hiểm, mã băm độc hại và từ khóa tiến trình đào coin.
- [x] Viết mới `engine/core_scanner.ps1` tích hợp 5 lớp nhận diện:
  1. Kiểm tra đuôi tệp kép giả mạo (`Double Extension`).
  2. Kiểm tra giả mạo tiến trình hệ thống ngoài thư mục chuẩn (`Masquerading`).
  3. Kiểm tra `MZ Header` (Magic Bytes `0x4D 0x5A`) trong tệp tài liệu/hình ảnh với cơ chế đóng luồng `try/finally` an toàn.
  4. Đối chiếu mã băm MD5/SHA256 có chọn lọc định dạng.
  5. Phân tích hành vi Script độc hại (Downloader / xóa Shadow Copy).
- [x] Bổ sung chế độ xuất dữ liệu `-OutputFormat JSON` và `-NonInteractive`.

### 🔄 Giai đoạn 2 (Tuần 2): Hoàn thiện Giao diện CLI & Quản lý Cách ly thông minh
- [x] Xây dựng `bin/SCOM_CLI.bat` và `bin/run.bat` với cơ chế tự nâng quyền UAC chuẩn xác.
- [x] Xây dựng hệ thống Cách ly có khả năng khôi phục (`Quarantine & Restore`):
  - [x] Đổi tên tệp sang `.quarantined` và lưu đường dẫn gốc kèm thời gian vào `quarantine_manifest.json`.
  - [x] Cho phép người dùng khôi phục (`Restore`) tệp về vị trí ban đầu hoặc xóa vĩnh viễn (`Secure Wipe`).
- [x] Tích hợp module `engine/cleaner.ps1` dọn dẹp `User Temp`, `Windows Temp`, `Prefetch`, `CrashDumps`, `WER`, `Recycle Bin` và `DNS Cache`.

### 🚀 Giai đoạn 3 (Tuần 3): Phát triển Giao diện Đồ họa (GUI Dashboard)
- [x] Xây dựng tầng giao diện trong `src/` kết nối với `engine/core_scanner.ps1` qua luồng JSON bất đồng bộ.
- [x] Thiết kế 5 phân khu chức năng:
  1. **Bảng điều khiển & Quét Virus (Quick / Custom / Full Scan).**
  2. **Thợ săn Tiến trình (Process Hunter — Theo dõi RAM & Diệt nóng PID).**
  3. **Tối ưu & Dọn rác Hệ thống (1-Click System Cleaner).**
  4. **Lá chắn Khởi động & File Hosts (Startup & DNS Shield).**
  5. **Quản lý Khu Cách ly (Xem / Khôi phục / Xóa vĩnh viễn).**

### 📦 Giai đoạn 4 (Tuần 4): Kiểm thử Tự động, CI/CD & Đóng gói Phát hành
- [x] Viết bộ kiểm thử tự động `tests/test_core_scanner.ps1` gồm 12 bài kiểm tra chuyên sâu:
  - [x] Kiểm thử 5 tầng Heuristic: Đuôi kép, Masquerading, MZ Header, I/O leak Dispose, Script Download Cradle.
  - [x] Kiểm thử cách ly & khôi phục toàn vẹn qua mã băm SHA-256.
  - [x] Kiểm thử chặn Path Traversal (`..`) khi restore từ manifest.
  - [x] Kiểm thử chặn khôi phục khi tệp bị can thiệp mã băm (`IntegrityViolation`).
  - [x] Kiểm thử giới hạn tài nguyên quét & loại trừ thư mục nặng (`.git`, `node_modules`).
  - [x] Kiểm thử cơ chế hủy quét hợp tác (`Cooperative Cancellation Flag`).
  - [x] Kiểm thử Process Hunter bảo vệ tiến trình hệ thống cốt lõi.
- [ ] Thiết lập GitHub Actions tự động kiểm tra lỗi cú pháp PowerShell (`PSScriptAnalyzer`) và JavaScript.
- [ ] Đóng gói bản phát hành hoàn chỉnh (`v3.1.0`) qua `electron-builder`.

---

## 🛡️ PHẦN 5: BIÊN BẢN KHẮC PHỤC SENIOR REVIEW & BẢO MẬT (v3.1 HARDENING)

| Mức Độ | Phát Hiện (Findings) | Biện Pháp Khắc Phục Triệt Để Trong Code | Trạng Thái |
| :--- | :--- | :--- | :--- |
| **Blocker** | **Command Injection khi kill process** (`src/main.js` nội suy PID vào `-Command`) | Chuyển sang `taskkill.exe` trực tiếp qua mảng tham số `['/F', '/PID', String(cleanPid)]` (không dùng shell), kiểm tra `Number.isInteger(cleanPid) && cleanPid > 4`, chặn danh sách PID hệ thống (`0, 4`). | **ĐÃ SỬA & KIỂM THỬ** |
| **Blocker** | **Quét đệ quy không giới hạn, nghẽn RAM/I/O** | Viết lại thuật toán quét `Get-ScannableFiles` bằng hàng đợi BFS, giới hạn `LimitDepth = 12`, `LimitFiles = 25000`, loại trừ thư mục nặng (`.git`, `node_modules`, `vendor`, `inetcache`), bỏ qua `ReparsePoint/Junction`, hỗ trợ streaming tiến độ `JSON_EVENT` và cờ hủy `scom_cancel_scan.flag`. | **ĐÃ SỬA & KIỂM THỬ** |
| **Blocker** | **Khu cách ly chưa có biên giới bảo mật thực sự** | Bổ sung siết ACL thư mục `SCOM_Quarantine` (`SetAccessRuleProtection`), gắn cờ `ReadOnly` cho tệp cách ly, lưu mã băm SHA-256 trong `quarantine_manifest.json`, từ chối khôi phục nếu mã băm sai lệch (`IntegrityViolation`), chặn triệt để Path Traversal (`..`). | **ĐÃ SỬA & KIỂM THỬ** |
| **High** | **Cơ sở dữ liệu chữ ký chứa hash giả** | Loại bỏ toàn bộ hash giả mạo khỏi `engine/signatures.json`. Chỉ giữ mã băm chuẩn xác thực tế (EICAR MD5/SHA256, WannaCry Executable & Dropper), minh bạch chiến lược `Heuristic-First`. | **ĐÃ SỬA & KIỂM THỬ** |
| **High** | **Bề mặt False-Positive của Process Hunter & nút Kill** | Bảo vệ tiến trình hệ thống (`0, 4, csrss, svchost, explorer...`), chỉ cảnh báo tệp trong `Temp` nếu là Script Interpreter (`powershell, cmd, wscript, cscript, mshta`), thêm hộp thoại xác nhận cảnh báo trên giao diện Desktop GUI. | **ĐÃ SỬA & KIỂM THỬ** |
| **High** | **Reset Hosts xóa cấu hình mà không sao lưu** | Tự động tạo bản sao lưu có timestamp (`hosts.backup_yyyyMMdd_HHmmss`) trước khi ghi đè khôi phục file hosts mặc định. | **ĐÃ SỬA & KIỂM THỬ** |
| **High** | **Tư thế bảo mật Electron thiếu CSP & Sandbox** | Bật `sandbox: true`, giữ `nodeIntegration: false` + `contextIsolation: true`, thêm thẻ `Content-Security-Policy` nghiêm ngặt trong `index.html`. | **ĐÃ SỬA & KIỂM THỬ** |
| **Medium** | **Heuristic kịch bản thiếu cradles hiện đại** | Mở rộng danh mục mẫu nhận diện: `Invoke-RestMethod (irm)`, `Invoke-Expression (iex)`, Base64 payload decoding (`[System.Convert]::FromBase64String`), `certutil -urlcache`, `vssadmin delete shadows`. Đồng bộ động từ `signatures.json`. | **ĐÃ SỬA & KIỂM THỬ** |
| **Medium** | **An toàn File Handle & I/O** | Chuẩn hóa giải phóng `Dispose()` trong khối `try/finally` với `FileShare.ReadWrite`, bắt lỗi tệp bị khóa. | **ĐÃ SỬA & KIỂM THỬ** |
| **Medium** | **Bộ kiểm thử tự động toàn diện** | Mở rộng `tests/test_core_scanner.ps1` lên 12 test cases kiểm tra từ Heuristic, Cách ly, Toàn vẹn mã băm, Path Traversal, Loại trừ thư mục đến Hủy hợp tác (12/12 PASS). | **ĐÃ SỬA & KIỂM THỬ** |

---

## ✔️ PHẦN 6: DANH SÁCH KIỂM TRA CHẤT LƯỢNG TRƯỚC KHI COMMIT (QUALITY GATE)

Trước khi thực hiện `git commit`, đảm bảo toàn bộ 5 tiêu chí sau đạt trạng thái **PASS**:
1. Chạy `powershell -File ./tests/test_core_scanner.ps1` đạt **12 / 12 PASS**.
2. Chạy `SCOM_CLI.bat` xác nhận chỉ mở duy nhất 1 cửa sổ CMD dưới quyền Administrator.
3. Tạo mẫu thử `[T] EICAR` và chạy `[1] Quet Nhanh` phát hiện, cách ly và khôi phục thành công.
4. Nhập đường dẫn chứa dấu cách và ngoặc đơn (ví dụ `C:\Program Files (x86)`) vào mục `[2] Quet Tuy Chon` không gây văng cửa sổ.
5. Kiểm tra GUI Electron khởi động an toàn, không có lỗi CSP hay lỗi IPC trong DevTools console.