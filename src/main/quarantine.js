const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class QuarantineManager {
  constructor(storageDir) {
    this.storageDir = storageDir || path.join(process.cwd(), 'quarantine_storage');
    this.manifestPath = path.join(this.storageDir, 'quarantine_manifest.json');
    this.xorKey = 0x5A; // Simple byte-mask to neutralize executables safely
    this.ensureStorage();
  }

  ensureStorage() {
    if (!fs.existsSync(this.storageDir)) {
      fs.mkdirSync(this.storageDir, { recursive: true });
    }
    if (!fs.existsSync(this.manifestPath)) {
      fs.writeFileSync(this.manifestPath, JSON.stringify([], null, 2), 'utf-8');
    }
  }

  getManifest() {
    try {
      this.ensureStorage();
      const data = fs.readFileSync(this.manifestPath, 'utf-8');
      return JSON.parse(data);
    } catch (err) {
      console.error('Error reading quarantine manifest:', err);
      return [];
    }
  }

  saveManifest(items) {
    try {
      fs.writeFileSync(this.manifestPath, JSON.stringify(items, null, 2), 'utf-8');
    } catch (err) {
      console.error('Error saving quarantine manifest:', err);
    }
  }

  // XOR buffer to render executable non-functional while in storage
  maskBuffer(buffer) {
    const masked = Buffer.alloc(buffer.length);
    for (let i = 0; i < buffer.length; i++) {
      masked[i] = buffer[i] ^ this.xorKey;
    }
    return masked;
  }

  async quarantineFile(filePath, threatInfo = {}) {
    try {
      if (!fs.existsSync(filePath)) {
        return { success: false, error: 'Tệp không tồn tại.' };
      }

      const id = 'Q_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7);
      const stat = fs.statSync(filePath);
      const originalName = path.basename(filePath);
      const targetQuarantineFile = path.join(this.storageDir, `${id}.quarantined`);

      // Read, mask and write
      const originalBuffer = fs.readFileSync(filePath);
      const maskedBuffer = this.maskBuffer(originalBuffer);
      fs.writeFileSync(targetQuarantineFile, maskedBuffer);

      // Try removing original file
      try {
        fs.unlinkSync(filePath);
      } catch (unlinkErr) {
        // If locked, attempt to overwrite with empty first
        try {
          fs.writeFileSync(filePath, Buffer.alloc(0));
          fs.unlinkSync(filePath);
        } catch (e) {
          // If still locked, file might be in use
          return {
            success: false,
            error: `Tệp đang bị khóa hoặc được sử dụng bởi tiến trình khác: ${unlinkErr.message}`
          };
        }
      }

      const entry = {
        id,
        fileName: originalName,
        originalPath: filePath,
        fileSize: stat.size,
        threatName: threatInfo.name || 'Phần mềm độc hại chưa rõ',
        threatType: threatInfo.type || 'Malware.General',
        severity: threatInfo.severity || 'High',
        quarantinedAt: new Date().toISOString(),
        storedFileName: `${id}.quarantined`
      };

      const manifest = this.getManifest();
      manifest.unshift(entry);
      this.saveManifest(manifest);

      return { success: true, entry };
    } catch (err) {
      console.error('Quarantine error:', err);
      return { success: false, error: err.message };
    }
  }

  async restoreFile(id, customRestoreDir = null) {
    try {
      const manifest = this.getManifest();
      const index = manifest.findIndex((item) => item.id === id);
      if (index === -1) {
        return { success: false, error: 'Không tìm thấy mục cách ly.' };
      }

      const item = manifest[index];
      const quarantinedFilePath = path.join(this.storageDir, item.storedFileName);
      if (!fs.existsSync(quarantinedFilePath)) {
        return { success: false, error: 'Tệp lưu trữ cách ly đã bị mất.' };
      }

      let restorePath = item.originalPath;
      if (customRestoreDir) {
        restorePath = path.join(customRestoreDir, item.fileName);
      }

      const targetDir = path.dirname(restorePath);
      if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
      }

      // Read, unmask and write back
      const maskedBuffer = fs.readFileSync(quarantinedFilePath);
      const restoredBuffer = this.maskBuffer(maskedBuffer);
      fs.writeFileSync(restorePath, restoredBuffer);

      // Remove from quarantine storage
      fs.unlinkSync(quarantinedFilePath);

      // Update manifest
      manifest.splice(index, 1);
      this.saveManifest(manifest);

      return { success: true, restoredPath: restorePath };
    } catch (err) {
      console.error('Restore error:', err);
      return { success: false, error: err.message };
    }
  }

  async deletePermanently(id) {
    try {
      const manifest = this.getManifest();
      const index = manifest.findIndex((item) => item.id === id);
      if (index === -1) {
        return { success: false, error: 'Không tìm thấy mục trong danh sách cách ly.' };
      }

      const item = manifest[index];
      const quarantinedFilePath = path.join(this.storageDir, item.storedFileName);
      if (fs.existsSync(quarantinedFilePath)) {
        // Overwrite before deleting (secure wipe)
        try {
          const zeroBuffer = Buffer.alloc(Math.min(item.fileSize || 1024, 65536));
          fs.writeFileSync(quarantinedFilePath, zeroBuffer);
        } catch (e) {
          // ignore wipe error
        }
        fs.unlinkSync(quarantinedFilePath);
      }

      manifest.splice(index, 1);
      this.saveManifest(manifest);

      return { success: true };
    } catch (err) {
      console.error('Delete permanently error:', err);
      return { success: false, error: err.message };
    }
  }

  clearAll() {
    try {
      const manifest = this.getManifest();
      for (const item of manifest) {
        const filePath = path.join(this.storageDir, item.storedFileName);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      }
      this.saveManifest([]);
      return { success: true, count: manifest.length };
    } catch (err) {
      return { success: false, error: err.message };
    }
  }
}

module.exports = QuarantineManager;
