# Windows Known Issues

> Living document for Windows-specific issues that are known but not yet fixed.
> Each entry should be self-contained: enough context for a future contributor
> (or future-you) to pick it up cold without re-doing the investigation.

---

## Issue 1: Pre-existing test failures T06 / T19 in `tests/test-windows.sh`

**Status**: Open. Pre-existing — present on `master` before the 2026-04-11 Windows fixes.
**Discovered**: 2026-04-11 while running the Windows smoke tests against the IPv6 / mtls / installer fixes.
**Severity**: Low (test-only; runtime behavior is correct on the affected line).

### Symptom

```
[T06] 进程替换 <(printf 已移除
  ❌ 进程替换残留:
/e/Users/.../src/cmd_check.sh:217:                read -r proxy_ip ip_tz < <(printf '%s' "$proxy_meta" | node -e "

[T19] env check read 兼容 set -e
  ❌ proxy metadata read 仍可能提前退出
```

Both failures point at the same line: `src/cmd_check.sh:217`.

### Root cause

Two test invariants the rest of the codebase has migrated away from, but this specific line still violates:

1. **T06** asserts that no `<(printf ...)` process substitution remains anywhere under `src/`. The intent is to keep the codebase compatible with shells / contexts where `<(...)` is not available or interacts badly with `set -euo pipefail` (notably some Git Bash edge cases). Line 217 still uses `read -r proxy_ip ip_tz < <(printf '%s' "$proxy_meta" | node -e "...")`.

2. **T19** asserts that the same `read -r proxy_ip ip_tz` call has a `|| true` suffix so that under `set -e` an empty/short read does not abort `cac env check`. The current line does not have `|| true`.

The two assertions overlap — fixing T06 by switching off process substitution will likely also let T19 pass naturally, depending on how the rewrite is structured.

### Likely origin

The recent commit `84c24a8 IP检测与Cert检测报错修复` rewrote the proxy metadata parsing in `cmd_check.sh` and reintroduced the process-substitution form, presumably without re-running `tests/test-windows.sh`. The test was added earlier to enforce a previous cleanup pass.

### Suggested fix

Rewrite line 217 to use a heredoc or temp variable instead of process substitution, and add `|| true` for `set -e` safety. Approximately:

```bash
_proxy_meta_parsed=$(printf '%s' "$proxy_meta" | node -e "...")
read -r proxy_ip ip_tz <<<"$_proxy_meta_parsed" || true
```

Then re-run `bash tests/test-windows.sh` and confirm 30 passed / 0 failed on Windows (Git Bash / MINGW64).

### Notes

- These failures are **not regressions** introduced by the 2026-04-11 Windows fixes. Verified by running `git stash && bash tests/test-windows.sh` against pristine `master` — same 28 pass / 2 fail.
- The runtime behavior on the affected line is **functionally correct** — `cac env check` does not crash. The test failures are about codebase invariants, not user-visible bugs.
- This issue should be bundled into a separate "test cleanup" PR rather than mixed with Windows-support work, to keep the diff scope clear.

---

## Issue 2: Relay `disown` lifecycle on Git Bash is unverified

**Status**: Open. P1 in `windows-support-assessment.md`.
**Severity**: Medium (potential silent failure of long-running relay sessions on Windows).

### Symptom

None observed yet — the issue is that we **don't know** whether it works. The relay watchdog is supposed to keep the local mTLS proxy alive across terminal sessions; on macOS/Linux it does, but Git Bash's `disown` semantics differ from native Bash and have never been validated end-to-end on Windows.

### Background

`src/cmd_relay.sh:24` and `src/templates.sh:441,486` all rely on:

```bash
node "$relay_js" "$port" "$proxy" "$pid_file" </dev/null >"$log" 2>&1 &
disown
```

…to spawn the relay (and the watchdog subshell) as background processes that survive the launching terminal. On native Linux Bash this is well-defined: `disown` removes the job from the shell's job table, so the parent shell exiting does not send SIGHUP. On **Git Bash / MSYS2** the implementation routes through MSYS's process emulation layer, and there are documented edge cases where:

- background processes still receive SIGHUP / get killed when the parent `mintty` window closes
- `disown` may silently no-op if the job has already finished its setup phase
- Process group ownership doesn't always survive the MSYS → native Windows boundary

There is no Windows-specific code path or fallback in the current implementation — it's the same `disown` line on every platform.

### Why this matters

The whole point of the watchdog is to make the relay process **a shared singleton** across Claude sessions. If closing the first terminal that spawned it kills the relay, then:

1. Other concurrent Claude sessions silently lose their proxy
2. They start trying to talk directly to the upstream, which (depending on TUN config) may either fail or **bypass the privacy layer entirely**

