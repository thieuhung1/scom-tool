# ============================================================================
# SCOM CYBERSHIELD v3.1 - CORE SCANNER ENGINE (SECURITY HARDENED)
# Kiến trúc 5 lớp nhận diện mã độc Heuristic-First & Zero-Bug Pattern
# ============================================================================
[CmdletBinding()]
param (
    [ValidateSet('Quick', 'Custom', 'Full', 'ProcessHunter', 'Startup', 'HostsShield', 'QuarantineList', 'QuarantineRestore', 'QuarantineWipe', 'EicarTest')]
    [string]$Mode = "Quick",

    [string]$TargetPath = "",
    [string]$QuarantineDir = "",
    [string]$RestoreId = "",

    [int]$MaxDepth = 12,
    [int]$MaxFiles = 25000,

    [ValidateSet('Text', 'JSON')]
    [string]$OutputFormat = "Text",

    [switch]$NonInteractive,
    [switch]$AutoQuarantine
)

# Thiết lập UTF-8 chuẩn
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Tệp cờ hủy hợp tác (Cooperative Cancellation Flag)
$CancelFlagPath = Join-Path $env:TEMP "scom_cancel_scan.flag"

# Nạp cơ sở dữ liệu Chữ ký nhận diện (signatures.json)
$EngineDir = $PSScriptRoot
if (-not $EngineDir) {
    $EngineDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$SigPath = Join-Path $EngineDir "signatures.json"

$Signatures = $null
if (Test-Path $SigPath) {
    try {
        $rawJson = Get-Content -Path $SigPath -Raw -Encoding UTF8
        $Signatures = $rawJson | ConvertFrom-Json
    } catch {
        $Signatures = $null
    }
}

# Cấu hình danh sách mẫu nhận diện
$suspiciousDoubleExt = if ($Signatures -and $Signatures.suspiciousDoubleExtensions) {
    $Signatures.suspiciousDoubleExtensions
} else {
    @('.pdf.exe', '.docx.exe', '.xlsx.exe', '.jpg.exe', '.png.exe', '.mp4.exe', '.txt.exe', '.zip.exe', '.pdf.vbs', '.doc.scr', '.jpg.scr')
}

$fakeSystemNames = if ($Signatures -and $Signatures.disguisedSystemProcesses) {
    $Signatures.disguisedSystemProcesses
} else {
    @('svchost.exe', 'csrss.exe', 'lsass.exe', 'services.exe', 'smss.exe', 'winlogon.exe', 'wininit.exe', 'taskhostw.exe', 'runtimebroker.exe', 'spoolsv.exe')
}

$execExts = if ($Signatures -and $Signatures.executableExtensions) {
    $Signatures.executableExtensions
} else {
    @('.exe', '.dll', '.sys', '.scr', '.com', '.bat', '.cmd', '.ps1', '.vbs', '.hta', '.js', '.wsf', '.cpl')
}

$minerKeywords = if ($Signatures -and $Signatures.coinMinerKeywords) {
    $Signatures.coinMinerKeywords
} else {
    @('xmrig', 'cpuminer', 'ccminer', 'nicehash', 'minerd', 'ethminer', 'phoenixminer', 'srbminer', 'cryptonight')
}

if (-not $QuarantineDir) {
    $QuarantineDir = Join-Path $env:LOCALAPPDATA "SCOM_Quarantine"
}
if (-not (Test-Path $QuarantineDir)) {
    New-Item -ItemType Directory -Path $QuarantineDir -Force | Out-Null
    try {
        $acl = Get-Acl $QuarantineDir
        $acl.SetAccessRuleProtection($true, $true)
        Set-Acl -Path $QuarantineDir -AclObject $acl
    } catch {}
}
$ManifestPath = Join-Path $QuarantineDir "quarantine_manifest.json"

# ============================================================================
# HÀM BỔ TRỢ & KIỂM TRA ĐƯỜNG DẪN HỆ THỐNG CHUẨN (Fix PS-BUG-05)
# ============================================================================
function Test-LegitSystemPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = $Path.Trim().ToLower()
    $winDir = $env:SystemRoot.ToLower()
    $legitDirs = @(
        "$winDir\system32\",
        "$winDir\syswow64\",
        "$winDir\winsxs\"
    )
    foreach ($dir in $legitDirs) {
        if ($p.StartsWith($dir) -or $p.Contains($dir)) {
            return $true
        }
    }
    # Tệp giao diện Windows Explorer chính thống nằm trực tiếp tại C:\Windows\explorer.exe
    if ($p -eq "$winDir\explorer.exe") {
        return $true
    }
    return $false
}

