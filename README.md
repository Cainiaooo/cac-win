# cac-win

这是面向 **Windows 本地使用** 的 cac 适配仓库。

> 重点：本仓库 **没有发布到 npm**。不要用 `npm install -g claude-cac` 安装本仓库；那个命令安装的是上游 `nmhjklnm/cac`。使用本仓库时必须先 clone 到本地，再运行本地安装脚本。

## 项目定位

`cac-win` 保留上游 cac 的 Claude Code 环境管理能力，但 README 只保留 Windows 使用路径：

- Windows 10/11 下通过 CMD、PowerShell 或 Git Bash 使用
- `cac.cmd` / `cac.ps1` 自动查找 Git Bash，并委托给 Bash 主实现
- 通过 `scripts/install-local-win.ps1` 注册本地 checkout 的 `cac` 命令
- 初始化后生成 `%USERPROFILE%\.cac\bin\claude.cmd`
- Windows 下环境 clone 默认使用复制模式，避免 NTFS 符号链接权限问题

完整的上游式跨平台 README 已归档到 [docs/original-readme.md](docs/original-readme.md)。其中的 npm 安装/更新说明只适用于上游包，不代表本仓库已发布到 npm。

> **版本号说明**：`package.json`、`src/utils.sh:CAC_VERSION` 和构建产物 `cac` 内嵌的版本号通过 CI 强制一致。本 fork 不发布到 npm registry —— 安装方式仅限本地 clone（见上文）。`-win.N` 后缀表示这是 Windows fork 在某个上游版本基础上的累计修订。

## 前置要求

- Windows 10/11
- Git for Windows，必须包含 Git Bash
- Node.js 18+，并确保 npm 在 PATH 中
- PowerShell 5.1+

## 本地安装

```powershell
git clone https://github.com/Cainiaooo/cac-win.git
cd cac-win

# 安装当前 checkout 的本地依赖
npm install

# 把当前 checkout 注册为全局 cac 命令
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1
```

安装完成后，重新打开 CMD、PowerShell 或 Git Bash，再验证：

```powershell
cac -v
cac help
```

如果提示找不到 `cac`，检查 npm 全局 bin 目录是否在用户 PATH 中：

```powershell
npm prefix -g
```

常见路径是 `%APPDATA%\npm`。安装脚本会自动尝试写入用户 PATH，并适配 nvm-windows / fnm / volta 等 Node.js 管理器；如果当前终端没有刷新，重开终端后再试。

## 快速开始

