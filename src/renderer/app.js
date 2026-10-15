// SCOM CyberShield Frontend Controller
document.addEventListener('DOMContentLoaded', () => {
  // App State
  const state = {
    activeTab: 'tab-dashboard',
    scanMode: 'quick',
    customTargetPath: null,
    isScanning: false,
    isPaused: false,
    filesScanned: 0,
    threats: [],
    quarantinedCount: 0,
    cleanedMB: 0,
    processes: [],
    cleanupData: null
  };

  // DOM Elements
  const navItems = document.querySelectorAll('.nav-item');
  const tabPanes = document.querySelectorAll('.tab-pane');

  // Titlebar controls
  document.getElementById('btnMinimize')?.addEventListener('click', () => window.securityAPI.minimizeWindow());
  document.getElementById('btnMaximize')?.addEventListener('click', () => window.securityAPI.maximizeWindow());
  document.getElementById('btnClose')?.addEventListener('click', () => window.securityAPI.closeWindow());

  // Toast System
  function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `<span>${message}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(40px)';
      toast.style.transition = 'all 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, 3800);
  }

  // Navigation switching
  function switchTab(tabId) {
    state.activeTab = tabId;
    navItems.forEach((btn) => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tabId);
    });
    tabPanes.forEach((pane) => {
      pane.classList.toggle('active', pane.id === tabId);
    });

    if (tabId === 'tab-processes') {
      loadProcesses();
    } else if (tabId === 'tab-cleaner') {
      analyzeCleaner();
    } else if (tabId === 'tab-quarantine') {
      loadQuarantine();
    } else if (tabId === 'tab-shield') {
      loadStartupShield();
    } else if (tabId === 'tab-dashboard') {
      updateDashboardOverview();
    }
  }

  navItems.forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetTab = btn.getAttribute('data-tab');
      switchTab(targetTab);
    });
  });

  // Quick Action Buttons on Dashboard
  document.getElementById('btnQuickScanNow')?.addEventListener('click', () => {
    switchTab('tab-scanner');
    selectScanMode('quick');
    startScanning();
  });

  document.getElementById('btnQuickCleanNow')?.addEventListener('click', () => {
    switchTab('tab-cleaner');
    executeClean();
  });

  document.getElementById('btnRefreshOverview')?.addEventListener('click', () => {
    updateDashboardOverview();
    showToast('Đã làm mới thông tin an ninh hệ thống', 'info');
  });

  // ==================== DASHBOARD LOGIC ====================
  function setSecurityScore(score) {
    const meterCircle = document.getElementById('meterProgressCircle');
    const meterScore = document.getElementById('meterScore');
    const maxDash = 264;
    const offset = maxDash - (maxDash * score) / 100;

    if (meterCircle) {
      meterCircle.style.strokeDashoffset = offset;
      if (score >= 80) {
        meterCircle.style.stroke = '#10b981';
      } else if (score >= 50) {
        meterCircle.style.stroke = '#f59e0b';
      } else {
        meterCircle.style.stroke = '#ef4444';
      }
    }
    if (meterScore) {
      meterScore.textContent = score;
    }
  }

  async function updateDashboardOverview() {
    try {
      const overview = await window.securityAPI.getSecurityOverview(state.threats.length, state.quarantinedCount);
      setSecurityScore(overview.score);

      const shieldCard = document.getElementById('mainShieldCard');
      const statusTag = document.getElementById('statusTag');
      const statusHeading = document.getElementById('statusHeading');
      const statusDesc = document.getElementById('statusDesc');

      if (state.threats.length > 0) {
        shieldCard?.classList.add('danger');
        if (statusTag) statusTag.textContent = 'MỐI ĐE DỌA';
        if (statusHeading) statusHeading.textContent = `Phát Hiện ${state.threats.length} Mã Độc!`;
        if (statusDesc) statusDesc.textContent = 'Hệ thống đã phát hiện tệp hoặc tiến trình nguy hiểm cần xử lý cách ly ngay lập tức.';
      } else {
        shieldCard?.classList.remove('danger');
        if (statusTag) statusTag.textContent = 'AN TOÀN';
        if (statusHeading) statusHeading.textContent = 'Máy Tính Đang Được Bảo Vệ';
        if (statusDesc) statusDesc.textContent = 'Hệ thống bảo vệ chủ động đang quét và ngăn chặn các mối đe dọa, tiến trình độc hại và tệp rác.';
      }

      // Windows Defender Indicator
      const realTimeInd = document.getElementById('statusRealTimeInd');
      const realtimeDesc = document.getElementById('txtRealtimeDesc');
      if (overview.defender.realTimeProtection) {
        realTimeInd?.setAttribute('class', 'shield-status-indicator status-ok');
        if (realtimeDesc) realtimeDesc.textContent = 'Bảo vệ thời gian thực Windows đang bật và hoạt động tốt.';
      } else {
        realTimeInd?.setAttribute('class', 'shield-status-indicator status-err');
        if (realtimeDesc) realtimeDesc.textContent = 'Cảnh báo: Bảo vệ thời gian thực Windows đang bị tắt!';
      }

      // Hosts Indicator
      const hostsInd = document.getElementById('statusHostsInd');
      const hostsDesc = document.getElementById('txtHostsDesc');
      if (overview.hostsStatus === 'WARNING') {
        hostsInd?.setAttribute('class', 'shield-status-indicator status-err');
        if (hostsDesc) hostsDesc.textContent = 'File Hosts có chuyển hướng lạ nghi vấn bị tấn công DNS!';
      } else {
        hostsInd?.setAttribute('class', 'shield-status-indicator status-ok');
        if (hostsDesc) hostsDesc.textContent = 'Không phát hiện hành vi chiếm quyền DNS hoặc chuyển hướng lừa đảo.';
      }

      // Startup Indicator
      const startupInd = document.getElementById('statusStartupInd');
      const startupDesc = document.getElementById('txtStartupDesc');
      if (overview.suspiciousStartupCount > 0) {
        startupInd?.setAttribute('class', 'shield-status-indicator status-warn');
        if (startupDesc) startupDesc.textContent = `Phát hiện ${overview.suspiciousStartupCount} mục khởi động đáng ngờ.`;
      } else {
        startupInd?.setAttribute('class', 'shield-status-indicator status-ok');
        if (startupDesc) startupDesc.textContent = 'Không phát hiện script độc hại tự kích hoạt cùng Windows.';
      }
    } catch (e) {
      console.error(e);
    }
  }

  function addLog(text, isThreat = false) {
    const stream = document.getElementById('dashLogStream');
    if (!stream) return;
    const item = document.createElement('div');
    item.className = `log-item ${isThreat ? 'threat' : ''}`;
    const now = new Date().toLocaleTimeString('vi-VN');
    item.innerHTML = `<span class="log-time">${now}</span><span class="log-text">${text}</span>`;
    stream.prepend(item);
  }

  // ==================== SCANNER LOGIC ====================
  const modeCards = document.querySelectorAll('.mode-card');
  const customTargetBar = document.getElementById('customTargetBar');
  const inputCustomPath = document.getElementById('inputCustomPath');

  function selectScanMode(mode) {
    state.scanMode = mode;
    modeCards.forEach((c) => c.classList.toggle('active', c.getAttribute('data-mode') === mode));
    if (customTargetBar) {
      customTargetBar.style.display = mode === 'custom' ? 'flex' : 'none';
    }
  }

  modeCards.forEach((c) => {
    c.addEventListener('click', () => {
      selectScanMode(c.getAttribute('data-mode'));
    });
  });

  document.getElementById('btnSelectFolder')?.addEventListener('click', async () => {
    const folder = await window.securityAPI.selectFolder();
    if (folder) {
      state.customTargetPath = folder;
      if (inputCustomPath) inputCustomPath.value = folder;
    }
  });

  document.getElementById('btnSelectFile')?.addEventListener('click', async () => {
    const file = await window.securityAPI.selectFile();
    if (file) {
      state.customTargetPath = file;
      if (inputCustomPath) inputCustomPath.value = file;
    }
  });

  const btnStartScan = document.getElementById('btnStartScan');
  const btnPauseScan = document.getElementById('btnPauseScan');
  const btnStopScan = document.getElementById('btnStopScan');
  const radarBox = document.getElementById('scanActiveBox');
  const radarAnimation = document.getElementById('radarAnimation');
  const scanProgressBar = document.getElementById('scanProgressBar');
  const scanStageText = document.getElementById('scanStageText');
  const scanFilesCount = document.getElementById('scanFilesCount');
  const scanThreatCount = document.getElementById('scanThreatCount');
  const scanCurrentPath = document.getElementById('scanCurrentPath');
  const threatTableBody = document.getElementById('threatTableBody');
  const btnQuarantineAll = document.getElementById('btnQuarantineAll');

  async function startScanning() {
    if (state.scanMode === 'custom' && !state.customTargetPath) {
      showToast('Vui lòng chọn thư mục hoặc tệp cần quét.', 'warning');
      return;
    }

    state.isScanning = true;
    state.isPaused = false;
    radarBox?.classList.add('scanning');
    radarAnimation?.classList.add('scanning');

    if (btnStartScan) btnStartScan.style.display = 'none';
    if (btnPauseScan) {
      btnPauseScan.style.display = 'inline-flex';
      btnPauseScan.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg> Tạm Dừng`;
    }
    if (btnStopScan) btnStopScan.style.display = 'inline-flex';
    if (scanStageText) scanStageText.textContent = 'Đang phân tích cấu trúc tệp và chữ ký mã độc...';

    addLog(`Bắt đầu tiến trình ${state.scanMode.toUpperCase()} SCAN...`);

    try {
      const result = await window.securityAPI.startScan(state.scanMode, state.customTargetPath);
      finishScan(result);
    } catch (err) {
      showToast(`Lỗi quét: ${err.message}`, 'danger');
      finishScan();
    }
  }

  function finishScan(result) {
    state.isScanning = false;
    radarBox?.classList.remove('scanning');
    radarAnimation?.classList.remove('scanning');

    if (btnStartScan) {
      btnStartScan.style.display = 'inline-flex';
      btnStartScan.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg> Quét Lại`;
    }
    if (btnPauseScan) btnPauseScan.style.display = 'none';
    if (btnStopScan) btnStopScan.style.display = 'none';

    if (scanStageText) {
      scanStageText.textContent = state.threats.length > 0
        ? `Quét xong: Phát hiện ${state.threats.length} mối nguy hại!`
        : 'Hoàn tất quét: Hệ thống của bạn hoàn toàn sạch và an toàn.';
    }
    if (scanProgressBar) scanProgressBar.style.width = '100%';

    addLog(`Hoàn tất quét: Đã kiểm tra ${state.filesScanned} tệp, tìm thấy ${state.threats.length} mối đe dọa.`);
    updateDashboardOverview();

    if (state.threats.length > 0) {
      showToast(`Cảnh báo: Đã phát hiện ${state.threats.length} tệp độc hại!`, 'danger');
      btnQuarantineAll.style.display = 'inline-flex';
    } else {
      showToast('Tuyệt vời! Không phát hiện mối đe dọa nào.', 'success');
    }
  }

  btnStartScan?.addEventListener('click', startScanning);

  btnPauseScan?.addEventListener('click', async () => {
    if (!state.isPaused) {
      await window.securityAPI.pauseScan();
      state.isPaused = true;
      btnPauseScan.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg> Tiếp Tục`;
      if (scanStageText) scanStageText.textContent = 'Đã tạm dừng tiến trình quét.';
      radarAnimation?.classList.remove('scanning');
    } else {
      await window.securityAPI.resumeScan();
      state.isPaused = false;
      btnPauseScan.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg> Tạm Dừng`;
      if (scanStageText) scanStageText.textContent = 'Đang phân tích cấu trúc tệp...';
      radarAnimation?.classList.add('scanning');
    }
  });

  btnStopScan?.addEventListener('click', async () => {
    await window.securityAPI.stopScan();
    showToast('Đã dừng quét theo yêu cầu của bạn.', 'info');
  });

  // Scanner Progress Event Listener
  window.securityAPI.onScanProgress((data) => {
    state.filesScanned = data.filesScanned;
    if (scanFilesCount) scanFilesCount.textContent = data.filesScanned;
    if (scanThreatCount) scanThreatCount.textContent = data.threatsFound;
    if (scanCurrentPath) scanCurrentPath.textContent = data.currentFile || '';

    // Update Dashboard metric
    const dashFiles = document.getElementById('dashFilesScanned');
    if (dashFiles) dashFiles.textContent = data.filesScanned;

    // Simulate animated bar pulse
    if (scanProgressBar && !data.completed) {
      const currentVal = parseInt(scanProgressBar.style.width || '0', 10);
      const nextVal = Math.min(95, currentVal + (data.filesScanned % 7 === 0 ? 1 : 0));
      scanProgressBar.style.width = `${nextVal}%`;
    }
  });

  // Scanner Threat Event Listener
  window.securityAPI.onScanThreat((threat) => {
    state.threats.push(threat);

    // Update radar blip
    const blip = document.querySelector('.radar-blip');
    if (blip) blip.classList.add('active');

    // Update badges
    const badge = document.getElementById('navThreatBadge');
    if (badge) {
      badge.style.display = 'inline-block';
      badge.textContent = state.threats.length;
    }
    const dashThreats = document.getElementById('dashThreatsFound');
    if (dashThreats) dashThreats.textContent = state.threats.length;

    renderThreatRow(threat);
    addLog(`Phát hiện mã độc: ${threat.threatName} tại ${threat.fileName}`, true);
  });

  function renderThreatRow(threat) {
    if (threatTableBody.querySelector('.empty-row')) {
      threatTableBody.innerHTML = '';
    }

    const tr = document.createElement('tr');
    tr.id = `threat-row-${state.threats.length}`;
    tr.innerHTML = `
      <td><span class="badge-danger">${threat.severity}</span></td>
      <td><strong>${threat.threatName}</strong><br><small style="color: #94a3b8;">${threat.description || ''}</small></td>
      <td><span class="badge-warning">${threat.threatType}</span></td>
      <td style="font-family: monospace; font-size: 11.5px; max-width: 250px; overflow: hidden; text-overflow: ellipsis;" title="${threat.filePath}">${threat.filePath}</td>
      <td>
        <button class="btn btn-sm btn-danger btn-quarantine" data-path="${encodeURIComponent(threat.filePath)}" data-info='${JSON.stringify({ name: threat.threatName, type: threat.threatType, severity: threat.severity })}'>
          Cách Ly Ngay
        </button>
      </td>
    `;
    threatTableBody.prepend(tr);

    tr.querySelector('.btn-quarantine').addEventListener('click', async (e) => {
      const targetBtn = e.currentTarget;
      const fPath = decodeURIComponent(targetBtn.getAttribute('data-path'));
      const tInfo = JSON.parse(targetBtn.getAttribute('data-info'));
      await isolateFile(fPath, tInfo, tr);
    });
  }

  async function isolateFile(fPath, tInfo, rowElement) {
    const res = await window.securityAPI.quarantineFile(fPath, tInfo);
    if (res.success) {
      showToast(`Đã cách ly an toàn: ${tInfo.name}`, 'success');
      rowElement?.remove();
      state.threats = state.threats.filter((t) => t.filePath !== fPath);
      updateDashboardOverview();
      loadQuarantine();
      if (state.threats.length === 0 && btnQuarantineAll) {
        btnQuarantineAll.style.display = 'none';
      }
    } else {
      showToast(`Không thể cách ly: ${res.error}`, 'danger');
    }
  }

  btnQuarantineAll?.addEventListener('click', async () => {
    const items = [...state.threats];
    for (const t of items) {
      await window.securityAPI.quarantineFile(t.filePath, {
        name: t.threatName,
        type: t.threatType,
        severity: t.severity
      });
    }
    state.threats = [];
    threatTableBody.innerHTML = '<tr class="empty-row"><td colspan="5">Tất cả mối đe dọa đã được đưa vào Khu Cách Ly an toàn!</td></tr>';
    btnQuarantineAll.style.display = 'none';
    showToast('Đã cách ly toàn bộ mối đe dọa thành công!', 'success');
    updateDashboardOverview();
    loadQuarantine();
  });

  // ==================== PROCESS MONITOR ====================
  const processTableBody = document.getElementById('processTableBody');
  const inputSearchProcess = document.getElementById('inputSearchProcess');

  async function loadProcesses() {
    processTableBody.innerHTML = '<tr><td colspan="7" class="loading-cell">Đang tải và đánh giá tiến trình hệ thống...</td></tr>';
    try {
      const procs = await window.securityAPI.getProcesses();
      state.processes = procs;
      renderProcesses(procs);
    } catch (e) {
      processTableBody.innerHTML = '<tr><td colspan="7" class="loading-cell text-danger">Không thể tải danh sách tiến trình.</td></tr>';
    }
  }

  function renderProcesses(list) {
    if (!list || list.length === 0) {
      processTableBody.innerHTML = '<tr class="empty-row"><td colspan="7">Không tìm thấy tiến trình nào phù hợp.</td></tr>';
      return;
    }

    processTableBody.innerHTML = '';
    list.slice(0, 100).forEach((proc) => {
      const tr = document.createElement('tr');

      let riskBadge = '<span class="badge-success">An Toàn</span>';
      if (proc.riskLevel === 'DANGEROUS') {
        riskBadge = '<span class="badge-danger">Nguy Hiểm</span>';
      } else if (proc.riskLevel === 'SUSPICIOUS') {
        riskBadge = '<span class="badge-warning">Nghi Ngờ</span>';
      }

      tr.innerHTML = `
        <td style="font-family: monospace;">${proc.pid}</td>
        <td><strong>${proc.name}</strong></td>
        <td>${riskBadge}<br><small style="color: #94a3b8; font-size: 11px;">${proc.riskReason}</small></td>
        <td>${proc.memoryMB || 0} MB</td>
        <td style="color: #94a3b8; font-size: 12px;">${proc.company || 'Không rõ'}</td>
        <td style="font-family: monospace; font-size: 11px; max-width: 220px; overflow: hidden; text-overflow: ellipsis;" title="${proc.path}">${proc.path}</td>
        <td>
          <button class="btn btn-sm btn-danger btn-kill-proc" data-pid="${proc.pid}" data-name="${proc.name}">Tắt</button>
        </td>
      `;

      tr.querySelector('.btn-kill-proc')?.addEventListener('click', async (e) => {
        const pid = e.currentTarget.getAttribute('data-pid');
        const name = e.currentTarget.getAttribute('data-name');
        if (confirm(`Bạn có chắc muốn cưỡng chế dừng tiến trình ${name} (PID: ${pid}) không?`)) {
          const res = await window.securityAPI.killProcess(pid);
          if (res.success) {
            showToast(`Đã tắt tiến trình ${name} (PID: ${pid})`, 'success');
            tr.remove();
          } else {
            showToast(`Lỗi khi tắt tiến trình: ${res.error}`, 'danger');
          }
        }
      });

      processTableBody.appendChild(tr);
    });
  }

  inputSearchProcess?.addEventListener('input', (e) => {
    const val = e.target.value.toLowerCase().trim();
    if (!val) {
      renderProcesses(state.processes);
      return;
    }
    const filtered = state.processes.filter(
      (p) =>
        (p.name && p.name.toLowerCase().includes(val)) ||
        (p.pid && p.pid.toString().includes(val)) ||
        (p.path && p.path.toLowerCase().includes(val))
    );
    renderProcesses(filtered);
  });

  document.getElementById('btnRefreshProcesses')?.addEventListener('click', loadProcesses);

  // ==================== SYSTEM CLEANER ====================
  const cleanerTotalMB = document.getElementById('cleanerTotalMB');
  const cleanerCategoriesList = document.getElementById('cleanerCategoriesList');
  const btnAnalyzeCleaner = document.getElementById('btnAnalyzeCleaner');
  const btnExecuteClean = document.getElementById('btnExecuteClean');
  const cleanResultCard = document.getElementById('cleanResultCard');

  async function analyzeCleaner() {
    if (cleanResultCard) cleanResultCard.style.display = 'none';
    if (btnAnalyzeCleaner) btnAnalyzeCleaner.disabled = true;

    try {
      const data = await window.securityAPI.analyzeJunk();
      state.cleanupData = data;

      if (cleanerTotalMB) cleanerTotalMB.textContent = data.totalMB;
      const dashJunk = document.getElementById('dashJunkSize');
      if (dashJunk) dashJunk.textContent = `${data.totalMB} MB`;

      renderCleanerCategories(data.items);
    } catch (e) {
      console.error(e);
    } finally {
      if (btnAnalyzeCleaner) btnAnalyzeCleaner.disabled = false;
    }
  }

  function renderCleanerCategories(items) {
    if (!cleanerCategoriesList) return;
    cleanerCategoriesList.innerHTML = '';

    items.forEach((item) => {
      const card = document.createElement('div');
      card.className = 'clean-cat-card';
      card.innerHTML = `
        <div class="clean-cat-header">
          <div>
            <div class="clean-cat-title">${item.name}</div>
            <div class="clean-cat-desc">${item.description}</div>
          </div>
          <span class="clean-cat-size">${item.sizeMB} MB</span>
        </div>
        <small style="color: #64748b; font-family: monospace; font-size: 11px;">${item.fileCount} tệp tin</small>
      `;
      cleanerCategoriesList.appendChild(card);
    });
  }

  async function executeClean() {
    if (btnExecuteClean) btnExecuteClean.disabled = true;
    showToast('Đang tiến hành dọn dẹp các tệp rác và làm trống thùng rác...', 'info');

    try {
      const res = await window.securityAPI.cleanJunk([]);
      if (res.success) {
        if (cleanResultCard) cleanResultCard.style.display = 'flex';
        const heading = document.getElementById('cleanResultHeading');
        const text = document.getElementById('cleanResultText');
        if (heading) heading.textContent = `Dọn dẹp thành công! Đã giải phóng ${res.freedMB} MB`;
        if (text) text.textContent = `Đã xóa ${res.deletedFiles} tệp rác và tệp tạm thời không còn sử dụng.`;

        showToast(`Tuyệt vời! Đã dọn dẹp thành công ${res.freedMB} MB!`, 'success');
        addLog(`Dọn dẹp hệ thống: Giải phóng ${res.freedMB} MB, xóa ${res.deletedFiles} tệp rác.`);
        analyzeCleaner();
      }
    } catch (e) {
      showToast(`Lỗi dọn rác: ${e.message}`, 'danger');
    } finally {
      if (btnExecuteClean) btnExecuteClean.disabled = false;
    }
  }

  btnAnalyzeCleaner?.addEventListener('click', analyzeCleaner);
  btnExecuteClean?.addEventListener('click', executeClean);

  // ==================== QUARANTINE VAULT ====================
  const quarantineTableBody = document.getElementById('quarantineTableBody');
  const btnRefreshQuarantine = document.getElementById('btnRefreshQuarantine');
  const btnClearAllQuarantine = document.getElementById('btnClearAllQuarantine');

  async function loadQuarantine() {
    try {
      const items = await window.securityAPI.getQuarantinedFiles();
      state.quarantinedCount = items.length;

      const badge = document.getElementById('navQuarantineBadge');
      if (badge) badge.textContent = items.length;
      const dashQuarantined = document.getElementById('dashQuarantined');
      if (dashQuarantined) dashQuarantined.textContent = items.length;

      renderQuarantine(items);
    } catch (e) {
      console.error(e);
    }
  }

  function renderQuarantine(items) {
    if (!items || items.length === 0) {
      quarantineTableBody.innerHTML = '<tr class="empty-row"><td colspan="6">Hiện không có tệp nào trong khu cách ly. Máy tính sạch sẽ!</td></tr>';
      return;
    }

    quarantineTableBody.innerHTML = '';
    items.forEach((item) => {
      const tr = document.createElement('tr');
      const dateStr = new Date(item.quarantinedAt).toLocaleString('vi-VN');

      tr.innerHTML = `
        <td><strong>${item.fileName}</strong></td>
        <td><span class="badge-danger">${item.threatName}</span></td>
        <td><span class="badge-warning">${item.severity}</span></td>
        <td style="font-family: monospace; font-size: 11px; max-width: 200px; overflow: hidden; text-overflow: ellipsis;" title="${item.originalPath}">${item.originalPath}</td>
        <td style="font-size: 12px; color: #94a3b8;">${dateStr}</td>
        <td>
          <button class="btn btn-sm btn-secondary btn-restore" data-id="${item.id}">Khôi Phục</button>
          <button class="btn btn-sm btn-danger btn-del-perm" data-id="${item.id}">Xóa Hẳn</button>
        </td>
      `;

      tr.querySelector('.btn-restore')?.addEventListener('click', async () => {
        if (confirm(`Bạn có chắc muốn khôi phục tệp ${item.fileName} về vị trí ban đầu không?`)) {
          const res = await window.securityAPI.restoreQuarantinedFile(item.id);
          if (res.success) {
            showToast(`Đã khôi phục tệp về: ${res.restoredPath}`, 'success');
            loadQuarantine();
          } else {
            showToast(`Lỗi khôi phục: ${res.error}`, 'danger');
          }
        }
      });

      tr.querySelector('.btn-del-perm')?.addEventListener('click', async () => {
        if (confirm(`Hành động này sẽ xóa vĩnh viễn tệp ${item.fileName}. Tiếp tục?`)) {
          const res = await window.securityAPI.deleteQuarantinedFile(item.id);
          if (res.success) {
            showToast(`Đã xóa vĩnh viễn tệp độc hại`, 'success');
            loadQuarantine();
          } else {
            showToast(`Lỗi xóa tệp: ${res.error}`, 'danger');
          }
        }
      });

      quarantineTableBody.appendChild(tr);
    });
  }

  btnRefreshQuarantine?.addEventListener('click', loadQuarantine);
  btnClearAllQuarantine?.addEventListener('click', async () => {
    if (confirm('Bạn có chắc muốn xóa sạch tất cả các tệp trong khu cách ly không?')) {
      await window.securityAPI.clearAllQuarantined();
      showToast('Đã xóa sạch các tệp trong khu cách ly.', 'info');
      loadQuarantine();
    }
  });

  // ==================== SHIELD & STARTUP ====================
  const startupTableBody = document.getElementById('startupTableBody');
  const btnRefreshStartup = document.getElementById('btnRefreshStartup');

  async function loadStartupShield() {
    startupTableBody.innerHTML = '<tr><td colspan="4" class="loading-cell">Đang kiểm tra các mục khởi động Windows...</td></tr>';
    try {
      const items = await window.securityAPI.getStartupItems();
      renderStartupItems(items);
    } catch (e) {
      startupTableBody.innerHTML = '<tr><td colspan="4" class="loading-cell text-danger">Không thể nạp dữ liệu khởi động.</td></tr>';
    }
  }

  function renderStartupItems(items) {
    if (!items || items.length === 0) {
      startupTableBody.innerHTML = '<tr class="empty-row"><td colspan="4">Không phát hiện mục khởi động nào trong hệ thống.</td></tr>';
      return;
    }

    startupTableBody.innerHTML = '';
    items.forEach((item) => {
      const tr = document.createElement('tr');
      const statusBadge = item.isSuspicious
        ? `<span class="badge-danger">Đáng Ngờ</span><br><small style="color: #f87171;">${item.reason}</small>`
        : `<span class="badge-success">Hợp Lệ</span>`;

      tr.innerHTML = `
        <td><strong>${item.name}</strong></td>
        <td>${statusBadge}</td>
        <td style="font-family: monospace; font-size: 11px; max-width: 320px; overflow: hidden; text-overflow: ellipsis;" title="${item.command}">${item.command}</td>
        <td style="color: #94a3b8; font-size: 11.5px;">${item.location}</td>
      `;
      startupTableBody.appendChild(tr);
    });
  }

  btnRefreshStartup?.addEventListener('click', loadStartupShield);

  // Initialize
  updateDashboardOverview();
  loadQuarantine();
  analyzeCleaner();
});
