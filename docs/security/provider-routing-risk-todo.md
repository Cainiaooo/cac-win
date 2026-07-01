# Provider Routing 风险优化 TODO

> 状态：TODO
> 日期：2026-06-30
> 范围：以 Windows 为重点的 `cac-win` 本地环境管理

## 调研验证结论

本文件已按当前源码重新核对。核对过程只读取仓库文件，未运行 `cac env create`、`cac env check`、`claude` 启动链路，未触碰本机正在使用的 `cac` main 环境。

外部信息核对时间：2026-07-01。以下背景来自公开报告、第三方逆向分析和 Anthropic/Claude Code 官方文档；第三方逆向结论需要在实现审计命令时按版本重新验证，不应直接当作长期稳定事实。

已确认的当前实现：

- wrapper 在配置 proxy 时会导出 `HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY`，并设置 `NO_PROXY=localhost,127.0.0.1`。
- wrapper 在 proxy 模式下会从子进程环境中移除 `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY`；无 proxy 时保留这些用户环境变量。
- 环境创建会写入 `tz` 和 `lang`；启动时会导出 `TZ`、`CAC_TZ`、`LANG`、`LC_ALL`、`LC_MESSAGES`、`LC_TIME`、`CAC_LANG`、`LANGUAGE`。
- wrapper 已同时向 `NODE_OPTIONS --require` 和 `BUN_OPTIONS --preload` 注入 `fingerprint-hook.js` 与 `cac-dns-guard.js`，用于覆盖 Node.js 和 Bun runtime。
- `fingerprint-hook.js` 会读取 `CAC_TZ`/`TZ` 和语言环境变量，修补 JS runtime 的 `Intl.DateTimeFormat`、`Date#toLocale*`、`Date#toString`、`getTimezoneOffset`、`navigator.language(s)` 等运行时表现。
- `cac env check -d` 已包含 Node Intl 时区/语言 smoke test，并把 runtime 探针结果放在 Identity 详情中；但当前 smoke test 只验证 Node，不验证 Bun。
- 每个环境有独立 `.claude` 目录，并通过 `CLAUDE_CONFIG_DIR` 注入；clone 模式会继承 host 或其他环境的配置资源。

已确认的缺口：

- 当前没有 `provider-routing` 环境配置项，也没有 `managed`、`warn`、`preserve` 的显式策略。
- 当前没有 `signal-guard` 环境配置项，也没有启动期 strict 模式。
- 当前 `cac env check` 没有独立的 `Signal guard` 区块。
- 当前没有扫描 `.claude/settings*.json`、`~/.claude/settings*.json` 或 `~/.claude.json` 中 provider routing key 的逻辑。
- 当前 clone/sync 流程不会专门清理或提示 provider routing key。
- 当前没有 Bun runtime 的独立 timezone/locale smoke test，`cac env check -d` 可能在 Node 探针通过时漏报 Bun standalone binary 注入失败。
- 当前没有 `cac debug runtime`、`cac claude audit`、`cac env report --redact` 这些命令。

## 外部披露背景

2026-06-30 至 2026-07-01 附近，公开讨论集中在 Claude Code 对自定义 provider routing 的 prompt 级标记逻辑。相关报告称，在特定版本中，Claude Code 会读取非一方 `ANTHROPIC_BASE_URL`、本地 timezone，以及和中国域名/AI provider/代理路由相关的域名或关键词列表，然后把分类结果编码到系统 prompt 的日期行中。

已公开描述的机制边界：

