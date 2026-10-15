const { exec } = require('child_process');
const path = require('path');
const signatures = require('../data/signatures.json');

class ProcessMonitor {
  // Query all active Windows processes with their paths and memory usage
  async getProcesses() {
    return new Promise((resolve) => {
      // Use PowerShell to get rich process metadata
      const psCommand = `powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process | Where-Object { $_.Path } | Select-Object Id, ProcessName, Path, CPU, @{Name='MemoryMB';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}}, @{Name='Company';Expression={$_.Company}} | ConvertTo-Json -Compress"`;

      exec(psCommand, { maxBuffer: 10 * 1024 * 1024 }, (err, stdout) => {
        if (err || !stdout.trim()) {
          // Fallback to simpler tasklist if PowerShell fails
          return this.getProcessesFallback().then(resolve);
        }

        try {
          let list = JSON.parse(stdout);
          if (!Array.isArray(list)) {
            list = [list];
          }

          const evaluated = list.map((proc) => this.evaluateProcess(proc));
          // Sort by risk descending, then memory descending
          evaluated.sort((a, b) => {
            const riskWeight = { DANGEROUS: 3, SUSPICIOUS: 2, SAFE: 1 };
            const diff = riskWeight[b.riskLevel] - riskWeight[a.riskLevel];
            if (diff !== 0) return diff;
            return (b.memoryMB || 0) - (a.memoryMB || 0);
          });

          resolve(evaluated);
        } catch (parseErr) {
          this.getProcessesFallback().then(resolve);
        }
      });
    });
  }

  // Fallback using WMIC or tasklist
  async getProcessesFallback() {
    return new Promise((resolve) => {
      exec('tasklist /FO CSV /NH', { maxBuffer: 5 * 1024 * 1024 }, (err, stdout) => {
        if (err || !stdout) return resolve([]);
        const lines = stdout.split('\r\n');
        const procs = [];

        for (const line of lines) {
          if (!line.trim()) continue;
          const parts = line.split('","').map((p) => p.replace(/"/g, ''));
          if (parts.length >= 5) {
            const memStr = parts[4].replace(/[^\d]/g, '');
            const memMB = Math.round(parseInt(memStr || '0', 10) / 1024);
            procs.push(
              this.evaluateProcess({
                Id: parseInt(parts[1], 10),
                ProcessName: parts[0],
                Path: '',
                MemoryMB: memMB
              })
            );
          }
        }
        resolve(procs);
      });
    });
  }

  // Evaluate risk level of a process
  evaluateProcess(proc) {
    const name = (proc.ProcessName || '').toLowerCase();
    const filePath = (proc.Path || '').toLowerCase();
    const company = proc.Company || '';
    const memory = proc.MemoryMB || 0;
    const pid = proc.Id;

    let riskLevel = 'SAFE';
    let riskReason = 'Tiến trình bình thường';

    // 1. Check known malicious process names or miners
    const knownBadNames = ['xmrig', 'miner', 'minerd', 'cpuminer', 'ccminer', 'ethminer', 'nicehash', 'wannacry', 'darkcomet'];
    for (const bad of knownBadNames) {
      if (name.includes(bad)) {
        riskLevel = 'DANGEROUS';
        riskReason = `Tên tiến trình trùng khớp với phần mềm đào coin / mã độc: ${bad}`;
        break;
      }
    }

    // 2. Disguised system processes (e.g., svchost.exe outside System32)
    if (riskLevel === 'SAFE' && filePath) {
      for (const sysName of signatures.disguisedSystemProcesses) {
        if (name === sysName.replace('.exe', '') || name === sysName) {
          const isSystemLocation =
            filePath.includes('\\windows\\system32\\') ||
            filePath.includes('\\windows\\syswow64\\') ||
            filePath.includes('\\windows\\winsxs\\');
          if (!isSystemLocation) {
            riskLevel = 'DANGEROUS';
            riskReason = `Mạo danh tiến trình hệ thống Windows (${sysName}) nhưng chạy từ thư mục bất thường: ${filePath}`;
            break;
          }
        }
      }
    }

    // 3. Process running from Temp or AppData root
    if (riskLevel === 'SAFE' && filePath) {
      if (filePath.includes('\\appdata\\local\\temp\\') || filePath.includes('\\windows\\temp\\')) {
        riskLevel = 'SUSPICIOUS';
        riskReason = 'Tiến trình đang chạy từ thư mục Temp (nơi virus thường ẩn nấp)';
      } else if (filePath.includes('\\users\\') && !filePath.includes('\\appdata\\local\\programs\\') && filePath.includes('\\appdata\\')) {
        if (!company || company === '') {
          riskLevel = 'SUSPICIOUS';
          riskReason = 'Tiến trình không có chứng thư công ty phát hành, chạy từ thư mục người dùng cá nhân (AppData)';
        }
      }
    }

    // 4. Double extension check on process executable
    if (riskLevel === 'SAFE' && filePath) {
      for (const doubleExt of signatures.suspiciousDoubleExtensions) {
        if (filePath.endsWith(doubleExt)) {
          riskLevel = 'DANGEROUS';
          riskReason = `Tiến trình mang phần mở rộng kép giả mạo: ${doubleExt}`;
          break;
        }
      }
    }

    return {
      pid,
      name: proc.ProcessName,
      path: proc.Path || 'Không thể truy cập đường dẫn (Hệ thống bảo vệ)',
      memoryMB: memory,
      company: company || 'Không rõ',
      riskLevel,
      riskReason
    };
  }

  // Kill a process by PID
  async killProcess(pid) {
    return new Promise((resolve) => {
      if (!pid) return resolve({ success: false, error: 'PID không hợp lệ' });

      exec(`powershell -NoProfile -Command "Stop-Process -Id ${pid} -Force"`, (err) => {
        if (err) {
          // Fallback to taskkill
          exec(`taskkill /F /PID ${pid}`, (err2) => {
            if (err2) {
              resolve({
                success: false,
                error: `Không thể tắt tiến trình: Quyền hệ thống bị từ chối hoặc tiến trình đã tắt.`
              });
            } else {
              resolve({ success: true });
            }
          });
        } else {
          resolve({ success: true });
        }
      });
    });
  }
}

module.exports = ProcessMonitor;
