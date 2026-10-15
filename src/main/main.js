const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const QuarantineManager = require('./quarantine');
const VirusScanner = require('./scanner');
const ProcessMonitor = require('./processMonitor');
const SystemCleaner = require('./cleaner');
const SystemShield = require('./systemShield');

let mainWindow = null;
let currentScanner = null;

const quarantineManager = new QuarantineManager(path.join(app.getPath('userData'), 'quarantine'));
const processMonitor = new ProcessMonitor();
const systemCleaner = new SystemCleaner();
const systemShield = new SystemShield();

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 820,
    minWidth: 960,
    minHeight: 660,
    frame: false,
    titleBarStyle: 'hidden',
    backgroundColor: '#0d1117',
    webPreferences: {
      preload: path.join(__dirname, '../preload/preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false
    },
    icon: path.join(__dirname, '../renderer/assets/icon.png')
  });

  mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));

  mainWindow.on('closed', () => {
    mainWindow = null;
    if (currentScanner) {
      currentScanner.stop();
    }
  });
}

// App lifecycle
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
ipcMain.handle('window:minimize', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.handle('window:maximize', () => {
  if (mainWindow) {
    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow.maximize();
    }
  }
});

ipcMain.handle('window:close', () => {
  if (mainWindow) mainWindow.close();
});

// Scanner Handlers
ipcMain.handle('scanner:start', async (event, { mode, customTarget }) => {
  if (currentScanner && currentScanner.isScanning) {
    return { error: 'Tiến trình quét đang hoạt động.' };
  }

  currentScanner = new VirusScanner(
    (progress) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('scanner:progress', progress);
      }
    },
    (threat) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('scanner:threat', threat);
      }
    }
  );

  return await currentScanner.startScan(mode, customTarget);
});

ipcMain.handle('scanner:pause', () => {
  if (currentScanner) {
    currentScanner.pause();
    return { success: true };
  }
  return { success: false };
});

ipcMain.handle('scanner:resume', () => {
  if (currentScanner) {
    currentScanner.resume();
    return { success: true };
  }
  return { success: false };
});

ipcMain.handle('scanner:stop', () => {
  if (currentScanner) {
    currentScanner.stop();
    return { success: true };
  }
  return { success: false };
});

// Quarantine Handlers
ipcMain.handle('quarantine:list', async () => {
  return quarantineManager.getManifest();
});

ipcMain.handle('quarantine:isolate', async (event, { filePath, threatInfo }) => {
  return await quarantineManager.quarantineFile(filePath, threatInfo);
});

ipcMain.handle('quarantine:restore', async (event, id) => {
  return await quarantineManager.restoreFile(id);
});

ipcMain.handle('quarantine:delete', async (event, id) => {
  return await quarantineManager.deletePermanently(id);
});

ipcMain.handle('quarantine:clearAll', async () => {
  return quarantineManager.clearAll();
});

// Process Monitor Handlers
ipcMain.handle('process:list', async () => {
  return await processMonitor.getProcesses();
});

ipcMain.handle('process:kill', async (event, pid) => {
  return await processMonitor.killProcess(pid);
});

// Cleaner Handlers
ipcMain.handle('cleaner:analyze', async () => {
  return await systemCleaner.analyzeJunk();
});

ipcMain.handle('cleaner:clean', async (event, targetIds) => {
  return await systemCleaner.cleanJunk(targetIds);
});

// Shield & System Overview Handlers
ipcMain.handle('shield:overview', async (event, { threatsCount, quarantinedCount }) => {
  return await systemShield.getSecurityOverview(threatsCount, quarantinedCount);
});

ipcMain.handle('shield:startup', async () => {
  return await systemShield.getStartupItems();
});

// Native Dialogs
ipcMain.handle('dialog:selectFolder', async () => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: 'Chọn thư mục cần quét virus'
  });
  if (result.canceled || !result.filePaths || result.filePaths.length === 0) {
    return null;
  }
  return result.filePaths[0];
});

ipcMain.handle('dialog:selectFile', async () => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile'],
    title: 'Chọn tệp khả nghi cần kiểm tra'
  });
  if (result.canceled || !result.filePaths || result.filePaths.length === 0) {
    return null;
  }
  return result.filePaths[0];
});
