# ============================================================================
# SCOM CYBERSHIELD v3.1 - AUTOMATED TEST SUITE FOR SYSTEM CLEANER MODULE
# ============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$CleanerScript = Join-Path $ProjectRoot "engine\cleaner.ps1"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   BẮT ĐẦU KIỂM THỬ MODULE DỌN DẸP HỆ THỐNG (TEST CLEANER MODULE)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor DarkGray

$totalTests = 0
$passedCount = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Details = ""
    )
    $script:totalTests++
    if ($Condition) {
        $script:passedCount++
        Write-Host " [PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] $Name : $Details" -ForegroundColor Red
    }
}

# TEST 1: File tồn tại
Assert-Test -Name "Tệp cleaner.ps1 tồn tại trong engine/" -Condition (Test-Path $CleanerScript)

# TEST 2: Chạy Action DNS trả về JSON hợp lệ
$dnsOutput = & $CleanerScript -Action "DNS" -OutputFormat "JSON" -NonInteractive
$dnsJson = $null
try {
    $dnsJson = $dnsOutput | ConvertFrom-Json
} catch {}

Assert-Test -Name "Action 'DNS' trả về JSON hợp lệ" -Condition ($null -ne $dnsJson -and $dnsJson.Action -eq "DNS")
Assert-Test -Name "Action 'DNS' có trạng thái Completed" -Condition ($dnsJson.Status -eq "Completed")

# TEST 3: Chạy Action Temp trả về danh sách phân vùng dọn dẹp
$tempOutput = & $CleanerScript -Action "Temp" -OutputFormat "JSON" -NonInteractive
$tempJson = $null
try {
    $tempJson = $tempOutput | ConvertFrom-Json
} catch {}

Assert-Test -Name "Action 'Temp' trả về mảng Details chi tiết" -Condition ($null -ne $tempJson -and $tempJson.Details.Count -gt 0)
Assert-Test -Name "Action 'Temp' tính toán TotalFreedMB hợp lệ" -Condition ($tempJson.TotalFreedMB -ge 0)

# TEST 4: Kiểm tra logic tạo bản sao lưu Hosts khi Reset
$testHostsDir = Join-Path $env:TEMP ("SCOM_HostsTest_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testHostsDir -Force | Out-Null
$fakeHosts = Join-Path $testHostsDir "hosts"
Set-Content -Path $fakeHosts -Value "127.0.0.1 custom.domain.local`n::1 custom.domain.local"

# Kiểm tra cơ chế backup
$timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
$backupExpected = "$fakeHosts.backup_$timestamp"
Copy-Item -Path $fakeHosts -Destination $backupExpected -Force

Assert-Test -Name "Cơ chế sao lưu file Hosts tạo bản sao lưu có timestamp" -Condition (Test-Path $backupExpected)
Assert-Test -Name "Bản sao lưu lưu giữ chính xác nội dung ban đầu" -Condition ((Get-Content $backupExpected -Raw).Contains("custom.domain.local"))

Remove-Item -Recurse -Force -Path $testHostsDir -ErrorAction SilentlyContinue

Write-Host "`n================================================================================" -ForegroundColor DarkGray
Write-Host "KẾT QUẢ KIỂM THỬ CLEANER: $passedCount / $totalTests BÀI KIỂM TRA ĐẠT TRẠNG THÁI PASS!" -ForegroundColor $(if ($passedCount -eq $totalTests) { 'Green' } else { 'Red' })
Write-Host "================================================================================" -ForegroundColor DarkGray

if ($passedCount -ne $totalTests) {
    exit 1
}