> **只想快速用起来？** 安装好之后只需两行：
> ```powershell
> cac claude install latest
> cac env create main -p 127.0.0.1:7897
> ```
> 然后跳到 [日常使用](#日常使用) 看每天怎么操作。下面场景按需查阅，不需要全看。

在使用 cac 之前，先理解两个概念：

- **环境（env）**：一组隔离的配置，包括代理、Claude Code 版本、设备指纹、`.claude` 配置目录。每个环境互不干扰。
- **版本（version）**：cac 托管的 Claude Code 二进制，存放在 `~/.cac/versions/`，多个环境可以共享同一个版本。

下面按常见场景介绍如何创建环境，可以按需跳读：

| 场景 | 适合谁 | 
|:--|:--|
| [A：只要隔离，不要代理](#场景-a只要环境隔离不需要代理) | 不走代理、只做配置隔离 |
| [B：需要代理](#场景-b需要通过代理连接-anthropic-api) | 用了 Clash/V2Ray 等本地代理 |
| [C：多套独立配置](#场景-c多个环境各自独立配置-clone-与-no-link) | 需要不同 skills/hooks/settings |
| [D：始终用最新版](#场景-d希望环境始终使用最新-claude-code) | 不想手动管版本 |
| [E：固定版本](#场景-e固定使用某个-claude-code-版本) | 需要稳定、不升级 |

### 场景 A：只要环境隔离，不需要代理

只是想隔离 `.claude` 配置、设备指纹，让不同用途（个人/工作）的 Claude Code 互不干扰：

```powershell
# 第一次使用，先安装 Claude Code
cac claude install latest

# 创建环境（不带 -p，不配置代理）
cac env create personal

# 创建第二个环境
cac env create work

# 切换到 personal 环境
cac personal

# 启动 Claude
claude
```

创建环境时如果不指定版本，会自动安装最新版。

### 场景 B：需要通过代理连接 Anthropic API

最常见的场景：本地跑了 Clash Verge，监听 `127.0.0.1:7897`，想让 Claude Code 走这个代理：

```powershell
# 用 Clash Verge 的本地 HTTP 代理端口
cac env create main -p 127.0.0.1:7897

# 或者同时指定 Claude 版本
cac env create main -p 127.0.0.1:7897 -c 2.1.81
```

代理格式支持多种写法（详见 [代理格式](#代理格式)）：

```powershell
# 带认证的代理
cac env create work -p 1.2.3.4:1080:username:password

# SOCKS5 代理
cac env create work -p socks5://127.0.0.1:1080

# HTTP 代理（显式指定协议）
cac env create work -p http://127.0.0.1:7897
```

**代理端口变化了怎么办？** 不需要重建环境，直接修改：

```powershell
# 比如 Clash Verge 端口从 7897 改成了 7890
cac env set main proxy 127.0.0.1:7890

# 临时不想走代理了
cac env set main proxy --remove
```

### 场景 C：多个环境各自独立配置（--clone 与 --no-link）

`--clone` 控制环境是否继承宿主 `~/.claude` 的已有配置（commands、hooks、skills、plugins、settings 等）。默认情况下（不加 `--clone`），每个环境从**空白 `.claude` 目录**开始，完全独立。

| 行为 | 默认（不加 `--clone`） | `--clone` | `--clone --no-link` |
|:--|:--|:--|:--|
| `.claude/` 配置来源 | 空白，独立创建 | 从宿主 `~/.claude` 继承 | 从宿主 `~/.claude` 继承 |
| 配置联动 | 无（独立） | 链接模式，宿主改 → 环境自动同步 | 复制独立副本，宿主改 → 环境不变 |

> **注意**：Windows 上 cac 不会尝试创建符号链接，即使只写 `--clone`，也会自动走复制模式，效果等同 `--clone --no-link`（代码在 MINGW/MSYS/CYGWIN 下强制 `clone_link=false`）。

```powershell
# 继承宿主 ~/.claude 的配置（macOS/Linux 上会保持联动）
cac env create work --clone

# 复制一份完全独立的配置（Windows 默认行为）
cac env create work --clone --no-link

# 从已有环境 clone 配置
cac env create work2 --clone work
```

**什么时候用 `--no-link`？**
- 你想用完全不同的 `.claude` 配置（不同的 hooks、skills、settings）
- 你希望环境不受宿主或 cc-switch 等工具的配置改动影响
- 你在 Windows 上（本身就是默认行为）

**什么时候用 `--clone`？**
- 你用了 cc-switch 管理账号/API，希望切换后环境自动跟随
- 你有统一的 skills/hooks 想在所有环境间共享
- 你在 macOS/Linux 上

### 场景 D：希望环境始终使用最新 Claude Code

```powershell
# 创建时加 --autoupdate，每次激活环境时提示是否有新版本
cac env create main -p 127.0.0.1:7897 --autoupdate

# 也可以在已有环境上开启
cac env set main autoupdate on

# 关闭自动检查
cac env set main autoupdate off
```

激活环境时（`cac main`），如果远端有新版本，cac 会提示你是否更新。

### 场景 E：固定使用某个 Claude Code 版本

```powershell
# 创建时指定版本
cac env create legacy -c 2.1.81

# 已有环境绑定到指定版本
cac env set legacy version 2.1.81

# 更新到最新版
cac claude update legacy
```

> 场景速览结束。**已经知道怎么创建环境了？** 直接看 [日常使用](#日常使用) 和 [故障排查](#故障排查)。

## 核心概念

### 代理格式

cac 支持以下代理格式，都会自动检测协议类型：

| 格式 | 示例 | 说明 |
|:--|:--|:--|
| `host:port` | `127.0.0.1:7897` | 自动检测协议，默认 http |
| `host:port:user:pass` | `1.2.3.4:1080:admin:1234` | 带认证 |
| `http://host:port` | `http://127.0.0.1:7897` | 显式 HTTP |
| `http://user:pass@host:port` | `http://admin:1234@1.2.3.4:1080` | 带认证的 HTTP |
| `socks5://host:port` | `socks5://127.0.0.1:1080` | SOCKS5 |
| `socks5://user:pass@host:port` | `socks5://admin:1234@1.2.3.4:1080` | 带认证的 SOCKS5 |

### 环境做了什么？

每个 cac 环境在 `~/.cac/envs/<name>/` 下保存了一组文件：

```
~/.cac/envs/main/
├── .claude/          ← 独立的 CLAUDE_CONFIG_DIR
├── proxy             ← 代理地址
├── version           ← 绑定的 Claude Code 版本
├── uuid / machine_id / hostname / mac_address  ← 随机生成的设备指纹
├── tz / lang         ← 从代理 IP 地理检测的时区和语言
├── client_cert.pem / client_key.pem  ← mTLS 客户端证书
└── telemetry_mode    ← 遥测阻断策略
```

激活环境（`cac main`）后，运行 `claude` 会：

1. 把 `~/.cac/bin/claude` wrapper 注入到 PATH
2. wrapper 读取当前环境的配置
3. 设置遥测阻断环境变量（12 个）
4. 注入 `fingerprint-hook.js` 和 `cac-dns-guard.js`（通过 `NODE_OPTIONS`）
5. 把 Claude Code 的配置目录指向环境独立的 `.claude/`
6. 启动对应版本的 claude 二进制

### 配置 clone 机制

`--clone` 控制环境是否继承宿主 `~/.claude` 的已有配置。三种模式对比：

```
不加 --clone（默认，空白模式）
  宿主 ~/.claude/commands/       环境 ~/.cac/envs/work/.claude/commands/
  各自独立，环境从空白开始

--clone（链接模式，macOS/Linux）
  宿主 ~/.claude/commands/  ←──  环境 ~/.cac/envs/work/.claude/commands/
  宿主改了 commands → 环境自动同步

--clone --no-link（复制模式，Windows 默认）
  宿主 ~/.claude/commands/       环境 ~/.cac/envs/work/.claude/commands/
  创建时复制一份，后续各自独立
```

settings.json 的处理更细致：cac 会在基础 settings 上叠加环境专属配置（如 statusline），不会直接覆盖。

## 日常使用

### 每天最常用的几条

```powershell
cac main          # 激活主环境
cac env check     # 检查环境状态（代理是否通、指纹是否生效）
claude            # 启动 Claude Code
cac env ls        # 看看有哪些环境
cac env stop      # 暂停 cac 注入，恢复原生 Claude Code
```

> **激活是持久化的**：`cac <name>` 激活环境后，cac 注入会一直生效——关闭终端、重启电脑都不会自动取消。之后每次运行 `claude` 都会经过 cac wrapper。如果想恢复原生 Claude Code（不带任何注入），需要执行 `cac env stop`。

### 管理环境

```powershell
# 创建环境
cac env create <name> [-p <proxy>] [-c <version>] [--clone] [--no-link] [--autoupdate]

# 切换环境
cac <name>

# 查看环境列表（▶ 表示当前激活）
cac env ls

# 修改当前环境的代理
cac env set proxy 127.0.0.1:7890
cac env set proxy --remove               # 移除代理

# 修改指定环境的版本
cac env set work version 2.1.81

# 删除环境
cac env rm work
```

### 管理 Claude Code 版本

```powershell
# 安装
cac claude install latest                # 最新版
cac claude install 2.1.81                # 指定版本

# 查看已安装版本
cac claude ls

# 将当前环境更新到远端最新版
cac claude update                        # 更新当前环境
cac claude update work                   # 更新指定环境

# 审计当前或指定 Claude Code 版本的 provider-routing 风险状态
cac claude audit current
cac claude audit 2.1.196

# 清理未被任何环境使用的版本
cac claude prune
cac claude prune --yes                   # 直接删除

# 卸载指定版本
cac claude uninstall 2.1.81
```

### 检查环境

```powershell
cac env check          # 快速检查
cac env check -d       # 详细检查（显示所有指纹、DNS、mTLS 状态）
```

检查项目包括：wrapper 是否激活、遥测是否阻断、设备指纹是否 spoof、IPv6 是否泄露、代理是否可达、出口 IP、TUN 冲突检测。

### 故障排查

| 问题 | 原因 | 解决 |
|:--|:--|:--|
| `which claude` 不是 `~/.cac/bin/claude` | PATH 顺序不对 | 重开终端，确认 `~/.cac/bin` 在 PATH 最前面 |
| `claude` 提示找不到命令 | 没激活环境 | 先执行 `cac <name>` 激活 |
| `cac env check` 代理不通 | 代理未启动或端口变了 | 确认 Clash/V2Ray 正在监听，用 `cac env set` 更新端口 |
| 代理协议检测失败 | cac 自动检测不准确 | 显式指定协议：`cac env set proxy http://127.0.0.1:7897` |
| IPv6 泄露警告 | 系统有 IPv6 公网地址 | 在网卡设置中关闭 IPv6，或代理软件中加 IPv6 规则 |
| TUN 冲突 | Clash/sing-box TUN 模式拦截了代理流量 | 在代理软件中给代理服务器 IP 加 DIRECT 规则 |
| 重启后 `claude` 仍然走 cac | cac 激活是持久化的 | 执行 `cac env stop` 暂停注入 |
| 环境配置总被外部改动覆盖 | 创建时没加 `--no-link`，配置与宿主联动 | 重新创建环境并加 `--clone --no-link`，或用 `cac env detach <name>` 断开现有链接 |

## 高级用法

### 遥测阻断模式

三种模式控制遥测阻断的力度：

```powershell
# stealth（默认）：只阻断 1p_events，功能正常
cac env create main --telemetry stealth

# paranoid：阻断所有遥测，部分功能可能受限（如 /bug 命令）
cac env create main --telemetry paranoid

# transparent：不阻断，所有遥测正常上报
cac env create main --telemetry transparent
```

### Provider routing and signal guard

cac can manage local Claude Code launch signals: shell environment variables, the per-env `.claude` settings directory, timezone/locale runtime hooks, and whether the wrapper warns or blocks before starting Claude. It cannot control Anthropic account status, payment signals, OAuth state, IP reputation, or any provider-side routing decision.

Provider routing policy controls whether Claude can see custom provider endpoint/auth variables such as `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, Bedrock/Vertex routing variables, and trace propagation flags:

```powershell
cac env set main provider-routing managed
cac env set main provider-routing warn
cac env set main provider-routing preserve
```

Defaults are conservative: proxy environments use `managed`; non-proxy environments use `warn` so API-key workflows keep working but remain visible in `cac env check`.

Signal guard controls launch-time handling:

```powershell
cac env set main signal-guard warn
cac env set main signal-guard strict
```

`warn` prints redacted key names and continues. `strict` blocks startup when local provider routing signals are visible in a risky combination, such as custom provider routing plus `Asia/Shanghai` or `Asia/Urumqi`, or provider routing keys inside Claude settings. Error output never includes secret values.

`cac env check -d` includes a `Signal guard` block with provider-routing policy, settings scan results, Node runtime timezone/locale probe, and a Bun probe when `bun` is available.

When cloning Claude settings, cac sanitizes provider routing keys by default:

```powershell
cac env create work --clone --sanitize-provider-routing
cac env create work --clone --preserve-provider-routing
```

The sanitize mode removes only known provider-routing key names from cloned `settings.json`; commands, agents, hooks, skills, plugins, and normal settings remain unchanged. Output shows key names only.

### Relay 模式（TUN 代理穿透）

当使用 TUN 模式代理（Clash TUN、sing-box 等）时，所有流量被虚拟网卡拦截，可能导致 cac 的代理配置无法正常工作。Relay 模式在本地启动一个 TCP 中继来解决这个问题。

```powershell
# 检查 relay 状态（TUN 冲突时自动提示）
cac env check

# 如果 check 提示 TUN 冲突，开启 relay
cac relay on

# 关闭 relay
cac relay off
```

### Persona（终端伪装）

主要用于 Docker/服务器环境，注入桌面终端环境变量来伪装成本地开发机：

```powershell
cac env set main persona macos-vscode
cac env set main persona --remove
```

可选值：`macos-vscode`、`macos-cursor`、`macos-iterm`、`linux-desktop`

### 手动设置时区/语言

默认情况下，创建环境时 cac 会根据代理出口 IP 自动检测时区和语言。你也可以手动覆盖：

```powershell
cac env set main tz Asia/Shanghai
cac env set main lang zh_CN.UTF-8
```

## 命令速查

| 命令 | 用途 |
|:--|:--|
| `cac env create <name> [-p proxy] [-c version] [--clone] [--no-link] [--autoupdate] [--telemetry mode]` | 创建并激活环境 |
| `cac <name>` | 切换到指定环境 |
| `cac env ls` / `cac ls` | 查看环境列表 |
| `cac env rm <name>` | 删除环境 |
| `cac env set [name] proxy <proxy>` | 设置环境代理 |
| `cac env set [name] proxy --remove` | 移除环境代理 |
| `cac env set [name] version <version>` | 切换环境绑定的 Claude Code 版本 |
| `cac env set [name] autoupdate <on\|off>` | 开启或关闭激活时的 Claude Code 更新检查 |
| `cac env set [name] telemetry <stealth\|paranoid\|transparent>` | 设置遥测阻断模式 |
| `cac env set [name] tz <timezone>` | 设置时区 |
| `cac env set [name] lang <locale>` | 设置语言 |
| `cac env detach <name>` | 断开 clone 链接，使环境配置独立 |
| `cac env check [-d]` / `cac check` | 检查当前环境 |
| `cac env stop` | 暂停 cac 注入，claude 原生运行 |
| `cac relay on\|off\|status` | 管理 TUN 穿透中继 |
| `cac claude install [latest\|<version>]` | 安装 Claude Code 版本 |
| `cac claude ls` | 查看已安装 Claude Code 版本 |
| `cac claude update [env]` | 将环境更新到远端最新 Claude Code |
| `cac claude audit [current\|<version>]` | 保守审计 Claude Code provider-routing 风险状态 |
| `cac claude prune [--yes]` | 列出或删除未被环境引用的 Claude Code 版本 |
| `cac claude uninstall <version>` | 卸载指定版本 |
| `cac self delete` | 删除 cac 运行目录、wrapper 和环境数据 |
| `cac -v` | 查看 cac 版本 |

## 更新本地安装

pull 新代码或移动仓库目录后，重新生成本地 shim：

```powershell
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

```powershell
# 1. 进入仓库目录，拉取最新代码
cd E:\Projects\cac-win
git pull
```

然后在 **Git Bash** 中执行：

```bash
# 2. 重新构建（必须在 Git Bash 中运行）
bash build.sh

# 3. 同步 JS 运行时文件（如果本次更新涉及 JS 文件修改）
cp fingerprint-hook.js relay.js cac-dns-guard.js ~/.cac/
```

最后重新激活环境，触发自动修复（如 mTLS 证书补全等）：

```powershell
# 4. 重新激活环境（会自动补全缺失的证书等）
cac <你的环境名>

# 5. 验证
cac env check -d
```

**不需要**删除任何已有文件、重新运行安装脚本或重新创建环境。已有的环境数据、身份信息、代理配置都会保留。

**常见问题**：

- **新命令/新选项不可用**（如 `--autoupdate` 提示 `unknown option`）：说明 `bash build.sh` 未执行或未成功，确认在 Git Bash 中重新运行。
- **mTLS 显示 `client cert not found`**：旧版本在 Windows 上因 OpenSSL 兼容问题未能生成证书。更新代码并 `bash build.sh` 后，重新激活环境即可自动补全（`cac <环境名>`）。
- **`bash build.sh` 报 WSL 错误**：系统把 `bash` 解析到了 WSL 而非 Git Bash。请直接在开始菜单打开 **Git Bash** 终端再执行命令。

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

本地 shim 会记录当前 checkout 路径；仓库位置变化后必须重新执行一次。

如果你是开发者并修改了 `src/`，还需要重新生成根目录脚本：

```bash
bash build.sh
```

如果本次更新涉及 JS 运行时文件修改（`src/fingerprint-hook.js`、`src/relay.js` 或 `src/dns_block.sh`），运行任意 cac 命令会触发同步到 `%USERPROFILE%\.cac`：

```powershell
cac env ls
```

> **Do I need to sync JS files?** Check `git log` or `git diff HEAD~1` — if only `src/*.sh` changed, no sync needed. If `src/fingerprint-hook.js`, `src/relay.js`, or `src/dns_block.sh` changed, sync is required.

### Quickstart

First, install a Claude Code version, then create an environment:

```powershell
# Install Claude Code
cac claude install latest

# Create an environment (no proxy)
cac env create personal

# Create an environment with proxy (e.g. Clash Verge on localhost:7897)
cac env create main -p 127.0.0.1:7897
```

Common scenarios:

```powershell
# Auto-update Claude on activation
cac env create main -p 127.0.0.1:7897 --autoupdate

# Pin to a specific version
cac env create legacy -c 2.1.81

# Clone host ~/.claude config (linked, macOS/Linux)
cac env create work --clone

# Independent copy of config (Windows default)
cac env create work --clone --no-link
```

### Proxy formats

| Format | Example |
|:--|:--|
| `host:port` | `127.0.0.1:7897` |
| `host:port:user:pass` | `1.2.3.4:1080:admin:1234` |
| `http://host:port` | `http://127.0.0.1:7897` |
| `http://user:pass@host:port` | `http://admin:1234@1.2.3.4:1080` |
| `socks5://host:port` | `socks5://127.0.0.1:1080` |
| `socks5://user:pass@host:port` | `socks5://admin:1234@1.2.3.4:1080` |

### Daily usage

```powershell
cac main              # Activate environment
cac env check         # Verify environment (proxy, fingerprint, telemetry)
claude                # Start Claude Code
cac env ls            # List environments
cac env stop          # Pause cac injection, run Claude natively
```

> **Activation is persistent**: Once you run `cac <name>`, the cac wrapper stays active across terminal sessions and reboots. Every `claude` invocation will go through cac until you explicitly run `cac env stop`.

### Modifying environments

```powershell
# Change proxy
cac env set main proxy 127.0.0.1:7890

# Remove proxy
cac env set main proxy --remove

# Change Claude version
cac env set main version 2.1.81

# Toggle auto-update
cac env set main autoupdate on
```

### Managing Claude Code versions

```powershell
cac claude install latest
cac claude install 2.1.81
cac claude ls
cac claude update work          # Update env to latest
cac claude audit current        # Conservative provider-routing risk audit
cac claude audit 2.1.196
cac claude prune --yes          # Remove unused versions
cac claude uninstall 2.1.81
```

### Environment check

```powershell
cac env check          # Quick check
cac env check -d       # Detailed check (fingerprints, DNS, mTLS)
```

### Telemetry modes

```powershell
# stealth (default): block 1p_events only
cac env create main --telemetry stealth

# paranoid: block all telemetry
cac env create main --telemetry paranoid

# transparent: no blocking
cac env create main --telemetry transparent
```

### Provider routing and signal guard

cac manages local Claude Code launch signals only: inherited environment variables, the per-env `.claude` settings directory, timezone/locale runtime hooks, and launch-time warnings or blocks. It cannot control account status, payment signals, OAuth state, IP reputation, or provider-side routing decisions.

Provider routing policy:

```powershell
cac env set main provider-routing managed   # hide provider routing env vars before launch
cac env set main provider-routing warn      # keep them, but report visible keys
cac env set main provider-routing preserve  # explicit opt-out from local management
```

Proxy environments default to `managed`. Non-proxy environments default to `warn` so API-key workflows keep working while `cac env check` still reports visible routing keys.

Signal guard:

```powershell
cac env set main signal-guard warn
cac env set main signal-guard strict
```

`warn` reports redacted key names and continues. `strict` blocks startup when provider routing signals are visible in high-risk local combinations or inside Claude settings. `cac env check -d` shows a `Signal guard` section with settings scan results and Node/Bun timezone probes.

Clone behavior:

```powershell
cac env create work --clone --sanitize-provider-routing
cac env create work --clone --preserve-provider-routing
```

Clone sanitization is the default. It removes known provider-routing key names from cloned `settings.json` without printing values.

### Relay mode (TUN proxy bypass)

```powershell
cac relay on           # Enable relay for TUN-mode proxy
cac relay off          # Disable
cac relay status       # Check status
```

### Updating an existing installation

If you already have cac installed with environments set up, the update process is:

```powershell
# 1. Navigate to the repo and pull latest
cd E:\Projects\cac-win
git pull
```

Then from **Git Bash**:

```bash
# 2. Rebuild (must run from Git Bash)
bash build.sh

# 3. Sync JS runtime files (only if this update changed JS files)
cp fingerprint-hook.js relay.js cac-dns-guard.js ~/.cac/
```

Finally, reactivate your environment to trigger auto-repair (e.g. mTLS cert backfill):

```powershell
# 4. Reactivate environment (auto-generates missing certs etc.)
cac <your-env-name>

# 5. Verify
cac env check -d
```

**No need** to delete any files, re-run the installer, or recreate environments. Existing environment data, identities, and proxy configs are preserved.

**Common issues**:

- **New commands/options not available** (e.g. `--autoupdate` shows `unknown option`): `bash build.sh` was not run or failed. Confirm it was run from Git Bash.
- **mTLS shows `client cert not found`**: Older versions failed to generate certs on Windows due to an OpenSSL compatibility issue. After updating and running `bash build.sh`, simply reactivate the environment to auto-generate the missing cert.
- **`bash build.sh` triggers WSL error**: Your system resolves `bash` to WSL instead of Git Bash. Open **Git Bash** from the Start Menu and run the command there.

### Uninstall

```powershell
# Delete cac runtime, wrappers, and environment data
cac self delete

# Remove global shim created by install-local-win.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1 -Uninstall
```

If `cac` is already unavailable, manually delete `%USERPROFILE%\.cac`, then run the `-Uninstall` command above from the repo root.

## Windows 注意事项

- `cac.cmd` 和 `cac.ps1` 需要能找到 Git Bash；如果启动失败，先确认 Git for Windows 安装完整。
- Windows 的指纹保护主要依赖 Node.js 层的 `fingerprint-hook.js`，用于拦截 `wmic`、`reg query`、`os.hostname()`、`os.networkInterfaces()` 等调用。
- Docker 模式需要原生 Linux；Windows 用户优先使用 `cac env`，确实需要 Docker 隔离时再考虑 WSL2 + Docker Desktop。
- 如果代理不处理 IPv6，建议在系统或网卡层面关闭 IPv6，避免真实 IPv6 出口泄露。

## 更多文档

- [完整 README 归档](docs/original-readme.md)
- [Windows 排障](docs/windows/troubleshooting.md)
- [Windows 测试指南](docs/windows/testing-guide.md)
- [Windows 已知问题](docs/windows/known-issues.md)
- [Windows IPv6 测试指南](docs/windows/ipv6-test-guide.md)
- [Windows 支持评估](docs/windows/windows-support-assessment.md)
- [上游文档站](https://cac.nextmind.space/docs)
