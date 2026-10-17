# ============================================================================
# SCOM CYBERSHIELD v3.0 - SYSTEM CLEANER & OPTIMIZER MODULE
# ============================================================================
[CmdletBinding()]
param (
    [ValidateSet('CleanAll', 'Temp', 'RecycleBin', 'DNS', 'HostsReset')]
    [string]$Action = "CleanAll",

    [ValidateSet('Text', 'JSON')]
    [string]$OutputFormat = "Text",

    [switch]$NonInteractive
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Remove-DirectoryFilesSafely {
    param([string]$Path, [string]$Label)
    $deletedFiles = 0
    $freedBytes = 0

    if (Test-Path $Path) {
        Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $len = $_.Length
                Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                $deletedFiles++
                $freedBytes += $len
            } catch {}
        }
        Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    return [PSCustomObject]@{
        Label = $Label
        DeletedFiles = $deletedFiles
        FreedBytes = $freedBytes
        FreedMB = [Math]::Round(($freedBytes / 1MB), 2)
    }
}

$results = @()

if ($Action -eq "CleanAll" -or $Action -eq "Temp") {
    $results += Remove-DirectoryFilesSafely -Path $env:TEMP -Label "User Temp (%TEMP%)"
    $results += Remove-DirectoryFilesSafely -Path ([System.IO.Path]::Combine($env:LOCALAPPDATA, 'Temp')) -Label "LocalAppData Temp"
    $results += Remove-DirectoryFilesSafely -Path 'C:\Windows\Temp' -Label "Windows Temp"
    $results += Remove-DirectoryFilesSafely -Path 'C:\Windows\Prefetch' -Label "Windows Prefetch"
    $results += Remove-DirectoryFilesSafely -Path ([System.IO.Path]::Combine($env:LOCALAPPDATA, 'CrashDumps')) -Label "Crash Dumps"
    $results += Remove-DirectoryFilesSafely -Path ([System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft\Windows\WER')) -Label "Windows Error Reporting (WER)"
}

if ($Action -eq "CleanAll" -or $Action -eq "RecycleBin") {
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
        $results += [PSCustomObject]@{
            Label = "Thùng Rác (Recycle Bin)"
            DeletedFiles = 0
            FreedBytes = 0
            FreedMB = 0
            Status = "Cleaned"
        }
    } catch {}
}

if ($Action -eq "CleanAll" -or $Action -eq "DNS") {
    try {
        Clear-DnsClientCache -ErrorAction SilentlyContinue | Out-Null
        $results += [PSCustomObject]@{
            Label = "Bộ nhớ đệm DNS (DNS Cache)"
            DeletedFiles = 0
            FreedBytes = 0
            FreedMB = 0
            Status = "Flushed"
        }
    } catch {}
}

if ($Action -eq "HostsReset") {
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    $status = "Failed"
    $msg = ""
    $backupPath = ""
    try {
        if (Test-Path $hostsPath) {
            $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
            $backupPath = "$hostsPath.backup_$timestamp"
            Copy-Item -Path $hostsPath -Destination $backupPath -Force -ErrorAction Stop
        }
        $defaultHosts = "# Microsoft Windows default hosts file`r`n127.0.0.1 localhost`r`n::1 localhost`r`n"
        [System.IO.File]::WriteAllText($hostsPath, $defaultHosts, [System.Text.Encoding]::UTF8)
        $status = "Success"
        $msg = "Đã khôi phục file hosts về mặc định của Microsoft. Đã tự động tạo bản sao lưu tại: $backupPath"
    } catch {
        $status = "Error: $($_.Exception.Message)"
        $msg = "Không thể sửa file hosts (Yêu cầu quyền Administrator): $($_.Exception.Message)"
    }
    $results += [PSCustomObject]@{
        Label = "Hosts Shield Reset"
        Status = $status
        Message = $msg
        BackupPath = $backupPath
    }
}

$totalFreedMB = 0
$totalFiles = 0
foreach ($r in $results) {
    if ($r.FreedMB) { $totalFreedMB += $r.FreedMB }
    if ($r.DeletedFiles) { $totalFiles += $r.DeletedFiles }
}

if ($OutputFormat -eq 'JSON') {
    [PSCustomObject]@{
        Action = $Action
        Status = "Completed"
        TotalFilesDeleted = $totalFiles
        TotalFreedMB = [Math]::Round($totalFreedMB, 2)
        Details = $results
    } | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "             SCOM DEEP SYSTEM CLEANER - BÁO CÁO DỌN DẸP HỆ THỐNG" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor DarkGray
    foreach ($r in $results) {
        if ($r.DeletedFiles -gt 0) {
            Write-Host " [+] $($r.Label): Đã xóa $($r.DeletedFiles) tệp rác (Giải phóng $($r.FreedMB) MB)" -ForegroundColor Green
        } elseif ($r.Status) {
            Write-Host " [+] $($r.Label): $($r.Status)" -ForegroundColor Cyan
        } else {
            Write-Host " [*] $($r.Label): Đã sạch" -ForegroundColor Gray
        }
    }
    Write-Host "`n================================================================================" -ForegroundColor DarkGray
    Write-Host "[V] HOÀN TẤT DỌN DẸP: Đã xóa $totalFiles tệp rác, giải phóng $totalFreedMB MB dung lượng!" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor DarkGray
}
