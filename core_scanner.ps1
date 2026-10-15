# ============================================================================
# SCOM CYBERSHIELD - POWERSHELL CORE SCANNER ENGINE
# ============================================================================
param (
    [string]$Mode = "Quick",
    [string]$TargetPath = "",
    [string]$QuarantineDir = ""
)

# Output encoding UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $QuarantineDir) {
    $QuarantineDir = Join-Path $env:LOCALAPPDATA "SCOM_Quarantine"
}
if (-not (Test-Path $QuarantineDir)) {
    New-Item -ItemType Directory -Path $QuarantineDir -Force | Out-Null
}

$suspiciousDoubleExt = @('.pdf.exe', '.docx.exe', '.xlsx.exe', '.jpg.exe', '.png.exe', '.pdf.vbs', '.doc.scr', '.jpg.scr', '.txt.exe', '.mp4.exe')
$fakeSystemNames = @('svchost.exe', 'csrss.exe', 'lsass.exe', 'services.exe', 'smss.exe', 'taskhostw.exe', 'runtimebroker.exe')
$eicarHash = '44d88612fea8a8f36de82e1278abb02f'
$wannacryHash = '09a0815e659483d6bc09fca8e559443a'
$knownBadHashes = @($eicarHash, $wannacryHash)

function Scan-File {
    param([System.IO.FileInfo]$file)

    $name = $file.Name.ToLower()
    $path = $file.FullName.ToLower()
    $threatReason = $null
    $threatSeverity = "Cao"

    # 1. Double extension trick
    foreach ($dExt in $suspiciousDoubleExt) {
        if ($name.EndsWith($dExt)) {
            $threatReason = "Trojan.Disguise.DoubleExtension ($dExt)"
            $threatSeverity = "Cuc Ky Nguy Hiem"
            break
        }
    }

    # 2. Fake system process name outside System32
    if (-not $threatReason) {
        foreach ($sys in $fakeSystemNames) {
            if ($name -eq $sys) {
                if (-not ($path.Contains('\windows\system32\') -or $path.Contains('\windows\syswow64\') -or $path.Contains('\windows\winsxs\'))) {
                    $threatReason = "Trojan.Masquerade.FakeSystemFile ($sys)"
                    $threatSeverity = "Cuc Ky Nguy Hiem"
                    break
                }
            }
        }
    }

    # 3. Disguised PE file (MZ Header in non-executable files)
    if (-not $threatReason -and $file.Length -gt 2 -and ($name.EndsWith('.jpg') -or $name.EndsWith('.png') -or $name.EndsWith('.pdf') -or $name.EndsWith('.txt'))) {
        try {
            $stream = [System.IO.File]::OpenRead($file.FullName)
            $buf = New-Object byte[] 2
            $read = $stream.Read($buf, 0, 2)
            $stream.Close()
            if ($buf[0] -eq 0x4D -and $buf[1] -eq 0x5A) {
                $threatReason = "Trojan.PE.DisguisedAsDocument (Header MZ trong file duoi " + $file.Extension + ")"
                $threatSeverity = "Cuc Ky Nguy Hiem"
            }
        } catch {}
    }

    # 4. Known malware MD5 check
    if (-not $threatReason -and $file.Length -lt 25MB) {
        try {
            $md5 = (Get-FileHash -Path $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash.ToLower()
            if ($md5 -eq $eicarHash) {
                $threatReason = "Malware.Test.EICAR-Standard-AV-File"
                $threatSeverity = "Cao (Mau Test Chuan)"
            } elseif ($knownBadHashes -contains $md5) {
                $threatReason = "Malware.KnownSignature.HashMatch ($md5)"
                $threatSeverity = "Cuc Ky Nguy Hiem"
            }
        } catch {}
    }

    # 5. Dangerous scripts with downloader cradle or shadow copy deletion
    if (-not $threatReason -and ($name.EndsWith('.ps1') -or $name.EndsWith('.bat') -or $name.EndsWith('.cmd') -or $name.EndsWith('.vbs') -or $name.EndsWith('.hta')) -and $file.Length -lt 2MB) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match 'powershell.*(-enc|downloadstring|invoke-webrequest|iwr)' -or $content -match 'certutil.*-urlcache' -or $content -match 'vssadmin.*delete.*shadows') {
                $threatReason = "Script.Malicious.DownloadCradle_or_RansomwareBehavior"
                $threatSeverity = "Cao"
            }
        } catch {}
    }

    if ($threatReason) {
        return [PSCustomObject]@{
            Path = $file.FullName
            Name = $file.Name
            Reason = $threatReason
            Severity = $threatSeverity
            Size = $file.Length
        }
    }
    return $null
}

