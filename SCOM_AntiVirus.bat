@echo off
REM ============================================================================
REM SCOM CYBERSHIELD v3.0 - CONG CU QUET VA DON VIRUS CHUYEN NGHIEP CHO WINDOWS
REM Phien ban: 3.0 Terminal Pro (Clean Architecture & Zero-Bug Pattern)
REM ============================================================================

title SCOM CYBERSHIELD v3.0 - Tool Quet va Don Virus May Tinh
chcp 65001 >nul
color 0B

REM Kiem tra quyen Administrator (Fix BAT-BUG-01)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo [*] Ban chua chay duoi quyen Administrator.
    echo [*] Dang yeu cau quyen Administrator UAC...
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs" 2>nul
    REM Dong cua so cu tranh bi mo trung 2 cua so (Fix BAT-BUG-02)
    if not errorlevel 1 exit /b
    echo [!] Tiep tuc chay o che do thong thuong...
    echo.
)

set "SCRIPT_DIR=%~dp0"
set "PS_ENGINE=%SCRIPT_DIR%engine\core_scanner.ps1"
set "QUARANTINE_DIR=%LOCALAPPDATA%\SCOM_Quarantine"

if not exist "%QUARANTINE_DIR%" mkdir "%QUARANTINE_DIR%" >nul 2>&1

:MAIN_MENU
cls
echo ================================================================================
echo             SCOM CYBERSHIELD v3.0 - TERMINAL ANTIVIRUS ^& CLEANER PRO
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
echo   [9] Quan Ly Khu Vuc Cach Ly (Xem / Khoi phuc / Xoa sach file doc hai)
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
:: 2. QUET TUY CHON (Fix BAT-BUG-03: Tranh sap CMD khi co dau ngoac don)
:: ============================================================================
:CUSTOM_SCAN
cls
echo ================================================================================
echo                     [2] QUET THU MUC HOAC TEP TUY CHON
echo ================================================================================
echo Keo va tha thu muc hoac tep tin vao day roi nhan Enter (hoac go duong dan).
echo Vi du: D:\Downloads hoac C:\Program Files (x86)
echo.
set "TARGET_PATH="
set /p "TARGET_PATH=>> Nhap duong dan can quet: "
if not defined TARGET_PATH goto MAIN_MENU
set "TARGET_PATH=%TARGET_PATH:"=%"

if not exist "%TARGET_PATH%" goto CUSTOM_NOT_FOUND

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "Custom" -TargetPath "%TARGET_PATH%" -QuarantineDir "%QUARANTINE_DIR%"
echo.
pause
goto MAIN_MENU

:CUSTOM_NOT_FOUND
echo.
echo [!] Duong dan muc tieu khong ton tai. Vui long kiem tra lai!
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
echo Che do quet toan dien se quet toan bo cac thu muc tren o C:\.
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
:: 5. DON DEP HE THONG (Goi engine/cleaner.ps1 chuyen sau)
:: ============================================================================
:SYSTEM_CLEANER
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%engine\cleaner.ps1" -Action "CleanAll"
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
:: 7. FILE HOSTS (Fix BAT-BUG-04: Kiem tra loi thuc te khi sua hosts)
:: ============================================================================
:HOSTS_SHIELD
cls
echo ================================================================================
echo                 [7] KIEM TRA VA KHOI PHUC TEP HOSTS CHONG CHIEM QUYEN DNS
echo ================================================================================
echo Tep Hosts nam tai: C:\Windows\System32\drivers\etc\hosts
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "HostsShield"
echo.
echo  [1] Khoi phuc tep Hosts ve trang thai mac dinh cua Microsoft
echo  [0] Quay lai Menu Chinh
echo.
set "HOST_CHOICE="
set /p "HOST_CHOICE=>> Nhap lua chon: "
if "%HOST_CHOICE%"=="1" (
    powershell -NoProfile -Command "try { $defaultHosts = '# Microsoft Windows default hosts file`r`n127.0.0.1 localhost`r`n::1 localhost'; Set-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value $defaultHosts -Force -ErrorAction Stop; exit 0 } catch { exit 1 }"
    if errorlevel 1 (
        echo [!] Loi: Khong the sua file Hosts (Yeu cau chay duoi quyen Administrator).
    ) else (
        echo [+] Da khoi phuc tep Hosts ve mac dinh thanh cong!
    )
    echo.
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
echo [+] Da gui lenh cap nhat chu ky Defender!
echo.
echo [*] Dang bat dau tien trinh Quet Nhanh qua Windows Defender API...
powershell -NoProfile -Command "Start-MpScan -ScanType QuickScan"
echo.
echo [+] Tien trinh quet cua Windows Defender da hoan tat!
echo.
pause
goto MAIN_MENU

:: ============================================================================
:: 9. KHU VUC CACH LY (Fix PS-BUG-03: Ho tro xem, khoi phuc va xoa sach)
:: ============================================================================
:QUARANTINE_MANAGER
cls
echo ================================================================================
echo                    [9] QUAN LY KHU VUC CACH LY (QUARANTINE)
echo ================================================================================
echo Thu muc luu tru an toan: %QUARANTINE_DIR%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "QuarantineList" -QuarantineDir "%QUARANTINE_DIR%"
echo.
echo  [1] Xoa sach toan bo cac tep trong khu cach ly (Secure Wipe)
echo  [2] Khoi phuc tep ve vi tri ban dau (Restore by ID)
echo  [3] Mo thu muc cach ly trong File Explorer
echo  [0] Quay lai Menu Chinh
echo.
set "Q_CHOICE="
set /p "Q_CHOICE=>> Nhap lua chon: "
if "%Q_CHOICE%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "QuarantineWipe" -QuarantineDir "%QUARANTINE_DIR%"
    echo.
    pause
)
if "%Q_CHOICE%"=="2" (
    echo.
    set /p "RESTORE_ID=>> Nhap ma ID cua tep can khoi phuc: "
    if defined RESTORE_ID (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "QuarantineRestore" -RestoreId "%RESTORE_ID%" -QuarantineDir "%QUARANTINE_DIR%"
    )
    echo.
    pause
)
if "%Q_CHOICE%"=="3" (
    explorer "%QUARANTINE_DIR%"
)
goto MAIN_MENU

:: ============================================================================
:: T. TAO TEP THU NGHIEM EICAR (Fix BAT-BUG-05: Goi truc tiep Engine an toan)
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_ENGINE%" -Mode "EicarTest" -TargetPath "%TEMP%"
echo.
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