- 触发条件重点是 `ANTHROPIC_BASE_URL` 指向非默认 `api.anthropic.com` 的自定义 endpoint；单纯使用 VPN 或单纯处在某个 timezone 并不等价于触发该路径。
- 公开逆向分析称，`Asia/Shanghai` 或 `Asia/Urumqi` 会影响日期分隔符，非默认 base URL 的域名分类会影响 `Today's` 中 apostrophe 的 Unicode 变体。
- 该机制不是单独的 telemetry event，也不是额外读取文件或网络接口；更准确的风险描述是“把本地 routing/timezone 信号编码进本来就会发送的 prompt 上下文”。
- 披露者称相关逻辑至少在 Claude Code `2.1.196` 存在，并追溯到 `2.1.91`；这一点需要后续 `cac claude audit` 按本地安装版本重新验证。
- 该机制的主要争议不是 provider 进行反滥用检测本身，而是检测信号被隐藏在看似普通的模型上下文里，用户和 wrapper 层不容易观察或审计。

官方文档可确认的配置面：

- Claude Code 官方环境变量文档说明，环境变量可控制认证、请求路由、provider、feature toggle，且可通过 shell 或 `settings.json` 的 `env` 字段设置；settings 中的 `env` 会在 `claude` 启动时生效。
- 官方文档明确列出 `ANTHROPIC_BASE_URL` 用于把请求路由到 proxy/gateway；并说明当它指向非一方 host 时，部分功能会改变，例如 MCP tool search 默认禁用，`2.1.196` 起 Remote Control 会禁用。
- 官方文档同时列出 Bedrock、Vertex、Foundry、Claude Platform on AWS 等 provider 的 base URL / routing 变量，说明 routing 配置面不只限于 `ANTHROPIC_BASE_URL`。
- 官方文档还列出 `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST`，说明 host-managed 场景会忽略 settings 里的 provider-selection、endpoint、auth 变量，例如 `CLAUDE_CODE_USE_BEDROCK`、`ANTHROPIC_BASE_URL`、`ANTHROPIC_API_KEY`。
- Anthropic 隐私中心说明，平台安全和反滥用会使用 IP address 和其他信号推断粗粒度位置；这说明 server-side 决策本来就存在，但不等于公开披露的 prompt-level marker 已被官方充分解释。

Bun runtime 相关背景：

- Anthropic 已公开说明 Bun 是 Claude Code 背后的关键 runtime；公开 issue 和第三方分析也显示 Claude Code standalone / Windows binary 场景经常表现为 Bun single-file executable。
- Bun 官方文档说明 `BUN_OPTIONS` 会向 Bun 执行预置命令行参数，`--preload` 可在入口脚本前加载 setup 文件；这与当前 wrapper 使用 `BUN_OPTIONS="--preload <hook>"` 的方向一致。
- 风险点不在于当前完全没处理 Bun，而在于 check/diagnostic 还没有使用 Bun 复测实际 hook 效果。只用 Node probe 可能给出 false green。

参考来源：

- https://www.reddit.com/r/ClaudeAI/comments/1ujila1/anthropic_embedded_spyware_in_claude_code_and/
- https://www.vincentschmalbach.com/claude-code-china-router-fingerprint/
- https://gist.github.com/AdnaneKhan/0a0edb5620d5214282ef4027caad8950
- https://code.claude.com/docs/en/env-vars
- https://privacy.claude.com/en/articles/11186740-does-claude-use-my-location
- https://www.anthropic.com/news/anthropic-acquires-bun-as-claude-code-reaches-usd1b-milestone
- https://bun.com/docs/runtime/environment-variables

## 对 `cac-win` 的影响

这次披露把本 TODO 的优先级从“清理 provider routing 配置”提升为“审计 Claude Code 启动时真实可见的 routing/timezone 信号”。对 `cac-win` 来说，关键不是承诺规避任何服务端策略，而是把本地 wrapper 管理范围做实：

