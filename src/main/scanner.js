const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');
const signatures = require('../data/signatures.json');

class VirusScanner {
  constructor(onProgress = () => {}, onThreat = () => {}) {
    this.onProgress = onProgress;
    this.onThreat = onThreat;
    this.isScanning = false;
    this.isPaused = false;
    this.shouldStop = false;
    this.stats = {
      filesScanned: 0,
      threatsFound: 0,
      errorsCount: 0,
      startTime: null,
      endTime: null
    };
    this.foundThreats = [];
  }

  // Calculate file hash efficiently
  async calculateHashes(filePath, maxBytes = 50 * 1024 * 1024) {
    return new Promise((resolve) => {
      try {
        const stat = fs.statSync(filePath);
        if (stat.size > maxBytes) {
          // For very large files, skip deep hashing or hash first 10MB
          return resolve({ md5: null, sha256: null, size: stat.size });
        }

        const md5Hash = crypto.createHash('md5');
        const sha256Hash = crypto.createHash('sha256');
        const stream = fs.createReadStream(filePath);

        stream.on('data', (data) => {
          md5Hash.update(data);
          sha256Hash.update(data);
        });

        stream.on('end', () => {
          resolve({
            md5: md5Hash.digest('hex').toLowerCase(),
            sha256: sha256Hash.digest('hex').toLowerCase(),
            size: stat.size
          });
        });

        stream.on('error', () => {
          resolve({ md5: null, sha256: null, size: stat.size });
        });
      } catch (e) {
        resolve({ md5: null, sha256: null, size: 0 });
      }
    });
  }

  // Check if file starts with PE MZ magic header (0x4D, 0x5A)
  checkPEMagicHeader(filePath) {
    try {
      const fd = fs.openSync(filePath, 'r');
      const buffer = Buffer.alloc(2);
      fs.readSync(fd, buffer, 0, 2, 0);
      fs.closeSync(fd);
      return buffer[0] === 0x4d && buffer[1] === 0x5a; // 'M' 'Z'
    } catch (e) {
      return false;
    }
  }

