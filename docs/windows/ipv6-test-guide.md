# Windows IPv6 Detection — Test Guide

> 本文档说明如何验证 `cac env check` 中 IPv6 泄漏检测修复在 Windows 上的正确性。
> 同时覆盖 Git Bash、PowerShell、CMD 三种运行环境。

---

## 背景

2026-04-11 之前, `src/cmd_check.sh` 在 Windows 上通过以下方式检测 IPv6 泄漏:

```bash
ipconfig.exe | grep -ci "IPv6 Address"
```

此方式在**非英文 Windows** 上静默失败:

| 系统语言 | `ipconfig` 标签 |
|:---|:---|
| English | `IPv6 Address` |
| 简体中文 | `IPv6 地址` |
| 繁體中文 | `IPv6 位址` |
| 日本語 | `IPv6 アドレス` |
| 한국어 | `IPv6 주소` |

旧版 grep 在非英文系统上会返回 `0`, 导致 `cac env check` 显示绿色 **✓ IPv6 no global address** — 即使主机存在真实的公网 IPv6。对一个隐私工具而言, 这是**静默的隐私误报**。

修复方案改为直接匹配 IPv6 地址**模式**:

```bash
ipconfig.exe | grep -cE '[[:space:]][23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

匹配 IPv6 全球单播地址 (2000::/3 前缀), 与 `ipconfig` 输出语言无关。

---

## 关于 Windows 上的 `grep`

**使用 cac 不需要在 CMD 或 PowerShell 中安装 grep。** cac 的入口 (`cac.cmd`) 会自动委托给 Git Bash, 所有内部逻辑 — 包括 IPv6 检测 — 都运行在 Git Bash 子进程中。`grep`, `awk`, `sed` 等 Unix 工具随 Git for Windows 一起安装, 对 cac 命令自动可用。

**grep 有影响的场景**: 手动运行以下测试命令时。如果你不想打开 Git Bash, 本文档为每个测试提供了 PowerShell 和 CMD 的等效命令。

---

## Test 1 — 正向检测 (必须匹配)

**目标**: 验证修复后能在非英文 Windows 上检测到 IPv6 泄漏。

### Git Bash

```bash
echo "   IPv6 地址 . . . . . . . : 2409:8a55:1234:5678::abcd" \
  | grep -cE '[[:space:]][23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

**期望输出**: `1`

### PowerShell

```powershell
"   IPv6 地址 . . . . . . . : 2409:8a55:1234:5678::abcd" -match '\s[23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

**期望输出**: `True`

### CMD

```cmd
echo    IPv6 地址 . . . . . . . : 2409:8a55:1234:5678::abcd | findstr /R "[23][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]:"
```

**期望**: 回显匹配行 (exit code 0)。`findstr` 的正则比 `grep` 弱, 没有 `{3}` 量词, 需手动展开。

---

## Test 2 — 链路本地地址不应误报

**目标**: 验证 `fe80::` 链路本地地址**不会**被标记为泄漏。

### Git Bash

```bash
echo "   fe80::1%14" | grep -cE '[[:space:]][23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

**期望**: `0`

### PowerShell

```powershell
"   fe80::1%14" -match '\s[23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

**期望**: `False`

---

## Test 3 — DHCP 时间字符串不应误报

**目标**: 验证 `23:30:00` 这样的时间字符串**不会**被误判为 IPv6 地址。正则要求第一组恰好 4 个十六进制字符 (`{3}` after the first), 将 `2409:...` (IPv6) 与 `23:30:00` (时间) 区分开。

### Git Bash

```bash
echo "   Lease Obtained. . . . : Friday, April 11, 2026 23:30:00" \
  | grep -cE '[[:space:]][23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

**期望**: `0`

### PowerShell

```powershell
"   Lease Obtained. . . . : Friday, April 11, 2026 23:30:00" -match '\s[23][0-9a-fA-F]{3}:[0-9a-fA-F:]+'
```

**期望**: `False`

---

## Test 4 — 旧版 Bug 复现

**目标**: 证明旧版检测逻辑在非英文 Windows 上静默失效。