- proxy 模式目前已经 unset `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY`，这与默认 `managed` 策略方向一致，但还没有显式策略、可见性报告或 strict mode。
- 无 proxy / API key 用户场景目前保留 `ANTHROPIC_BASE_URL`，这可能是合法 workflow；因此默认不应强行移除，而应进入 `warn` 并在 `env check` 中明确显示。
- `settings.json` 的 `env` 字段会绕过父 shell 清理，因此 scanner 必须覆盖受管 `.claude` 和 host `.claude` 的 settings 文件，尤其是 clone/linked settings 场景。
- timezone 不再只是“IP 与 locale 是否匹配”的普通一致性检查，也应该在 custom provider routing 可见时作为组合风险显示，并且必须同时验证 Node 与 Bun 的 runtime 表现。
- 版本审计不能只看 cac wrapper，还需要记录 Claude Code 版本，并在未知版本、自动更新后或 marker 逻辑疑似变化时提示重新跑 `cac env check -d`。

## 目的

近期 Claude Code 版本似乎会把 provider routing 配置以及运行时 locale/timezone 当作有意义的客户端侧信号。`cac-win` 已经管理了其中一部分值，但当前行为分散在 wrapper、环境创建、运行时 hook 和 check 命令里。

本文把该场景整理为实现 TODO。目标不是保证任何账号结果，也不是绕过任何服务商策略；目标是让本地环境行为更明确、可审计、并在高风险组合下尽量 fail-safe：

- 显示受管环境是否向 Claude Code 暴露了自定义 provider routing 值。
- 当 clone 进来的设置携带 provider routing 或疑似凭据 key 时给出警告。
- 验证运行时 timezone/locale 是否与环境配置一致。
- 避免在日志或诊断信息中泄露 secret 值。
- 明确说明本地环境管理与服务端 provider 决策之间的边界。

## 当前状态

`cac-win` 已经具备以下基础能力：

- 配置 proxy 时，wrapper 会使用 proxy 相关环境变量。
- proxy 模式下，wrapper 当前会移除 `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY`。
- 环境保存 `tz` 和 `lang`，启动时导出 `TZ`、`CAC_TZ`、`LANG`、`LC_ALL`、`LC_MESSAGES`、`LC_TIME`、`CAC_LANG`、`LANGUAGE`。
- `fingerprint-hook.js` 会修补 JS runtime locale/timezone API；wrapper 已通过 `NODE_OPTIONS` 和 `BUN_OPTIONS` 同时覆盖 Node 与 Bun 注入路径。
- `cac env check -d` 已经包含 Node Intl timezone/locale smoke test，但还缺少 Bun runtime probe。
- 每个环境隔离自己的 `.claude` 配置，但 clone 模式仍可能导入 host 设置。

需要补齐的缺口：

- `cac env check` 里没有独立的 provider routing 风险区块。
- 没有扫描 `.claude/settings*.json` 或 clone 设置里的 provider routing key。
- 没有面向用户的显式策略来定义 provider routing 环境变量应该被保留、警告还是移除。
- 没有针对高风险本地配置组合的启动期 strict mode。
- 没有 Bun runtime 级别的 Signal guard 检查，无法确认 standalone Claude Code 的实际时区/语言 hook 是否生效。
- Claude Code 版本变化后，没有升级/审计提醒。

## P0 任务

### 1. 增加显式 provider routing 策略

新增环境设置：

```bash
cac env set [name] provider-routing <managed|warn|preserve>
```

建议行为：

| 模式 | 行为 |
|---|---|
| `managed` | wrapper 在启动 Claude Code 前移除自定义 provider routing 和疑似凭据环境变量。 |
| `warn` | wrapper 保留用户配置，但 `cac env check` 报告可见的 provider routing key。 |
| `preserve` | wrapper 保留用户配置，并记录用户已明确选择退出管理。 |

建议默认值：

- proxy 环境：`managed`。
- 无 proxy 环境：`warn`。

可能影响的文件：

- `src/templates.sh`
- `src/cmd_env.sh`
- `src/cmd_check.sh`
- `README.md`

验收标准：

- proxy 环境默认继续避免暴露自定义 provider routing 变量。
- 无 proxy 环境不破坏现有用户工作流，但会报告可见的 provider routing。
- 诊断只显示 key 名，不显示值。
- 没有该设置的既有环境能获得合理默认值。