  // Heuristic analysis of single file
  async analyzeFile(filePath) {
    try {
      if (!fs.existsSync(filePath)) return null;

      const stat = fs.lstatSync(filePath);
      if (stat.isDirectory() || stat.isSymbolicLink()) return null;

      const lowerName = path.basename(filePath).toLowerCase();
      const lowerPath = filePath.toLowerCase();
      const ext = path.extname(lowerName);

      let threat = null;

      // Rule 1: Suspicious Double Extensions (e.g. invoice.pdf.exe)
      for (const doubleExt of signatures.suspiciousDoubleExtensions) {
        if (lowerName.endsWith(doubleExt)) {
          threat = {
            name: 'Heur.DoubleExtension.Trick',
            type: 'Trojan.Disguise',
            severity: 'Critical',
            description: `Tệp ngụy trang nguy hiểm với phần mở rộng kép: ${doubleExt}. Rất có thể là mã độc tống tiền hoặc đánh cắp dữ liệu.`
          };
          break;
        }
      }

      // Rule 2: Fake system executable placed in user directories
      if (!threat) {
        for (const sysProc of signatures.disguisedSystemProcesses) {
          if (lowerName === sysProc) {
            const isSystemDir =
              lowerPath.includes('\\windows\\system32\\') ||
              lowerPath.includes('\\windows\\syswow64\\') ||
              lowerPath.includes('\\windows\\winsxs\\');
            if (!isSystemDir) {
              threat = {
                name: 'Trojan.DisguisedSystemFile',
                type: 'Trojan.Masquerade',
                severity: 'Critical',
                description: `Tệp mang tên tiến trình hệ thống quan trọng (${sysProc}) nhưng lại nằm ngoài System32. Đây là dấu hiệu mã độc mạo danh.`
              };
              break;
            }
          }
        }
      }

      // Rule 3: Executable disguised as image/document (PE Header mismatch)
      if (!threat && stat.size > 2) {
        const nonExecExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.pdf', '.docx', '.xlsx', '.txt', '.mp3', '.mp4'];
        if (nonExecExtensions.includes(ext)) {
          if (this.checkPEMagicHeader(filePath)) {
            threat = {
              name: 'Trojan.PE.DisguisedAsDocument',
              type: 'Trojan.Disguise',
              severity: 'Critical',
              description: `Tệp có đuôi ${ext} nhưng phần đầu nhị phân lại là file thực thi Windows (MZ Executable). Đây là mã độc trá hình.`
            };
          }
        }
      }

      // Rule 4: Script analysis (PowerShell, VBS, BAT, CMD, HTA, JS)
      const scriptExtensions = ['.ps1', '.bat', '.cmd', '.vbs', '.vbe', '.js', '.wsf', '.hta'];
      if (!threat && scriptExtensions.includes(ext) && stat.size < 2 * 1024 * 1024) {
        try {
          const content = fs.readFileSync(filePath, 'utf-8');
          for (const rule of signatures.maliciousScriptPatterns) {
            const regex = new RegExp(rule.pattern, 'i');
            if (regex.test(content)) {
              threat = {
                name: rule.name,
                type: 'Script.Malicious',
                severity: rule.severity,
                description: rule.description
              };
              break;
            }
          }
        } catch (readErr) {
          // binary or encoding issue, skip script regex
        }
      }

      // Rule 5: Signature Hash Match
      const hashes = await this.calculateHashes(filePath);
      if (hashes.md5 && signatures.knownHashes[hashes.md5]) {
        const match = signatures.knownHashes[hashes.md5];
        threat = {
          name: match.name,
          type: match.type,
          severity: match.severity,
          description: match.description
        };
      } else if (hashes.sha256 && signatures.knownHashes[hashes.sha256]) {
        const match = signatures.knownHashes[hashes.sha256];
        threat = {
          name: match.name,
          type: match.type,
          severity: match.severity,
          description: match.description
        };
      }

      // Rule 6: Dangerous executable residing inside AppData/Temp root directly with high entropy or unusual names
      if (!threat && (ext === '.exe' || ext === '.scr')) {
        const isInTempOrAppData =
          lowerPath.includes('\\appdata\\local\\temp\\') ||
          lowerPath.includes('\\windows\\temp\\');
        if (isInTempOrAppData) {
          // If created recently or random numeric name
          if (/^[a-f0-9]{8,}\.exe$/i.test(lowerName) || /^tmp[0-9a-z]+\.exe$/i.test(lowerName)) {
            threat = {
              name: 'Heur.Suspicious.TempExecutable',
              type: 'Suspicious.DropExecutable',
              severity: 'High',
              description: `Tệp thực thi có tên tạo ngẫu nhiên đang chạy hoặc được sinh ra trong thư mục Temp rác.`
            };
          }
        }
      }

      if (threat) {
        return {
          filePath,
          fileName: path.basename(filePath),
          fileSize: stat.size,
          md5: hashes.md5,
          sha256: hashes.sha256,
          threatName: threat.name,
          threatType: threat.type,
          severity: threat.severity,
          description: threat.description,
          detectedAt: new Date().toISOString()
        };
      }

      return null;
    } catch (err) {
      this.stats.errorsCount++;
      return null;
    }
  }

