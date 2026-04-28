# Fork 专有内容保护清单

合入上游更新时，**任何 PR 都不得删除或覆盖**以下内容。本清单按"独占文件"和"共享文件中的 fork 段"分类，每条说明保留原因。

> 状态以 master 当前 HEAD 为准，最近一次维护：2026-04-28（T07 收口后）。

## 独占文件（上游不存在）

合并时绝不能让 upstream merge 删除这些文件。

| 文件 | 用途 |
| --- | --- |
| `cac.cmd` | Windows 批处理入口，cmd.exe 用户用 `cac` 命令的真实落点 |
| `cac.ps1` | PowerShell 等价于 bash `cac` 脚本，cmd.exe / PowerShell 双入口 |
| `scripts/install-local-win.ps1` | Windows 本地 clone 安装脚本 |
| `tests/test-cmd-entry.sh` | `cac` 入口（cmd / ps1 / bash）一致性测试 |
| `tests/test-windows.sh` | Windows 主路径回归测试套件（48+ 用例） |
| `tests/test-claude-autoupdate.sh` | Claude Code 自动更新测试 |
| `docs/windows/*` | Windows-specific 文档（安装、故障排查、protection assessment 等） |
| `docs/upstream-sync/*` | 本目录（上游同步指南） |
| `AGENTS.md` | Codex / 多 agent 协作约定（参考性） |
| `CLAUDE.md` | Claude Code 协作约定 |

## 共享文件中的 fork 专有段

这些文件上下游都有，但 fork 在特定函数/区块里做了 Windows 适配，**移植上游补丁时只能在这些段之外动，或者在 fork 段内插入 hunk**，绝不能让上游版本整段覆盖。

### `src/utils.sh`

| 函数 / 段 | fork 改动 | 不能退回的原因 |
| --- | --- | --- |
| `_gen_uuid` | 加了 `node -e` fallback | Git Bash / Windows 上无 `uuidgen` 也无 `/proc/sys/kernel/random/uuid` |
| `_new_user_id` | 用 `node -e` 生成而非 `python3` | fork 不假设 python3 存在，Windows 默认无 |
| `_new_machine_id` | 全小写无连字符（保持上游语义但要确认 Node fallback 不被改） | 上游修改时勿替换 |
| `_new_hostname` / `_detect_hostname_platform` / `_new_hostname_suffix` | 平台分支：Windows 输出 `DESKTOP-xxxxx`/`LAPTOP-xxxxx` | T04 引入，是 fork 主推的"指纹一致性"目标 |
| `_time_now` / `_timer_start` / `_timer_elapsed` | regex 校验非 GNU `date +%s%N` 输出 | T04 引入，Git Bash / MSYS 上 `%N` 是字面量 |
| `_parse_proxy` | 支持 `socks5://host:port:user:pass` legacy 形式 | T02 引入，与上游已对齐但要保留扩展逻辑 |
| `_proxy_host_port` | 先调 `_parse_proxy` | T02 引入 |
| `_curl_proxy_url` | 把 `socks5://` 转 `socks5h://` 强制远端 DNS | T03 引入 |
| `_tcp_check` | 纯 Node fallback，避免 `/dev/tcp` 在 Git Bash 不稳 | fork 长期改动，CI / wrapper 都依赖 |
| `CAC_VERSION` | 形如 `1.5.8-win.<N>` | fork 版本命名约定，与上游 `1.5.x` 区别 |

### `src/templates.sh`

模板里的 wrapper（`~/.cac/bin/claude`）跑在子 shell，**不能调用主 cac 的 helper**，所有逻辑必须内联。fork 在以下区块加了 Windows 增强：

- runtime locale / timezone spoof（生成的 wrapper 启动时设置 `LC_ALL` / `TZ` 等）
- `.cmd` wrapper 生成（Windows cmd.exe 入口）
- `CLAUDE_CODE_GIT_BASH_PATH` 自动探测
- `_tcp_check`（前面已说明）
- proxy 内联 normalization（T02 引入）

合入上游 templates.sh 改动时**只能新增 hunk**，不能整段替换。

### `src/cmd_check.sh`

| 区块 | fork 改动 | 不能退回 |
| --- | --- | --- |
| 一次性 `proxy_meta` 请求（约 250 行起） | 用 `node -e` 解析 JSON 而非 `python3` | T03 时被 wrap 了 `_curl_proxy_url`，移植时三处 curl 都要包 |
| TUN 冲突检测 | Windows 特有路径 | 上游无对应逻辑 |
| relay localhost 探测 | 用 `http://127.0.0.1:$rport`，**不应**包 `_curl_proxy_url` | 不是 SOCKS5，没有 DNS 问题 |

### `src/cmd_env.sh`

- `--no-link` flag 与 `clone_mode=copied` 默认行为：Windows 上强制复制，因为 symlink 需要管理员权限。**绝不能让上游的默认 symlink 行为覆盖。**
- `--telemetry`、`--persona`、`--autoupdate` 这些 flag 的扩展用法是 fork 增强，help 行里列得比上游多

### `src/cmd_help.sh`

顶层 help 输出包含 `--clone`、`--no-link`、`--autoupdate` 等 fork 扩展 flag。

### `src/cmd_claude.sh`

- `_download_version` 的 Windows 适配（node + `.exe`）
- 各种 `local x; x=$(...)` 风格（T07 修了 SC2155 一处）

### `src/fingerprint-hook.js`

- Windows 特有：拦截 `wmic csproduct get uuid` 和 `reg query …MachineGuid` 在 `execSync` / `exec` / `execFileSync` 三处
- 这是 Windows 上**唯一**的进程级拦截层（`shim-bin/` 在 Windows 上失效），任何上游对这个文件的修改都要逐字审查

## CI / Workflow 配置

| 文件 | fork 状态 | 与上游差异 |
| --- | --- | --- |
| `.github/workflows/ci.yml` | 含 `shellcheck` / `build-check` / `js-check` / `version-check`（T07 新增）+ `Run proxy regression checks`（T03 新增） | 上游也有 ci.yml 但内容会 drift；合并时只新增 step / job，不替换整文件 |
| `.github/workflows/feishu-notify.yml` | 加了 webhook 空值 guard | 上游无此文件，是 fork 引入 |
| `.github/workflows/docker.yml` | 与上游基本一致 | — |
| `.github/workflows/npm-publish.yml` | **已删除**（T07） | 上游有，fork 不发布 npm，**重新引入是错的** |

## 安装路径与发布

- fork **不发布到 npm**。上游的 npm publish 流程、`scripts/postinstall.js` 中假设 npm 安装的逻辑都不应被加强。
- fork 安装路径：`git clone` + `scripts/install-local-win.ps1` / 本地 `cac setup`。

## 标识符

- fork 版本号约定：`<上游 base>-win.<N>`（例：`1.5.8-win.4`）。`-win.N` 部分由 fork 自己递增，每轮 T07 收口时 +1。
- fork commit prefix 与上游一致（Conventional Commits），但合并 PR 标题约定为 `merge/upstream-T0N-topic` 分支名。

## 维护本清单

每次有以下情况发生时更新本文档：

1. fork 新增独占文件 → 加到"独占文件"表
2. fork 在共享文件里加新函数或修改新区块 → 加到对应"共享文件中的 fork 专有段"
3. workflow 配置调整 → 更新"CI / Workflow 配置"表

不要在这里记录已完成的合并 PR / 临时改动 — 那些归 `history/<日期>.md`。