# ==================== MODE HANDLERS ====================

if ($Mode -eq "Quick") {
    Write-Host "[*] Dang bat dau Quet Nhanh cac vung trong yeu..." -ForegroundColor Cyan
    Write-Host "[*] Cac vung quet: Temp, Downloads, Startup, AppData, Windows Temp`n" -ForegroundColor Gray

    $targets = @(
        $env:TEMP,
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Temp'),
        [System.IO.Path]::Combine($env:USERPROFILE, 'Downloads'),
        [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\Startup'),
        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup',
        'C:\Windows\Temp'
    )

    $scanned = 0
    $threats = @()

    foreach ($dir in $targets) {
        if (-not (Test-Path $dir)) { continue }
        Write-Host " -> Dang quet thu muc: $dir" -ForegroundColor DarkCyan

        Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $scanned++
            $t = Scan-File -file $_
            if ($t) {
                Write-Host "`n [!] PHAT HIEN MA DOC: $($t.Path)" -ForegroundColor Red
                Write-Host "     Phan loai: $($t.Reason) | Muc do: $($t.Severity)" -ForegroundColor Yellow
                $threats += $t
            }
            if ($scanned % 50 -eq 0) {
                Write-Host -NoNewline "."
            }
        }
    }

    Write-Host "`n"
    Write-Host "================================================================================" -ForegroundColor DarkGray
    Write-Host "[*] KET QUA: Da quet tong cong $scanned tep tin." -ForegroundColor Green

    if ($threats.Count -gt 0) {
        Write-Host "[!] Canh bao: Phat hien $($threats.Count) moi de doa doc hai!" -ForegroundColor Red
        $ans = Read-Host "`n>> Ban co muon CACH LY tat ca cac tep doc hai nay vao khu an toan khong? (Y/N)"
        if ($ans -eq 'Y' -or $ans -eq 'y') {
            foreach ($t in $threats) {
                try {
                    $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
                    $dest = Join-Path $QuarantineDir ("$($t.Name).$timestamp.quarantined")
                    Move-Item -Path $t.Path -Destination $dest -Force
                    Write-Host " [+] Da cach ly an toan: $($t.Name)" -ForegroundColor Cyan
                } catch {
                    Write-Host " [-] Khong the cach ly (tep dang bi khoa): $($t.Path)" -ForegroundColor Red
                }
            }
            Write-Host "`n[V] Hoan tat cach ly moi de doa!" -ForegroundColor Green
        }
    } else {
        Write-Host "[+] He thong hoan toan SACH se, khong phat hien moi de doa nao!" -ForegroundColor Green
    }
}
elseif ($Mode -eq "Custom") {
    if (-not (Test-Path $TargetPath)) {
        Write-Host "[!] Duong dan khong ton tai: $TargetPath" -ForegroundColor Red
        exit
    }

    Write-Host "[*] Dang quet muc tieu: $TargetPath`n" -ForegroundColor Cyan
    $scanned = 0
    $threats = @()

    if ((Get-Item $TargetPath) -is [System.IO.FileInfo]) {
        $file = Get-Item $TargetPath
        $scanned = 1
        $t = Scan-File -file $file
        if ($t) {
            Write-Host "[!] PHAT HIEN MA DOC: $($t.Path)" -ForegroundColor Red
            Write-Host "    Loai: $($t.Reason)" -ForegroundColor Yellow
            $threats += $t
        }
    } else {
        Get-ChildItem -Path $TargetPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $scanned++
            $t = Scan-File -file $_
            if ($t) {
                Write-Host "`n[!] PHAT HIEN: $($t.Path)" -ForegroundColor Red
                Write-Host "    Loai: $($t.Reason) | Muc do: $($t.Severity)" -ForegroundColor Yellow
                $threats += $t
            }
            if ($scanned % 50 -eq 0) {
                Write-Host -NoNewline "."
            }
        }
    }

    Write-Host "`n"
    Write-Host "[*] Hoan tat: Da phan tich $scanned tep." -ForegroundColor Green
    if ($threats.Count -gt 0) {
        Write-Host "[!] Phat hien $($threats.Count) moi de doa doc hai!" -ForegroundColor Red
        $ans = Read-Host "`n>> Ban co muon cach ly tat ca tep nay khong? (Y/N)"
        if ($ans -eq 'Y' -or $ans -eq 'y') {
            foreach ($t in $threats) {
                try {
                    $timestamp = [DateTime]::Now.ToString("yyyyMMdd_HHmmss")
                    $dest = Join-Path $QuarantineDir ("$($t.Name).$timestamp.quarantined")
                    Move-Item -Path $t.Path -Destination $dest -Force
                    Write-Host " [+] Da cach ly: $($t.Name)" -ForegroundColor Cyan
                } catch {
                    Write-Host " [-] Loi cach ly: $($t.Path)" -ForegroundColor Red
                }
            }
        }
    } else {
        Write-Host "[+] Khong phat hien ma doc trong duong dan nay!" -ForegroundColor Green
    }
}
elseif ($Mode -eq "Full") {
    Write-Host "[*] Dang bat dau Quet Toan Dien o C:\..." -ForegroundColor Cyan
    $scanned = 0
    $threats = @()

    $roots = @('C:\Users', 'C:\ProgramData')
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        Write-Host " -> Dang quet phan vung: $r" -ForegroundColor DarkCyan

        Get-ChildItem -Path $r -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $scanned++
            $t = Scan-File -file $_
            if ($t) {
                Write-Host "`n[!] PHAT HIEN: $($t.Path)" -ForegroundColor Red
                Write-Host "    Loai: $($t.Reason)" -ForegroundColor Yellow
                $threats += $t
            }
            if ($scanned % 100 -eq 0) {
                Write-Host -NoNewline "."
            }
        }
    }

    Write-Host "`n"
    Write-Host "[*] Hoan tat quet toan dien: Da quet $scanned tep tin." -ForegroundColor Green
    Write-Host "[*] So moi de doa phat hien: $($threats.Count)" -ForegroundColor Yellow
}
elseif ($Mode -eq "ProcessHunter") {
    Write-Host "[*] Dang phan tich toan bo tien trinh dang chay trong bo nho...`n" -ForegroundColor Cyan

    $badProcesses = @('xmrig', 'cpuminer', 'ccminer', 'nicehash', 'ethminer', 'minerd', 'wannacry')
    $fakeNames = @('svchost', 'csrss', 'lsass', 'services')

    $procs = Get-Process | Where-Object { $_.Path } | Select-Object Id, ProcessName, Path, @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}}

    $flagged = @()

    Write-Host ("{0,-8} {1,-25} {2,-12} {3,-20}" -f 'PID', 'TEN TIEN TRINH', 'RAM (MB)', 'DANH GIA') -ForegroundColor Cyan
    Write-Host ("-" * 75) -ForegroundColor DarkGray

    foreach ($p in $procs) {
        $pName = $p.ProcessName.ToLower()
        $pPath = $p.Path.ToLower()
        $risk = "AN TOAN"
        $color = "Green"

        # Check miner
        foreach ($b in $badProcesses) {
            if ($pName.Contains($b)) {
                $risk = "NGUY HIEM (CoinMiner)"
                $color = "Red"
                $flagged += $p
                break
            }
        }

        # Check fake system
        if ($risk -eq "AN TOAN") {
            foreach ($f in $fakeNames) {
                if ($pName -eq $f -and -not ($pPath.Contains('\system32\') -or $pPath.Contains('\syswow64\'))) {
                    $risk = "NGUY HIEM (Gia Mao System32)"
                    $color = "Red"
                    $flagged += $p
                    break
                }
            }
        }

        # Check run from temp
        if ($risk -eq "AN TOAN" -and ($pPath.Contains('\temp\') -or $pPath.Contains('\appdata\local\temp\'))) {
            $risk = "NGHI NGO (Chay Tu Temp)"
            $color = "Yellow"
            $flagged += $p
        }

        if ($risk -ne "AN TOAN") {
            Write-Host ("{0,-8} {1,-25} {2,-12} {3,-20}" -f $p.Id, $p.ProcessName, $p.RAM_MB, $risk) -ForegroundColor $color
            Write-Host ("         Path: " + $p.Path) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    if ($flagged.Count -gt 0) {
        Write-Host "[!] Canh bao: Co $($flagged.Count) tien trinh bat thuong dang chay!" -ForegroundColor Red
        $killPid = Read-Host ">> Nhap PID muon CUONG CHE DUNG (hoac nhan Enter de bo qua)"
        if ($killPid) {
            try {
                Stop-Process -Id $killPid -Force
                Write-Host "[+] Da tieu diet tien trinh PID $killPid thanh cong!" -ForegroundColor Green
            } catch {
                Write-Host "[-] Khong the dung tien trinh: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "[+] Khong phat hien tien trinh doc hai hay dao coin nao dang chay." -ForegroundColor Green
    }
}
elseif ($Mode -eq "Startup") {
    Write-Host "[*] Dang quet danh sach ung dung tu dong khoi dong cung Windows...`n" -ForegroundColor Cyan

    $items = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
    Write-Host ("{0,-22} {1,-35} {2}" -f 'TEN UNG DUNG', 'LENH THUC THI', 'VI TRI') -ForegroundColor Cyan
    Write-Host ("-" * 75) -ForegroundColor DarkGray

    foreach ($it in $items) {
        $cmd = ($it.Command + "").ToLower()
        $isWarn = $false

        if ($cmd.Contains('.vbs') -or $cmd.Contains('.bat') -or $cmd.Contains('powershell -enc') -or $cmd.Contains('\temp\')) {
            $isWarn = $true
        }

        $color = if ($isWarn) { "Red" } else { "White" }
        $flag = if ($isWarn) { " [!] DANG NGO" } else { "" }
        $cmdShort = if ($it.Command.Length -gt 34) { $it.Command.Substring(0, 31) + "..." } else { $it.Command }

        Write-Host ("{0,-22} {1,-35} {2}{3}" -f $it.Name, $cmdShort, $it.Location, $flag) -ForegroundColor $color
    }
}
elseif ($Mode -eq "Hosts") {
    $hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
    if (Test-Path $hostsPath) {
        $lines = Get-Content $hostsPath | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }
        if ($lines.Count -gt 0) {
            Write-Host "[!] Phat hien cac dong chuyen huong IP trong file hosts:" -ForegroundColor Yellow
            $lines | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor Red }
        } else {
            Write-Host "[+] File hosts hoan toan binh thuong, khong co chuyen huong doc hai." -ForegroundColor Green
        }
    }
}
elseif ($Mode -eq "QuarantineList") {
    $files = Get-ChildItem -Path $QuarantineDir -File -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) {
        Write-Host "[+] Khu cach ly hien dang trong. May tinh sach se!" -ForegroundColor Green
    } else {
        Write-Host "Co $($files.Count) tep dang bi co lap an toan trong khu cach ly:" -ForegroundColor Yellow
        $files | ForEach-Object {
            Write-Host (" - " + $_.Name + " (" + [math]::Round($_.Length / 1KB, 1) + " KB)") -ForegroundColor Cyan
        }
    }
}
