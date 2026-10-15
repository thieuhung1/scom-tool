@echo off
REM ============================================================================
REM SCOM CYBERSHIELD - CONG CU QUET VA DON VIRUS CHUYEN NGHIEP CHO WINDOWS
REM Phien ban: 2.0 Terminal Pro
REM ============================================================================

title SCOM CYBERSHIELD - Tool Quet va Don Virus May Tinh
chcp 65001 >nul
color 0B

REM 1. Kiem tra quyen Administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo [*] Ban chua chay duoi quyen Administrator.
    echo [*] Dang thu yeu cau quyen Administrator UAC...
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs" 2>nul
    echo [!] Tiep tuc chay o che do thong thuong...
    echo.
)

set "SCRIPT_DIR=%~dp0"
set "PS_ENGINE=%SCRIPT_DIR%core_scanner.ps1"
set "QUARANTINE_DIR=%LOCALAPPDATA%\SCOM_Quarantine"

if not exist "%QUARANTINE_DIR%" mkdir "%QUARANTINE_DIR%" >nul 2>&1

:MAIN_MENU
cls
echo ================================================================================
echo             SCOM CYBERSHIELD - TERMINAL ANTIVIRUS ^& CLEANER PRO
echo                  CONG CU QUET VA DON DEP VIRUS MAY TINH
echo ================================================================================
echo  [Trang Thai]: San sang hoat dong   ^|   Khu cach ly: %QUARANTINE_DIR%
echo ================================================================================
echo.
echo   [1] Quet Nhanh He Thong (Quick Scan - Temp, AppData, Downloads, Startup)
echo   [2] Quet Thu Muc Tuy Chon (Custom Folder / File Scan)
echo   [3] Quet Toan Dien O Dia C:\ (Full Deep Scan)
echo   [4] Kiem Tra va Diet Tien Trinh La / Dao Coin (Process Hunter)
echo   [5] Don Dep File Rac, Temp va Tang Toc PC (Deep System Cleaner)
echo   [6] Kiem Tra Khoi Dong Windows va Autorun (Startup Inspector)
echo   [7] Kiem Tra va Khoi Phuc File Hosts Chong Chiem Quyen DNS
echo   [8] Kich Hoat Quet Windows Defender va Cap Nhat Signature
echo   [9] Quan Ly Khu Vuc Cach Ly (Xem / Xoa sach file doc hai)
echo   [T] Tao Tep Thu Nghiem Diet Virus Chuan Quoc Te EICAR
echo   [0] Thoat Tool
echo.
echo ================================================================================
set /p "CHOICE=>> Nhap lua chon cua ban [0-9, T]: "

if defined CHOICE set "CHOICE=%CHOICE: =%"

if "%CHOICE%"=="1" goto QUICK_SCAN
if "%CHOICE%"=="2" goto CUSTOM_SCAN
if "%CHOICE%"=="3" goto FULL_SCAN
if "%CHOICE%"=="4" goto PROCESS_HUNTER
if "%CHOICE%"=="5" goto SYSTEM_CLEANER
if "%CHOICE%"=="6" goto STARTUP_INSPECT
if "%CHOICE%"=="7" goto HOSTS_SHIELD
if "%CHOICE%"=="8" goto DEFENDER_TRIGGER
if "%CHOICE%"=="9" goto QUARANTINE_MANAGER
if /i "%CHOICE%"=="T" goto CREATE_TEST_SAMPLE
if "%CHOICE%"=="0" goto EXIT_TOOL

echo.
echo [!] Lua chon khong hop le. Vui long chon lai!
ping 127.0.0.1 -n 2 >nul
goto MAIN_MENU