  // Get directories for Quick Scan
  getQuickScanTargets() {
    const userProfile = process.env.USERPROFILE || 'C:\\Users\\Default';
    const targets = [];

    const candidatePaths = [
      process.env.TEMP,
      path.join(process.env.LOCALAPPDATA || '', 'Temp'),
      path.join(userProfile, 'Downloads'),
      path.join(userProfile, 'Desktop'),
      path.join(process.env.APPDATA || '', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup'),
      'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup',
      'C:\\Windows\\Temp',
      // AppData roots
      path.join(process.env.APPDATA || ''),
      path.join(process.env.LOCALAPPDATA || '')
    ];

    for (const p of candidatePaths) {
      if (p && fs.existsSync(p) && !targets.includes(p)) {
        targets.push(p);
      }
    }

    return targets;
  }

  // Scan a list of directories recursively
  async *walkDirectory(dirPath, maxDepth = 4, currentDepth = 0) {
    if (this.shouldStop) return;
    if (currentDepth > maxDepth) return;

    // Skip problematic or gigantic Windows system caches
    const lower = dirPath.toLowerCase();
    if (
      lower.includes('\\winsxs') ||
      lower.includes('\\system volume information') ||
      lower.includes('\\$recycle.bin') ||
      lower.includes('\\node_modules') ||
      lower.includes('\\windows\\assembly')
    ) {
      return;
    }

    let entries = [];
    try {
      entries = fs.readdirSync(dirPath, { withFileTypes: true });
    } catch (err) {
      return;
    }

    for (const entry of entries) {
      if (this.shouldStop) return;

      while (this.isPaused) {
        await new Promise((r) => setTimeout(r, 200));
      }

      const fullPath = path.join(dirPath, entry.name);

      if (entry.isDirectory()) {
        yield* this.walkDirectory(fullPath, maxDepth, currentDepth + 1);
      } else if (entry.isFile()) {
        yield fullPath;
      }
    }
  }

  async startScan(mode = 'quick', customTarget = null) {
    if (this.isScanning) {
      throw new Error('Đang có tiến trình quét đang chạy.');
    }

    this.isScanning = true;
    this.isPaused = false;
    this.shouldStop = false;
    this.stats = {
      filesScanned: 0,
      threatsFound: 0,
      errorsCount: 0,
      startTime: Date.now(),
      endTime: null
    };
    this.foundThreats = [];

    let scanPaths = [];
    let maxDepth = 3;

    if (mode === 'quick') {
      scanPaths = this.getQuickScanTargets();
      maxDepth = 3;
    } else if (mode === 'custom' && customTarget) {
      scanPaths = Array.isArray(customTarget) ? customTarget : [customTarget];
      maxDepth = 8;
    } else if (mode === 'full') {
      // Typically C:\ with selective depth to ensure completion
      scanPaths = ['C:\\Users', 'C:\\Program Files', 'C:\\Program Files (x86)', 'C:\\ProgramData'];
      maxDepth = 6;
    }

    try {
      for (const rootPath of scanPaths) {
        if (this.shouldStop) break;

        if (!fs.existsSync(rootPath)) continue;

        const stat = fs.statSync(rootPath);
        if (stat.isFile()) {
          this.stats.filesScanned++;
          const threat = await this.analyzeFile(rootPath);
          if (threat) {
            this.stats.threatsFound++;
            this.foundThreats.push(threat);
            this.onThreat(threat);
          }
          this.onProgress({
            currentFile: rootPath,
            filesScanned: this.stats.filesScanned,
            threatsFound: this.stats.threatsFound
          });
          continue;
        }

        // Directory walk
        for await (const filePath of this.walkDirectory(rootPath, maxDepth)) {
          if (this.shouldStop) break;

          this.stats.filesScanned++;
          const threat = await this.analyzeFile(filePath);

          if (threat) {
            this.stats.threatsFound++;
            this.foundThreats.push(threat);
            this.onThreat(threat);
          }

          if (this.stats.filesScanned % 15 === 0 || threat) {
            this.onProgress({
              currentFile: filePath,
              filesScanned: this.stats.filesScanned,
              threatsFound: this.stats.threatsFound
            });
          }
        }
      }
    } finally {
      this.isScanning = false;
      this.stats.endTime = Date.now();
      this.onProgress({
        currentFile: 'Hoàn tất quét hệ thống!',
        filesScanned: this.stats.filesScanned,
        threatsFound: this.stats.threatsFound,
        completed: true
      });
    }

    return {
      stats: this.stats,
      threats: this.foundThreats
    };
  }

  pause() {
    this.isPaused = true;
  }

  resume() {
    this.isPaused = false;
  }

  stop() {
    this.shouldStop = true;
    this.isPaused = false;
  }
}

module.exports = VirusScanner;
