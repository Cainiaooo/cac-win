# Provider Routing / Signal Guard 变更说明

> 日期：2026-07-03
> 对应提交：`cb16864 fix(security): guard provider routing signals`
> 面向对象：已经通过本地 checkout 使用 `cac-win` 的 Windows 用户和维护者

## 背景

近期旧版 Claude Code 曾公开暴露 provider routing / timezone 信号被编码进 prompt 上下文的风险。上游最新 Claude Code 已修复对应问题，但 `cac-win` 仍加入本地防护和审计能力，目标是防止旧版本、未来回归或自定义 provider 配置再次出现同类风险。

这次更新不承诺改变任何 Anthropic 或第三方 provider 的服务端决策，也不会绕过账号、支付、OAuth、IP 信誉或 provider 侧策略。它只管理本地 wrapper 启动前后可见的环境变量、settings key、timezone/locale runtime 表现和诊断输出。

## 更新了什么

### 1. Provider routing 策略

新增环境配置：

```bash
cac env set [name] provider-routing <managed|warn|preserve>
```

策略含义：

| 模式 | 行为 |
|---|---|
| `managed` | Claude 启动前隐藏已知 provider routing / credential 环境变量。 |
| `warn` | 保留用户变量，但在 wrapper / `cac env check` 中报告可见 key 名。 |
| `preserve` | 明确选择退出本地 provider routing 管理，保留用户配置。 |

默认值：

- 有 proxy 的环境默认 `managed`。
- 无 proxy 的环境默认 `warn`。

如果已有环境没有 `provider_routing` 文件，也会按上述规则得到默认行为。

### 2. Signal guard

新增环境配置：

```bash
cac env set [name] signal-guard <warn|strict>
```

默认是 `warn`。`warn` 只提示，不阻止启动。`strict` 会在以下高风险本地信号可见时阻止 Claude 启动：

- provider routing / credential 环境变量在子进程中可见；
- 受管或 host Claude settings 中包含 provider routing key；
- 自定义 provider routing 与 `Asia/Shanghai` 或 `Asia/Urumqi` timezone 同时可见，且 policy 不是 `preserve`。

所有提示只输出 key 名，不输出 secret 值。

### 3. `cac env check` 新增 `Signal guard` 区块

`cac env check` 和 `cac env check -d` 会显示独立的 `Signal guard` 区块，包含：

- provider-routing policy；
- settings scan 结果；
- Node Intl timezone/locale probe；
- Bun Intl timezone/locale probe，未安装 Bun 时明确显示 skip；
- custom provider routing + China timezone 组合风险提示。

### 4. Settings scanner

现在会扫描以下文件中的 provider routing key：

```text
$env_dir/.claude/settings.json
$env_dir/.claude/settings.local.json
$env_dir/.claude/settings.override.json
$HOME/.claude/settings.json
$HOME/.claude/settings.local.json
$HOME/.claude.json
```

扫描结果区分 `routing`、`credential`、`provider-mode`、`trace-propagation`。诊断和日志只显示文件路径、key 名和类别，不显示值。

### 5. Clone 默认清理 provider routing key

从 host `.claude` 或其他环境 clone 配置时，provider routing key 默认会被 sanitize：

```bash
cac env create work --clone --sanitize-provider-routing
```

如果你确实需要保留这些 key，需要显式声明：

```bash
cac env create work --clone --preserve-provider-routing
```

保留模式会让 provider routing policy 进入 `preserve`，除非你另行指定 policy。

### 6. Claude Code 版本审计

新增命令：

```bash
cac claude audit current
cac claude audit 2.1.196
```

当前实现是保守版本范围审计：

- `2.1.91` 到 `2.1.196` 输出 `needs review`；
- 其他版本输出 `unknown`；
- 不会输出“known safe”这类假安全状态。

## 已有用户如何更新

本 fork 不发布到 npm。不要使用 `npm install -g claude-cac` 更新本仓库；那会安装上游包，不是当前 Windows fork。

在 PowerShell 或 CMD 中进入本地仓库：

```powershell
cd D:\Projects\cac-win
git pull
```

然后在 Git Bash 中重新生成根 `cac`：

```bash
bash build.sh
```

