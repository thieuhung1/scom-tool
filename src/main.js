const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const os = require('os');
const fs = require('fs');

let mainWindow = null;
let currentChildProcess = null;

const projectRoot = path.join(__dirname, '..');
const engineDir = path.join(projectRoot, 'engine');
const coreScannerScript = path.join(engineDir, 'core_scanner.ps1');
const cleanerScript = path.join(engineDir, 'cleaner.ps1');
const cancelFlagPath = path.join(os.tmpdir(), 'scom_cancel_scan.flag');

// Protected PIDs & System processes (System Idle, System, Session Manager, etc.)
const PROTECTED_PIDS = new Set([0, 4]);

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1240,
    height: 840,
    minWidth: 1000,
    minHeight: 680,
    frame: false,
    titleBarStyle: 'hidden',
    backgroundColor: '#0b0f19',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.on('closed', () => {
    mainWindow = null;
    if (currentChildProcess) {
      try {
        currentChildProcess.kill();
      } catch {}
    }
  });
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// Window controls
ipcMain.on('window:minimize', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.on('window:maximize', () => {
  if (mainWindow) {
    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow.maximize();
    }
  }
});

ipcMain.on('window:close', () => {
  if (mainWindow) mainWindow.close();
});

// Helper to execute PowerShell scripts asynchronously and return parsed JSON
function runPowerShellScript(scriptPath, args = []) {
  return new Promise((resolve, reject) => {
    const psArgs = [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', scriptPath,
      ...args
    ];

    let stdoutBuffer = '';
    let stderrBuffer = '';

    const ps = spawn('powershell.exe', psArgs, {
      cwd: projectRoot,
      windowsHide: true
    });

    currentChildProcess = ps;

    ps.stdout.on('data', (data) => {
      const text = data.toString('utf8');
      stdoutBuffer += text;

      // Stream lines and progress events to UI
      const lines = text.split(/\r?\n/).filter(l => l.trim().length > 0);
      lines.forEach(line => {
        if (line.startsWith('JSON_EVENT:')) {
          try {
            const ev = JSON.parse(line.substring('JSON_EVENT:'.length));
            if (mainWindow && !mainWindow.isDestroyed()) {
              mainWindow.webContents.send('scan:progress', ev);
            }
          } catch {}
        } else if (!line.startsWith('{') && !line.startsWith('}')) {
          if (mainWindow && !mainWindow.isDestroyed()) {
            mainWindow.webContents.send('scan:log', line);
          }
        }
      });
    });

    ps.stderr.on('data', (data) => {
      const errText = data.toString('utf8');
      stderrBuffer += errText;
    });

    ps.on('close', (code) => {
      currentChildProcess = null;

      // Extract JSON from stdoutBuffer (ignoring JSON_EVENT prefixes)
      const cleanLines = stdoutBuffer
        .split(/\r?\n/)
        .filter(l => !l.startsWith('JSON_EVENT:'))
        .join('\n')
        .trim();

      let parsed = null;
      try {
        parsed = JSON.parse(cleanLines);
      } catch (e) {
        const start = cleanLines.indexOf('{');
        const end = cleanLines.lastIndexOf('}');
        if (start !== -1 && end !== -1 && end > start) {
          try {
            parsed = JSON.parse(cleanLines.substring(start, end + 1));
          } catch (innerErr) {
            console.error('Failed to parse inner JSON:', innerErr);
          }
        }
      }

      if (parsed) {
        resolve(parsed);
      } else {
        if (code !== 0 && stderrBuffer) {
          reject(new Error(stderrBuffer));
        } else {
          resolve({
            status: 'Completed',
            rawOutput: cleanLines
          });
        }
      }
    });

    ps.on('error', (err) => {
      currentChildProcess = null;
      reject(err);
    });
  });
}

// Dialog: Select Folder
ipcMain.handle('dialog:select-folder', async () => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: 'Chọn thư mục cần quét mã độc'
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  return result.filePaths[0];
});

// Dialog: Select File
ipcMain.handle('dialog:select-file', async () => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile'],
    title: 'Chọn tệp tin cần quét kiểm tra'
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  return result.filePaths[0];
});

// Scanner: Start Scan (Clears cancel flag)
ipcMain.handle('scan:start', async (event, params = {}) => {
  const mode = params.mode || 'Quick';
  const targetPath = params.targetPath || '';
  const autoQuarantine = !!params.autoQuarantine;

  // Clear any existing cancellation flag
  try {
    if (fs.existsSync(cancelFlagPath)) {
      fs.unlinkSync(cancelFlagPath);
    }
  } catch {}

  const scriptArgs = [
    '-Mode', mode,
    '-OutputFormat', 'JSON',
    '-NonInteractive'
  ];

  if (targetPath) {
    scriptArgs.push('-TargetPath', targetPath);
  }

  if (autoQuarantine) {
    scriptArgs.push('-AutoQuarantine');
  }

  try {
    return await runPowerShellScript(coreScannerScript, scriptArgs);
  } catch (error) {
    return {
      status: 'Error',
      message: error.message
    };
  }
});

