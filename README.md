<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/logo-light.svg">
  <img alt="cac" src="docs/images/logo-light.svg" width="200">
</picture>

**Claude Code 小雨衣** — Isolate, protect, and manage your Claude Code.

*Run Claude Code your way — isolated, protected, managed.*

**[中文](#中文) | [English](#english) | [:book: Docs](https://cac.nextmind.space/docs)**

[![npm version](https://img.shields.io/npm/v/claude-cac.svg)](https://www.npmjs.com/package/claude-cac)
[![GitHub stars](https://img.shields.io/github/stars/nmhjklnm/cac?style=social)](https://github.com/nmhjklnm/cac)
[![Docs](https://img.shields.io/badge/Docs-cac.nextmind.space-D97706.svg)](https://cac.nextmind.space/docs)
[![Telegram](https://img.shields.io/badge/Telegram-Community-2CA5E0?logo=telegram)](https://t.me/claudecodecloak)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)]()

:star: Star this repo if it helps — it helps others find it too.

</div>

---

<a id="中文"></a>

## 中文

> **[Switch to English](#english)**

### 简介

**cac** 是 Claude Code 的环境管理器，类似 uv 之于 Python：

- **版本管理** — 安装、切换、回滚 Claude Code 版本
- **环境隔离** — 每个环境独立的 `.claude` 配置 + 身份 + 代理
- **隐私保护** — 设备指纹伪装 + 遥测分级（`conservative`/`aggressive`）+ mTLS
- **配置继承** — `--clone` 从宿主或其他环境继承配置，`~/.cac/settings.json` 全局偏好
- **零配置** — 无需 setup，首次使用自动初始化

### 注意事项

> **封号风险说明**：cac 提供设备指纹层保护（UUID、主机名、MAC、遥测阻断、配置隔离），但**无法影响账号层风险**——包括 OAuth 账号本身、支付方式指纹、IP 信誉评分，以及 Anthropic 的服务端封禁决策。封号是账号层问题，cac 对此无能为力。详见 [封号风险 FAQ](https://cac.nextmind.space/docs/zh/guides/ban-risk)。

> **代理工具冲突**：如果本地启动了 Clash、Shadowrocket、Surge、sing-box 等代理/VPN 工具，建议在使用 cac 时先关闭。TUN 模式兼容性仍属实验性功能。即使发生冲突，cac 也会自动停止连接（fail-closed），**不会泄露你的真实 IP**。

- **首次登录**：启动 `claude` 后，输入 `/login` 完成 OAuth 授权
- **安全验证**：随时运行 `cac env check` 确认隐私保护状态，也可以 `which claude` 确认使用的是 cac 托管的 claude
- **自动安全检查**：每次启动 Claude Code 会话时，cac 会快速检查环境。如有异常会终止会话，不会发送任何数据
- **网络稳定性**：流量严格走代理——代理断开时流量完全停止，不会回退直连。内置心跳检测和自动恢复，断线后无需手动重启
- **IPv6**：建议系统级关闭，防止真实地址泄露

### 安装

#### macOS / Linux

```bash
# npm（推荐）
npm install -g claude-cac

# 或手动安装
curl -fsSL https://raw.githubusercontent.com/nmhjklnm/cac/master/install.sh | bash
```

#### Windows

**前置要求**：Windows 10/11 + [Git for Windows](https://git-scm.com/download/win)（必须包含 Git Bash） + Node.js 18+

两种安装方式，选其一：

**方式 A — npm 安装（已发布到 npm 后使用）**

```powershell
npm install -g claude-cac
```

安装完成后 `cac` 命令即可在 CMD / PowerShell / Git Bash 中使用。

**方式 B — 本地 checkout（开发者 / 测试未发布版本）**

```powershell
git clone https://github.com/nmhjklnm/cac.git
cd cac
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1
```

安装脚本会在 npm 全局目录中生成 shim（自动探测 `npm config get prefix`），并将该目录加入用户 PATH。

> **找不到 `cac` 命令？** 重新打开终端窗口。如果仍然找不到，运行 `npm prefix -g` 确认该目录在 PATH 中。使用 nvm-windows / fnm / volta 的用户无需额外操作，安装脚本会自动适配。

**首次使用**

```powershell
# 安装 Claude Code 二进制
cac claude install latest

# 创建环境（代理可选）
cac env create work -p 1.2.3.4:1080:u:p

# 验证隐私保护状态
cac env check

# 启动 Claude Code（首次需输入 /login 完成授权）
claude
```

首次初始化后会自动生成 `%USERPROFILE%\.cac\bin\claude.cmd`。如果新终端里找不到 `claude`，把 `%USERPROFILE%\.cac\bin` 加入用户 PATH 后重开终端。

#### Windows 更新同步

cac 更新后，需要同步本地安装才能使用新功能和修复：

**方式 A — npm 安装用户**

```powershell
npm update -g claude-cac
```

npm 的 `postinstall` 会自动同步运行时文件（`fingerprint-hook.js`、`cac-dns-guard.js`、`relay.js`）到 `~/.cac/` 并触发 wrapper 重建。

**方式 B — 本地 checkout 用户**

```bash
# 拉取最新代码并重建
git pull
bash build.sh
```

`build.sh` 重新生成 `cac` 脚本后立即生效（shim 直接指向本地 checkout 目录）。

如果本次更新涉及 JS 运行时文件的修改（`fingerprint-hook.js`、`relay.js`、`cac-dns-guard.js`），还需要同步到 `~/.cac/`：

```bash
# 方式一：手动复制（最快）
cp cac-dns-guard.js fingerprint-hook.js relay.js ~/.cac/

# 方式二：运行任意 cac 命令触发自动同步
cac env ls
```

> **如何判断是否需要同步 JS 文件？** 查看 `git diff` 输出，如果只改了 `src/*.sh` 文件则不需要。如果改了 `src/fingerprint-hook.js`、`src/relay.js` 或 `src/dns_block.sh`（包含 `cac-dns-guard.js`），则需要同步。

#### Windows 卸载

```powershell
# 1. 删除 cac 运行目录、wrapper、环境数据
cac self delete

# 2. 移除全局 shim
#    npm 安装用户：
npm uninstall -g claude-cac
#    本地 checkout 用户：
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1 -Uninstall

# 3.（可选）清理仓库
Remove-Item -Recurse -Force .\node_modules
```

如果 `cac` 已经不可用，可直接删除 `%USERPROFILE%\.cac` 目录。

#### Windows 已知限制

- **Git Bash 是硬依赖** — 核心逻辑用 Bash 实现，Windows 入口（`cac.cmd` / `cac.ps1`）会自动查找 Git Bash 并委托执行。未安装 Git Bash 时会给出明确报错和下载链接。
- **Shell shim 层不适用** — `shim-bin/` 下的指纹拦截脚本（`ioreg`、`ifconfig`、`hostname`、`cat`）是 Unix 命令，Windows 上不生效。Windows 的指纹保护完全依赖 Node.js 层的 `fingerprint-hook.js`（拦截 `wmic`、`reg query` 等调用）。
- **Docker 容器模式仅 Linux** — sing-box TUN 网络隔离目前不支持 Windows。可通过 WSL2 + Docker Desktop 作为替代方案。
- 完整的 Windows 支持评估和已知问题见 [`docs/windows/`](docs/windows/)。

### 快速上手

```bash
# 安装 Claude Code
cac claude install latest

# 创建环境（自动激活，自动使用最新版）
cac env create work -p 1.2.3.4:1080:u:p

# 启动 Claude Code（首次需 /login）
claude
```

代理可选 — 不需要代理也能用：

```bash
cac env create personal                  # 只要身份隔离
cac env create work -c 2.1.81           # 指定版本，无代理
```

### 版本管理

```bash
cac claude install latest               # 安装最新版
cac claude install 2.1.81               # 安装指定版本
cac claude ls                           # 列出已安装版本
cac claude pin 2.1.81                   # 当前环境切换版本
cac claude uninstall 2.1.81             # 卸载
```

### 环境管理

```bash
cac env create <name> [-p <proxy>] [-c <version>]   # 创建并自动激活（自动解析最新版）
cac env ls                              # 列出所有环境
cac env rm <name>                       # 删除环境
cac env set [name] proxy <url>          # 设置 / 修改代理
cac env set [name] proxy --remove       # 移除代理
cac env set [name] version <ver>        # 切换版本
cac <name>                              # 激活环境（快捷方式）
cac ls                                  # = cac env ls
```

每个环境完全隔离：
- **Claude Code 版本** — 不同环境可以用不同版本
- **`.claude` 配置** — sessions、settings、memory 各自独立
- **身份信息** — UUID、hostname、MAC 等完全不同
- **代理出口** — 每个环境走不同代理（或不走代理）

### 全部命令

| 命令 | 说明 |
|:---|:---|
| **版本管理** | |
| `cac claude install [latest\|<ver>]` | 安装 Claude Code |
| `cac claude uninstall <ver>` | 卸载版本 |
| `cac claude ls` | 列出已安装版本 |
| `cac claude pin <ver>` | 当前环境绑定版本 |
| **环境管理** | |
| `cac env create <name> [-p proxy] [-c ver] [--clone] [--telemetry mode] [--persona preset]` | 创建环境（自动激活，`--telemetry transparent/stealth/paranoid` 控制遥测，`--persona macos-vscode/...` 用于容器） |
| `cac env ls` | 列出环境 |
| `cac env rm <name>` | 删除环境 |
| `cac env set [name] <key> <value>` | 修改环境（proxy / version / telemetry / persona） |
| `cac env check [-d]` | 验证当前环境（`-d` 显示详情） |
| `cac <name>` | 激活环境 |
| **自管理** | |
| `cac self update` | 更新 cac 自身 |
| `cac self delete` | 卸载 cac |
| **其他** | |
| `cac ls` | 列出环境（= `cac env ls`） |
| `cac check` | 检查当前环境（`cac env check` 的别名） |
| `cac -v` | 版本号 |

### 代理格式

```
host:port:user:pass       带认证（自动检测协议）
host:port                 无认证
socks5://u:p@host:port    指定协议
```

### 隐私保护

| 特性 | 实现方式 |
|:---|:---|
| 硬件 UUID 隔离 | macOS `ioreg` / Linux `machine-id` / Windows `wmic`+`reg` shim |
| 主机名 / MAC 隔离 | Shell shim + Node.js `os.hostname()` / `os.networkInterfaces()` hook |
| Node.js 指纹钩子 | `fingerprint-hook.js` 通过 `NODE_OPTIONS --require` 注入 |
| 遥测阻断 | DNS guard + 环境变量 + fetch 拦截 + 分级模式（`conservative`/`aggressive`） |
| 健康检查 bypass | 进程内 Node.js 拦截（无需 /etc/hosts 或 root） |
| mTLS 客户端证书 | 自签 CA + 每环境独立客户端证书 |
| `.claude` 配置隔离 | 每个环境独立的 `CLAUDE_CONFIG_DIR` |

### 工作原理

```
              cac wrapper（进程级，零侵入源代码）
              ┌──────────────────────────────────────────┐
  claude ────►│  CLAUDE_CONFIG_DIR → 隔离配置目录          │
              │  版本解析 → ~/.cac/versions/<ver>/claude   │
              │  健康检查 bypass（进程内拦截）                │
              │  12 层遥测环境变量保护                      │──► 代理 ──► Anthropic API
              │  NODE_OPTIONS: DNS guard + 指纹钩子        │
              │  PATH: 设备指纹 shim                       │
              │  mTLS: 客户端证书注入                       │
              └──────────────────────────────────────────┘
```

### 文件结构

```
~/.cac/
├── versions/<ver>/claude     # Claude Code 二进制文件
├── bin/claude                # wrapper
├── shim-bin/                 # ioreg / hostname / ifconfig / cat shim
├── fingerprint-hook.js       # Node.js 指纹拦截
├── cac-dns-guard.js          # DNS + fetch 遥测拦截
├── ca/                       # 自签 CA + 健康检查 bypass 证书
├── current                   # 当前激活的环境名
└── envs/<name>/
    ├── .claude/              # 隔离的 .claude 配置目录
    │   ├── settings.json     # 环境专属设置
    │   ├── CLAUDE.md         # 环境专属记忆
    │   └── statusline-command.sh
    ├── proxy                 # 代理地址（可选）
    ├── version               # 绑定的 Claude Code 版本
    ├── uuid / stable_id      # 隔离身份
    ├── hostname / mac_address / machine_id
    └── client_cert.pem       # mTLS 证书
```

### Docker 容器模式

完全隔离的运行环境：sing-box TUN 网络隔离 + cac 身份伪装，预装 Claude Code。

```bash
cac docker setup     # 粘贴代理地址，网络自动检测
cac docker start     # 启动容器
cac docker enter     # 进入容器，claude + cac 直接可用
cac docker check     # 网络 + 身份一键诊断
cac docker port 6287 # 端口转发
```

代理格式：`ip:port:user:pass`（SOCKS5）、`ss://...`、`vmess://...`、`vless://...`、`trojan://...`

---

<a id="english"></a>

## English

> **[切换到中文](#中文)**

### Overview

**cac** — Isolate, protect, and manage your Claude Code:

- **Version management** — install, switch, rollback Claude Code versions
- **Environment isolation** — independent `.claude` config + identity + proxy per environment
- **Privacy protection** — device fingerprint spoofing + telemetry modes (`conservative`/`aggressive`) + mTLS
- **Config inheritance** — `--clone` inherits config from host or other envs, `~/.cac/settings.json` for global preferences
- **Zero config** — no setup needed, auto-initializes on first use

### Notes

> **Account ban notice**: cac provides device fingerprint layer protection (UUID, hostname, MAC, telemetry blocking, config isolation), but **cannot affect account-layer risks** — including your OAuth account, payment method fingerprint, IP reputation score, or Anthropic's server-side ban decisions. Account bans are an account-layer issue that cac does not address. See the [Ban Risk FAQ](https://cac.nextmind.space/docs/guides/ban-risk) for details.

> **Proxy tool conflicts**: If you have Clash, Shadowrocket, Surge, sing-box or other proxy/VPN tools running locally, turn them off before using cac. TUN-mode compatibility is still experimental. Even if a conflict occurs, cac will fail-closed — **your real IP is never exposed**.

- **First login**: Run `claude`, then type `/login`. Health check is automatically bypassed.
- **Verify your setup**: Run `cac env check` anytime. Use `which claude` to confirm you're using the cac-managed wrapper.
- **Automatic safety checks**: Every new Claude Code session runs a quick cac check. If anything is wrong, the session is terminated before any data is sent.
- **Network resilience**: Traffic is strictly routed through your proxy. If the proxy drops, traffic stops entirely — no fallback to direct connection. Built-in heartbeat detection and auto-recovery — no manual restart needed after disconnections.
- **IPv6**: Recommend disabling system-wide to prevent real address exposure.

### Install

#### macOS / Linux

```bash
# npm (recommended)
npm install -g claude-cac

# or manual
curl -fsSL https://raw.githubusercontent.com/nmhjklnm/cac/master/install.sh | bash
```

#### Windows

**Prerequisites**: Windows 10/11 + [Git for Windows](https://git-scm.com/download/win) (must include Git Bash) + Node.js 18+

Choose one of the following:

**Option A — npm install (after npm release)**

```powershell
npm install -g claude-cac
```

After installation, `cac` is available in CMD, PowerShell, and Git Bash.

**Option B — local checkout (developers / testing unreleased changes)**

```powershell
git clone https://github.com/nmhjklnm/cac.git
cd cac
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1
```

The installer creates shims in the npm global directory (auto-detected via `npm config get prefix`) and adds it to your user PATH. Works with nvm-windows, fnm, volta, and Scoop out of the box.

> **`cac` not found?** Reopen your terminal. If still missing, run `npm prefix -g` to verify the directory is on your PATH.

**First run**

```powershell
# install Claude Code binary
cac claude install latest

# create an environment (proxy is optional)
cac env create work -p 1.2.3.4:1080:u:p

# verify privacy protection status
cac env check

# start Claude Code (first time: type /login to authorize)
claude
```

First initialization auto-generates `%USERPROFILE%\.cac\bin\claude.cmd`. If `claude` is not found in a new terminal, add `%USERPROFILE%\.cac\bin` to your user PATH and reopen.

#### Windows update sync

After cac receives updates, sync your local installation to get new features and fixes:

**Option A — npm install users**

```powershell
npm update -g claude-cac
```

The `postinstall` script automatically syncs runtime JS files (`fingerprint-hook.js`, `cac-dns-guard.js`, `relay.js`) to `~/.cac/` and triggers wrapper regeneration.

**Option B — local checkout users**

```bash
# pull latest and rebuild
git pull
bash build.sh
```

The rebuilt `cac` takes effect immediately (shims point to your local checkout).

If the update changed JS runtime files (`fingerprint-hook.js`, `relay.js`, or `cac-dns-guard.js`), also sync them to `~/.cac/`:

```bash
# option 1: manual copy (fastest)
cp cac-dns-guard.js fingerprint-hook.js relay.js ~/.cac/

# option 2: run any cac command to trigger auto-sync
cac env ls
```

> **Do I need to sync JS files?** Check `git diff` — if only `src/*.sh` files changed, no sync is needed. If `src/fingerprint-hook.js`, `src/relay.js`, or `src/dns_block.sh` (which contains `cac-dns-guard.js`) changed, sync is required.

#### Windows uninstall

```powershell
# 1. remove cac runtime data, wrappers, and environments
cac self delete

# 2. remove global shims
#    npm install users:
npm uninstall -g claude-cac
#    local checkout users:
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1 -Uninstall

# 3. (optional) clean repository
Remove-Item -Recurse -Force .\node_modules
```

If `cac` is already unavailable, delete `%USERPROFILE%\.cac` directly.

#### Windows known limitations

- **Git Bash is a hard dependency** — core logic is written in Bash. Windows entry points (`cac.cmd` / `cac.ps1`) auto-locate Git Bash and delegate to it. A clear error message with a download link is shown if Git Bash is not installed.
- **Shell shim layer is inactive** — `shim-bin/` scripts (`ioreg`, `ifconfig`, `hostname`, `cat`) are Unix commands and have no effect on Windows. Windows fingerprint protection relies entirely on the Node.js `fingerprint-hook.js` layer (intercepts `wmic`, `reg query`, etc.).
- **Docker mode is Linux-only** — sing-box TUN network isolation does not support Windows. Use WSL2 + Docker Desktop as an alternative.
- See [`docs/windows/`](docs/windows/) for the full Windows support assessment and known issues.

### Quick start

```bash
# Install Claude Code
cac claude install latest

# Create environment (auto-activates, auto-resolves latest version)
cac env create work -p 1.2.3.4:1080:u:p

# Run Claude Code (first time: /login)
claude
```

Proxy is optional:

```bash
cac env create personal                  # identity isolation only
cac env create work -c 2.1.81           # pinned version, no proxy
```

### Version management

```bash
cac claude install latest               # install latest
cac claude install 2.1.81               # install specific version
cac claude ls                           # list installed versions
cac claude pin 2.1.81                   # pin current env to version
cac claude uninstall 2.1.81             # remove
```

### Environment management

```bash
cac env create <name> [-p <proxy>] [-c <version>]   # create and auto-activate (auto-resolves latest)
cac env ls                              # list all environments
cac env rm <name>                       # remove environment
cac env set [name] proxy <url>          # set / change proxy
cac env set [name] proxy --remove       # remove proxy
cac env set [name] version <ver>        # change version
cac <name>                              # activate (shortcut)
cac ls                                  # = cac env ls
```

Each environment is fully isolated:
- **Claude Code version** — different envs can use different versions
- **`.claude` config** — sessions, settings, memory are independent
- **Identity** — UUID, hostname, MAC are all different
- **Proxy** — each env routes through a different proxy (or none)

### All commands

| Command | Description |
|:---|:---|
| **Version management** | |
| `cac claude install [latest\|<ver>]` | Install Claude Code |
| `cac claude uninstall <ver>` | Remove version |
| `cac claude ls` | List installed versions |
| `cac claude pin <ver>` | Pin current env to version |
| **Environment management** | |
| `cac env create <name> [-p proxy] [-c ver] [--clone] [--telemetry mode] [--persona preset]` | Create environment (auto-activates, `--telemetry transparent/stealth/paranoid` for telemetry control, `--persona macos-vscode/...` for containers) |
| `cac env ls` | List environments |
| `cac env rm <name>` | Remove environment |
| `cac env set [name] <key> <value>` | Modify environment (proxy / version / telemetry / persona) |
| `cac env check [-d]` | Verify current environment (`-d` for details) |
| `cac <name>` | Activate environment |
| **Self-management** | |
| `cac self update` | Update cac itself |
| `cac self delete` | Uninstall cac |
| **Other** | |
| `cac ls` | List environments (= `cac env ls`) |
| `cac check` | Verify environment (alias for `cac env check`) |
| `cac -v` | Show version |

### Privacy protection

| Feature | How |
|:---|:---|
| Hardware UUID isolation | macOS `ioreg` / Linux `machine-id` / Windows `wmic`+`reg` shim |
| Hostname / MAC isolation | Shell shim + Node.js `os.hostname()` / `os.networkInterfaces()` hook |
| Node.js fingerprint hook | `fingerprint-hook.js` via `NODE_OPTIONS --require` |
| Telemetry blocking | DNS guard + env vars + fetch interception + modes (`conservative`/`aggressive`) |
| Health check bypass | In-process Node.js interception (no `/etc/hosts`, no root) |
| mTLS client certificates | Self-signed CA + per-profile client certs |
| `.claude` config isolation | Per-environment `CLAUDE_CONFIG_DIR` |

### How it works

```
              cac wrapper (process-level, zero source invasion)
              ┌──────────────────────────────────────────┐
  claude ────►│  CLAUDE_CONFIG_DIR → isolated config dir   │
              │  Version resolve → ~/.cac/versions/<ver>   │
              │  Health check bypass (in-process intercept) │
              │  Env vars: 12-layer telemetry kill         │──► Proxy ──► Anthropic API
              │  NODE_OPTIONS: DNS guard + fingerprint     │
              │  PATH: device fingerprint shims            │
              │  mTLS: client cert injection               │
              └──────────────────────────────────────────┘
```

### File layout

```
~/.cac/
├── versions/<ver>/claude     # Claude Code binaries
├── bin/claude                # wrapper
├── shim-bin/                 # ioreg / hostname / ifconfig / cat shims
├── fingerprint-hook.js       # Node.js fingerprint interception
├── cac-dns-guard.js          # DNS + fetch telemetry interception
├── ca/                       # self-signed CA + health bypass cert
├── current                   # active environment name
└── envs/<name>/
    ├── .claude/              # isolated .claude config directory
    │   ├── settings.json     # env-specific settings
    │   ├── CLAUDE.md         # env-specific memory
    │   └── statusline-command.sh
    ├── proxy                 # proxy URL (optional)
    ├── version               # pinned Claude Code version
    ├── uuid / stable_id      # isolated identity
    ├── hostname / mac_address / machine_id
    └── client_cert.pem       # mTLS cert
```

### Docker mode

Fully isolated environment: sing-box TUN network isolation + cac identity protection, with Claude Code pre-installed.

```bash
cac docker setup     # paste proxy, network auto-detected
cac docker start     # start container
cac docker enter     # shell with claude + cac ready
cac docker check     # network + identity diagnostics
cac docker port 6287 # port forwarding
```

Proxy formats: `ip:port:user:pass` (SOCKS5), `ss://...`, `vmess://...`, `vless://...`, `trojan://...`

---

<div align="center">

MIT License

</div>
