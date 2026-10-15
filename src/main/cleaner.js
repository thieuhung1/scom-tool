const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

class SystemCleaner {
  constructor() {
    this.targets = this.getCleanupTargets();
  }

  getCleanupTargets() {
    const userProfile = process.env.USERPROFILE || 'C:\\Users\\Default';
    const localAppData = process.env.LOCALAPPDATA || path.join(userProfile, 'AppData', 'Local');

    return [
      {
        id: 'user_temp',
        name: 'Tệp tạm người dùng (User Temp)',
        path: process.env.TEMP || path.join(localAppData, 'Temp'),
        description: 'Tệp tạm thời do các ứng dụng và trình cài đặt tạo ra.'
      },
      {
        id: 'win_temp',
        name: 'Tệp tạm Windows (Windows Temp)',
        path: 'C:\\Windows\\Temp',
        description: 'Tệp tạm của hệ thống Windows và các dịch vụ nền.'
      },
      {
        id: 'prefetch',
        name: 'Bộ nhớ đệm nạp trước (Windows Prefetch)',
        path: 'C:\\Windows\\Prefetch',
        description: 'Dữ liệu nạp sẵn của các ứng dụng cũ không còn dùng.'
      },
      {
        id: 'crash_dumps',
        name: 'Bản ghi sự cố phần mềm (Crash Dumps)',
        path: path.join(localAppData, 'CrashDumps'),
        description: 'Tệp ghi lại lỗi khi ứng dụng bị sập, chiếm dụng bộ nhớ.'
      },
      {
        id: 'chrome_cache',
        name: 'Bộ nhớ đệm Google Chrome',
        path: path.join(localAppData, 'Google', 'Chrome', 'User Data', 'Default', 'Cache', 'Cache_Data'),
        description: 'Hình ảnh và tập tin web tạm của Google Chrome.'
      },
      {
        id: 'edge_cache',
        name: 'Bộ nhớ đệm Microsoft Edge',
        path: path.join(localAppData, 'Microsoft', 'Edge', 'User Data', 'Default', 'Cache', 'Cache_Data'),
        description: 'Tập tin lưu tạm duyệt web của Microsoft Edge.'
      }
    ];
  }

  // Calculate size of a folder
  getFolderSize(folderPath) {
    let totalSize = 0;
    let fileCount = 0;

    if (!fs.existsSync(folderPath)) {
      return { totalSize: 0, fileCount: 0 };
    }

    try {
      const files = fs.readdirSync(folderPath);
      for (const file of files) {
        const fullPath = path.join(folderPath, file);
        try {
          const stat = fs.statSync(fullPath);
          if (stat.isFile()) {
            totalSize += stat.size;
            fileCount++;
          } else if (stat.isDirectory()) {
            // subfolder
            try {
              const subFiles = fs.readdirSync(fullPath);
              for (const sf of subFiles) {
                try {
                  const sstat = fs.statSync(path.join(fullPath, sf));
                  if (sstat.isFile()) {
                    totalSize += sstat.size;
                    fileCount++;
                  }
                } catch (e) {}
              }
            } catch (e) {}
          }
        } catch (e) {}
      }
    } catch (e) {}

    return { totalSize, fileCount };
  }

  // Scan all cleanup targets without deleting
  async analyzeJunk() {
    const results = [];
    let grandTotalBytes = 0;
    let grandTotalFiles = 0;

    for (const target of this.targets) {
      const { totalSize, fileCount } = this.getFolderSize(target.path);
      grandTotalBytes += totalSize;
      grandTotalFiles += fileCount;

      results.push({
        id: target.id,
        name: target.name,
        path: target.path,
        description: target.description,
        sizeBytes: totalSize,
        sizeMB: (totalSize / (1024 * 1024)).toFixed(2),
        fileCount,
        available: fs.existsSync(target.path)
      });
    }

    return {
      items: results,
      totalBytes: grandTotalBytes,
      totalMB: (grandTotalBytes / (1024 * 1024)).toFixed(2),
      totalFiles: grandTotalFiles
    };
  }

  // Clean files in selected target categories
  async cleanJunk(targetIds = []) {
    let freedBytes = 0;
    let deletedFiles = 0;
    let errorsCount = 0;

    for (const target of this.targets) {
      if (targetIds.length > 0 && !targetIds.includes(target.id)) {
        continue;
      }

      if (!fs.existsSync(target.path)) continue;

      try {
        const files = fs.readdirSync(target.path);
        for (const file of files) {
          const fullPath = path.join(target.path, file);
          try {
            const stat = fs.statSync(fullPath);
            if (stat.isFile()) {
              const size = stat.size;
              fs.unlinkSync(fullPath);
              freedBytes += size;
              deletedFiles++;
            } else if (stat.isDirectory()) {
              try {
                fs.rmSync(fullPath, { recursive: true, force: true });
                deletedFiles++;
              } catch (subErr) {
                errorsCount++;
              }
            }
          } catch (e) {
            // File is likely locked by an open program, gracefully skip
            errorsCount++;
          }
        }
      } catch (e) {
        errorsCount++;
      }
    }

    // Attempt to empty Recycle Bin via PowerShell
    await new Promise((resolve) => {
      exec('powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"', () => {
        resolve();
      });
    });

    return {
      success: true,
      freedBytes,
      freedMB: (freedBytes / (1024 * 1024)).toFixed(2),
      deletedFiles,
      errorsCount
    };
  }
}

module.exports = SystemCleaner;
