# Windows Support Assessment Report

> **Date**: 2026-04-10 (updated)
> **Branch**: master
> **Overall Completion**: ~95%

---

## 1. Overview

This document provides a comprehensive assessment of the current Windows support status for the `cac-win` project. It covers what has been implemented, what gaps remain, and actionable recommendations for reaching full production-ready Windows support.

---

## 2. Current Windows Support Status

### 2.1 Completed Items

| Capability | Implementation Details |
|:--|:--|
| **Entry Points / Launchers** | `cac.cmd` (CMD), `cac.ps1` (PowerShell), and `cac` (Git Bash) are all implemented. They auto-locate Git Bash and delegate to the main Bash script. |
| **Git Bash Pre-flight Check** | Both `cac.cmd` and `cac.ps1` search multiple standard Git installation paths and provide a clear error message (exit code 9009) if Git Bash is not found. |
| **Installation Script** | `scripts/install-local-win.ps1` generates shims in the npm global bin directory (dynamically detected via `npm config get prefix`) and auto-adds to user PATH. Supports `-Uninstall` for cleanup. |
| **Platform Detection** | `_detect_os()` recognizes `MINGW*/MSYS*/CYGWIN*` → `"windows"`; `_detect_platform()` maps to `win32-x64` / `win32-arm64`. |
| **Path Conversion** | `_native_path()` uses `cygpath -w` to convert Unix-style paths to Windows native paths. |
| **Binary Identification** | `_version_binary()` automatically uses `claude.exe` on Windows. |
| **UUID / Machine ID Generation** | Triple fallback: `uuidgen` → `/proc/sys/kernel/random/uuid` → Node.js `crypto.randomUUID()`. |
| **Claude Wrapper (`claude.cmd`)** | `_write_wrapper()` in `templates.sh` generates an additional `claude.cmd` on Windows that delegates to the Git Bash wrapper. |
| **Windows Fingerprint Interception** | `fingerprint-hook.js` intercepts `wmic csproduct get uuid` and `reg query...MachineGuid` across `execSync`, `exec`, and `execFileSync`. Also covers `os.hostname()`, `os.networkInterfaces()`, `os.userInfo()`. |
| **Process Counting** | `_count_claude_processes()` uses `tasklist.exe //FO CSV` on Windows. |
| **IPv6 Detection** | `cmd_check.sh` uses `ipconfig.exe` for IPv6 address detection. |
| **TUN Conflict Detection** | Scans `ipconfig.exe` output for TAP/TUN/Wintun/WireGuard/VPN keywords. |
| **User PATH Management** | `_add_to_user_path()` writes to user-level PATH via PowerShell registry operations. |
| **Clone Mode Compatibility** | Automatically forces `copy` instead of `symlink` on Windows (NTFS symlinks require admin privileges). |
| **`package.json` Declaration** | `"os": ["darwin", "linux", "win32"]` includes win32; `"files"` array includes `cac.ps1` and `cac.cmd`. |
| **Relay Process Management** | `disown` calls use `2>/dev/null \|\| true` fallback for Git Bash edge cases. |
| **Docker Mode Guard** | `cmd_docker()` detects Windows and exits early with a clear message directing users to WSL2 or `cac env`. |
| **postinstall.js Compatibility** | Uses `path.join()`/`path.resolve()` throughout, handles Windows line endings, properly detects `win32` platform. |

### 2.2 Scoring Summary

| Dimension | Score | Notes |
|:--|:--|:--|
| Core Functionality | ★★★★★ | Env create, version management, proxy routing, privacy check all work via Git Bash |
| Fingerprint Spoofing | ★★★★★ | Node.js layer `fingerprint-hook.js` fully covers Windows `wmic`/`reg` interception |
| Installation Experience | ★★★★★ | Dedicated PowerShell installer with dynamic npm path detection and auto PATH handling |
| Native Integration | ★★★ | Still a "Git Bash on Windows" model, not a native Windows application |
| Stability / Production-readiness | ★★★★ | Relay `disown` has fallback handling; Docker mode properly guarded |

---

## 3. Design Decisions & Resolved Issues

### 3.1 Git Bash Pre-flight Check — RESOLVED

