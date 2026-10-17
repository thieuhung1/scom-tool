---
name: code-review
description: >-
  Expert multi-axis code reviewer and security auditor. Use this skill when asked
  to review code, inspect pull requests, perform security audits, find edge-case bugs,
  evaluate architectural soundness, or prepare a formal rebuttal for a senior code review.
---

# 🛡️ Expert Multi-Axis Code Review & Security Audit Skill

This skill guides the agent in conducting thorough, adversarial, and constructive senior-level code reviews across five primary dimensions: **Security**, **Resource Management & Concurrency**, **Correctness & Edge Cases**, **Resilience & Error Handling**, and **Architecture & Maintainability**.

---

## 🎯 When to Activate This Skill
- When the user asks: *"Review my code"*, *"Audit this PR"*, *"Find potential vulnerabilities/bugs"*, *"Kiểm tra mã nguồn"*, or *"Review bảo mật"*.
- When evaluating a pull request or uncommitted diff before merging.
- When drafting an evidence-grounded response or rebuttal to an existing audit report.

---

## 🔍 The 5 Review Axes

### 1. Security Vulnerabilities (Zero-Trust Assessment)
- **Command & Script Injection**: Check if external or renderer inputs are interpolated into shells (`bash`, `sh`, `cmd.exe`, `powershell.exe -Command`). Demand parameter arrays or native process execution (`spawn('prog', [args])`).
- **Path Traversal & File Access**: Verify all file paths are validated against `..`, rooted, and canonicalized (`Path.resolve` / `[System.IO.Path]::GetFullPath`).
- **IPC & Boundary Isolation**: In Electron / Tauri / WebView apps, ensure `contextIsolation: true`, `sandbox: true`, and `nodeIntegration: false`. Preload scripts must expose only minimal, strictly validated APIs.
- **Privilege & Access Control**: Check if elevated operations (UAC, root, admin) enforce safe permissions and strict ACLs on created files and directories.
- **Secrets & Credentials**: Ensure no hardcoded tokens, private keys, or credentials exist in the codebase.

### 2. Resource Management & Concurrency
- **Handle & Stream Leaks**: Every file stream, socket, database connection, or process handle must be disposed in a `finally` block or equivalent context manager (`using` / `try...finally`).
- **Unbounded Operations**: Look for recursive directory scans or collections without depth limits, pagination, or maximum element caps.
- **Memory Consumption**: Ensure large files are streamed in chunks rather than read entirely into RAM via single-shot reads.
- **Process Lifecycle**: Subprocesses spawned in background tasks must have proper termination handlers on parent exit or cancellation.

### 3. Correctness & Edge Cases
- **Encoding & Character Sets**: On Windows, PowerShell scripts with non-ASCII characters must have UTF-8 BOM (`\uFEFF`) to prevent syntax errors in PS 5.1.
- **Boundary Conditions**: Test empty strings, zero, negative numbers, maximum integers, null/undefined, and special characters (`"`, `'`, `$`, `%`, `&`, `(`, `)`).
- **Filesystem Nuances**: Check case-insensitivity on Windows/macOS vs case-sensitivity on Linux, path separators (`\` vs `/`), and path lengths exceeding MAX_PATH (260 chars).
- **Symbolic Links & Junctions**: Recursive walkers must check `ReparsePoint` / symlink attributes to prevent infinite circular traversal.

### 4. Resilience & Error Handling
- **No Silent Failures**: Avoid empty `catch {}` blocks or `-ErrorAction SilentlyContinue` on critical operations without logging or handling.
- **Cooperative Cancellation**: Long-running loops must periodically inspect a cancellation token or flag and terminate cleanly.
- **Graceful Degradation**: If an optional subsystem fails (e.g., fetching remote signatures), the core engine must continue operating safely with clear user warnings.

### 5. Architecture & Clean Code
- **Separation of Concerns**: Keep UI/Renderer, IPC Gateway, and Core Business/Engine layers decoupled.
- **Dead Code & Redundancy**: Identify duplicate entry points, unused helper scripts, or contradictory configuration definitions.
- **Testing Coverage**: Critical security boundaries and heuristic detectors must be backed by automated regression tests.

---

## 📋 Standard Review Output Format

When delivering a code review report, format findings hierarchically using standard severity categories:

```markdown
# 🛡️ Code Review Report: [Component / PR Name]

## 🚨 Blocker (Must fix before merge)
*Issues causing security compromise, crash, data loss, deadlock, or resource leaks.*
- **[Finding Name]**: Description, exact file and line reference, security/system impact, and concrete fix code.

## ⚠️ High (Should fix)
*Issues causing significant performance degradation, false positives, or missing critical safeguards.*
- **[Finding Name]**: Description, impact, and proposed resolution.

## 🔍 Medium (Improvement recommended)
*Edge-case vulnerabilities, brittle patterns, incomplete heuristic coverage, or missing test cases.*
- **[Finding Name]**: Description and recommended change.

## 💡 Low / Nit (Cosmetic & Maintainability)
*Code style, documentation, naming consistency, localization, or unused artifacts.*
- **[Finding Name]**: Minor notes.

---

## 🛠️ Recommended Action Plan
1. Immediate blocker fixes.
2. High-priority hardening.
3. Verification test execution.
```