# ============================================================================
# BỘ DUYỆT TỆP TIN KIỂM SOÁT TÀI NGUYÊN (Resource-Controlled File Enumerator)
# Giới hạn độ sâu, danh sách loại trừ và hỗ trợ hủy hợp tác
# ============================================================================
function Get-ScannableFiles {
    param(
        [string]$RootPath,
        [int]$LimitDepth = 12,
        [int]$LimitFiles = 25000,
        [string]$CancelFlag = ""
    )

    $excludedDirNames = @('.git', 'node_modules', 'vendor', '$recycle.bin', 'system volume information', 'inetcache')

    if (-not (Test-Path $RootPath)) { return }

    if ((Get-Item $RootPath) -is [System.IO.FileInfo]) {
        Get-Item $RootPath
        return
    }

    $queue = New-Object System.Collections.Generic.Queue[PSCustomObject]
    $queue.Enqueue([PSCustomObject]@{ Path = $RootPath; Depth = 0 })

    $count = 0

    while ($queue.Count -gt 0 -and $count -lt $LimitFiles) {
        if ($CancelFlag -and (Test-Path $CancelFlag)) {
            break
        }

        $current = $queue.Dequeue()
        $dir = $current.Path
        $depth = $current.Depth

        try {
            $files = [System.IO.Directory]::GetFiles($dir)
            foreach ($f in $files) {
                if ($CancelFlag -and (Test-Path $CancelFlag)) { break }
                $count++
                if ($count -gt $LimitFiles) { break }
                try {
                    New-Object System.IO.FileInfo($f)
                } catch {}
            }
        } catch {}

        if ($depth -lt $LimitDepth) {
            try {
                $subDirs = [System.IO.Directory]::GetDirectories($dir)
                foreach ($sd in $subDirs) {
                    $dName = [System.IO.Path]::GetFileName($sd).ToLower()
                    if ($excludedDirNames -contains $dName) { continue }

                    # Bỏ qua ReparsePoint / Junction để tránh loop
                    try {
                        $di = New-Object System.IO.DirectoryInfo($sd)
                        if ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                            continue
                        }
                    } catch {}

                    $queue.Enqueue([PSCustomObject]@{ Path = $sd; Depth = $depth + 1 })
                }
            } catch {}
        }
    }
}

# ============================================================================
# HÀM QUÉT 5 LỚP CHO MỘT TỆP TIN (Fix PS-BUG-01, PS-BUG-02)
# ============================================================================
function Scan-FileRecord {
    param([System.IO.FileInfo]$file)

    if (-not $file -or -not (Test-Path $file.FullName)) { return $null }

    $name = $file.Name.ToLower()
    $ext = $file.Extension.ToLower()
    $threatReason = $null
    $threatSeverity = "Cao"
    $threatHash = ""

    # LỚP 1: Kiểm tra đuôi kép giả mạo tài liệu / hình ảnh
    foreach ($dExt in $suspiciousDoubleExt) {
        if ($name.EndsWith($dExt)) {
            $threatReason = "Trojan.Disguise.DoubleExtension ($dExt)"
            $threatSeverity = "Cực Kỳ Nguy Hiểm"
            break
        }
    }

    # LỚP 2: Kiểm tra mạo danh tiến trình Windows cốt lõi ngoài thư mục chuẩn (Fix PS-BUG-05)
    if (-not $threatReason) {
        foreach ($sysName in $fakeSystemNames) {
            if ($name -eq $sysName.ToLower()) {
                if (-not (Test-LegitSystemPath -Path $file.FullName)) {
                    $threatReason = "Trojan.Masquerade.FakeSystemFile ($sysName)"
                    $threatSeverity = "Cực Kỳ Nguy Hiểm"
                    break
                }
            }
        }
    }

    # LỚP 3: Phân tích MZ Magic Bytes trong tệp hình ảnh/tài liệu (Fix PS-BUG-01: An toàn giải phóng luồng)
    if (-not $threatReason -and $file.Length -gt 2) {
        $docExts = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.pdf', '.txt', '.docx', '.xlsx', '.mp4')
        if ($docExts -contains $ext) {
            $stream = $null
            try {
                $stream = New-Object System.IO.FileStream(
                    $file.FullName,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite
                )
                $buf = New-Object byte[] 2
                $bytesRead = $stream.Read($buf, 0, 2)
                if ($bytesRead -ge 2 -and $buf[0] -eq 0x4D -and $buf[1] -eq 0x5A) {
                    $threatReason = "Trojan.PE.DisguisedAsDocument (Header MZ trong tệp $ext)"
                    $threatSeverity = "Cực Kỳ Nguy Hiểm"
                }
            } catch {
            } finally {
                if ($null -ne $stream) {
                    $stream.Dispose()
                    $stream = $null
                }
            }
        }
    }

    # LỚP 4: Đối chiếu mã băm MD5 / SHA256 (Fix PS-BUG-02: Bỏ nghẽn I/O, chỉ băm tệp khả thi hoặc < 100KB)
    if (-not $threatReason) {
        $shouldHash = ($file.Length -lt 100KB) -or (($execExts -contains $ext) -and ($file.Length -lt 50MB))
        if ($shouldHash) {
            try {
                $md5 = (Get-FileHash -Path $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
                if ($md5) {
                    $md5 = $md5.ToLower()
                    $threatHash = $md5
                    if ($Signatures -and $Signatures.knownHashes) {
                        $known = $Signatures.knownHashes.$md5
                        if ($known) {
                            $threatReason = "$($known.name) ($($known.type))"
                            $threatSeverity = $known.severity
                        }
                    }
                }

                # Nếu chưa khớp MD5 và là tệp thực thi, đối chiếu SHA256
                if (-not $threatReason -and ($execExts -contains $ext) -and ($file.Length -lt 50MB)) {
                    $sha256 = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    if ($sha256) {
                        $sha256 = $sha256.ToLower()
                        if ($Signatures -and $Signatures.knownHashes) {
                            $known = $Signatures.knownHashes.$sha256
                            if ($known) {
                                $threatHash = $sha256
                                $threatReason = "$($known.name) ($($known.type))"
                                $threatSeverity = $known.severity
                            }
                        }
                    }
                }
            } catch {}
        }
    }

    # LỚP 5: Phân tích hành vi kịch bản độc hại động từ signatures.json (< 5MB)
    if (-not $threatReason -and ($file.Length -lt 5MB)) {
        $scriptExts = @('.ps1', '.bat', '.cmd', '.vbs', '.hta', '.js', '.wsf', '.txt', '.com')
        if ($scriptExts -contains $ext -or $file.Length -lt 50KB) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    if ($Signatures -and $Signatures.maliciousScriptPatterns) {
                        foreach ($sp in $Signatures.maliciousScriptPatterns) {
                            if ($content -match $sp.pattern) {
                                $threatReason = $sp.name
                                $threatSeverity = $sp.severity
                                break
                            }
                        }
                    }
                    if (-not $threatReason) {
                        if ($content -match 'powershell.*(-enc|-encodedcommand|downloadstring|downloadfile|invoke-webrequest|iwr|invoke-restmethod|irm|bypass|-w\s+hidden)') {
                            $threatReason = "Script.Malicious.PowerShellDownloadCradle"
                            $threatSeverity = "Cao"
                        } elseif ($content -match '(invoke-expression|iex)\s*(\(|\[|\$|`|")') {
                            $threatReason = "Script.Malicious.InvokeExpressionExecution"
                            $threatSeverity = "Cao"
                        } elseif ($content -match 'certutil.*(-urlcache|-split|-f)') {
                            $threatReason = "Script.Malicious.CertutilAbuse"
                            $threatSeverity = "Cao"
                        } elseif ($content -match 'vssadmin.*delete.*shadows') {
                            $threatReason = "Ransomware.Behavior.ShadowCopyDeletion"
                            $threatSeverity = "Cực Kỳ Nguy Hiểm"
                        }
                    }
                }
            } catch {}
        }
    }

    if ($threatReason) {
        return [PSCustomObject]@{
            Path = $file.FullName
            Name = $file.Name
            Size = $file.Length
            Reason = $threatReason
            Severity = $threatSeverity
            Hash = $threatHash
        }
    }

    return $null
}

