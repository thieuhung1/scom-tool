# SCOM CYBERSHIELD - CÔNG CỤ BẢO VỆ, QUÉT & DỌN VIRUS (TERMINAL PRO)

## 📌 Giới Thiệu
**SCOM CyberShield** là công cụ bảo vệ máy tính dạng Terminal / Batch Script (`.bat`) chuyên nghiệp, nhẹ nhàng, chạy trực tiếp trên Windows mà không cần cài đặt thêm bất kỳ phần mềm hay môi trường nặng nề nào.

---

## 🚀 Cách Sử Dụng Nhanh

1. **Chạy Trực Tiếp Bằng 1 Click:**
   - Nhấp đúp chuột vào tệp [SCOM_AntiVirus.bat](file:///d:/dev/scom%20tool/SCOM_AntiVirus.bat) hoặc [run.bat](file:///d:/dev/scom%20tool/run.bat).
   - Chọn **Yes** khi Windows hỏi quyền Administrator (để công cụ có thể truy cập các thư mục hệ thống và dọn rác triệt để).

2. **Chạy Từ Terminal / PowerShell / CMD:**
   ```cmd
   cd /d "d:\dev\scom tool"
   SCOM_AntiVirus.bat
   ```

---

## 🛡️ Các Tính Năng Trong Menu Terminal

| Phím Số | Tính Năng | Mô Tả Chi Tiết |
| :---: | :--- | :--- |
| **`[1]`** | **Quét Nhanh (Quick Scan)** | Quét các vị trí xung yếu mà virus thường ẩn nấp: `%TEMP%`, `Downloads`, `AppData`, `Startup`, `Windows Temp`. |
| **`[2]`** | **Quét Tùy Chọn (Custom Scan)** | Nhập hoặc kéo thả bất kỳ thư mục / tệp tin nào vào màn hình terminal để quét sâu. |
| **`[3]`** | **Quét Toàn Diện (Full Deep Scan)** | Quét diện rộng toàn bộ các phân vùng dữ liệu và thư mục phần mềm trên ổ `C:\`. |
| **`[4]`** | **Săn & Diệt Tiến Trình Lạ (Process Hunter)** | Phân tích RAM và tiến trình: phát hiện mã độc mạo danh `svchost.exe` ngoài System32, mã độc đào coin (`xmrig`, `miner`), cho phép cưỡng chế dừng (Kill PID). |
| **`[5]`** | **Dọn Rác & Tăng Tốc PC (System Cleaner)** | Xóa sạch User Temp, Windows Temp, Windows Prefetch, Crash Dumps, làm rỗng Thùng Rác (Recycle Bin) và Flush DNS. |
| **`[6]`** | **Kiểm Soát Khởi Động (Startup Shield)** | Quét Registry Run keys (`HKCU` và `HKLM`), cảnh báo script lạ hoặc file temp tự kích hoạt khi bật máy. |
| **`[7]`** | **Bảo Vệ File Hosts** | Phát hiện các dòng chuyển hướng lừa đảo / chiếm quyền DNS, cho phép 1-click khôi phục file `hosts` về mặc định của Microsoft. |
| **`[8]`** | **Kích Hoạt Windows Defender** | Tự động cập nhật chữ ký mẫu virus mới nhất từ Microsoft và kích hoạt quét nhanh qua Defender API. |
| **`[9]`** | **Quản Lý Khu Vực Cách Ly** | Xem danh sách các file mã độc đã bị cô lập an toàn tại `%LOCALAPPDATA%\SCOM_Quarantine`, xóa vĩnh viễn an toàn. |
| **`[T]`** | **Tạo Tệp Thử Nghiệm Chuẩn EICAR** | Tự động tạo tệp mẫu EICAR (chuẩn quốc tế vô hại) để bạn kiểm tra tính năng phát hiện của tool ngay lập tức. |
| **`[0]`** | **Thoát Tool** | Đóng giao diện terminal an toàn. |

---

## 🔍 Cơ Chế Phát Hiện Mã Độc (Heuristic & Signature)

- **Ngụy trang phần mở rộng kép (Double Extension):** Phát hiện các tệp như `document.pdf.exe`, `photo.jpg.scr`, `invoice.docx.vbs`.
- **Trá hình nhị phân (PE Header Mismatch):** Phát hiện tệp có đuôi ảnh/tài liệu (`.jpg`, `.png`, `.pdf`) nhưng ruột nhị phân lại chứa PE Executable Header (`MZ`).
- **Mạo danh tiến trình Windows:** Tệp mang tên `svchost.exe`, `csrss.exe`, `lsass.exe` nằm ngoài thư mục `C:\Windows\System32`.
- **Kịch bản độc hại (Malicious Scripts):** Phát hiện chuỗi tải mã độc từ xa (`downloadstring`, `invoke-webrequest`, `certutil -urlcache`, `vssadmin delete shadows`).
- **Chữ ký mã băm (MD5 / SHA256):** Kiểm tra đối chiếu với cơ sở dữ liệu mẫu mã độc và ransomware đã biết.
