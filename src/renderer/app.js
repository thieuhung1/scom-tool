// ============================================================================
// SCOM CYBERSHIELD v3.0 - RENDERER APPLICATION CONTROLLER
// ============================================================================

document.addEventListener('DOMContentLoaded', () => {
  // Elements
  const btnMinimize = document.getElementById('btnMinimize');
  const btnMaximize = document.getElementById('btnMaximize');
  const btnClose = document.getElementById('btnClose');
  const navItems = document.querySelectorAll('.nav-item');
  const tabPages = document.querySelectorAll('.tab-page');
  const toastContainer = document.getElementById('toastContainer');

  // Scanner Elements
  const scanModesContainer = document.getElementById('scanModesContainer');
  const liveScanPanel = document.getElementById('liveScanPanel');
  const scanResultsPanel = document.getElementById('scanResultsPanel');
  const scanTerminalBody = document.getElementById('scanTerminalBody');
  const scanCurrentPath = document.getElementById('scanCurrentPath');
  const btnStopScan = document.getElementById('btnStopScan');
  const btnStartQuickScan = document.getElementById('btnStartQuickScan');
  const btnStartCustomScan = document.getElementById('btnStartCustomScan');
  const btnStartFullScan = document.getElementById('btnStartFullScan');
  const dropZone = document.getElementById('dropZone');
  const dropTargetText = document.getElementById('dropTargetText');
  const btnBrowseFolder = document.getElementById('btnBrowseFolder');
  const btnBrowseFile = document.getElementById('btnBrowseFile');
  const btnDismissResults = document.getElementById('btnDismissResults');
  const threatsTableBody = document.getElementById('threatsTableBody');
  const resultsHeaderBanner = document.getElementById('resultsHeaderBanner');
  const resultsTitle = document.getElementById('resultsTitle');
  const resultsSubDesc = document.getElementById('resultsSubDesc');

  // Stats Counters
  const statFilesScanned = document.getElementById('statFilesScanned');
  const statThreats = document.getElementById('statThreats');
  const statQuarantineCount = document.getElementById('statQuarantineCount');
  const badgeQuarantine = document.getElementById('badgeQuarantine');

  // Process Hunter Elements
  const btnRefreshProcesses = document.getElementById('btnRefreshProcesses');
  const inputFilterProcess = document.getElementById('inputFilterProcess');
  const processTableBody = document.getElementById('processTableBody');
  const processStatsLabel = document.getElementById('processStatsLabel');

  // Cleaner Elements
  const btnRunDeepClean = document.getElementById('btnRunDeepClean');
  const cleanerReportBox = document.getElementById('cleanerReportBox');
  const cleanerStatsText = document.getElementById('cleanerStatsText');
  const cleanerDetailsList = document.getElementById('cleanerDetailsList');

  // Shields Elements
  const btnRefreshStartup = document.getElementById('btnRefreshStartup');
  const startupTableBody = document.getElementById('startupTableBody');
  const btnResetHosts = document.getElementById('btnResetHosts');
  const hostsIndicator = document.getElementById('hostsIndicator');
  const hostsListEntries = document.getElementById('hostsListEntries');

  // Quarantine Elements
  const btnRefreshQuarantine = document.getElementById('btnRefreshQuarantine');
  const btnWipeQuarantine = document.getElementById('btnWipeQuarantine');
  const quarantineTableBody = document.getElementById('quarantineTableBody');

  // Lab Elements
  const btnGenerateEicar = document.getElementById('btnGenerateEicar');
  const eicarResultNotice = document.getElementById('eicarResultNotice');

  // State
  let customSelectedPath = '';
  let allProcessesCache = [];
  let isScanning = false;

  // ================= 1. Window Controls =================
  if (btnMinimize) btnMinimize.addEventListener('click', () => window.api?.minimize());
  if (btnMaximize) btnMaximize.addEventListener('click', () => window.api?.maximize());
  if (btnClose) btnClose.addEventListener('click', () => window.api?.close());

  // ================= 2. Navigation Tabs =================
  navItems.forEach(item => {
    item.addEventListener('click', () => {
      const targetTabId = item.getAttribute('data-tab');
      
      navItems.forEach(n => n.classList.remove('active'));
      tabPages.forEach(p => p.classList.remove('active'));

      item.classList.add('active');
      const targetPage = document.getElementById(targetTabId);
      if (targetPage) targetPage.classList.add('active');

      // Auto-refresh when tab is switched
      if (targetTabId === 'tab-process') loadProcesses();
      if (targetTabId === 'tab-shields') { loadStartupItems(); loadHostsStatus(); }
      if (targetTabId === 'tab-quarantine') loadQuarantineList();
    });
  });

  // ================= 3. Toast Notifications =================
  function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `<span>${message}</span>`;
    toastContainer.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(10px)';
      toast.style.transition = 'all 0.3s';
      setTimeout(() => toast.remove(), 300);
    }, 3500);
  }

  // ================= 4. System Info =================
  async function loadSystemInfo() {
    if (!window.api?.getSystemInfo) return;
    try {
      const info = await window.api.getSystemInfo();
      document.getElementById('sysHostName').textContent = info.hostname;
      document.getElementById('sysMemUsage').textContent = `RAM: ${info.usedMemGB} / ${info.totalMemGB} GB (${info.cpus} Cores)`;
    } catch (e) {
      console.error(e);
    }
  }

  // ================= 5. Scanner Logic =================
  function setScanningState(scanning) {
    isScanning = scanning;
    if (scanning) {
      scanModesContainer.classList.add('hidden');
      scanResultsPanel.classList.add('hidden');
      liveScanPanel.classList.remove('hidden');
      scanTerminalBody.innerHTML = '<div class="log-line info">[*] Đang khởi động engine PowerShell quét đa lớp...</div>';
    } else {
      liveScanPanel.classList.add('hidden');
      scanModesContainer.classList.remove('hidden');
    }
  }

  function appendScanLog(line, type = '') {
    const div = document.createElement('div');
    div.className = `log-line ${type}`;
    div.textContent = line;
    scanTerminalBody.appendChild(div);
    scanTerminalBody.scrollTop = scanTerminalBody.scrollHeight;
  }

  // Realtime Log Listener
  if (window.api?.onScanLog) {
    window.api.onScanLog((line) => {
      if (line.includes('PHÁT HIỆN') || line.includes('CẢNH BÁO')) {
        appendScanLog(line, 'danger');
      } else if (line.includes('->')) {
        appendScanLog(line, 'info');
        scanCurrentPath.textContent = line.replace('->', '').trim();
      } else {
        appendScanLog(line);
      }
    });
  }

  // Realtime Progress Listener
  if (window.api?.onScanProgress) {
    window.api.onScanProgress((prog) => {
      if (prog && prog.scanned) {
        statFilesScanned.textContent = prog.scanned;
        if (prog.current) {
          scanCurrentPath.textContent = `[Đang quét ${prog.scanned}]: ${prog.current}`;
        }
      }
    });
  }

  // Start Scan Helper
  async function executeScan(params) {
    setScanningState(true);
    try {
      const result = await window.api.startScan(params);
      setScanningState(false);
      displayScanResults(result);
      loadQuarantineList();
    } catch (error) {
      setScanningState(false);
      showToast(`Lỗi quét: ${error.message}`, 'error');
    }
  }

  // Stop Scan
  if (btnStopScan) {
    btnStopScan.addEventListener('click', async () => {
      if (window.api?.stopScan) {
        await window.api.stopScan();
        setScanningState(false);
        showToast('Đã dừng tiến trình quét theo yêu cầu của bạn.', 'info');
      }
    });
  }

  // Quick Scan
  if (btnStartQuickScan) {
    btnStartQuickScan.addEventListener('click', () => {
      executeScan({ mode: 'Quick' });
    });
  }

  // Full Scan
  if (btnStartFullScan) {
    btnStartFullScan.addEventListener('click', () => {
      executeScan({ mode: 'Full' });
    });
  }

  // Custom Target Selection
  function setCustomTarget(targetPath) {
    customSelectedPath = targetPath;
    dropTargetText.textContent = targetPath;
    btnStartCustomScan.removeAttribute('disabled');
    showToast(`Đã chọn mục tiêu: ${targetPath}`, 'info');
  }

  if (btnBrowseFolder) {
    btnBrowseFolder.addEventListener('click', async () => {
      const folder = await window.api.selectFolder();
      if (folder) setCustomTarget(folder);
    });
  }

  if (btnBrowseFile) {
    btnBrowseFile.addEventListener('click', async () => {
      const file = await window.api.selectFile();
      if (file) setCustomTarget(file);
    });
  }

  // Drag & Drop
  if (dropZone) {
    dropZone.addEventListener('dragover', (e) => {
      e.preventDefault();
      dropZone.classList.add('dragover');
    });

    dropZone.addEventListener('dragleave', () => {
      dropZone.classList.remove('dragover');
    });

    dropZone.addEventListener('drop', (e) => {
      e.preventDefault();
      dropZone.classList.remove('dragover');
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        setCustomTarget(e.dataTransfer.files[0].path);
      }
    });

    dropZone.addEventListener('click', async () => {
      const folder = await window.api.selectFolder();
      if (folder) setCustomTarget(folder);
    });
  }

  if (btnStartCustomScan) {
    btnStartCustomScan.addEventListener('click', () => {
      if (!customSelectedPath) return;
      executeScan({ mode: 'Custom', targetPath: customSelectedPath });
    });
  }

  // Dismiss Results
  if (btnDismissResults) {
    btnDismissResults.addEventListener('click', () => {
      scanResultsPanel.classList.add('hidden');
      scanModesContainer.classList.remove('hidden');
    });
  }

  // Display Results
  function displayScanResults(result) {
    scanResultsPanel.classList.remove('hidden');
    scanModesContainer.classList.add('hidden');

    const total = result.TotalScanned || 0;
    const threats = result.Threats || [];
    statFilesScanned.textContent = total;
    statThreats.textContent = threats.length;

    if (threats.length === 0) {
      resultsHeaderBanner.className = 'results-header clean';
      resultsTitle.textContent = 'Hệ Thống An Toàn Tuyệt Đối!';
      resultsSubDesc.textContent = `Đã phân tích toàn diện ${total} tệp tin. Không phát hiện bất kỳ dấu hiệu mã độc hay tệp khả nghi nào.`;
      threatsTableBody.innerHTML = `<tr><td colspan="5" class="table-empty" style="color: var(--accent-green);">[V] Không có mối đe dọa nào. Máy tính của bạn hoàn toàn sạch sẽ!</td></tr>`;
      showToast('Quá trình quét hoàn tất: Hệ thống hoàn toàn sạch sẽ!', 'success');
    } else {
      resultsHeaderBanner.className = 'results-header danger';
      resultsTitle.textContent = `Cảnh Báo: Phát Hiện ${threats.length} Mối Đe Dọa!`;
      resultsSubDesc.textContent = `Đã phân tích ${total} tệp tin. Các tệp độc hại đã được khoanh vùng xử lý.`;
      
      threatsTableBody.innerHTML = '';
      threats.forEach(t => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td><strong>${t.Name || 'Unknown'}</strong></td>
          <td><span class="badge red">${t.Severity || 'Cao'}</span></td>
          <td><span class="badge amber">${t.Reason || 'Trojan/Script'}</span></td>
          <td style="font-family: var(--font-mono); font-size: 11px; max-width: 350px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="${t.Path}">${t.Path}</td>
          <td><span class="badge blue">Đã cách ly</span></td>
        `;
        threatsTableBody.appendChild(tr);
      });
      showToast(`Cảnh báo: Phát hiện ${threats.length} mối đe dọa!`, 'error');
    }
  }

  // ================= 6. Process Hunter =================
  async function loadProcesses() {
    processStatsLabel.textContent = 'Đang quét phân tích RAM & tiến trình...';
    try {
      const res = await window.api.getProcesses();
      const threats = res.Threats || [];
      allProcessesCache = threats;
      renderProcesses(threats);
      processStatsLabel.textContent = `Tổng tiến trình quét: ${res.TotalProcesses || 0} | Đáng ngờ: ${threats.length}`;
    } catch (e) {
      processStatsLabel.textContent = 'Lỗi phân tích tiến trình.';
      console.error(e);
    }
  }

  function renderProcesses(list) {
    processTableBody.innerHTML = '';
    if (!list || list.length === 0) {
      processTableBody.innerHTML = '<tr><td colspan="6" class="table-empty" style="color: var(--accent-green);">[+] Toàn bộ tiến trình đang hoạt động trên RAM đều hợp lệ và an toàn! Không có mã độc đào coin.</td></tr>';
      return;
    }

    list.forEach(p => {
      const tr = document.createElement('tr');
      const actionBtn = (p.IsKillable === false || p.PID <= 4)
        ? '<span class="badge blue">Hệ Thống</span>'
        : `<button class="btn btn-danger btn-sm" onclick="killPid(${p.PID}, '${p.Name}')">Diệt PID</button>`;

      tr.innerHTML = `
        <td style="font-family: var(--font-mono);">${p.PID}</td>
        <td><strong>${p.Name}</strong></td>
        <td>${p.RAM_MB} MB</td>
        <td><span class="badge red">${p.Severity}</span></td>
        <td><span class="badge amber">${p.Reason}</span></td>
        <td>${actionBtn}</td>
      `;
      processTableBody.appendChild(tr);
    });
  }

  window.killPid = async (pid, name) => {
    const cleanPid = Number(pid);
    if (!Number.isInteger(cleanPid) || cleanPid <= 4) {
      showToast('Không thể dừng tiến trình cốt lõi của hệ thống!', 'error');
      return;
    }

    if (confirm(`⚠️ CẢNH BÁO AN TOÀN:\nBạn có chắc chắn muốn cưỡng chế tiêu diệt tiến trình "${name}" (PID: ${cleanPid}) không?\n\nLưu ý: Nếu tiến trình đang mở tệp dữ liệu, dữ liệu chưa lưu có thể bị mất.`)) {
      const res = await window.api.killProcess(cleanPid);
      if (res.success) {
        showToast(`Đã tiêu diệt tiến trình ${name} (PID: ${cleanPid}) thành công!`, 'success');
        loadProcesses();
      } else {
        showToast(`Không thể dừng tiến trình ${cleanPid}: ${res.error || 'Quyền bị từ chối'}`, 'error');
      }
    }
  };

  if (btnRefreshProcesses) {
    btnRefreshProcesses.addEventListener('click', loadProcesses);
  }

  if (inputFilterProcess) {
    inputFilterProcess.addEventListener('input', (e) => {
      const query = e.target.value.toLowerCase();
      const filtered = allProcessesCache.filter(p => 
        p.Name.toLowerCase().includes(query) || String(p.PID).includes(query) || p.Reason.toLowerCase().includes(query)
      );
      renderProcesses(filtered);
    });
  }

  // ================= 7. System Cleaner =================
  if (btnRunDeepClean) {
    btnRunDeepClean.addEventListener('click', async () => {
      btnRunDeepClean.setAttribute('disabled', 'true');
      btnRunDeepClean.innerHTML = '<span>Đang dọn dẹp hệ thống...</span>';
      
      try {
        const res = await window.api.runCleaner('CleanAll');
        cleanerReportBox.classList.remove('hidden');
        cleanerStatsText.textContent = `Đã xóa thành công ${res.TotalFilesDeleted || 0} tệp rác. Thu hồi giải phóng ${res.TotalFreedMB || 0} MB dung lượng ổ đĩa!`;
        
        cleanerDetailsList.innerHTML = '';
        (res.Details || []).forEach(d => {
          const item = document.createElement('div');
          item.textContent = `• ${d.Label}: ${d.DeletedFiles ? `Đã xóa ${d.DeletedFiles} tệp (${d.FreedMB} MB)` : d.Status || 'Sạch sẽ'}`;
          cleanerDetailsList.appendChild(item);
        });

        showToast(`Hoàn tất dọn dẹp: Giải phóng ${res.TotalFreedMB || 0} MB!`, 'success');
      } catch (e) {
        showToast(`Lỗi dọn dẹp: ${e.message}`, 'error');
      } finally {
        btnRunDeepClean.removeAttribute('disabled');
        btnRunDeepClean.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="btn-icon"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg><span>Tiến Hành Dọn Dẹp Ngay</span>';
      }
    });
  }

  // ================= 8. Shields (Startup & Hosts) =================
  async function loadStartupItems() {
    try {
      const res = await window.api.getStartupItems();
      const items = res.Items || [];
      startupTableBody.innerHTML = '';
      if (items.length === 0) {
        startupTableBody.innerHTML = '<tr><td colspan="3" class="table-empty">Không có mục khởi động nào trong Registry.</td></tr>';
        return;
      }
      items.forEach(it => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td><strong>${it.Name}</strong></td>
          <td><span class="badge ${it.IsSuspicious ? 'red' : 'green'}">${it.IsSuspicious ? 'Đáng Ngờ' : 'Bình Thường'}</span></td>
          <td style="font-family: var(--font-mono); font-size: 11px; max-width: 320px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="${it.Command}">${it.Command}</td>
        `;
        startupTableBody.appendChild(tr);
      });
    } catch (e) {
      console.error(e);
    }
  }

  async function loadHostsStatus() {
    try {
      const res = await window.api.getHostsStatus();
      const entries = res.Entries || [];
      if (entries.length === 0) {
        hostsIndicator.innerHTML = '<span style="color: var(--accent-green);">[+] Tệp Hosts hoàn toàn chuẩn xác, không bị chèn điều hướng DNS lạ.</span>';
        hostsListEntries.innerHTML = '<div style="color: var(--text-dim);">Chỉ bao gồm localhost (127.0.0.1 và ::1).</div>';
      } else {
        hostsIndicator.innerHTML = `<span style="color: var(--accent-red);">[!] Cảnh báo: Phát hiện ${entries.length} dòng chuyển hướng lạ trong file Hosts!</span>`;
        hostsListEntries.innerHTML = entries.map(e => `<div>${e}</div>`).join('');
      }
    } catch (e) {
      console.error(e);
    }
  }

  if (btnRefreshStartup) btnRefreshStartup.addEventListener('click', loadStartupItems);

  if (btnResetHosts) {
    btnResetHosts.addEventListener('click', async () => {
      if (confirm('Bạn có muốn khôi phục tệp Hosts về cấu hình mặc định ban đầu của Microsoft không?')) {
        const res = await window.api.resetHosts();
        if (res.Status === 'Completed' || res.status === 'Completed') {
          showToast('Đã khôi phục file Hosts về mặc định thành công!', 'success');
          loadHostsStatus();
        } else {
          showToast('Không thể sửa file Hosts (Yêu cầu quyền Administrator).', 'error');
        }
      }
    });
  }

  // ================= 9. Quarantine Vault =================
  async function loadQuarantineList() {
    try {
      const res = await window.api.getQuarantineList();
      const items = res.Items || [];
      badgeQuarantine.textContent = items.length;
      statQuarantineCount.textContent = items.length;

      quarantineTableBody.innerHTML = '';
      if (items.length === 0) {
        quarantineTableBody.innerHTML = '<tr><td colspan="6" class="table-empty">Khu vực cách ly an toàn hiện đang trống.</td></tr>';
        return;
      }

      items.forEach(it => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td style="font-family: var(--font-mono);">${it.Id}</td>
          <td><strong>${it.FileName}</strong></td>
          <td><span class="badge red">${it.Severity || 'Cao'}</span></td>
          <td><span class="badge amber">${it.Reason || 'Malware'}</span></td>
          <td style="font-size: 11px; color: var(--text-muted);">${new Date(it.QuarantinedAt).toLocaleString('vi-VN')}</td>
          <td>
            <button class="btn btn-secondary btn-sm" onclick="restoreFile('${it.Id}', '${it.FileName}')">Khôi Phục</button>
          </td>
        `;
        quarantineTableBody.appendChild(tr);
      });
    } catch (e) {
      console.error(e);
    }
  }

  window.restoreFile = async (id, name) => {
    if (confirm(`Bạn có chắc muốn khôi phục tệp ${name} về lại đường dẫn ban đầu không?`)) {
      const res = await window.api.restoreQuarantine(id);
      if (res.Status === 'Success') {
        showToast(`Đã khôi phục thành công tệp ${name}!`, 'success');
        loadQuarantineList();
      } else {
        showToast(`Lỗi khôi phục tệp: ${res.Status || 'Không xác định'}`, 'error');
      }
    }
  };

  if (btnRefreshQuarantine) btnRefreshQuarantine.addEventListener('click', loadQuarantineList);

  if (btnWipeQuarantine) {
    btnWipeQuarantine.addEventListener('click', async () => {
      if (confirm('CẢNH BÁO: Thao tác này sẽ xóa vĩnh viễn toàn bộ các tệp nguy hiểm trong khu cách ly và không thể khôi phục. Bạn có chắc không?')) {
        const res = await window.api.wipeQuarantine();
        showToast(`Đã xóa sạch vĩnh viễn các tệp trong khu cách ly!`, 'success');
        loadQuarantineList();
      }
    });
  }

  // ================= 10. EICAR Test Lab =================
  if (btnGenerateEicar) {
    btnGenerateEicar.addEventListener('click', async () => {
      try {
        const res = await window.api.createEicarTest();
        if (res.Status === 'Created') {
          eicarResultNotice.innerHTML = `<strong>Thành công!</strong> Đã tạo tệp mẫu tại: <code>${res.FilePath}</code>.<br>Bạn hãy chuyển sang tab <strong>Quét & Bảo Vệ</strong> và bấm <strong>Bắt Đầu Quét Nhanh</strong> để xem kết quả nhận diện!`;
          showToast('Đã tạo tệp thử nghiệm EICAR thành công!', 'success');
        } else {
          eicarResultNotice.innerHTML = `<strong>Thông báo:</strong> ${res.Message}`;
          showToast('Windows Defender đã phát hiện và chặn mẫu EICAR tức thì!', 'info');
        }
      } catch (e) {
        showToast(`Lỗi tạo mẫu: ${e.message}`, 'error');
      }
    });
  }

  // Initial Load
  loadSystemInfo();
  loadQuarantineList();
});
