# PowerShell Execution Policy blocks profile loading

**Status**: Open
**Severity**: High — breaks native PowerShell startup
**Discovered**: 2026-04-19
**Platform**: Windows

## Symptom

When the user opens a native PowerShell terminal (not Git Bash), the following error appears on every launch:

```
. : 无法加载文件 C:\Users\<user>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1，
因为在此系统上禁止运行脚本。
有关详细信息，请参阅 https:/go.microsoft.com/fwlink/?LinkID=135170 中的 about_Execution_Policies。
所在位置 行:1 字符: 3
+ . 'C:\Users\<user>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
+   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : SecurityError: (:) []，PSSecurityException
    + FullyQualifiedErrorId : UnauthorizedAccess
```

## Root Cause

This branch (`feat/session-scoped-activation`) injects a `function cac { ... }` block into the user's PowerShell profile (`$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`).

Windows ships with the default PowerShell execution policy set to `Restricted`, which blocks all `.ps1` scripts from running — including the user's own profile. The profile injection code does **not** check or set the execution policy before writing, so on machines that have never changed this policy, the entire PowerShell profile fails to load.

This not only makes `cac` unavailable in PowerShell, but also prevents **any other** profile customizations the user may have from loading.

## Reproduction

1. On a Windows machine where `Get-ExecutionPolicy` returns `Restricted` (factory default)
2. Run `cac setup` or any command that triggers profile injection
3. Open a new PowerShell window
4. Observe the `PSSecurityException` error and broken profile

## Expected Behavior

One of:
- **Option A**: Before injecting into the PowerShell profile, check `Get-ExecutionPolicy` and warn the user or auto-set it to `RemoteSigned` (with consent)
- **Option B**: Skip PowerShell profile injection entirely and rely on PATH-based `cac.cmd` / `cac.ps1` shims (which already work without profile changes)
- **Option C**: Document the `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` prerequisite in setup output

## Workaround

Users can manually fix this by running in an elevated PowerShell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Impact Assessment

- Affects all Windows users who have never changed their execution policy (the vast majority)
- Breaks PowerShell startup globally, not just cac functionality
- No issue on macOS/Linux (no execution policy concept)