# ============================================================================
# QUẢN LÝ KHU CÁCH LY CHUNG (CỨNG HÓA ACL & BẢO VỆ TOÀN VẸN MÃ BĂM)
# ============================================================================
function Get-QuarantineManifest {
    if (Test-Path $ManifestPath) {
        try {
            $raw = Get-Content -Path $ManifestPath -Raw -Encoding UTF8
            return ($raw | ConvertFrom-Json)
        } catch {
            return @()
        }
    }
    return @()
}

function Save-QuarantineManifest {
    param([array]$Items)
    try {
        $json = $Items | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($ManifestPath, $json, [System.Text.Encoding]::UTF8)
    } catch {}
}

function Invoke-QuarantineAction {
    param(
        [array]$Threats,
        [string]$TargetQuarantineDir,
        [bool]$IsNonInteractive,
        [bool]$DoAutoQuarantine,
        [string]$CurrentOutputFormat
    )

    if (-not $Threats -or $Threats.Count -eq 0) { return @() }

    $shouldQuarantine = $DoAutoQuarantine
    if (-not $IsNonInteractive -and -not $DoAutoQuarantine) {
        Write-Host "`n"
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host "[!] CẢNH BÁO: Phát hiện $($Threats.Count) mối đe dọa độc hại cần xử lý an toàn!" -ForegroundColor Red
        $ans = Read-Host ">> Bạn có muốn CÁCH LY toàn bộ các tệp độc hại này vào Khu An Toàn không? (Y/N)"
        if ($ans -eq 'Y' -or $ans -eq 'y') {
            $shouldQuarantine = $true
        }
    }

    $results = @()
    if ($shouldQuarantine) {
        $manifest = @(Get-QuarantineManifest)

        foreach ($t in $Threats) {
            $quarantineId = [Guid]::NewGuid().ToString("N").Substring(0, 12)
            $timestamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
            $quarantineFileName = "$($t.Name).$timestamp.$quarantineId.quarantined"
            $destPath = Join-Path $TargetQuarantineDir $quarantineFileName

            # 1. Tính mã băm SHA256 để bảo vệ tính toàn vẹn khi khôi phục
            $sha256 = ""
            try {
                $sha256 = (Get-FileHash -Path $t.Path -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            } catch {}

            $actionStatus = "Failed"
            try {
                Move-Item -Path $t.Path -Destination $destPath -Force -ErrorAction Stop
                
                # Cấm ghi đè và đặt cờ ReadOnly để vô hiệu hóa
                try { (Get-Item $destPath).IsReadOnly = $true } catch {}

                $actionStatus = "Success"

                $entry = [PSCustomObject]@{
                    Id = $quarantineId
                    OriginalPath = $t.Path
                    FileName = $t.Name
                    FileSize = $t.Size
                    Sha256 = $sha256
                    Reason = $t.Reason
                    Severity = $t.Severity
                    QuarantinedAt = [DateTime]::UtcNow.ToString("o")
                    QuarantinedFile = $quarantineFileName
                }
                $manifest += $entry

                if ($CurrentOutputFormat -eq 'Text') {
                    Write-Host " [+] Đã cách ly an toàn (SHA256 lưu trữ): $($t.Name) -> $quarantineFileName" -ForegroundColor Cyan
                }
            } catch {
                if ($CurrentOutputFormat -eq 'Text') {
                    Write-Host " [-] Lỗi cách ly (Tệp đang được sử dụng hoặc bị khóa): $($t.Path)" -ForegroundColor Red
                }
            }

            $results += [PSCustomObject]@{
                Path = $t.Path
                Status = $actionStatus
                QuarantineId = $quarantineId
            }
        }

        Save-QuarantineManifest -Items $manifest
    }

    return $results
}

# ============================================================================
# CÁC CHẾ ĐỘ XỬ LÝ (MODES)
# ============================================================================

# 1. QUÉT NHANH (Quick Scan)
if ($Mode -eq "Quick") {
    $targets = @(
        $env:TEMP,
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Temp'),
        [System.IO.Path]::Combine($env:USERPROFILE, 'Downloads'),
        [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\Startup'),
        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup',
        'C:\Windows\Temp'
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "     SCOM CYBERSHIELD v3.1 - QUÉT NHANH CÁC KHU VỰC XUNG YẾU (QUICK SCAN)" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
        Write-Host "[*] Vùng quét: Temp, AppData\Temp, Downloads, Startup, Windows Temp" -ForegroundColor Gray
    }

    $scanned = 0
    $threats = @()
    $wasCancelled = $false

    foreach ($dir in $targets) {
        if (-not (Test-Path $dir)) { continue }
        if (Test-Path $CancelFlagPath) { $wasCancelled = $true; break }

        if ($OutputFormat -eq 'Text') {
            Write-Host "`n -> Đang quét vùng: $dir" -ForegroundColor DarkCyan
        }

        $files = Get-ScannableFiles -RootPath $dir -LimitDepth $MaxDepth -LimitFiles $MaxFiles -CancelFlag $CancelFlagPath
        foreach ($fileObj in $files) {
            if (Test-Path $CancelFlagPath) { $wasCancelled = $true; break }
            $scanned++
            $t = Scan-FileRecord -file $fileObj
            if ($t) {
                $threats += $t
                if ($OutputFormat -eq 'Text') {
                    Write-Host "`n [!] PHÁT HIỆN: $($t.Path)" -ForegroundColor Red
                    Write-Host "     Phân loại: $($t.Reason) | Mức độ: $($t.Severity)" -ForegroundColor Yellow
                }
            } elseif ($OutputFormat -eq 'Text' -and ($scanned % 50 -eq 0)) {
                Write-Host -NoNewline "."
            }

            if ($scanned % 50 -eq 0 -and $OutputFormat -eq 'JSON') {
                Write-Output ("JSON_EVENT:" + (@{ event = "progress"; scanned = $scanned; current = $fileObj.FullName } | ConvertTo-Json -Compress))
            }
        }
    }

    if (Test-Path $CancelFlagPath) { $wasCancelled = $true }

    $quarantineResults = @()
    if ($threats.Count -gt 0) {
        $quarantineResults = Invoke-QuarantineAction -Threats $threats -TargetQuarantineDir $QuarantineDir -IsNonInteractive $NonInteractive.IsPresent -DoAutoQuarantine $AutoQuarantine.IsPresent -CurrentOutputFormat $OutputFormat
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "Quick"
            Status = if ($wasCancelled) { "Cancelled" } else { "Completed" }
            TotalScanned = $scanned
            ThreatsCount = $threats.Count
            Threats = $threats
            QuarantineResults = $quarantineResults
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "`n"
        Write-Host "================================================================================" -ForegroundColor DarkGray
        Write-Host "[*] KẾT QUẢ: Đã kiểm tra $scanned tệp tin. Phát hiện: $($threats.Count) mối đe dọa." -ForegroundColor $(if ($threats.Count -gt 0) { 'Yellow' } else { 'Green' })
        if ($threats.Count -eq 0) {
            Write-Host "[+] Hệ thống hoàn toàn sạch sẽ, không có dấu hiệu mã độc!" -ForegroundColor Green
        }
    }
}

# 2. QUÉT TÙY CHỌN (Custom Scan - Giới hạn kiểm soát tài nguyên)
elseif ($Mode -eq "Custom") {
    if (-not $TargetPath -or -not (Test-Path $TargetPath)) {
        if ($OutputFormat -eq 'JSON') {
            [PSCustomObject]@{
                Mode = "Custom"
                Status = "Error"
                Message = "Đường dẫn mục tiêu không tồn tại hoặc bị bỏ trống: $TargetPath"
                TotalScanned = 0
                ThreatsCount = 0
                Threats = @()
            } | ConvertTo-Json -Depth 5 -Compress
        } else {
            Write-Host "[!] Lỗi: Đường dẫn mục tiêu không tồn tại: $TargetPath" -ForegroundColor Red
        }
        exit 1
    }

    if ($OutputFormat -eq 'Text') {
        Write-Host "[*] Đang quét mục tiêu (Độ sâu tối đa $MaxDepth): $TargetPath" -ForegroundColor Cyan
    }

    $scanned = 0
    $threats = @()
    $wasCancelled = $false

    $files = Get-ScannableFiles -RootPath $TargetPath -LimitDepth $MaxDepth -LimitFiles $MaxFiles -CancelFlag $CancelFlagPath
    foreach ($fileObj in $files) {
        if (Test-Path $CancelFlagPath) { $wasCancelled = $true; break }
        $scanned++
        $t = Scan-FileRecord -file $fileObj
        if ($t) {
            $threats += $t
            if ($OutputFormat -eq 'Text') {
                Write-Host "`n[!] PHÁT HIỆN: $($t.Path)" -ForegroundColor Red
                Write-Host "    Loại: $($t.Reason) | Mức độ: $($t.Severity)" -ForegroundColor Yellow
            }
        } elseif ($OutputFormat -eq 'Text' -and ($scanned % 50 -eq 0)) {
            Write-Host -NoNewline "."
        }

        if ($scanned % 50 -eq 0 -and $OutputFormat -eq 'JSON') {
            Write-Output ("JSON_EVENT:" + (@{ event = "progress"; scanned = $scanned; current = $fileObj.FullName } | ConvertTo-Json -Compress))
        }
    }

    if (Test-Path $CancelFlagPath) { $wasCancelled = $true }

    $quarantineResults = @()
    if ($threats.Count -gt 0) {
        $quarantineResults = Invoke-QuarantineAction -Threats $threats -TargetQuarantineDir $QuarantineDir -IsNonInteractive $NonInteractive.IsPresent -DoAutoQuarantine $AutoQuarantine.IsPresent -CurrentOutputFormat $OutputFormat
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "Custom"
            TargetPath = $TargetPath
            Status = if ($wasCancelled) { "Cancelled" } else { "Completed" }
            TotalScanned = $scanned
            ThreatsCount = $threats.Count
            Threats = $threats
            QuarantineResults = $quarantineResults
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "`n"
        Write-Host "[*] Hoàn tất quét tùy chọn: Đã phân tích $scanned tệp tin. Số mối đe dọa: $($threats.Count)" -ForegroundColor $(if ($threats.Count -gt 0) { 'Yellow' } else { 'Green' })
    }
}

# 3. QUÉT TOÀN DIỆN (Full Scan - Bỏ qua vòng lặp, kiểm soát bộ nhớ)
elseif ($Mode -eq "Full") {
    $roots = @('C:\Users', 'C:\ProgramData')

    if ($OutputFormat -eq 'Text') {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "          SCOM CYBERSHIELD v3.1 - QUÉT TOÀN DIỆN HỆ THỐNG (FULL SCAN)" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
        Write-Host "[*] Phân vùng quét sâu: C:\Users, C:\ProgramData (Loại trừ cache lớn và .git/node_modules)" -ForegroundColor Gray
    }

    $scanned = 0
    $threats = @()
    $wasCancelled = $false

    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        if (Test-Path $CancelFlagPath) { $wasCancelled = $true; break }

        if ($OutputFormat -eq 'Text') {
            Write-Host "`n -> Đang quét phân vùng dữ liệu: $r" -ForegroundColor DarkCyan
        }

        $files = Get-ScannableFiles -RootPath $r -LimitDepth $MaxDepth -LimitFiles $MaxFiles -CancelFlag $CancelFlagPath
        foreach ($fileObj in $files) {
            if (Test-Path $CancelFlagPath) { $wasCancelled = $true; break }
            $scanned++
            $t = Scan-FileRecord -file $fileObj
            if ($t) {
                $threats += $t
                if ($OutputFormat -eq 'Text') {
                    Write-Host "`n[!] PHÁT HIỆN: $($t.Path)" -ForegroundColor Red
                    Write-Host "    Loại: $($t.Reason) | Mức độ: $($t.Severity)" -ForegroundColor Yellow
                }
            } elseif ($OutputFormat -eq 'Text' -and ($scanned % 100 -eq 0)) {
                Write-Host -NoNewline "."
            }

            if ($scanned % 50 -eq 0 -and $OutputFormat -eq 'JSON') {
                Write-Output ("JSON_EVENT:" + (@{ event = "progress"; scanned = $scanned; current = $fileObj.FullName } | ConvertTo-Json -Compress))
            }
        }
    }

    if (Test-Path $CancelFlagPath) { $wasCancelled = $true }

    $quarantineResults = @()
    if ($threats.Count -gt 0) {
        $quarantineResults = Invoke-QuarantineAction -Threats $threats -TargetQuarantineDir $QuarantineDir -IsNonInteractive $NonInteractive.IsPresent -DoAutoQuarantine $AutoQuarantine.IsPresent -CurrentOutputFormat $OutputFormat
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "Full"
            Status = if ($wasCancelled) { "Cancelled" } else { "Completed" }
            TotalScanned = $scanned
            ThreatsCount = $threats.Count
            Threats = $threats
            QuarantineResults = $quarantineResults
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "`n"
        Write-Host "[*] Hoàn tất quét toàn diện: Đã phân tích $scanned tệp. Phát hiện: $($threats.Count) mối đe dọa." -ForegroundColor $(if ($threats.Count -gt 0) { 'Yellow' } else { 'Green' })
    }
}

# 4. SĂN TIẾN TRÌNH & ĐÀO COIN (Bảo vệ tiến trình hệ thống cốt lõi & Giảm False-Positive)
elseif ($Mode -eq "ProcessHunter") {
    if ($OutputFormat -eq 'Text') {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "          SCOM PROCESS HUNTER - SĂN LÙNG TIẾN TRÌNH LẠ & ĐÀO COIN" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
    }

    # Danh sách tiến trình cốt lõi được bảo vệ
    $protectedPids = @(0, 4)
    $protectedSystemNames = @('system', 'idle', 'smss', 'csrss', 'wininit', 'services', 'lsass', 'svchost', 'explorer', 'taskhostw', 'runtimebroker', 'dwm', 'fontdrvhost')

    $procs = Get-Process -ErrorAction SilentlyContinue
    $suspiciousList = @()

    foreach ($p in $procs) {
        $pName = $p.ProcessName.ToLower()
        $pPath = ""
        try {
            $pPath = $p.Path
        } catch {}

        $isProtected = ($protectedPids -contains $p.Id) -or ($protectedSystemNames -contains $pName -and (Test-LegitSystemPath -Path $pPath))

        $reason = $null
        $severity = "Cao"

        # 1. Kiểm tra từ khóa đào coin
        foreach ($kw in $minerKeywords) {
            if ($pName.Contains($kw)) {
                $reason = "CoinMiner.Process.Detected ($kw)"
                $severity = "Cực Kỳ Nguy Hiểm"
                break
            }
        }

        # 2. Kiểm tra tiến trình mạo danh hệ thống chạy ngoài System32 / SysWOW64 / WinSxS
        if (-not $reason -and $pPath) {
            foreach ($sys in $fakeSystemNames) {
                $sysBase = [System.IO.Path]::GetFileNameWithoutExtension($sys).ToLower()
                if ($pName -eq $sysBase) {
                    if (-not (Test-LegitSystemPath -Path $pPath)) {
                        $reason = "Trojan.Masquerade.ProcessNotInSystemDir ($pName)"
                        $severity = "Cực Kỳ Nguy Hiểm"
                        break
                    }
                }
            }
        }

        # 3. Kiểm tra tiến trình Temp (chỉ cảnh báo nếu là script runner hoặc không có mô tả chuẩn)
        if (-not $reason -and $pPath) {
            $pPathLower = $pPath.ToLower()
            if ($pPathLower.Contains('\appdata\local\temp\') -or $pPathLower.Contains('\windows\temp\')) {
                # Chỉ cảnh báo nếu là script interpreter hoặc có từ khóa nghi vấn, tránh false-positive installer
                $scriptInterpreters = @('powershell.exe', 'cmd.exe', 'wscript.exe', 'cscript.exe', 'mshta.exe')
                $isScriptRunner = $scriptInterpreters -contains [System.IO.Path]::GetFileName($pPathLower)
                if ($isScriptRunner) {
                    $reason = "Suspicious.ScriptInterpreterRunningFromTemp"
                    $severity = "Cao"
                }
            }
        }

        if ($reason) {
            $suspiciousList += [PSCustomObject]@{
                PID = $p.Id
                Name = $p.ProcessName
                Path = $pPath
                RAM_MB = [Math]::Round(($p.WorkingSet64 / 1MB), 2)
                Reason = $reason
                Severity = $severity
                IsKillable = (-not $isProtected)
            }
        }
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "ProcessHunter"
            TotalProcesses = $procs.Count
            ThreatsCount = $suspiciousList.Count
            Threats = $suspiciousList
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        if ($suspiciousList.Count -gt 0) {
            Write-Host "`n[!] CẢNH BÁO: Phát hiện $($suspiciousList.Count) tiến trình bất thường/nguy hiểm:" -ForegroundColor Red
            $suspiciousList | Format-Table -Property PID, Name, RAM_MB, Severity, Reason, IsKillable -AutoSize
            Write-Host "`nĐể tiêu diệt một tiến trình độc hại, dùng lệnh: Stop-Process -Id <PID> -Force" -ForegroundColor Yellow
        } else {
            Write-Host "[+] Toàn bộ tiến trình đang hoạt động trên RAM đều hợp lệ và an toàn!" -ForegroundColor Green
        }
    }
}

# 5. LÁ CHẮN KHỞI ĐỘNG CÙNG WINDOWS (Startup Inspector)
elseif ($Mode -eq "Startup") {
    $startupItems = @()

    $runKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )

    foreach ($k in $runKeys) {
        if (Test-Path $k) {
            $keyObj = Get-Item $k
            foreach ($valName in $keyObj.GetValueNames()) {
                $cmd = $keyObj.GetValue($valName)
                $isSus = $false
                $reason = "Normal"

                if ($cmd -match '(\.vbs|\.bat|\.cmd|\.hta|powershell.*-enc|wscript|cscript)') {
                    $isSus = $true
                    $reason = "Suspicious.ScriptInvocationAtBoot"
                } elseif ($cmd -match '(temp|appdata\\local\\temp)') {
                    $isSus = $true
                    $reason = "Suspicious.RunFromTempLocation"
                }

                $startupItems += [PSCustomObject]@{
                    Location = $k
                    Name = $valName
                    Command = $cmd
                    IsSuspicious = $isSus
                    Reason = $reason
                }
            }
        }
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "Startup"
            TotalStartupItems = $startupItems.Count
            Items = $startupItems
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "                DANH SÁCH CÁC MỤC KHỞI ĐỘNG CÙNG WINDOWS" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
        $startupItems | Format-Table -Property Name, IsSuspicious, Command, Location -AutoSize
    }
}

# 6. BẢO VỆ & KIỂM TRA FILE HOSTS (Hosts Shield - Fix PS-BUG-06)
elseif ($Mode -eq "HostsShield") {
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    $suspiciousLines = @()
    $totalEntries = 0

    if (Test-Path $hostsPath) {
        $lines = Get-Content -Path $hostsPath -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }

            # Bỏ qua localhost chuẩn (Fix PS-BUG-06)
            if ($trimmed -match '^\s*(127\.0\.0\.1|::1)\s+localhost\s*$') {
                continue
            }

            $totalEntries++
            $suspiciousLines += $trimmed
        }
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "HostsShield"
            HostsPath = $hostsPath
            SuspiciousEntriesCount = $suspiciousLines.Count
            Entries = $suspiciousLines
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "          KIỂM TRA TỆP TIN CẤU HÌNH DNS/HOSTS WINDOWS" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
        if ($suspiciousLines.Count -gt 0) {
            Write-Host "[!] Cảnh báo: Phát hiện $($suspiciousLines.Count) dòng chuyển hướng bất thường trong file Hosts:" -ForegroundColor Red
            $suspiciousLines | ForEach-Object { Write-Host " -> $_" -ForegroundColor Yellow }
        } else {
            Write-Host "[+] Tệp Hosts hoàn toàn chuẩn xác, không bị chiếm quyền hay chèn DNS độc hại!" -ForegroundColor Green
        }
    }
}