Both `cac.cmd` and `cac.ps1` include comprehensive Git Bash detection that searches:
- `%ProgramFiles%\Git\bin\bash.exe`
- `%ProgramW6432%\Git\bin\bash.exe`
- `%LocalAppData%\Programs\Git\bin\bash.exe` / `%LocalAppData%\Git\bin\bash.exe`
- PATH-based discovery via `git.exe` parent directory
- Direct `bash.exe` in PATH (excluding Windows Store App versions)

If not found, a clear error message is shown with exit code 9009.

---

### 3.2 Shell Shims on Windows — BY DESIGN

The `shim-bin/` Unix command shims (`ioreg`, `ifconfig`, `hostname`, `cat`) are intentionally skipped on Windows (`cmd_setup.sh` checks `$os != "windows"`). This is by design because:

- Claude Code is a Node.js application — all fingerprint reads go through Node.js APIs
- `fingerprint-hook.js` intercepts at the Node.js layer: `child_process.execSync/exec/execFileSync` for `wmic` and `reg query`, plus `os.hostname()`, `os.networkInterfaces()`, `os.userInfo()`
- Shell shims are a defense-in-depth layer for macOS/Linux where subprocess calls might bypass Node.js; this scenario does not apply on Windows

---

### 3.3 Relay `disown` Stability — RESOLVED

All three `disown` call sites now use `disown 2>/dev/null || true`:
- `src/cmd_relay.sh` — relay process startup
- `src/templates.sh` — wrapper relay startup
- `src/templates.sh` — watchdog process

Git Bash (MSYS2) supports `disown` as a bash built-in, but edge cases exist when invoked indirectly through CMD/PowerShell. The `|| true` fallback ensures the flow is never interrupted. Background processes are started with `&` regardless, and `disown` is only an additional protection against SIGHUP on terminal close.

---

### 3.4 Docker Mode on Windows — RESOLVED

`cmd_docker()` now detects Windows at entry and exits early:

```
error: 'cac docker' requires native Linux (sing-box TUN isolation)
  Windows users: use WSL2 with Docker Desktop, or use 'cac env' directly
```

Docker container mode (sing-box TUN network isolation) requires native Linux. Windows users should use `cac env` for environment management, or run `cac` inside WSL2 if Docker-based isolation is needed.

---

### 3.5 npm Global Install Path — RESOLVED

`scripts/install-local-win.ps1` now dynamically detects the npm global bin directory using `npm config get prefix`, with a fallback to `%APPDATA%\npm` for standard installations. This ensures compatibility with `nvm-windows`, `fnm`, `volta`, and other Node.js version managers.

---

### 3.6 `postinstall.js` Windows Compatibility — VERIFIED

Audit confirmed the script is fully Windows-compatible:
- Uses `path.join()`, `path.resolve()`, `path.normalize()` consistently
- Handles both `HOME` and `USERPROFILE` environment variables
- Splits on `\r?\n` for Windows line endings
- Filters Windows Store App paths with backslash checking
- `fs.chmodSync()` failures are caught in try-catch (no-op on Windows)

---

## 4. Remaining Considerations

| Area | Status | Notes |
|:--|:--|:--|
| **Native PowerShell entry point** | Future | Eliminating Git Bash dependency entirely would broaden Windows accessibility, but is a large effort and low priority given that developer users typically have Git installed |
| **Windows CI testing** | Recommended | Adding a Windows runner to CI would catch regressions automatically |
| **Windows Defender compatibility** | Monitor | `fingerprint-hook.js` and `NODE_OPTIONS --require` injection may trigger security software alerts in some enterprise environments |

---

## 5. Conclusion

The project has achieved **approximately 95% Windows support completion**. All identified issues from the original assessment have been resolved:

- **Git Bash pre-flight check**: already implemented with comprehensive search and clear error messages
- **Shell shims**: intentionally skipped on Windows by design, with Node.js layer providing equivalent coverage
- **Relay `disown` stability**: added fallback handling for Git Bash edge cases
- **Docker mode**: properly guarded with early exit and user guidance
- **npm path detection**: now uses dynamic resolution via `npm config get prefix`
- **postinstall.js**: verified fully compatible with Windows path handling

The critical path — installation → environment creation → fingerprint spoofing → launching Claude Code → privacy verification — is fully functional on Windows. The main architectural constraint remains the Git Bash runtime dependency, which is acceptable for the developer-oriented user base.