### Git Bash

```bash
echo "   IPv6 地址 . . . . . . . : 2409:8a55:1234:5678::abcd" | grep -ci "IPv6 Address"
```

**期望**: `0` — 输入里有真实 IPv6 地址, 但 grep 找的是英文标签 `IPv6 Address`, 所以返回 `0`。旧版 `cac env check` 会据此显示 "no global address", 这就是 bug 所在。

### PowerShell

```powershell
"   IPv6 地址 . . . . . . . : 2409:8a55:1234:5678::abcd" -match 'IPv6 Address'
```

**期望**: `False`

---

## Test 5 — 端到端 (Mock ipconfig.exe)

**目标**: 验证完整链路 `cac env check` → `ipconfig.exe` → grep, 即使用户没有真实 IPv6 也能测试。

### 前置条件

- cac 已安装, 且至少创建了一个环境 (`cac env create test`)
- 在 Git Bash 中运行

### 步骤

```bash
# 1. 创建一个假的 ipconfig.exe, 输出中文 Windows + 真实 IPv6
mkdir -p /tmp/cac-ipv6-test
cat > /tmp/cac-ipv6-test/ipconfig.exe <<'EOF'
#!/usr/bin/env bash
echo "Windows IP 配置"
echo ""
echo "以太网适配器 以太网:"
echo ""
echo "   连接特定的 DNS 后缀 . . . . . . . : local"
echo "   IPv6 地址 . . . . . . . . . . . . : 2409:8a55:1234:5678::abcd"
echo "   本地链接 IPv6 地址. . . . . . . . : fe80::1%14"
echo "   IPv4 地址 . . . . . . . . . . . . : 192.168.1.100"
echo "   子网掩码  . . . . . . . . . . . . : 255.255.255.0"
echo "   默认网关. . . . . . . . . . . . . : 192.168.1.1"
EOF
chmod +x /tmp/cac-ipv6-test/ipconfig.exe

# 2. 把假的 ipconfig 加到 PATH 最前面, 然后跑 cac env check
PATH="/tmp/cac-ipv6-test:$PATH" cac env check 2>&1 | grep -A0 IPv6

# 3. 清理
rm -rf /tmp/cac-ipv6-test
```

### 期望输出

```
    ⚠ IPv6       global address detected (potential leak)
```

### 失败排查

| 现象 | 原因 |
|:---|:---|
| ✓ IPv6 no global address | 修复没有生效。确认 `bash build.sh` 已运行, 且 `which cac` 指向重建后的版本 |
| ipconfig.exe: command not found | `$PATH` 修改在 cac env check 执行前被丢弃。确保整行作为一条命令运行 |
| 没有 IPv6 行 | `cac env check` 可能在更早的阶段就中止了。运行 `cac env check -d` 查看详细输出 |

---

## Test 6 — 真实环境 (如果你确实有 IPv6)

最简单的测试: 如果你的 ISP 给了公网 IPv6, 直接运行:

```bash
cac env check
```

在隐私检查段落中找 **IPv6** 行:

- **修复前** (旧版 build): 显示 ✓ no global address — 如果你真有 IPv6, 这是错的
- **修复后** (新版 build): 显示 ⚠ global address detected — 正确告警

确认你是否真有公网 IPv6:

```bash
# Git Bash
ipconfig.exe | grep -E '[23][0-9a-fA-F]{3}:'
```

```powershell
# PowerShell
Get-NetIPAddress -AddressFamily IPv6 | Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -match '^[23]' }
```

有输出说明你有公网 IPv6, Test 6 适用。

---

## 回归测试清单

未来修改 `src/cmd_check.sh` IPv6 相关代码时, 确保以下全部通过:

- [ ] Test 1 (中文标签 + 真实 IPv6) 返回匹配
- [ ] Test 2 (链路本地 `fe80::`) **不**返回匹配
- [ ] Test 3 (时间字符串 `23:30:00`) **不**返回匹配
- [ ] Test 5 (Mock 端到端) 渲染 ⚠ 警告
- [ ] 替换为日文 / 韩文 / 繁体中文标签后同样通过