### 2. 扫描受管 `.claude` 设置中的 provider routing key

新增 scanner，供 `cac env check` 和启动 strict mode 使用。

需要扫描的文件：

```text
$env_dir/.claude/settings.json
$env_dir/.claude/settings.local.json
$env_dir/.claude/settings.override.json
$HOME/.claude/settings.json
$HOME/.claude/settings.local.json
$HOME/.claude.json
```

按 key 名标记以下项目，不能输出值：

```text
ANTHROPIC_BASE_URL
ANTHROPIC_API_KEY
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_AWS_BASE_URL
ANTHROPIC_AWS_API_KEY
ANTHROPIC_BEDROCK_BASE_URL
ANTHROPIC_BEDROCK_MANTLE_BASE_URL
ANTHROPIC_FOUNDRY_BASE_URL
ANTHROPIC_VERTEX_BASE_URL
CLAUDE_CODE_USE_BEDROCK
CLAUDE_CODE_USE_VERTEX
CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST
CLAUDE_CODE_PROPAGATE_TRACEPARENT
```

验收标准：

- `cac env check` 在发现风险 key 时显示简洁警告。
- `cac env check -d` 显示文件路径和 key 名。
- 所有值始终脱敏。
- clone 模式不能在没有警告的情况下静默导入 provider routing key。
- key 分类应区分 `routing`、`credential`、`provider-mode`、`trace-propagation`，避免把所有项目都报成同一种风险。

### 3. 在 `cac env check` 增加 `Signal guard` 区块

新增独立输出块，不要混在 telemetry 或 identity 检查里：

```text
Signal guard
  ✓ provider routing   managed
  ✓ settings scan      no provider routing keys
  ✓ runtime timezone   Node Intl probe ok
  ✓ bun timezone       Bun Intl probe ok
  ⚠ timezone           review manually when using custom provider routing
  ⚠ prompt marker      custom endpoint + China timezone combination requires review
```

验收标准：

- 普通 check 和详细 check 都显示该区块。
- 问题会进入最终 summary。
- 未配置 proxy 时输出仍然有用。
- 如果检测到 Bun 可用或 Claude Code 当前版本是 Bun standalone binary，必须运行 Bun probe；不能只用 Node probe 代替。

### 4. 增加启动 strict mode

新增环境设置：

```bash
cac env set [name] signal-guard <warn|strict>
```

建议行为：

| 模式 | 行为 |
|---|---|
| `warn` | 打印警告但继续启动。 |
| `strict` | 当可见本地 routing 配置属于高风险组合时拒绝启动。 |

strict mode 应在以下情况下阻止启动：

- 子进程可见自定义 provider routing 环境变量。
- 受管 `.claude` 设置中包含 provider routing key。
- 自定义 provider routing 与 `Asia/Shanghai` 或 `Asia/Urumqi` timezone 同时可见，且 policy 不是 `preserve`。
- wrapper 未生效，但用户期望使用受管环境。

验收标准：

- strict mode 默认 fail closed，并给出清晰错误信息。
- 错误信息包含修复命令。
- 不打印任何 secret 值。

### 5. 更新 clone 行为

从 host `.claude` clone 配置时，provider routing key 不应静默进入受管环境。

建议选项：

```bash
cac env create work --clone --sanitize-provider-routing
cac env create work --clone --preserve-provider-routing
```

默认建议：默认 sanitize 或 warn；只有用户明确表达意图时才 preserve。

验收标准：

- clone 输出报告被移除或保留的 key 名。
- 值保持脱敏。
- 既有 clone 工作流仍可使用。

## P1 任务

### 6. 增加运行时检查命令

新增：

```bash
cac debug runtime
```

该命令应通过 cac wrapper 路径尽量模拟真实 Claude 启动环境，并输出脱敏摘要：

