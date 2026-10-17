---
name: systematic-debugging
description: >-
  Master systematic debugging workflows for software systems, Windows environments,
  PowerShell engines, Node/Electron IPC, and subprocesses. Use this skill when asked
  to diagnose bugs, investigate unexpected failures, trace crashes, fix test failures,
  or resolve mysterious errors.
---

# 🔬 Systematic Debugging & Diagnostics Skill

This skill guides the agent through a disciplined, scientific debugging process rather than guess-and-check ("shotgun debugging"). It is specialized for complex software environments, Windows native APIs, PowerShell script engines, and multi-process desktop applications (Electron/Node.js).

---

## 🎯 When to Activate This Skill
- When the user asks: *"Debug this issue"*, *"Tại sao test bị fail?"*, *"Sửa lỗi này giúp tôi"*, *"Investigate error"*, or *"Tìm nguyên nhân gây lỗi"*.
- When an automated test, build command, or runtime process crashes or returns unexpected output.
- When facing subtle platform-specific bugs (e.g., character encoding, file handle locks, deadlocks, zombie processes).

---

## 🧭 The 4-Phase Scientific Debugging Method

```
[1. Observe & Isolate] ──► [2. Formulate Hypothesis] ──► [3. Minimal Reproduction] ──► [4. Root-Cause Fix & Verify]
```

### Phase 1: Observation & Evidence Gathering
1. **Capture Raw Output**: Never rely on vague summaries. Read the complete stderr, exit code, and terminal logs.
2. **Identify State Drift**: Compare the last known working state (`git diff`, previous commit) with the failing state.
3. **Inspect the Environment**: Check OS differences (Windows vs POSIX), PowerShell version (5.1 Desktop vs 7+ Core), Node version, file encodings, and elevated rights (UAC).

### Phase 2: Hypothesis Formulation
1. **Single Variable Rule**: Identify the exact differential between success and failure. Formulate a specific hypothesis:
   * *“The script hangs because `Read-Host` expects interactive stdin while Node `child_process.spawn` runs without a TTY.”*
   * *“The test fails because the cancellation flag existed before the queue loop started, causing zero files to be processed.”*
2. **Avoid Premature Edits**: Do not modify production code until you can pinpoint the mechanism causing the failure.

### Phase 3: Minimal Isolated Reproduction
1. **Create a Scratch Probe**: Write a small, self-contained reproduction script in the `scratch/` directory or run a targeted one-liner.
2. **Instrument with Diagnostics**: Insert timestamps, variable dumps (`ConvertTo-Json`, `console.log`), and boundary assertions.
3. **Verify Hypothesis**: Confirm that the isolated script reproduces the exact same failure under identical inputs.

### Phase 4: Root-Cause Remediation & Regression Testing
1. **Fix the Cause, Not the Symptom**: Address the root architectural flaw rather than suppressing the exception with catch-all handlers.
2. **Verify Side Effects**: Check that the fix does not break related workflows or introduce performance regressions.
3. **Add Automated Regression Test**: Add a test case to the test suite (`tests/`) ensuring this specific bug can never silently regress.

---

## 🛠️ Specialized Diagnostic Runbooks

### Runbook A: Windows PowerShell 5.1 Encoding & Syntax Traps
- **Symptom**: PowerShell 5.1 throws `Token unrecognized` or garbled Vietnamese text even when the file looks normal in modern editors.
- **Root Cause**: PowerShell 5.1 requires a **UTF-8 Byte Order Mark (BOM: `\uFEFF`)** to parse non-ASCII Unicode characters properly. Without BOM, it defaults to Windows ANSI (Windows-1252/CodePage 437).
- **Diagnosis**:
  ```javascript
  const buf = fs.readFileSync('script.ps1');
  console.log('BOM:', buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf);
  ```
- **Remedy**: Always prepend `Buffer.from([0xef, 0xbb, 0xbf])` if the BOM is missing.

### Runbook B: File Handle Locking (`SharingViolationException`)
- **Symptom**: `Move-Item`, `Remove-Item`, or `Set-Content` fails with *"The process cannot access the file because it is being used by another process"*.
- **Root Cause**: A previous `[System.IO.File]::OpenRead` or `Get-Content` did not release the unmanaged handle when an error occurred.
- **Diagnosis**:
  ```powershell
  # Check if stream disposal was inside try block instead of finally
  try { $stream = [System.IO.File]::OpenRead($path) ... }
  finally { if ($null -ne $stream) { $stream.Dispose() } }
  ```
- **Remedy**: Always open streams with `[System.IO.FileShare]::ReadWrite` and place `.Dispose()` inside a `finally` block.

### Runbook C: Subprocess Deadlocks & Non-Blocking IPC
- **Symptom**: Child process hangs indefinitely when spawned from Node.js / Electron.
- **Root Cause**: Standard error/stdout buffer overflow (Node OS buffer size ~64KB), or child process waiting on interactive stdin prompt.
- **Remedy**:
  - Always pass `-NonInteractive` flags to CLI tools and scripts.
  - Listen to `data` events on both `stdout` and `stderr` streams concurrently.
  - Avoid shell string interpolation for argument passing; use direct binary execution with argument vectors:
    ```javascript
    spawn('taskkill.exe', ['/F', '/PID', String(pid)], { windowsHide: true });
    ```

### Runbook D: Cooperative Cancellation Latch Traps
- **Symptom**: Cancellation flag is set, but the process either ignores it or exits with "Completed" instead of "Cancelled".
- **Root Cause**: If the scan queue breaks before entering the processing loop, loop-internal cancellation flags never update the state variable `$wasCancelled`.
- **Remedy**: Always check `if (Test-Path $CancelFlagPath) { $wasCancelled = $true }` both inside the iteration loops AND immediately before constructing the final response payload.