:: ============================================================================
:: 1. QUET NHANH
:: ============================================================================
:QUICK_SCAN
cls
echo ================================================================================
echo                 [1] QUET NHANH CAC KHU VUC XUNG YEU (QUICK SCAN)
echo ================================================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "Quick" -QuarantineDir "%QUARANTINE_DIR%"
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 2. QUET TUY CHON
:: ============================================================================
:CUSTOM_SCAN
cls
echo ================================================================================
echo                     [2] QUET THU MUC HOAC TEP TUY CHON
echo ================================================================================
echo Keo va tha thu muc hoac tep tin vao day roi nhan Enter (hoac go duong dan).
echo Vi du: D:\Downloads hoac C:\Users\Username\Documents
echo.
set /p "TARGET_PATH=>> Nhap duong dan can quet: "
set "TARGET_PATH=%TARGET_PATH:"=%"

if not exist "%TARGET_PATH%" (
    echo [!] Duong dan khong ton tai: "%TARGET_PATH%"
    pause
    goto MAIN_MENU
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "Custom" -TargetPath "%TARGET_PATH%" -QuarantineDir "%QUARANTINE_DIR%"
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 3. QUET TOAN DIEN
:: ============================================================================
:FULL_SCAN
cls
echo ================================================================================
echo                     [3] QUET TOAN DIEN HE THONG (FULL SCAN)
echo ================================================================================
echo Che do quet toan dien se quet cac thu muc tren o C:\.
echo.
set /p "CONFIRM=>> Ban co muon bat dau quet toan dien ngay bay gio? (Y/N): "
if /i not "%CONFIRM%"=="Y" goto MAIN_MENU

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "Full" -QuarantineDir "%QUARANTINE_DIR%"
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 4. PROCESS HUNTER
:: ============================================================================
:PROCESS_HUNTER
cls
echo ================================================================================
echo             [4] SAN LUNG VA DIET TIEN TRINH DOC HAI / DAO COIN (PROCESS HUNTER)
echo ================================================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "ProcessHunter"
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 5. DON DEP HE THONG
:: ============================================================================
:SYSTEM_CLEANER
cls
echo ================================================================================
echo           [5] DON DEP TEP RAC, TEMP VA TOI UU HOA HE THONG (SYSTEM CLEANER)
echo ================================================================================
echo Dang tien hanh giai phong dung luong o dia va xoa sach cac cache rac...
echo.

echo [*] 1. Dang xoa tep tam User Temp (%TEMP%)...
del /s /f /q "%TEMP%\*.*" >nul 2>&1
for /d %%p in ("%TEMP%\*.*") do rmdir /s /q "%%p" >nul 2>&1

echo [*] 2. Dang xoa tep tam Windows Temp (C:\Windows\Temp)...
del /s /f /q "C:\Windows\Temp\*.*" >nul 2>&1
for /d %%p in ("C:\Windows\Temp\*.*") do rmdir /s /q "%%p" >nul 2>&1

echo [*] 3. Dang xoa bo nho dem nap truoc (Windows Prefetch)...
del /s /f /q "C:\Windows\Prefetch\*.*" >nul 2>&1

echo [*] 4. Dang xoa nhat ky loi Crash Dumps va WER...
if exist "%LOCALAPPDATA%\CrashDumps" (
    del /s /f /q "%LOCALAPPDATA%\CrashDumps\*.*" >nul 2>&1
)
if exist "%LOCALAPPDATA%\Microsoft\Windows\WER" (
    del /s /f /q "%LOCALAPPDATA%\Microsoft\Windows\WER\*.*" >nul 2>&1
)

echo [*] 5. Dang lam sach Thung Rac (Recycle Bin)...
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1

echo [*] 6. Dang xoa bo nho dem DNS (Flush DNS Cache)...
ipconfig /flushdns >nul 2>&1

echo.
echo ================================================================================
echo [V] DA HOAN TAT DON DEP TEP RAC VA TOI UU HE THONG THANH CONG!
echo ================================================================================
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 6. KHOI DONG WINDOWS
:: ============================================================================
:STARTUP_INSPECT
cls
echo ================================================================================
echo             [6] KIEM SOAT MUC KHOI DONG REGISTRY (STARTUP SHIELD)
echo ================================================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "Startup"
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 7. FILE HOSTS
:: ============================================================================
:HOSTS_SHIELD
cls
echo ================================================================================
echo                 [7] KIEM TRA VA KHOI PHUC TEP HOSTS CHONG CHIEM QUYEN DNS
echo ================================================================================
echo Tep Hosts nam tai: C:\Windows\System32\drivers\etc\hosts
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "Hosts"
echo.
echo  [1] Khoi phuc tep Hosts ve trang thai mac dinh cua Microsoft
echo  [0] Quay lai Menu Chinh
echo.
set /p "HOST_CHOICE=>> Nhap lua chon: "
if "%HOST_CHOICE%"=="1" (
    powershell -NoProfile -Command "
        $defaultHosts = '# Microsoft Windows default hosts file`r`n127.0.0.1 localhost`r`n::1 localhost';
        Set-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value $defaultHosts -Force;
    "
    echo [+] Da khoi phuc tep Hosts ve mac dinh thanh cong!
    pause
)
goto MAIN_MENU

:: ============================================================================
:: 8. WINDOWS DEFENDER
:: ============================================================================
:DEFENDER_TRIGGER
cls
echo ================================================================================
echo           [8] KICH HOAT QUET WINDOWS DEFENDER VA CAP NHAT CHU KY
echo ================================================================================
echo.
echo [*] Dang cap nhat co so du lieu ma doc Microsoft Defender moi nhat...
powershell -NoProfile -Command "Update-MpSignature" >nul 2>&1
echo [+] Da cap nhat chu ky Defender thanh cong!
echo.
echo [*] Dang bat dau tien trinh Quet Nhanh qua Windows Defender API...
powershell -NoProfile -Command "Start-MpScan -ScanType QuickScan"
echo.
echo [+] Tien trinh quet cua Windows Defender da hoan tat!
pause
goto MAIN_MENU

:: ============================================================================
:: 9. KHU VUC CACH LY
:: ============================================================================
:QUARANTINE_MANAGER
cls
echo ================================================================================
echo                    [9] QUAN LY KHU VUC CACH LY (QUARANTINE)
echo ================================================================================
echo Thu muc luu tru: %QUARANTINE_DIR%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "QuarantineList" -QuarantineDir "%QUARANTINE_DIR%"
echo.
echo  [1] Xoa sach toan bo cac tep trong khu cach ly (Secure Wipe)
echo  [2] Mo thu muc cach ly trong File Explorer
echo  [0] Quay lai Menu Chinh
echo.
set /p "Q_CHOICE=>> Nhap lua chon: "
if "%Q_CHOICE%"=="1" (
    del /f /q "%QUARANTINE_DIR%\*.*" >nul 2>&1
    echo [+] Da xoa sach toan bo tep trong khu cach ly!
    pause
)
if "%Q_CHOICE%"=="2" (
    explorer "%QUARANTINE_DIR%"
)
goto MAIN_MENU

:: ============================================================================
:: T. TAO TEP THU NGHIEM EICAR
:: ============================================================================
:CREATE_TEST_SAMPLE
cls
echo ================================================================================
echo             [T] TAO TEP MAU THU NGHIEM DIET VIRUS CHUAN QUOC TE (EICAR)
echo ================================================================================
echo EICAR la chuoi ma tieu chuan quoc te duoc tat ca cac hang bao mat (Kaspersky,
echo Defender, Bitdefender, Symantec...) cong nhan de kiem tra tinh nang quet virus
echo mot cach AN TOAN 100%%, KHONG HE CHUA MA DOC THUC SU.
echo.
set "TEST_FILE=%TEMP%\eicar_test_sample.com"
powershell -NoProfile -Command "[System.IO.File]::WriteAllText('%TEST_FILE%', 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*')"
echo [+] Da tao tep thu nghiem tai: %TEST_FILE%
echo [+] Bay gio ban co the quay lai Menu va chon [1] Quet Nhanh de xem tool phat hien!
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: THOAT
:: ============================================================================
:EXIT_TOOL
cls
echo ================================================================================
echo     Cam on ban da su dung SCOM CyberShield. Chuc may tinh cua ban luon an toan!
echo ================================================================================
ping 127.0.0.1 -n 2 >nul
exit /b