```text
wrapper active: yes/no
provider-routing policy: managed/warn/preserve
runtime family: node/bun/unknown
ANTHROPIC_BASE_URL: hidden/present
ANTHROPIC_API_KEY: hidden/present
ANTHROPIC_AUTH_TOKEN: hidden/present
TZ: <timezone>
Node Intl timezone: <timezone>
Bun Intl timezone: <timezone>
locale: <locale>
```

验收标准：

- 可在 PowerShell、CMD、Git Bash 中工作。
- 尽量复用真实 Claude 启动时的 wrapper 路径和环境设置。
- 同时报告 `NODE_OPTIONS` 和 `BUN_OPTIONS` 是否包含预期 preload hook；只显示 hook 文件名和状态，不显示完整 secret 环境。
- 所有 secret 值脱敏。

### 7. 增加 Claude Code 版本审计提示

新增轻量命令：

```bash
cac claude audit <current|version>
```

首版可以简单且保守：

- 识别已安装 Claude Code 版本。
- 区分 wrapper package 与平台二进制。
- 只查找已知 marker string 作为提示。
- 对 `2.1.91` 至 `2.1.196` 这类公开报告覆盖的版本输出 `needs review`，不要静默通过。
- 输出 `known`、`unknown` 或 `needs review`，不要伪装确定性。

验收标准：

- `cac claude audit current` 可用于受管版本。
- 未知版本不能输出假绿色状态。
- 自动更新流程提示用户在版本变化后运行 `cac env check -d`。

### 8. 改进文档

在 README 中增加类似章节：

```text
Provider routing and signal guard
```

需要说明：

- cac 能在本地管理什么。
- cac 不能控制什么，包括账号状态、支付资料、OAuth 状态、IP 信誉、provider 服务端决策。
- 如何运行 `cac env check -d`。
- 如何使用 `provider-routing` 和 `signal-guard` 模式。
- clone 模式如何处理 provider routing key。

## P2 任务

### 9. 增加脱敏环境报告

新增：

```bash
cac env report --redact
```

输出应可安全粘贴到 issue：

```text
cac version
Claude Code version
OS and shell
wrapper active
provider-routing policy
signal-guard policy
proxy configured yes/no
runtime timezone
settings scan result
runtime probe result
```

### 10. 增加自动化测试

建议测试文件：

```text
tests/provider-routing-managed.bats
tests/provider-routing-warn.bats
tests/settings-provider-scan.bats
tests/signal-guard-strict.bats
tests/runtime-inspection.bats
```

最低测试场景：

- 父 shell 存在 provider routing 变量，proxy 环境使用 managed mode。
- 无 proxy 环境使用 warn mode，并报告可见 provider routing。
- settings 文件包含 provider routing key，check 报告路径和 key 名。
- strict mode 会阻止不安全的本地配置。
- wrapper 改动后 Node 与 Bun runtime timezone probe 都能通过；如果 CI 没有 Bun，应明确 skip 而不是把 Node 结果当成 Bun 结果。

## 实施顺序

1. 实现 provider routing 策略的存储和默认值。
2. 增加 settings scanner。
3. 在 `cmd_check.sh` 中增加 `Signal guard` 输出。
4. 在 wrapper 生成逻辑中增加启动 strict mode。
5. 更新 clone sanitization 行为。
6. 更新 README。
7. 增加测试。
8. 增加版本审计和脱敏 report 命令。

## 完成定义

- `cac env check -d` 能清楚显示自定义 provider routing 是否可见。
- 受管 proxy 环境默认不暴露 provider routing 变量。
- clone 设置不能静默导入 provider routing key。
- runtime timezone/locale 检查保持可见且可靠，并覆盖 Node 与 Bun 两条注入路径。
- 启动 strict mode 在风险本地配置上 fail closed。
- 所有诊断都不打印 secret 值。
- 文档明确说明 cac 只管理本地环境行为，不能保证任何 provider 服务端账号决策。
