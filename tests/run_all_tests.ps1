# ============================================================================
# SCOM CYBERSHIELD v3.1 - RUN ALL AUTOMATED TESTS
# ============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "`n>>> [1/2] CHẠY TEST BỘ MÁY QUÉT MÃ ĐỘC (CORE SCANNER)..." -ForegroundColor Cyan
& (Join-Path $ScriptDir "test_core_scanner.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Core scanner test thất bại với mã lỗi: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n>>> [2/2] CHẠY TEST MODULE DỌN DẸP HỆ THỐNG (CLEANER)..." -ForegroundColor Cyan
& (Join-Path $ScriptDir "test_cleaner.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Cleaner test thất bại với mã lỗi: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host " [V] TẤT CẢ 19/19 BÀI KIỂM THỬ ĐÃ ĐẠT TRẠNG THÁI PASS (100% SUCCESS)!" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
exit 0