// Scanner: Stop Scan (Cooperative flag + kill)
ipcMain.handle('scan:stop', () => {
  try {
    fs.writeFileSync(cancelFlagPath, 'CANCEL', 'utf8');
  } catch {}

  if (currentChildProcess) {
    try {
      currentChildProcess.kill();
      currentChildProcess = null;
      return { status: 'Stopped' };
    } catch (e) {
      return { status: 'Error', message: e.message };
    }
  }
  return { status: 'Idle' };
});

// Process Hunter: List
ipcMain.handle('process:list', async () => {
  try {
    return await runPowerShellScript(coreScannerScript, [
      '-Mode', 'ProcessHunter',
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message, threats: [] };
  }
});

// Process Hunter: Kill PID (FIX: Eliminates Command Injection vulnerability)
ipcMain.handle('process:kill', async (event, pid) => {
  // Validate pid is strictly a positive integer and not a protected system PID
  const cleanPid = Number(pid);
  if (!Number.isInteger(cleanPid) || cleanPid <= 4 || PROTECTED_PIDS.has(cleanPid)) {
    return {
      success: false,
      error: 'PID không hợp lệ hoặc thuộc tiến trình hệ thống được bảo vệ.',
      pid
    };
  }

  return new Promise((resolve) => {
    // Use taskkill.exe with arguments array - NO shell string interpolation
    const tk = spawn('taskkill.exe', ['/F', '/PID', String(cleanPid)], {
      windowsHide: true
    });

    let errOutput = '';
    tk.stderr.on('data', (d) => { errOutput += d.toString(); });

    tk.on('close', (code) => {
      if (code === 0) {
        resolve({ success: true, pid: cleanPid });
      } else {
        resolve({
          success: false,
          error: errOutput.trim() || `Không thể dừng tiến trình PID ${cleanPid} (Mã lỗi: ${code})`,
          pid: cleanPid
        });
      }
    });

    tk.on('error', (err) => {
      resolve({ success: false, error: err.message, pid: cleanPid });
    });
  });
});

// Cleaner: Run Action
ipcMain.handle('cleaner:run', async (event, action = 'CleanAll') => {
  try {
    return await runPowerShellScript(cleanerScript, [
      '-Action', action,
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message };
  }
});

// Startup Shield: List
ipcMain.handle('startup:list', async () => {
  try {
    return await runPowerShellScript(coreScannerScript, [
      '-Mode', 'Startup',
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message, items: [] };
  }
});

// Hosts Shield: Status
ipcMain.handle('hosts:status', async () => {
  try {
    return await runPowerShellScript(coreScannerScript, [
      '-Mode', 'HostsShield',
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message, entries: [] };
  }
});

// Hosts Shield: Reset
ipcMain.handle('hosts:reset', async () => {
  try {
    return await runPowerShellScript(cleanerScript, [
      '-Action', 'HostsReset',
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message };
  }
});

// Quarantine: List
ipcMain.handle('quarantine:list', async () => {
  try {
    return await runPowerShellScript(coreScannerScript, [
      '-Mode', 'QuarantineList',
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message, items: [] };
  }
});

// Quarantine: Restore
ipcMain.handle('quarantine:restore', async (event, restoreId) => {
  if (typeof restoreId !== 'string' || !restoreId.trim()) {
    return { status: 'Error', message: 'RestoreId không hợp lệ' };
  }
  try {
    return await runPowerShellScript(coreScannerScript, [
      '-Mode', 'QuarantineRestore',
      '-RestoreId', restoreId.trim(),
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message };
  }
});

// Quarantine: Wipe
ipcMain.handle('quarantine:wipe', async () => {
  try {
    return await runPowerShellScript(coreScannerScript, [
      '-Mode', 'QuarantineWipe',
      '-OutputFormat', 'JSON',
      '-NonInteractive'
    ]);
  } catch (err) {
    return { status: 'Error', message: err.message };
  }
});

// EICAR Test Generator
ipcMain.handle('eicar:create', async (event, targetPath = '') => {
  const args = [
    '-Mode', 'EicarTest',
    '-OutputFormat', 'JSON',
    '-NonInteractive'
  ];
  if (targetPath && typeof targetPath === 'string') {
    args.push('-TargetPath', targetPath);
  }

  try {
    return await runPowerShellScript(coreScannerScript, args);
  } catch (err) {
    return { status: 'Error', message: err.message };
  }
});

// System Info
ipcMain.handle('system:info', () => {
  const totalMemGB = Math.round(os.totalmem() / (1024 * 1024 * 1024));
  const freeMemGB = (os.freemem() / (1024 * 1024 * 1024)).toFixed(1);
  return {
    platform: os.platform(),
    release: os.release(),
    arch: os.arch(),
    hostname: os.hostname(),
    cpus: os.cpus().length,
    cpuModel: os.cpus()[0]?.model || 'Windows Processor',
    totalMemGB,
    freeMemGB,
    usedMemGB: (totalMemGB - freeMemGB).toFixed(1)
  };
});