# 7. QUẢN LÝ KHU CÁCH LY (List / Restore an toàn toàn vẹn / Wipe)
elseif ($Mode -eq "QuarantineList") {
    $manifest = @(Get-QuarantineManifest)
    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "QuarantineList"
            QuarantineDir = $QuarantineDir
            TotalQuarantined = $manifest.Count
            Items = $manifest
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "                  DANH SÁCH TỆP TIN TRONG KHU VỰC CÁCH LY" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
        Write-Host "Vị trí lưu trữ an toàn: $QuarantineDir`n" -ForegroundColor Gray
        if ($manifest.Count -gt 0) {
            $manifest | Format-Table -Property Id, FileName, Severity, Reason, QuarantinedAt -AutoSize
        } else {
            Write-Host "[+] Khu cách ly đang trống." -ForegroundColor Green
        }
    }
}
elseif ($Mode -eq "QuarantineRestore") {
    if (-not $RestoreId) {
        if ($OutputFormat -eq 'JSON') {
            [PSCustomObject]@{ Status = "Error"; Message = "Thiếu tham số RestoreId" } | ConvertTo-Json -Compress
        } else {
            Write-Host "[!] Vui lòng cung cấp mã RestoreId của tệp cần khôi phục!" -ForegroundColor Red
        }
        exit 1
    }

    $manifest = @(Get-QuarantineManifest)
    $targetEntry = $manifest | Where-Object { $_.Id -eq $RestoreId }

    if (-not $targetEntry) {
        if ($OutputFormat -eq 'JSON') {
            [PSCustomObject]@{ Status = "NotFound"; Message = "Không tìm thấy tệp có Id $RestoreId trong nhật ký cách ly" } | ConvertTo-Json -Compress
        } else {
            Write-Host "[!] Không tìm thấy tệp có Id $RestoreId trong danh sách cách ly!" -ForegroundColor Red
        }
        exit 1
    }

    $quarantineFile = Join-Path $QuarantineDir $targetEntry.QuarantinedFile
    $restoreDest = $targetEntry.OriginalPath
    $restoreStatus = "Failed"

    # Kiểm tra bảo mật đường dẫn: Chống Path Traversal
    if ([string]::IsNullOrWhiteSpace($restoreDest) -or $restoreDest.Contains('..') -or -not [System.IO.Path]::IsPathRooted($restoreDest)) {
        $msg = "Đường dẫn gốc trong manifest không an toàn: $restoreDest"
        if ($OutputFormat -eq 'JSON') {
            [PSCustomObject]@{ Status = "Error"; Message = $msg } | ConvertTo-Json -Compress
        } else {
            Write-Host "[!] Lỗi: $msg" -ForegroundColor Red
        }
        exit 1
    }

    if (Test-Path $quarantineFile) {
        # Kiểm tra tính toàn vẹn (Integrity Check) qua mã băm SHA256
        if ($targetEntry.Sha256) {
            $currentSha = (Get-FileHash -Path $quarantineFile -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
            if ($currentSha -ne $targetEntry.Sha256) {
                $integrityErr = "CẢNH BÁO TOÀN VẸN: Tệp tin trên đĩa không khớp mã băm ban đầu (có thể đã bị chỉnh sửa hoặc giả mạo). Từ chối khôi phục để bảo vệ hệ thống!"
                if ($OutputFormat -eq 'JSON') {
                    [PSCustomObject]@{ Status = "IntegrityViolation"; Message = $integrityErr; Expected = $targetEntry.Sha256; Actual = $currentSha } | ConvertTo-Json -Compress
                } else {
                    Write-Host "[!] $integrityErr" -ForegroundColor Red
                }
                exit 1
            }
        }

        try {
            $parentDir = Split-Path -Parent $restoreDest
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }

            # Bỏ cờ ReadOnly trước khi khôi phục
            try { (Get-Item $quarantineFile).IsReadOnly = $false } catch {}

            Move-Item -Path $quarantineFile -Destination $restoreDest -Force -ErrorAction Stop
            $restoreStatus = "Success"

            # Cập nhật manifest loại bỏ entry đã khôi phục
            $manifest = @($manifest | Where-Object { $_.Id -ne $RestoreId })
            Save-QuarantineManifest -Items $manifest
        } catch {
            $restoreStatus = "Error: $($_.Exception.Message)"
        }
    } else {
        $restoreStatus = "FileNotFoundOnDisk"
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Status = $restoreStatus
            Id = $RestoreId
            RestoredTo = $restoreDest
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        if ($restoreStatus -eq "Success") {
            Write-Host "[+] Khôi phục thành công tệp: $($targetEntry.FileName) về lại: $restoreDest" -ForegroundColor Green
        } else {
            Write-Host "[!] Lỗi khôi phục tệp ($restoreStatus)" -ForegroundColor Red
        }
    }
}
elseif ($Mode -eq "QuarantineWipe") {
    $manifest = @(Get-QuarantineManifest)
    $deletedCount = 0

    Get-ChildItem -Path $QuarantineDir -Filter "*.quarantined" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            # Bỏ ReadOnly để xóa sạch
            $_.IsReadOnly = $false
            Remove-Item -Path $_.FullName -Force -ErrorAction Stop
            $deletedCount++
        } catch {}
    }

    Save-QuarantineManifest -Items @()

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Status = "Success"
            DeletedFiles = $deletedCount
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "[+] Đã xóa vĩnh viễn $deletedCount tệp nguy hiểm trong khu cách ly!" -ForegroundColor Green
    }
}

