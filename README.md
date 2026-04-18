# cac-win

这是面向 **Windows 本地使用** 的 cac 适配仓库。

**Claude Code 小雨衣 · Windows 版** — Windows 适配 fork

**[中文](#中文) | [English](#english)**

[![GitHub stars](https://img.shields.io/github/stars/nmhjklnm/cac?style=social)](https://github.com/nmhjklnm/cac)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)]()

> 本仓库是 [nmhjklnm/cac](https://github.com/nmhjklnm/cac) 的 Windows 适配 fork，专注于 Windows 平台兼容性。**未发布到 npm**，请通过 clone 仓库的方式安装。macOS / Linux 用户请直接使用 [上游仓库](https://github.com/nmhjklnm/cac)。

## 前置要求

- Windows 10/11
- Git for Windows，必须包含 Git Bash
- Node.js 18+，并确保 npm 在 PATH 中
- PowerShell 5.1+

<a id="中文"></a>

## 中文

> **[Switch to English](#english)**

### 关于本仓库

**cac-win** 是 [nmhjklnm/cac](https://github.com/nmhjklnm/cac) 的 Windows 适配版本，在上游基础上额外解决了：

- Windows 本地化系统（中文/日文等）下 IPv6 泄漏检测误报
- npm 全局目录在 nvm-windows / fnm / volta / Scoop 等非标准安装下路径错误
- Git Bash 下 OpenSSL 路径查找顺序问题
- Windows 专用入口（`cac.cmd` / `cac.ps1`）及 Git Bash 自动定位

cac 本身的功能与上游一致：版本管理、环境隔离、设备指纹伪装、遥测阻断、代理路由。

### 注意事项

> **封号风险**：cac 提供设备指纹层保护（UUID、主机名、MAC、遥测阻断、配置隔离），但**无法影响账号层风险**——包括 OAuth 账号本身、支付方式指纹、IP 信誉评分及 Anthropic 服务端决策。

> **代理工具冲突**：使用前建议关闭 Clash、sing-box 等本地代理/VPN 工具。即使发生冲突，cac 也会 fail-closed，**不会泄露真实 IP**。

- **首次登录**：启动 `claude` 后输入 `/login` 完成 OAuth 授权
- **安全验证**：随时运行 `cac env check` 确认隐私保护状态
- **IPv6**：建议系统级关闭，防止真实地址泄露

### 安装（Windows）

**前置要求**：
- Windows 10 / 11
- [Git for Windows](https://git-scm.com/download/win)（必须包含 Git Bash）
- Node.js 18+

```powershell
# 1. 克隆本仓库
git clone https://github.com/Cainiaooo/cac-win.git
cd cac-win

# 2. 运行安装脚本（在 PowerShell 中执行）
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1
```

安装脚本会在 npm 全局目录中生成 `cac` / `cac.cmd` / `cac.ps1` shim，并自动将该目录加入用户 PATH。支持 nvm-windows / fnm / volta / Scoop 等非标准 Node.js 安装。

> **找不到 `cac` 命令？** 重新打开终端窗口。如仍找不到，运行 `npm prefix -g` 确认输出目录在 PATH 中，然后手动添加。

### 首次使用

```powershell
cac -v
cac help
```

```powershell
# 安装 cac 托管的 Claude Code 二进制
cac claude install latest

# 创建并激活 Windows 环境；代理可按需填写
cac env create win-work -p 1.2.3.4:1080:u:p

# 检查当前环境
cac env check

# 启动 Claude Code；首次进入后使用 /login
claude
```

首次初始化后会自动生成 `%USERPROFILE%\.cac\bin\claude.cmd`。如果新终端里找不到 `claude`，把 `%USERPROFILE%\.cac\bin` 加入用户 PATH 后重开终端。

不需要代理时也可以只做身份/配置隔离：

```powershell
cac env create personal
cac env create work -c 2.1.81
```

### 常用流程

#### 查看当前状态

```powershell
cac env ls
cac env check
cac env check -d
cac -v
```

#### 创建和切换环境

```powershell
# 创建并自动激活环境
cac env create work

# 创建带代理的环境
cac env create work-proxy -p 1.2.3.4:1080:u:p

# 创建并绑定指定 Claude Code 版本
cac env create legacy -c 2.1.81

# 创建环境，并在每次激活时检查 Claude Code 更新
cac env create work-auto --autoupdate

# 从当前宿主配置复制 .claude 配置
cac env create cloned --clone

# 切换到某个环境
cac work

# 查看所有环境
cac env ls
```

#### 修改环境

```powershell
# 给当前环境设置或修改代理
cac env set proxy 1.2.3.4:1080:u:p

# 给指定环境设置代理
cac env set work proxy 1.2.3.4:1080:u:p

# 移除当前环境代理
cac env set proxy --remove

# 切换当前环境使用的 Claude Code 版本
cac env set version 2.1.81

# 开启或关闭激活时的 Claude Code 更新检查
cac env set work autoupdate on
cac env set work autoupdate off

# 删除环境
cac env rm work
```

#### 管理 Claude Code 版本

```powershell
cac claude install latest
cac claude install 2.1.81
cac claude ls
cac claude pin 2.1.81
cac claude update work
cac claude prune
cac claude prune --yes
cac claude uninstall 2.1.81
```

#### 启动 Claude Code

```powershell
# 确认已经激活目标环境
cac env check

# 启动；首次进入后执行 /login
claude
```

代理可选：

```text
host:port:user:pass
host:port
socks5://u:p@host:port
http://u:p@host:port
```

代理不是必填项；不加 `-p` 时，环境仍然会隔离 `.claude` 配置、身份信息和 Claude Code 版本。

### 全部命令

| 命令 | 说明 |
|:---|:---|
| `cac env create <name> [-p proxy] [-c ver] [--clone] [--autoupdate]` | 创建并激活环境 |
| `cac <name>` | 激活环境（快捷方式） |
| `cac env ls` / `cac ls` | 查看环境列表 |
| `cac env rm <name>` | 删除环境 |
| `cac env set [name] proxy <proxy>` | 设置环境代理 |
| `cac env set [name] proxy --remove` | 移除环境代理 |
| `cac env set [name] version <ver>` | 切换环境绑定的 Claude Code 版本 |
| `cac env set [name] autoupdate <on\|off>` | 开启或关闭激活时的 Claude Code 更新检查 |
| `cac env check [-d]` | 验证当前环境（`-d` 显示详情） |
| `cac claude install [latest\|<ver>]` | 安装 Claude Code |
| `cac claude uninstall <ver>` | 卸载版本 |
| `cac claude ls` | 列出已安装版本 |
| `cac claude pin <ver>` | 当前环境绑定版本 |
| `cac claude update [env]` | 将环境更新到远端最新 Claude Code |
| `cac claude prune [--yes]` | 列出或删除未被环境引用的 Claude Code 版本 |
| `cac self update` | 更新 cac 自身 |
| `cac self delete` | 卸载 cac |
| `cac -v` | 版本号 |

### 代理格式

```
host:port:user:pass       带认证（自动检测协议）
host:port                 无认证
socks5://u:p@host:port    指定协议
```

### 同步更新

当本仓库有新提交时，在仓库目录下执行：

```bash
# Git Bash 中运行
git pull
bash build.sh
```

`build.sh` 重新生成 `cac` 脚本后立即生效——shim 直接指向本地 checkout，无需重新运行安装脚本。

如果本次更新包含 JS 运行时文件的修改（`fingerprint-hook.js`、`relay.js`、`cac-dns-guard.js`），还需同步到 `~/.cac/`：

```bash
# 手动复制（最直接）
cp cac-dns-guard.js fingerprint-hook.js relay.js ~/.cac/

# 或运行任意 cac 命令触发自动同步
cac env ls
```

> **如何判断是否需要同步 JS 文件？** 查看 `git log` 或 `git diff HEAD~1`，如果只改了 `src/*.sh` 则不需要；如果改了 `src/fingerprint-hook.js`、`src/relay.js` 或 `src/dns_block.sh` 则需要同步。

### 已安装用户如何更新

如果之前已经安装过 cac 并创建了环境，更新流程如下：

```bash
# 1. 进入仓库目录，拉取最新代码
cd E:\Projects\cac-win
git pull

# 2. 重新构建（必须在 Git Bash 中运行）
bash build.sh

# 3. 同步 JS 运行时文件（如果本次更新涉及 JS 文件修改）
cp fingerprint-hook.js relay.js cac-dns-guard.js ~/.cac/
```

**常见问题**：

- **新命令/新选项不可用**（如 `--autoupdate` 提示 `unknown option`）：说明本地 `cac` 构建产物未更新。确认已执行 `bash build.sh`，然后重试。
- **已有环境不受影响**：更新只替换 cac 程序本身，`~/.cac/envs/` 下的环境数据、身份信息、代理配置都会保留。
- **不需要重新运行安装脚本**：shim 指向本地 checkout 路径，`build.sh` 更新后立即生效。
- **不需要重新创建环境**：已有的环境和配置全部兼容。

### 卸载

```powershell
# 1. 删除 cac 运行目录、wrapper 和环境数据
cac self delete

# 2. 移除全局 shim
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1 -Uninstall

# 3.（可选）删除仓库目录
cd .. && Remove-Item -Recurse -Force cac-win
```

如果 `cac` 已经不可用，可直接删除 `%USERPROFILE%\.cac` 目录，然后再执行步骤 2。

### Windows 已知限制

- **Git Bash 是硬依赖** — 核心逻辑用 Bash 实现，`cac.cmd` / `cac.ps1` 会自动查找 Git Bash 并委托执行。未安装时会给出明确报错和下载链接。
- **Shell shim 层不适用** — `shim-bin/` 下的 Unix 命令（`ioreg`、`ifconfig`、`hostname`、`cat`）在 Windows 上不生效，Windows 指纹保护完全依赖 `fingerprint-hook.js`（拦截 `wmic`、`reg query` 等调用）。
- **Docker 容器模式仅 Linux** — sing-box TUN 网络隔离不支持 Windows，可通过 WSL2 + Docker Desktop 替代。

完整的 Windows 支持评估和已知问题见 [`docs/windows/`](docs/windows/)。

---

### 隐私保护

| 特性 | 实现方式 |
|:---|:---|
| 硬件 UUID 隔离 | Windows: `wmic`+`reg query` hook；macOS: `ioreg`；Linux: `machine-id` |
| 主机名 / MAC 隔离 | Node.js `os.hostname()` / `os.networkInterfaces()` hook（Windows）|
| Node.js 指纹钩子 | `fingerprint-hook.js` 通过 `NODE_OPTIONS --require` 注入 |
| 遥测阻断 | DNS guard + 环境变量 + fetch 拦截 |
| 健康检查 bypass | 进程内 Node.js 拦截（无需 hosts 文件或管理员权限） |
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
              │  PATH: 设备指纹 shim（macOS/Linux）         │
              │  mTLS: 客户端证书注入                       │
              └──────────────────────────────────────────┘
```

---

<a id="english"></a>

## English

> **[切换到中文](#中文)**

### About this repository

**cac-win** is a Windows-focused fork of [nmhjklnm/cac](https://github.com/nmhjklnm/cac). It is **not published to npm** — installation requires cloning this repository locally. macOS and Linux users should use the [upstream repository](https://github.com/nmhjklnm/cac) instead.

Additional Windows fixes in this fork:
- IPv6 leak detection on localized Windows (Chinese/Japanese/etc.) — fixed false negatives caused by locale-dependent `ipconfig` labels
- npm global directory detection — now uses `npm config get prefix` instead of hardcoding `%APPDATA%\npm`, compatible with nvm-windows / fnm / volta / Scoop
- OpenSSL path resolution in `mtls.sh` — cleaned up to standard Git for Windows locations
- Windows entry points (`cac.cmd` / `cac.ps1`) with automatic Git Bash detection

### Notes

> **Account ban notice**: cac provides device fingerprint layer protection (UUID, hostname, MAC, telemetry blocking, config isolation), but **cannot affect account-layer risks** — including your OAuth account, payment method fingerprint, IP reputation score, or Anthropic's server-side decisions.

> **Proxy tool conflicts**: Turn off Clash, sing-box or other local proxy/VPN tools before using cac. Even if a conflict occurs, cac will fail-closed — **your real IP is never exposed**.

- **First login**: Run `claude`, then type `/login` to authorize.
- **Verify setup**: Run `cac env check` anytime to confirm privacy protection is active.
- **IPv6**: Recommend disabling system-wide to prevent real address exposure.

### Install (Windows)

**Prerequisites**:
- Windows 10 / 11
- [Git for Windows](https://git-scm.com/download/win) (must include Git Bash)
- Node.js 18+

```powershell
# 1. Clone this repository
git clone https://github.com/Cainiaooo/cac-win.git
cd cac-win

# 2. Run the installer (from PowerShell)
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1
```

The installer creates `cac` / `cac.cmd` / `cac.ps1` shims in the npm global directory (auto-detected via `npm config get prefix`) and adds that directory to your user PATH. Works with nvm-windows, fnm, volta, and Scoop out of the box.

> **`cac` not found?** Reopen your terminal. If still missing, run `npm prefix -g` to confirm the directory is on your PATH.

### First run

```powershell
cac -v
cac help
```

```powershell
# Install Claude Code binary
cac claude install latest

# Create an environment (proxy is optional)
cac env create work -p 1.2.3.4:1080:u:p

# Verify privacy protection
cac env check

# Start Claude Code (first time: type /login to authorize)
claude
```

First initialization auto-generates `%USERPROFILE%\.cac\bin\claude.cmd`. If `claude` is not found in a new terminal, add `%USERPROFILE%\.cac\bin` to your user PATH and reopen.

Proxy is optional:

```powershell
cac env create personal                  # identity isolation only
cac env create work -c 2.1.81           # pinned version, no proxy
```

### Common workflows

#### Check current status

```powershell
cac env ls
cac env check
cac env check -d
cac -v
```

#### Create and switch environments

```powershell
# Create and auto-activate
cac env create work

# With proxy
cac env create work-proxy -p 1.2.3.4:1080:u:p

# With pinned Claude Code version
cac env create legacy -c 2.1.81

# Auto-update Claude Code on each activation
cac env create work-auto --autoupdate

# Clone current .claude config
cac env create cloned --clone

# Switch environment
cac work

# List environments
cac env ls
```

#### Modify environments

```powershell
# Set or change proxy
cac env set proxy 1.2.3.4:1080:u:p

# Set proxy for a specific environment
cac env set work proxy 1.2.3.4:1080:u:p

# Remove proxy
cac env set proxy --remove

# Change Claude Code version
cac env set version 2.1.81

# Enable or disable auto-update on activation
cac env set work autoupdate on
cac env set work autoupdate off

# Remove environment
cac env rm work
```

#### Manage Claude Code versions

```powershell
cac claude install latest
cac claude install 2.1.81
cac claude ls
cac claude pin 2.1.81
cac claude update work
cac claude prune
cac claude prune --yes
cac claude uninstall 2.1.81
```

#### Start Claude Code

```powershell
# Verify active environment
cac env check

# Start (first time: type /login to authorize)
claude
```

### All commands

| Command | Description |
|:---|:---|
| `cac env create <name> [-p proxy] [-c ver] [--clone] [--autoupdate]` | Create and activate environment |
| `cac <name>` | Activate environment (shortcut) |
| `cac env ls` / `cac ls` | List environments |
| `cac env rm <name>` | Remove environment |
| `cac env set [name] proxy <proxy>` | Set environment proxy |
| `cac env set [name] proxy --remove` | Remove environment proxy |
| `cac env set [name] version <ver>` | Change Claude Code version |
| `cac env set [name] autoupdate <on\|off>` | Enable or disable auto-update on activation |
| `cac env check [-d]` | Verify current environment (`-d` for details) |
| `cac claude install [latest\|<ver>]` | Install Claude Code |
| `cac claude uninstall <ver>` | Remove version |
| `cac claude ls` | List installed versions |
| `cac claude pin <ver>` | Pin current env to version |
| `cac claude update [env]` | Update environment to latest Claude Code |
| `cac claude prune [--yes]` | List or remove unreferenced Claude Code versions |
| `cac self update` | Update cac itself |
| `cac self delete` | Uninstall cac |
| `cac -v` | Show version |

### Proxy format

```
host:port:user:pass       authenticated (protocol auto-detected)
host:port                 no auth
socks5://u:p@host:port    explicit protocol
```

### Keeping up to date

When this repository has new commits, run from inside the repo directory:

```bash
# Run from Git Bash
git pull
bash build.sh
```

The rebuilt `cac` takes effect immediately — the shims point directly to your local checkout, so no re-installation is needed.

If the update changed JS runtime files (`fingerprint-hook.js`, `relay.js`, or `cac-dns-guard.js`), also sync them to `~/.cac/`:

```bash
# Option 1: manual copy
cp cac-dns-guard.js fingerprint-hook.js relay.js ~/.cac/

# Option 2: trigger auto-sync via any cac command
cac env ls
```

> **Do I need to sync JS files?** Check `git log` or `git diff HEAD~1` — if only `src/*.sh` changed, no sync needed. If `src/fingerprint-hook.js`, `src/relay.js`, or `src/dns_block.sh` changed, sync is required.

### Updating an existing installation

If you already have cac installed with environments set up, the update process is:

```bash
# 1. Navigate to the repo and pull latest
cd E:\Projects\cac-win
git pull

# 2. Rebuild (must run from Git Bash)
bash build.sh

# 3. Sync JS runtime files (only if this update changed JS files)
cp fingerprint-hook.js relay.js cac-dns-guard.js ~/.cac/
```

**Common issues**:

- **New commands/options not available** (e.g. `--autoupdate` shows `unknown option`): the local `cac` build is stale. Confirm `bash build.sh` was run, then retry.
- **Existing environments are preserved**: updating only replaces the cac program itself. Environment data, identities, and proxy configs under `~/.cac/envs/` are kept intact.
- **No need to re-run the installer**: shims point to your local checkout path, so `build.sh` updates take effect immediately.
- **No need to recreate environments**: existing environments and configs are fully compatible.

### Uninstall

```powershell
# 1. Remove cac runtime data, wrappers, and environments
cac self delete

# 2. Remove global shims
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1 -Uninstall

# 3. (Optional) Delete the repository
cd .. && Remove-Item -Recurse -Force cac-win
```

If `cac` is already unavailable, delete `%USERPROFILE%\.cac` directly, then run step 2.

### Windows known limitations

- **Git Bash is a hard dependency** — core logic is Bash. `cac.cmd` / `cac.ps1` auto-locate Git Bash and delegate to it. A clear error with a download link is shown if Git Bash is not found.
- **Shell shim layer is inactive** — `shim-bin/` scripts (`ioreg`, `ifconfig`, `hostname`, `cat`) are Unix commands and have no effect on Windows. Windows fingerprint protection relies entirely on `fingerprint-hook.js` (intercepts `wmic`, `reg query`, etc.).
- **Docker mode is Linux-only** — sing-box TUN network isolation does not support Windows. Use WSL2 + Docker Desktop as an alternative.

See [`docs/windows/`](docs/windows/) for the full Windows support assessment and known issues.

---

### Privacy protection

| Feature | How |
|:---|:---|
| Hardware UUID isolation | Windows: `wmic`+`reg query` hook; macOS: `ioreg`; Linux: `machine-id` |
| Hostname / MAC isolation | Node.js `os.hostname()` / `os.networkInterfaces()` hook (Windows) |
| Node.js fingerprint hook | `fingerprint-hook.js` via `NODE_OPTIONS --require` |
| Telemetry blocking | DNS guard + env vars + fetch interception |
| Health check bypass | In-process Node.js interception (no `/etc/hosts`, no admin rights) |
| mTLS client certificates | Self-signed CA + per-environment client certs |
| `.claude` config isolation | Per-environment `CLAUDE_CONFIG_DIR` |

### How it works

```
              cac wrapper (process-level, zero source invasion)
              ┌──────────────────────────────────────────┐
  claude ────►│  CLAUDE_CONFIG_DIR → isolated config dir   │
              │  Version resolve → ~/.cac/versions/<ver>   │
              │  Health check bypass (in-process)           │
              │  Env vars: 12-layer telemetry kill         │──► Proxy ──► Anthropic API
              │  NODE_OPTIONS: DNS guard + fingerprint     │
              │  PATH: device fingerprint shims (Unix)     │
              │  mTLS: client cert injection               │
              └──────────────────────────────────────────┘
```

---

## 更多文档

- [完整 README 归档](docs/original-readme.md)
- [Windows 排障](docs/windows/troubleshooting.md)
- [Windows 测试指南](docs/windows/testing-guide.md)
- [Windows 已知问题](docs/windows/known-issues.md)
- [Windows IPv6 测试指南](docs/windows/ipv6-test-guide.md)
- [Windows 支持评估](docs/windows/windows-support-assessment.md)
- [上游文档站](https://cac.nextmind.space/docs)

---

<div align="center">

Fork of <a href="https://github.com/nmhjklnm/cac">nmhjklnm/cac</a> · MIT License

</div>
