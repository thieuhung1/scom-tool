const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('securityAPI', {
  // Scanner API
  startScan: (mode, customTarget) => ipcRenderer.invoke('scanner:start', { mode, customTarget }),
  pauseScan: () => ipcRenderer.invoke('scanner:pause'),
  resumeScan: () => ipcRenderer.invoke('scanner:resume'),
  stopScan: () => ipcRenderer.invoke('scanner:stop'),
  onScanProgress: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('scanner:progress', handler);
    return () => ipcRenderer.removeListener('scanner:progress', handler);
  },
  onScanThreat: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('scanner:threat', handler);
    return () => ipcRenderer.removeListener('scanner:threat', handler);
  },

  // Quarantine API
  getQuarantinedFiles: () => ipcRenderer.invoke('quarantine:list'),
  quarantineFile: (filePath, threatInfo) => ipcRenderer.invoke('quarantine:isolate', { filePath, threatInfo }),
  restoreQuarantinedFile: (id) => ipcRenderer.invoke('quarantine:restore', id),
  deleteQuarantinedFile: (id) => ipcRenderer.invoke('quarantine:delete', id),
  clearAllQuarantined: () => ipcRenderer.invoke('quarantine:clearAll'),

  // Process Monitor API
  getProcesses: () => ipcRenderer.invoke('process:list'),
  killProcess: (pid) => ipcRenderer.invoke('process:kill', pid),

  // System Cleaner API
  analyzeJunk: () => ipcRenderer.invoke('cleaner:analyze'),
  cleanJunk: (targetIds) => ipcRenderer.invoke('cleaner:clean', targetIds),

  // System Shield & Overview API
  getSecurityOverview: (threatsCount, quarantinedCount) =>
    ipcRenderer.invoke('shield:overview', { threatsCount, quarantinedCount }),
  getStartupItems: () => ipcRenderer.invoke('shield:startup'),

  // Native Dialogs
  selectFolder: () => ipcRenderer.invoke('dialog:selectFolder'),
  selectFile: () => ipcRenderer.invoke('dialog:selectFile'),

  // Window Controls
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  maximizeWindow: () => ipcRenderer.invoke('window:maximize'),
  closeWindow: () => ipcRenderer.invoke('window:close')
});