# 8. TẠO MẪU KIỂM THỬ CHUẨN QUỐC TẾ EICAR (Fix BAT-BUG-05)
elseif ($Mode -eq "EicarTest") {
    $destDir = if ($TargetPath -and (Test-Path $TargetPath)) { $TargetPath } else { [System.IO.Path]::Combine($env:USERPROFILE, "Downloads") }
    $testFilePath = Join-Path $destDir "SCOM_EICAR_Standard_Test.com.txt"

    $eicarPayload = 'X5O!P%@AP[4\PZX54(P^)7CC)7}' + [char]36 + 'EICAR-STANDARD-ANTIVIRUS-TEST-FILE!' + [char]36 + 'H+H*'
    $status = "Created"
    $message = ""

    try {
        [System.IO.File]::WriteAllText($testFilePath, $eicarPayload, [System.Text.Encoding]::ASCII)
        $message = "Đã tạo thành công tệp kiểm thử EICAR tại: $testFilePath"
    } catch {
        $status = "BlockedOrError"
        $message = "Windows Defender hoặc phần mềm bảo vệ đã can thiệp chặn tạo tệp tức thì: $($_.Exception.Message)"
    }

    if ($OutputFormat -eq 'JSON') {
        [PSCustomObject]@{
            Mode = "EicarTest"
            Status = $status
            FilePath = $testFilePath
            Message = $message
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "            TẠO TỆP KIỂM THỬ MÃ ĐỘC CHUẨN QUỐC TẾ EICAR" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor DarkGray
        if ($status -eq "Created") {
            Write-Host "[+] $message" -ForegroundColor Green
            Write-Host "[*] Tệp này hoàn toàn vô hại, dùng để bạn kiểm tra tính năng phát hiện của SCOM CyberShield." -ForegroundColor Gray
        } else {
            Write-Host "[!] $message" -ForegroundColor Yellow
        }
    }
}
