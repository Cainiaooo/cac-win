# Claude Code Agent View 代理绕过风险分析

> 记录时间：2026-05-12
> 状态：Open
> 范围：cac (全平台)、Claude Code v2.1.139 Agent View (`claude agents`) 功能
> 关联：[[proxy-mechanism-limitations]]
> 补充：代理凭据与环境变量泄露面见 `docs/windows/proxy-environment-leakage-analysis.md`
> 官方文档验证：2026-05-12 已逐条核对，见 [官方文档验证](#官方文档验证) 章节

## 背景

Claude Code v2.1.139 引入了 Agent View 功能（`claude agents` 命令），背后依赖一个 per-user **supervisor 进程**（daemon）来管理后台 session。用户通过 CAC wrapper 启动 Claude Code 时，CAC 会注入代理环境变量、指纹 hook、DNS guard 等；但 Agent View 的 supervisor 进程独立于终端生命周期，其环境变量继承链决定了代理是否持续生效。

本文档分析 supervisor/worker 架构下 CAC 代理被绕过的可能路径，以及当前实现的安全边界。

## Claude Code Agent View 架构概述

以下架构描述基于官方文档 [Agent View](https://code.claude.com/docs/en/agent-view) 和实际进程/文件系统观察。

### 进程层级

```
终端 (shell)
  └─ ~/.cac/bin/claude (CAC wrapper, bash 脚本)
       ├─ 设置 HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
       ├─ 设置 NODE_OPTIONS (fingerprint-hook.js + cac-dns-guard.js)
       ├─ 设置 CLAUDE_CONFIG_DIR (隔离的 .claude 目录)
       ├─ 启动 relay.js (本地 TCP 转发到上游代理，如需要)
       └─ exec → claude.exe (真实二进制)
            ├─ 交互式 session: 直接运行, 父进程为 terminal
            │   └─ /bg 后 → 转入 supervisor 管理
            └─ claude agents 或 --bg 模式:
                 └─ spawn → supervisor daemon (首次自动启动)
                      ├─ 状态文件: $CLAUDE_CONFIG_DIR/daemon/
                      │    ├─ daemon.status.json  (supervisorPid, workers)
                      │    ├─ daemon.log          (spawn/settle 事件)
                      │    └─ roster.json          (worker 列表)
                      └─ spawn → worker N (后台 session, 继承 supervisor env)
                           └─ spawn → sub-agents (继承 worker env)
```

### 关键特性（官方文档确认）

- **supervisor 独立于终端**："Background sessions are hosted by a per-user supervisor process, separate from your terminal and from agent view" ([Agent View docs](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted))
- **后台 session 的父进程是 supervisor**："Each background session is its own Claude Code process, parented to the supervisor rather than to your terminal" (同上)
- **supervisor 按需启动**："It starts automatically the first time you background a session or open agent view" (同上)
- **空闲时自动退出**："When every session has finished and no terminal is connected, the supervisor itself exits and starts again the next time you background a session or open agent view" (同上)
- **session 进程生命周期**：活跃或等待输入的 session 保持进程运行；"Once a session finishes and sits unattached for about an hour, the supervisor stops its process to free resources" (同上)
- **supervisor 自更新重启**："The supervisor watches the installed Claude Code binary on disk and restarts into the new version after the regular auto-updater replaces it" (同上)
- **状态持久化**：session 状态保存在 `$CLAUDE_CONFIG_DIR` 下，重启后从磁盘恢复
- **CLAUDE_CONFIG_DIR 多实例隔离**："If you set CLAUDE_CONFIG_DIR, the supervisor uses that directory instead of ~/.claude and runs as a separate instance with its own sessions" (同上)
- **可通过 `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` 全局禁用** supervisor 和 agent view 功能 ([Env Vars docs](https://code.claude.com/docs/en/env-vars))

### CAC 配置目录隔离

CAC 设置 `CLAUDE_CONFIG_DIR=$HOME/.cac/envs/<env>/.claude`，因此每个 CAC 环境拥有独立的 daemon 和相关状态：

| CAC 环境 | CLAUDE_CONFIG_DIR | daemon 路径 |
|----------|-------------------|-------------|
| `ds` | `~/.cac/envs/ds/.claude` | `~/.cac/envs/ds/.claude/daemon/` |
| `main` | `~/.cac/envs/main/.claude` | `~/.cac/envs/main/.claude/daemon/` |

**默认路径** `~/.claude/daemon/` 在不设置 `CLAUDE_CONFIG_DIR` 时使用，完全不受 CAC 管控。

## 代理环境变量继承链分析

### 正常路径：通过 CAC wrapper 启动

```text
1. 用户运行 `claude agents`
2. ~/.cac/bin/claude wrapper 设置:
   - HTTPS_PROXY=http://127.0.0.1:<relay_port>
   - HTTP_PROXY=http://127.0.0.1:<relay_port>
   - ALL_PROXY=http://127.0.0.1:<relay_port>
   - NODE_OPTIONS=--require fingerprint-hook.js --require cac-dns-guard.js
   - CLAUDE_CONFIG_DIR=~/.cac/envs/<env>/.claude
   - ... (12 个遥测屏蔽变量等)
3. exec → claude.exe agents (继承所有上述变量)
4. claude.exe 内部 child_process.spawn() → supervisor daemon (继承)
5. supervisor spawn → worker (继承)
```

**每一步都是 `process.env` 的继承传递，Node.js 的 `child_process.spawn()` 默认 `env: process.env`。经实际验证，当前运行的后台 worker 确实保留了 CAC 注入的 `NODE_OPTIONS` 和 `CLAUDE_CONFIG_DIR`。**

### 风险路径 1：绕过 wrapper 直接启动 Claude

```text
用户直接运行 ~/.cac/versions/2.1.139/claude.exe agents
  → CAC wrapper 不执行
  → 无代理 env vars 注入
  → supervisor 启动时无代理配置
  → 所有后台 session 直连 API (IP 泄露)
```

**触发条件**：
- 用户以绝对路径运行 `claude.exe`
- IDE 集成（VS Code / Cursor 插件）直接调用二进制
- 某些自动化脚本跳过 PATH 查找
- Windows 上通过 `claude.cmd` 以外的快捷方式启动

### 风险路径 2：默认 `~/.claude/daemon/` 残留

```text
历史上的某次直接运行 claude.exe（不经过 CAC）
  → 在 ~/.claude/daemon/ 创建了 supervisor 状态
  → 该 supervisor 无代理配置
  → 如果仍在运行，其 worker 直连 API
```

**实际发现**：在分析过程中，`~/.claude/daemon/roster.json` 存在且引用了 `supervisorPid: 35396`（当时进程已不存在），确认这一路径历史上发生过。

### 风险路径 3：Worker 不经 wrapper 重新初始化

当 supervisor 通过 CAC 启动（有代理），但后续 spawn 的 worker：

- **继承 supervisor 的 env vars** → 代理仍然生效
- **不重新执行 CAC wrapper 脚本** → 以下机制不会按 worker 重新运行：
  - relay 健康检查
  - relay 自动重启（watchdog）
  - proxy 可达性预检
  - telemetry_mode 重新评估

**影响**：代理仍路由，但 relay 进程崩溃后 worker 不会自动恢复。由于 relay 是 fail-closed 设计（代理指向 dead port → 连接拒绝），这不会导致 IP 泄露，但会导致 worker 功能不可用。

### 风险路径 4：代理配置变更后 supervisor 不更新

```text
1. cac main + claude agents → supervisor 启动，使用 main 环境的代理
2. cac env set main proxy http://127.0.0.1:9999 (更换代理)
3. 现有 supervisor 仍使用旧代理
4. 新 attach 的 session 仍继承旧代理
```

**supervisor 是长生命周期进程，其环境变量在启动时固化，不会随 CAC 环境配置更新而刷新。**

## 安全边界总结

### CAC 代理生效的必要条件

| 条件 | 满足时 | 不满足时 |
|------|--------|----------|
| supervisor 通过 CAC wrapper 启动 | 代理生效 | 代理不生效 (fail-open, 直连) |
| CLAUDE_CONFIG_DIR 指向隔离目录 | daemon 状态隔离 | 与默认 daemon 混淆 |
| PATH 中 `~/.cac/bin` 在最前 | `claude` 命令经 wrapper | 可能绕过 wrapper |
| relay 进程健康 | 代理正常转发 | fail-closed, 连接拒绝 |

### 已验证的安全属性

1. **env vars 继承可靠**：当前后台 session 确认保留了 CAC 注入的 `NODE_OPTIONS` 和 `CLAUDE_CONFIG_DIR`
2. **CAC 环境配置目录隔离有效**：不同环境有独立 daemon
3. **CAC wrapper 拒绝无环境启动**：`~/.cac/current` 不存在时退出并报错，防止意外绕过
4. **relay fail-closed**：relay 崩溃后代理连接拒绝，不会退化为直连
5. **默认 daemon 与 CAC daemon 不冲突**：`CLAUDE_CONFIG_DIR` 不同，各管各的

### 未覆盖的风险

1. **supervisor 初始启动路径不受后续验证**：CAC 无法检测 supervisor 是否由其启动
2. **默认 `~/.claude/daemon/` 不受 CAC 管控**：任何时候的 "裸" `claude.exe` 调用都可能在那里创建 supervisor
3. **supervisor 生命周期与代理配置不同步**：变更代理需手动重启 supervisor
4. **Worker 不经过 CAC wrapper 脚本**：wrapper 的预检和 relay 管理能力不适用于 worker

## 当前系统状态

> 以下状态来自 2026-05-12 实际检查。

| 项目 | 状态 |
|------|------|
| CAC 版本 | 1.5.8-win.5 |
| Claude Code 版本 | 2.1.139 |
| 当前环境 | `ds` (无代理) |
| `ds` daemon | 运行中, PID 58640, `CLAUDE_CONFIG_DIR=~/.cac/envs/ds/.claude` |
| `main` daemon | 未运行 (有代理配置 `http://127.0.0.1:7897`) |
| 默认 daemon (`~/.claude/daemon/`) | roster.json 存在但 supervisor 进程已停止 |
| PATH 顺序 | `~/.cac/bin` 在最前 |
| `NODE_OPTIONS` | fingerprint-hook.js + cac-dns-guard.js 已注入 |

## 建议的改进措施

### 短期（用户侧）

```bash
# 1. 清理默认 daemon 残留（确认无活跃进程后）
rm -rf ~/.claude/daemon/

# 2. 更换代理设置后重启 supervisor
#    supervisor 在对应 CAC env 中重新启动 claude agents 时会自动刷新

# 3. 确保始终通过终端 shell 运行 claude（不要用绝对路径）
#    验证：which claude 应该指向 ~/.cac/bin/claude
```

### 长期（cac 代码侧）

1. **daemon 路径监控**：`cac env check` 检测默认 `~/.claude/daemon/` 是否存在并告警
2. **supervisor 来源标记**：在 wrapper 中设置 `CAC_SUPERVISOR_ORIGIN=<env>` 环境变量，供诊断
3. **关闭前检查**：`cac stop` 或 `cac env activate <other>` 时提醒用户当前 env 的 supervisor 仍在运行
4. **代理变更后 supervisor 重启提示**：`cac env set main proxy <new>` 时检测对应 env 的 daemon 是否在运行，提示重启
5. **文档化**：在 README 和 Agent View 相关指南中说明代理 env vars 仅对通过 wrapper 启动的 supervisor 生效

## 实测验证

> 测试时间：2026-05-12
> 测试环境：cac 1.5.8-win.5 + Claude Code 2.1.139 + Windows 11

### 测试目标

验证后台 worker（通过 `claude --bg` 或 Agent View 派发的 session）的 API 请求是否经过 CAC 代理链路。

### 测试架构

```
测试代理 (127.0.0.1:18999, Node.js, 记录所有入站请求, 返回 502)
  ↑
CAC relay (127.0.0.1:1789x, 自动分配端口)
  ↑
Claude Code worker (后台 session, 由 supervisor spawn)
  ↑
supervisor daemon (由 claude.exe agents 首次启动)
  ↑
CAC wrapper (~/.cac/bin/claude, 设置 HTTPS_PROXY 等)
```

### 测试步骤

1. **搭建 dummy 代理**：Node.js `net.createServer` 监听 `127.0.0.1:18999`，记录所有入站 TCP 数据的首包内容（含 HTTP 请求行/头），返回 502
2. **创建隔离 CAC 环境**：`cac env create test-agentview -p http://127.0.0.1:18999 --clone ds`，从 `ds` 环境克隆 API 凭据（`ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`），配测试代理
3. **手动完成首次交互式 setup**：新环境首次启动时，CAC wrapper 因代理存在而 `unset ANTHROPIC_AUTH_TOKEN`，导致 worker 卡在启动对话框。需手动运行一次交互式 `claude` 完成设置向导
4. **派发后台任务**：`claude --bg "say hello world"` → session `06a73ee3` 被 supervisor 派发为后台 worker
5. **检查代理日志**：读取 `/tmp/proxy-test.log`，按 `X-Claude-Code-Session-Id` 匹配后台 worker 的请求

### 测试结果

**后台 worker 的 API 请求完整经过了代理链路。** 代理日志中 session `06a73ee3` 的请求示例：

```
[65] 2026-05-12T13:22:12.300Z [127.0.0.1:56377] POST http://10.70.174.231:9001/v1/messages?beta=true HTTP/1.1
Proxy-Connection: Keep-Alive
Authorization: Bearer sk-986af694...
User-Agent: claude-cli/2.1.139 (external, cli)
X-Claude-Code-Session-Id: 06a73ee3-bd2e-470a-bad3-33f98bebb89e
```

日志中共出现两个真实 session 的请求：

| Session ID | 来源 | 说明 |
|-----------|------|------|
| `81b59aea-...` | 用户手动 `claude` 交互式会话 | 完成首次 setup 向导 |
| `06a73ee3-...` | `claude --bg` 后台 worker | Agent View 派发的后台任务 |

两者均经过 `CAC wrapper → relay → test proxy` 完整链路。测试代理日志中没有出现任何不经过代理的直连请求。worker 因 test proxy 返回 502 而多次重试，每次重试都重新走代理。

### 验证结论

1. **env vars 继承链实测通过**：`wrapper → supervisor → worker` 的代理环境变量（`HTTPS_PROXY`）在整条进程树上可靠传递
2. **CAC relay 机制正常工作**：relay 按需启动、端口自动分配（17892 → 17897）、正确转发到上游代理
3. **agent view 不会绕过代理**：没有观测到任何绕过代理的直连请求

## 测试中发现的额外 Agent View 机制

### 发现 1：CAC wrapper 有代理时清除 API 凭据

`templates.sh` 第 396-399 行：

```bash
if [[ -n "$PROXY" ]]; then
    unset ANTHROPIC_BASE_URL
    unset ANTHROPIC_AUTH_TOKEN
    unset ANTHROPIC_API_KEY
fi
```

设计意图：有代理时强制走 OAuth 认证，防止 API Key 明文经过代理出口。但副作用是：对于使用自建 API 端点 + 自定义 Token 的环境（`ANTHROPIC_AUTH_TOKEN` 在 `settings.json` → `env` 中），wrapper 清除环境变量后，Claude Code 启动时从 `settings.json` 重新加载 `env` 段，凭据最终恢复可用。**但在首次启动时，如果启动对话框（Research Preview 条款等）在凭据恢复之前弹出，worker 会卡住等待交互式确认。**

### 发现 2：新环境首次后台启动必须交互式完成

全新 CAC 环境（尤其是配了代理的）不能直接用 `--bg` 完成首次启动。测试中尝试了以下方法均无效：
- 修改 `numStartups: 99`（跳过新手提示）
- 预置 `hasUsedAgentsFleet: true`
- 多次 respawn

最终需要用户在交互式 `claude` 中完成设置向导后，`--bg` worker 才能正常运行。这对纯自动化/headless 部署场景是一个限制。

### 发现 3：Stuck worker 在环境就绪后自动恢复

worker `06a73ee3` 最初状态为 `"stuck on a startup dialog"`。在用户完成交互式 setup 后，**同一个 worker 自动恢复执行**，开始发起 API 调用。这说明 worker 进程未被杀死，而是在阻塞等待某个条件（设置完成）后自行继续。

### 发现 4：Relay 端口动态分配

CAC relay 从 17890 开始扫描可用端口（`tcp_check`），测试中观察到 relay 使用过 `17892` 和 `17897`。每次 wrapper 启动时如果 relay 不在运行，都会重新分配端口。relay 状态文件（`~/.cac/relay.*`）是**全局共享**的（非 per-env），多个环境切换时可能产生端口冲突。

### 发现 5：Worker 的 API 请求类型

测试代理日志显示两种请求模式：
- **HTTP 代理请求**（`POST http://api-endpoint/... HTTP/1.1`）：用于 HTTP API 端点（如 `http://10.70.174.231:9001`）。请求行包含完整 URL，不走 CONNECT 隧道
- **CONNECT 隧道**（`CONNECT api.githubcopilot.com:443 HTTP/1.1`）：用于 HTTPS 端点（如 GitHub Copilot 插件市场）。先建立 TCP 隧道，再在隧道内进行 TLS 握手

## 官方文档验证

以下逐条列出本文档的架构推断与官方文档的对应关系。验证时间：2026-05-12。

### 官方文档直接确认的推断

| 本文档推断 | 官方文档原文 | 来源 |
|-----------|-------------|------|
| supervisor 独立于终端，后台 session 不依赖终端运行 | "Background sessions don't need any terminal open to keep working. A separate supervisor process runs them" | [Agent View](https://code.claude.com/docs/en/agent-view#monitor-sessions-with-agent-view) |
| 后台 session 的父进程是 supervisor | "Each background session is its own Claude Code process, parented to the supervisor rather than to your terminal" | [Agent View](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted) |
| supervisor 按需首次自动启动 | "It starts automatically the first time you background a session or open agent view" | [Agent View](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted) |
| supervisor 空闲时自动退出 | "When every session has finished and no terminal is connected, the supervisor itself exits" | [Agent View](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted) |
| session 闲置约 1 小时后进程被回收 | "Once a session finishes and sits unattached for about an hour, the supervisor stops its process to free resources" | [Agent View](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted) |
| CLAUDE_CONFIG_DIR 使 daemon 实例隔离 | "If you set CLAUDE_CONFIG_DIR, the supervisor uses that directory instead of ~/.claude and runs as a separate instance with its own sessions" | [Agent View](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted) |
| daemon 状态文件路径 | `~/.claude/daemon.log`, `~/.claude/daemon/roster.json`, `~/.claude/jobs/<id>/state.json` | [Agent View](https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted) |
| 后台 session 的 settings 和 permission 从运行目录读取 | "A dispatched session reads its settings and permission mode from the directory it runs in" | [Agent View](https://code.claude.com/docs/en/agent-view#permission-mode-and-settings) |
| 非 git 仓库下 worktree 写入隔离不生效 | "The block doesn't apply when... the working directory isn't a git repository" | [Agent View](https://code.claude.com/docs/en/agent-view#how-file-edits-are-isolated) |
| `claude agents` 和 `/agents` 是不同的功能 | "Despite the similar name, this is separate from claude agents" | [Parallel Agents](https://code.claude.com/docs/en/agents#check-on-running-work) |

### 基于 OS 行为推断、官方文档未明确说明的部分

以下判断基于 Unix/Windows 进程模型（`child_process.spawn()` 默认继承 `process.env`），官方文档未直接说明，但原理上是确定的：

| 本文档推断 | 推断依据 |
|-----------|---------|
| supervisor 继承 CAC wrapper 的 env vars | Node.js `child_process.spawn()` 默认 `env: process.env`；supervisor 由 wrapper-exec'd 的 claude.exe 进程 spawn |
| worker 继承 supervisor 的 env vars | 同上；worker 由 supervisor spawn |
| supervisor 不重新执行 wrapper 脚本 | supervisor 是 claude.exe 的子进程，不经过 shell；由 Node.js 直接 spawn |
| supervisor 自更新重启时 env vars 仍保留 | `child_process.spawn()` 行为一致；但需确认 Claude Code 的更新重启实现是否使用 `process.execPath` 或绝对路径 |

### 官方文档暴露的新关注点

以下是从官方文档中新发现、值得关注的细节：

1. **supervisor 二进制热更新重启**："The supervisor watches the installed Claude Code binary on disk and restarts into the new version after the regular auto-updater replaces it" — 这意味着 supervisor 可能在**运行时被替换为新版本二进制**。如果更新后的二进制行为不同（例如不再遵守 `HTTP_PROXY`），将产生新的代理绕过风险。不过 CAC 默认设置 `DISABLE_AUTOUPDATER=1`，已经阻止了自动更新。

2. **`CLAUDE_CODE_DISABLE_AGENT_VIEW=1`**：可在 CAC wrapper 中按需注入此变量，使特定环境完全禁用 Agent View 功能。对于高安全需求的环境（如必须强制代理的环境），这是一个可选的"硬关闭"手段。

3. **supervisor 并非始终运行**：与最初印象不同，supervisor 在所有 session 完成且无终端连接后会**自行退出**。这意味着：
   - 每次打开 `claude agents` 时，supervisor 可能被重新创建
   - 如果某次 supervisor 由非 CAC 路径创建，它退出后下一次通过 CAC wrapper 创建的新 supervisor 会恢复正确的代理配置
   - **这对于代理绕过风险是一个缓解因素**——错误的 supervisor 不会永久存在

## 复测补充（2026-05-12 第二轮）

> 测试时间：2026-05-12 21:54-22:06 UTC+8
> 测试环境：cac 1.5.8-win.5 + Claude Code 2.1.139 + Windows 11
> 测试环境名：`test-av`（从默认 `~/.claude` 克隆，代理设置为 `http://127.0.0.1:18999`）
> 复测者：与首次调研不同的 Agent，独立复测

### 复测方法

1. 搭建 Node.js 测试代理（`E:\tmp\test-proxy.js`），监听 `127.0.0.1:18999`，记录所有入站 TCP 连接首包，额外标记空连接（无数据收到）
2. `cac env create test-av -p http://127.0.0.1:18999 --clone host` 创建隔离环境
3. 注入 ds 环境的 API 凭据（`ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`）到 `settings.json → env`
4. 用户交互式完成首次 setup
5. `claude --bg "say hello world, this is a background test"` 派发后台 worker
6. 分析代理日志 + 收集进程树、daemon roster、relay 状态等诊断信息

### 核心结论再次确认

后台 worker `300bc193` 的所有 API 请求完整经过代理链路。代理日志中 session `300bc193-1428-4783-97ea-15fe2e8be3c9` 共 22 条 POST，全部通过 `wrapper → relay (17899) → test proxy (18999)`，无直连泄漏。

### 补充发现 1：`x-app: cli-bg` header

后台 worker 请求中包含 `x-app: cli-bg`，这是区分交互式/后台请求的可靠标识。首次报告中注意到 User-Agent 中 `sdk-cli` vs `cli` 的差异，但 `x-app` header 是更准确的来源标记。

### 补充发现 2：两种 `anthropic-beta` header 变体

worker 的 POST 请求交替使用两种 `anthropic-beta` 值：

| 变体 | 特征 beta flags | Content-Length | 推测用途 |
|------|----------------|---------------|---------|
| A（主请求） | `claude-code-20250219`, `context-1m-2025-08-07`, `effort-2025-11-24` | 135138 | 完整 context 对话请求 |
| B（轻量请求） | `structured-outputs-2025-12-15` | 1521 | tool use / structured output |

11 条 A + 11 条 B，完全成对出现，每次重试都是一对。

### 补充发现 3：空连接之谜已解 — relay heartbeat

`relay.js:48-68` 实现了 30 秒间隔的 heartbeat，直接 TCP 连接到上游代理检查可达性。连接后立即 `sock.destroy()`，不发送数据。在 test proxy 侧表现为 "empty connection"。

```javascript
// relay.js lines 46-70
var HEARTBEAT_INTERVAL = 30000; // 30s
function heartbeat() {
  var sock = net.connect({ port: upstreamPort, host: upstreamHost, timeout: HEARTBEAT_TIMEOUT });
  sock.on('connect', function() { _upstreamHealthy = true; sock.destroy(); });
  // ...
}
setInterval(heartbeat, HEARTBEAT_INTERVAL);
```

这解释了首次报告中观察到但未分析的空连接（日志条目 `[3]`, `[48]`, `[63]`）。

### 补充发现 4（重大 Bug）：Relay 进程泄漏

复测中发现 **10 个 relay 实例同时运行**，占用端口 17890-17899：

| PID | Port | Upstream Proxy | 创建时间 | 来源环境 |
|-----|------|----------------|---------|---------|
| 36932 | 17890 | 127.0.0.1:7897 | May 11 20:51 | main |
| 53120 | 17891 | 127.0.0.1:7897 | May 12 12:16 | main |
| 35276 | 17893 | 127.0.0.1:7897 | May 12 16:39 | main |
| 56840 | 17894 | 127.0.0.1:7897 | May 12 17:32 | main |
| 4872 | 17892 | 127.0.0.1:18999 | May 12 21:08 | test-av |
| 24744 | 17895 | 127.0.0.1:18999 | May 12 21:12 | test-av |
| 42056 | 17896 | 127.0.0.1:18999 | May 12 21:20 | test-av |
| 46352 | 17897 | 127.0.0.1:18999 | May 12 21:22 | test-av |
| 41788 | 17898 | 127.0.0.1:18999 | May 12 21:58 | test-av |
| **33140** | **17899** | **127.0.0.1:18999** | **May 12 21:59** | **当前活跃** |

**根因**：`relay.pid` / `relay.port` / `relay.proxy` 是全局单文件（`~/.cac/relay.*`）。每次 wrapper 启动新 relay 时写入新 PID 覆盖旧值。旧 relay 进程失去 PID 文件引用，成为孤儿进程永远运行。每个孤儿 relay 每 30 秒向上游代理发一次 heartbeat，产生大量空连接。

**影响**：
- 每个孤儿 relay 独立占用一个端口（17890-17999 范围）
- 10 个 relay × 30s heartbeat = 每 3 秒一次空连接到上游代理
- 端口耗尽风险：端口范围仅 110 个（17890-17999）
- 内存泄漏：每个 relay 是独立 node 进程

**修复**：见 commit（改为基于端口复用的检测机制，防止新 relay 启动时累积孤儿）。

### 补充发现 5：CAC wrapper IP 检测请求经过代理

代理日志中观察到 wrapper 的 curl 请求也通过了代理（User-Agent: `curl/8.12.1`）：

| 时间 | 请求 | 用途 |
|------|------|------|
| 13:55:15 | `GET http://ip-api.com/json/?fields=timezone,countryCode` | 环境创建时时区检测 |
| 13:57:51 | `GET http://ip-api.com/json/?fields=query,timezone` | 环境激活时 IP+时区检测 |
| 13:57:51 | `CONNECT api.ip.sb:443` / `api.ipify.org:443` / `ipinfo.io:443` | `cac env check` IP 验证 |

说明 `cac env check` 的 IP 验证请求本身也经过代理链路。

### 补充发现 6：Supervisor "no token found" 行为

```
[supervisor] auth: no token found, will re-check keychain every 30s
```

Supervisor 检测不到 API token（wrapper 在有代理时 `unset ANTHROPIC_AUTH_TOKEN`），但 worker 仍然能正常发送请求（token 来自 `settings.json → env` 重新加载）。说明 supervisor 和 worker 的凭据来源不同：supervisor 查 OAuth/keychain，worker 读 settings.json。

### 补充发现 7：dispatch.env 只传递 CLAUDE_CONFIG_DIR

Roster 中 `dispatch.env` 仅包含：

```json
{"CLAUDE_CONFIG_DIR": "C:/Users/Admin/.cac/envs/test-av/.claude"}
```

代理相关变量（`HTTPS_PROXY` 等）不在 dispatch.env 中，通过 supervisor 进程的 `process.env` 继承给 worker。dispatch.env 是增量覆盖，代理传递靠进程树继承。

### 补充发现 8：Watchdog PID 在 Bash/WMI 间不一致

`relay.watchdog.pid` 记录 PID 44508，bash `kill -0` 报告存活，但 WMI `Get-CimInstance Win32_Process` 查不到。这是 MSYS2/Git Bash 的 PID 命名空间差异——watchdog 是 bash 后台子 shell，使用 POSIX PID，不是独立的 Windows 进程。

### 对首次报告风险路径 3 的修正

首次报告声称"relay 进程崩溃后 worker 不会自动恢复 ... 导致 worker 功能不可用"。

复测发现 wrapper 在启动 relay 时同时 spawn 了一个独立的 **watchdog 后台进程**（`templates.sh:581-618`），每 5 秒检查 relay 状态并自动重启。watchdog 由 wrapper 启动后被 `disown`，独立运行。只要 watchdog 存活，relay 崩溃后**会被自动恢复**。

真正的风险应修正为：**如果 watchdog 本身死亡（例如 bash 进程被杀）且没有新的 wrapper 启动来重新创建 watchdog，则 relay 崩溃后 worker 会 fail-closed**。

### 更新的系统状态

> 以下状态来自 2026-05-12 第二轮测试。

| 项目 | 状态 |
|------|------|
| CAC 版本 | 1.5.8-win.5 |
| Claude Code 版本 | 2.1.139 |
| 测试环境 | `test-av`（从默认 ~/.claude 克隆，代理 http://127.0.0.1:18999） |
| `test-av` daemon | supervisor PID 12996, worker PID 58760 |
| Relay 活跃进程数 | **10 个**（端口 17890-17899 全部占用） |
| Relay 当前活跃 | PID 33140, port 17899 → upstream 127.0.0.1:18999 |
| Watchdog PID | 44508 (bash POSIX PID, WMI 不可见) |
| 默认 daemon (`~/.claude/daemon/`) | supervisor PID 35396 已停止 |

## 参考

- Claude Code Agent View 官方文档: https://code.claude.com/docs/en/agent-view
- Claude Code Parallel Agents: https://code.claude.com/docs/en/agents
- Claude Code Environment Variables: https://code.claude.com/docs/en/env-vars
- CAC wrapper 源码: `src/templates.sh` `_write_wrapper()`
- CAC relay 机制: `src/relay.js`, `src/cmd_relay.sh`
- [[proxy-mechanism-limitations]] — cac 代理机制其他已知缺陷
