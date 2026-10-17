const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  // Window controls
  minimize: () => ipcRenderer.send('window:minimize'),
  maximize: () => ipcRenderer.send('window:maximize'),
  close: () => ipcRenderer.send('window:close'),

  // Scanner methods
  startScan: (params) => ipcRenderer.invoke('scan:start', params),
  stopScan: () => ipcRenderer.invoke('scan:stop'),
  selectFolder: () => ipcRenderer.invoke('dialog:select-folder'),
  selectFile: () => ipcRenderer.invoke('dialog:select-file'),

  // Process Hunter
  getProcesses: () => ipcRenderer.invoke('process:list'),
  killProcess: (pid) => ipcRenderer.invoke('process:kill', pid),

  // System Cleaner
  runCleaner: (action) => ipcRenderer.invoke('cleaner:run', action),

  // Startup & Hosts Shield
  getStartupItems: () => ipcRenderer.invoke('startup:list'),
  getHostsStatus: () => ipcRenderer.invoke('hosts:status'),
  resetHosts: () => ipcRenderer.invoke('hosts:reset'),

  // Quarantine
  getQuarantineList: () => ipcRenderer.invoke('quarantine:list'),
  restoreQuarantine: (id) => ipcRenderer.invoke('quarantine:restore', id),
  wipeQuarantine: () => ipcRenderer.invoke('quarantine:wipe'),

  // EICAR Test
  createEicarTest: (targetPath) => ipcRenderer.invoke('eicar:create', targetPath),

  // System Info & stats
  getSystemInfo: () => ipcRenderer.invoke('system:info'),

  // Real-time Event listeners
  onScanLog: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('scan:log', handler);
    return () => ipcRenderer.removeListener('scan:log', handler);
  }
});