如果你的系统把 `bash` 解析到 WSL，而不是 Git Bash，请直接打开 Git Bash，或使用完整路径：

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -lc 'bash build.sh'
```

之后运行任意 `cac` 命令即可触发初始化自愈，刷新 `~/.cac/bin/claude` wrapper 和运行时文件：

```powershell
cac env ls
cac env check -d
```

不需要删除 `~/.cac`，不需要重新创建环境，也通常不需要重新运行 `scripts/install-local-win.ps1`。只有当你移动了仓库目录、全局 `cac` 命令找不到，或 shim 指向了旧 checkout 时，才需要重新运行安装脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-local-win.ps1
```

## 更新后建议做什么

先确认当前环境：

```powershell
cac env check -d
cac claude audit current
```

如果你使用 proxy 环境，默认 provider routing policy 会是 `managed`。通常不需要手动设置。

如果你是 API key / custom base URL 用户，并且没有使用 proxy，默认 policy 会是 `warn`。这会保留你的环境变量，但 `cac env check` 会提示可见 key。确认这是你预期的行为后，可以保持 `warn`，或显式设置为 `preserve`：

```powershell
cac env set main provider-routing preserve
```

如果你希望更严格地防止本地高风险组合启动 Claude，可以开启 strict：

```powershell
cac env set main signal-guard strict
```

如果 strict 阻止启动，按错误提示处理：隐藏 provider routing env、移除 settings 中的 key，或在你明确接受风险后改回 `warn` / `preserve`。

## 对已有环境的影响

### 不会改变的内容

- 不会删除已有环境。
- 不会删除已有 Claude Code 版本。
- 不会重置 `.claude` 会话、commands、hooks、skills、plugins。
- 不会打印真实 API key、auth token 或 settings value。
- 不会改变 provider 服务端对账号、支付、OAuth、IP 信誉等信号的判断。

### 会变化的内容

- 已有 proxy 环境如果没有显式 `provider_routing`，现在会按默认 `managed` 处理，并隐藏更多已知 provider routing / credential 环境变量。
- 已有非 proxy 环境如果没有显式 `provider_routing`，现在会按默认 `warn` 处理，保留变量但显示 key 名警告。
- `cac env check` 输出会多出 `Signal guard` 区块，部分以前没显示的问题现在会进入 summary。
- 如果你手动设置了 `signal-guard strict`，启动可能被阻止；默认 `warn` 不会阻止启动。
- linked clone 环境在 wrapper 合并 settings 时，默认会 sanitize provider routing key；如果你确实依赖这些 key，需要改用 `--preserve-provider-routing` 创建新环境，或确认环境中的 clone 策略。

## 常见场景

### 场景 A：普通代理环境

```powershell
cac env check -d
```

看到 `provider routing managed` 且 settings scan 没有 key 即可。无需额外操作。

### 场景 B：自定义 Base URL / API Key 用户

如果你确实需要 `ANTHROPIC_BASE_URL` 或相关 provider key：

```powershell
cac env set main provider-routing preserve
cac env check -d
```

这表示你明确选择保留 provider routing 信号。诊断仍会显示 key 名，但不会输出值。

### 场景 C：从 host `.claude` clone 配置

默认使用 sanitize：

```powershell
cac env create work --clone
```

如果 host settings 中有 provider routing key，输出会报告被移除的 key 名。需要保留时必须显式使用：

```powershell
cac env create work --clone --preserve-provider-routing
```

### 场景 D：检查旧版 Claude Code

```powershell
cac claude audit current
```

如果输出 `needs review`，建议升级 Claude Code 版本或至少运行：

```powershell
cac env check -d
```

如果输出 `unknown`，这不是“安全通过”，只是当前本地审计没有已知结论。

## 排查提示

- 新命令不可用：确认已经在 Git Bash 中执行 `bash build.sh`。
- `Signal guard` 没出现：确认你运行的是更新后的本地 checkout，`where cac` / `which cac` 不应指向其他安装。
- Bun probe 显示 skip：表示当前 PATH 中没有 `bun`，不是失败。需要验证 Bun 路径时安装 Bun 后重新运行 `cac env check -d`。
- strict 阻止启动：先运行 `cac env check -d` 看具体可见 key；输出只含 key 名，secret 值不会显示。

## 后续计划

优先级最高的是实现 `cac env report --redact`，让用户可以安全粘贴环境报告到 issue；其次是补 wrapper inactive、unknown runtime、linked clone 重新 merge 等回归测试。`cac debug runtime` 和真实二进制 marker string 扫描暂缓，后者维护成本高且容易造成“检测不到就是安全”的误解。