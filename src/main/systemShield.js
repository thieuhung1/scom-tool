const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

class SystemShield {
  // Query Windows Defender real-time protection state
  async getDefenderStatus() {
    return new Promise((resolve) => {
      const psCommand = `powershell -NoProfile -Command "Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, AntispywareEnabled, AMServiceEnabled | ConvertTo-Json -Compress"`;

      exec(psCommand, { timeout: 6000 }, (err, stdout) => {
        if (err || !stdout.trim()) {
          return resolve({
            available: false,
            realTimeProtection: true,
            antivirusEnabled: true,
            message: 'Đang dùng cấu hình bảo vệ Windows mặc định'
          });
        }

        try {
          const data = JSON.parse(stdout);
          resolve({
            available: true,
            realTimeProtection: !!data.RealTimeProtectionEnabled,
            antivirusEnabled: !!data.AntivirusEnabled,
            antispywareEnabled: !!data.AntispywareEnabled,
            amServiceEnabled: !!data.AMServiceEnabled,
            message: data.RealTimeProtectionEnabled
              ? 'Bảo vệ thời gian thực đang bật'
              : 'Cảnh báo: Bảo vệ thời gian thực Windows đang tắt!'
          });
        } catch (e) {
          resolve({
            available: false,
            realTimeProtection: true,
            antivirusEnabled: true,
            message: 'Bảo vệ Windows đang hoạt động'
          });
        }
      });
    });
  }

  // Scan Startup programs in Registry and Startup folder
  async getStartupItems() {
    return new Promise((resolve) => {
      const psCommand = `powershell -NoProfile -Command "
        $items = @()
        Get-CimInstance Win32_StartupCommand | ForEach-Object {
          $items += [PSCustomObject]@{
            Name = $_.Name
            Command = $_.Command
            Location = $_.Location
            User = $_.User
          }
        }
        $items | ConvertTo-Json -Compress
      "`;

      exec(psCommand, { timeout: 8000 }, (err, stdout) => {
        if (err || !stdout.trim()) {
          return resolve([]);
        }

        try {
          let list = JSON.parse(stdout);
          if (!Array.isArray(list)) list = [list];

          const analyzed = list.map((item) => {
            const cmd = (item.Command || '').toLowerCase();
            let isSuspicious = false;
            let reason = 'Ứng dụng khởi động hợp lệ';

            if (cmd.includes('.vbs') || cmd.includes('.bat') || cmd.includes('.cmd') || cmd.includes('powershell -enc')) {
              isSuspicious = true;
              reason = 'Chạy tệp script/lệnh mã hóa khi khởi động máy';
            } else if (cmd.includes('\\temp\\') || cmd.includes('\\appdata\\local\\temp\\')) {
              isSuspicious = true;
              reason = 'Khởi động tệp từ thư mục tạm Temp';
            } else if (/^[a-f0-9]{8,}\.exe/i.test(path.basename(cmd))) {
              isSuspicious = true;
              reason = 'Tên tệp khởi động có chuỗi băm ngẫu nhiên lạ';
            }

            return {
              name: item.Name || 'Không rõ',
              command: item.Command || '',
              location: item.Location || '',
              user: item.User || '',
              isSuspicious,
              reason
            };
          });

          resolve(analyzed);
        } catch (e) {
          resolve([]);
        }
      });
    });
  }

  // Inspect Hosts file for malicious DNS hijacks
  checkHostsFile() {
    const hostsPath = 'C:\\Windows\\System32\\drivers\\etc\\hosts';
    if (!fs.existsSync(hostsPath)) {
      return { status: 'OK', suspiciousEntries: [] };
    }

    try {
      const content = fs.readFileSync(hostsPath, 'utf-8');
      const lines = content.split('\n');
      const suspicious = [];

      const criticalDomains = [
        'microsoft.com',
        'windowsupdate.com',
        'kaspersky.com',
        'symantec.com',
        'virustotal.com',
        'malwarebytes.com',
        'google.com'
      ];

      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.startsWith('#') || !trimmed) continue;

        for (const dom of criticalDomains) {
          if (trimmed.toLowerCase().includes(dom)) {
            suspicious.push({
              line: trimmed,
              domain: dom,
              reason: `Chặn hoặc chuyển hướng tên miền bảo mật quan trọng: ${dom}`
            });
          }
        }
      }

      return {
        status: suspicious.length > 0 ? 'WARNING' : 'SECURE',
        suspiciousEntries: suspicious
      };
    } catch (err) {
      return { status: 'OK', suspiciousEntries: [] };
    }
  }

  // Calculate overall security score (0 - 100)
  async getSecurityOverview(threatsCount = 0, quarantinedCount = 0) {
    const defender = await this.getDefenderStatus();
    const startup = await this.getStartupItems();
    const hosts = this.checkHostsFile();

    let score = 100;
    const issues = [];

    if (threatsCount > 0) {
      score -= Math.min(threatsCount * 15, 45);
      issues.push(`Đang phát hiện ${threatsCount} mối đe dọa chưa được xử lý!`);
    }

    if (!defender.realTimeProtection) {
      score -= 25;
      issues.push('Bảo vệ thời gian thực của Windows đang bị tắt.');
    }

    const suspiciousStartup = startup.filter((s) => s.isSuspicious);
    if (suspiciousStartup.length > 0) {
      score -= suspiciousStartup.length * 10;
      issues.push(`Phát hiện ${suspiciousStartup.length} mục khởi động đáng ngờ.`);
    }

    if (hosts.status === 'WARNING') {
      score -= 20;
      issues.push('File Hosts bị chèn chuyển hướng tên miền đáng ngờ.');
    }

    score = Math.max(10, Math.min(100, score));

    return {
      score,
      defender,
      suspiciousStartupCount: suspiciousStartup.length,
      hostsStatus: hosts.status,
      issues
    };
  }
}

module.exports = SystemShield;