The latter is the dangerous failure mode — a silent privacy regression.

### How to test (manual, on real Windows)

There is no automated test for this because it requires a real Windows desktop session with the ability to close terminal windows and observe processes outliving them. Steps:

```bash
# Prerequisite: a working env with a real proxy
cac env create relay-probe -p http://your-proxy:port
cac relay-probe
cac relay on

# Trigger relay startup (any cac/claude command that activates the wrapper)
claude --version

# Capture the relay PID and port
RPID=$(cat ~/.cac/relay.pid)
RPORT=$(cat ~/.cac/relay.port)
WPID=$(cat ~/.cac/relay.watchdog.pid 2>/dev/null || echo "")
echo "relay=$RPID watchdog=$WPID port=$RPORT"

# Verify both are alive in the native Windows process table (NOT just kill -0)
tasklist.exe //FI "PID eq $RPID" //FO CSV //NH
tasklist.exe //FI "PID eq $WPID" //FO CSV //NH

# === Test 1: Survival across terminal close ===
# Close the *entire* mintty/terminal window (Alt+F4 or click X — NOT `exit`)
# Open a fresh Git Bash window. Run again:
tasklist.exe //FI "PID eq $RPID" //FO CSV //NH
tasklist.exe //FI "PID eq $WPID" //FO CSV //NH
# Expected (PASS): both processes still listed
# Observed (FAIL): "INFO: No tasks are running..." for one or both

# Also verify the port is still serving
node -e "require('net').connect($RPORT,'127.0.0.1',()=>{console.log('OK');process.exit(0)}).on('error',e=>{console.log('DEAD:'+e.message);process.exit(1)})"

# === Test 2: Watchdog auto-restart ===
# Kill the relay manually but leave the watchdog
taskkill.exe //F //PID $RPID
sleep 8  # watchdog polls every 5s
NEW_RPID=$(cat ~/.cac/relay.pid)
echo "old=$RPID new=$NEW_RPID"
# Expected (PASS): NEW_RPID differs from $RPID and points at a live process
tasklist.exe //FI "PID eq $NEW_RPID" //FO CSV //NH

# === Test 3: Concurrent session sees the same relay ===
# In terminal A:
echo "Terminal A relay: $(cat ~/.cac/relay.pid)"
# In a separate terminal B:
claude --version
echo "Terminal B relay: $(cat ~/.cac/relay.pid)"
# Expected: identical PID. Both sessions share one relay singleton.
```

### Possible fixes (in order of effort)

1. **Document the gap** — at minimum, add a warning to `docs/windows/` that closing the launching terminal may kill the relay until this is validated. Tell users to keep the original terminal open.

2. **Use `Start-Process` / `start /B`** — replace the bash `&; disown` pattern with a Windows-specific spawn path inside the `[[ "$os" == "windows" ]]` branch:
   ```bash
   if [[ "$os" == "windows" ]]; then
       cmd.exe //C "start /B node \"$(cygpath -w "$relay_js")\" $port $proxy ..." </dev/null >/dev/null 2>&1 &
   else
       node "$relay_js" "$port" "$proxy" "$pid_file" </dev/null >"$log" 2>&1 &
       disown
   fi
   ```
   `start /B` detaches the child from the console properly on Windows.

3. **PowerShell `Start-Process -WindowStyle Hidden`** — same idea, cleaner output and PID handling, but adds a PowerShell dependency to the relay path.

4. **Windows Service wrapper** — register the relay as a Windows Service via `nssm` or a native PowerShell `Register-ScheduledTask`. Survives reboots, no terminal coupling at all. Heaviest option, but production-grade.

### Acceptance criteria

This issue can be closed when:

- All three manual tests above pass on a fresh Windows 11 + Git for Windows install
- A documented test procedure is added under `docs/windows/` (or scripted into a manual checklist)
- The relay survives at minimum: terminal close, manual SIGTERM of the relay process (watchdog restart), and concurrent Claude sessions sharing the singleton

### Notes

- The `_relay_is_running()` check at `cmd_relay.sh:73` uses `kill -0 $pid` which works on Git Bash as long as the PID is in the same MSYS PID namespace. If we move to `start /B`, we may need to switch to `tasklist //FI "PID eq $pid"` for liveness checks.
- The watchdog itself uses `kill "$_rpid"` and `kill -0` extensively (`templates.sh:459-486`); any spawn-mechanism change needs to update those checks too.
- Windows Defender is known to occasionally flag long-lived `node.exe` background processes — worth checking that the relay isn't being killed by AV during the test, not by `disown`.
