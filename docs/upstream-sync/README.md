# Upstream Sync 流程指南

本目录保存 `cac-win` 同步上游 `nmhjklnm/cac` 的方法论与历史归档。

- [`history/`](./history/) — 每轮同步的完整计划与执行结果
- [`preserve-list.md`](./preserve-list.md) — fork 专有内容清单，合并时必须保护

每次准备合入上游新更新前，**完整读完本文档** + **复核 preserve-list**。

## 为什么不直接 `git merge upstream/master`

`cac-win` 是 Windows-only fork，与上游在多个文件上深度分歧（详见 `preserve-list.md`）。直接合并会：

- 删除 fork 专有文件（`cac.cmd`、`cac.ps1`、`scripts/install-local-win.ps1`、`docs/windows/*` 等）
- 在 `src/utils.sh`、`src/templates.sh`、`src/cmd_*.sh` 上把 fork 的 Windows 适配（runtime locale spoof、`_tcp_check`、Node fallback、Git Bash path 等）覆盖回上游版本
- 把生成文件 `cac` 留在冲突状态，但 `cac` 是 `bash build.sh` 产出的派生物，不能手工解冲突

正确的做法是**按功能域小批量移植补丁**，每批一个 worktree、一个 PR，由 reviewer 逐个 verify 后合入 master。

## 总流程

每一轮上游同步分四阶段：

1. **调研**：列上游领先提交、判断每个的处理方式（移植 / 跳过 / 拆分）
2. **写计划**：在 `docs/upstream-sync/history/<日期>.md` 草拟分批方案，包含全局策略决策、提交映射、各任务范围与风险
3. **执行**：按计划逐个 worktree 落地，每任务一个 PR
4. **收口**：版本号统一 + CI 校验 + 计划文档归档

## 阶段 1：调研

```bash
# 第一次同步前需要 add remote
git remote add upstream https://github.com/nmhjklnm/cac.git

git fetch upstream --prune --tags
git log master..upstream/master --oneline
```

对每个上游提交回答 3 个问题：

1. **要不要做？** 上游的功能/修复对 Windows 用户有价值吗？纯 npm 发布、fish shell 等优先级低。
2. **能不能直接 cherry-pick？** 提交是否触及 fork 已大改的文件（`templates.sh`、`utils.sh` hostname/timer 段、`cmd_check.sh` 等）？通常需要手工 apply 而非 cherry-pick。
3. **是不是混合提交？** 一个上游 commit 可能同时改两类语义（典型例子：`902728b` 同时做 proxy 规范化和 exit IP 严格化）。这种要拆 hunk 到不同任务里。

跳过的常见类别：

- 纯版本号 / changelog 的 release 标签提交（如 `16cfd72`）
- 上游单独 `build: regenerate cac` 提交（由本地 build 自然吸收）
- npm publish 相关（fork 不发布）
- merge commits

## 阶段 2：写计划

新建 `docs/upstream-sync/history/<YYYY-MM-DD>.md`，必须包含：

- **当前基线**：master HEAD、upstream HEAD、共同祖先、双方领先提交数
- **全局策略决策**：版本号策略、生成文件处理、npm 立场、Windows 专有内容保护清单（参考 preserve-list.md）
- **上游提交映射表**：每个上游 commit → 任务编号 / 跳过原因
- **每个任务**：目标、范围（具体到文件和行级 hunk）、风险、验证命令、worktree 命令
- **执行顺序**：考虑硬依赖（如 T05 依赖 T02 的 `_parse_proxy`）
- **回滚策略**：默认 `git revert -m 1 <merge-commit>`，不允许 force-push 已合入的 PR

参考 `history/2026-04-28.md` 的结构。

## 阶段 3：执行

### Worktree 与 PR 规则

每个任务一个独立 worktree、独立分支、独立 PR：

```bash
git checkout master
git pull origin master
git fetch upstream --prune --tags

git worktree add ../cac-win-wt-T0N -b merge/upstream-T0N-topic master
cd ../cac-win-wt-T0N
```

每个 PR 必须：

- 只动本任务范围内的文件
- 修改 `src/` 后跑 `bash build.sh`，提交重新生成的 `cac`
- 中英 `docs/changelog.mdx` 同步加条目（命名 `v<base>-win.N`）
- 不动 `package.json` 与 `CAC_VERSION`（统一在末轮 T07 处理）
- PR 描述列上游 commit ID（精确到 hunk 边界）+ 验证命令
- CI 全绿后才合入

### 移植技巧

**首选手工 apply**（最干净）：

```bash
git show <commit> -- <paths>      # 看 diff
# 然后手工 Edit 应用，跳过不要的 hunk
```

**次选 cherry-pick -n**（保留更多元数据但容易带入意外文件）：

```bash
git cherry-pick -n <commit>
git restore --staged <unwanted-files>
git checkout -- <unwanted-files>
```

**避免 `git merge upstream/master`**：会一次性带进所有冲突。

### Hunk 切分的强制要求

如果一个上游 commit 跨任务（如 `902728b` 拆成 T02 + T05），prompt / PR 描述必须明确：

> "本 PR 仅取 `<commit>` 中 `<file>:<lineN>` 这一块 hunk，**排除** `<file>:<lineM>` 那块（属于 T0X）。"

reviewer 验收时**显式 grep** 确认排除的 hunk 没被误带入。

### Subagent 派工模式（可选）

如多个独立任务（不共享文件、不互相依赖），可并行派 subagent 各占一个 worktree。每个 prompt 必须自包含：

- 任务编号 + 上游 commit ID
- 全局约束（不动 package.json / 不退回 python3 / 保留 Node fallback 等）
- 范围（具体到文件、行号、hunk）
- 验证命令
- 提交格式（Conventional Commits）+ 推送命令

参考 `history/2026-04-28.md` 中实际派工记录。

### 验证命令

每个 PR 在合入前都要跑：

```bash
bash build.sh
shellcheck -s bash -S warning src/utils.sh src/cmd_*.sh src/dns_block.sh src/mtls.sh src/templates.sh src/main.sh build.sh
node --check src/relay.js
node --check src/fingerprint-hook.js
bash scripts/test-socks5h-probes.sh
bash tests/test-cmd-entry.sh
bash tests/test-windows.sh
```

shellcheck 在 Windows 本地常缺失，可用 `bash -n` 兜底，CI 上必须过。

## 阶段 4：收口

末轮（典型为 T07）做版本元数据收口：

- `package.json` 与 `src/utils.sh:CAC_VERSION` 对齐到本轮最终版本号 `<base>-win.<N>`
- `bash build.sh` 让 `cac` 内嵌版本号同步
- `.github/workflows/ci.yml` 的 `version-check` job 会在三方漂移时挂红灯
- 在 `docs/upstream-sync/history/<日期>.md` 顶部加"执行结果"小节，列出所有 PR 与 commit

## 常见陷阱

| 陷阱 | 表现 | 对策 |
| --- | --- | --- |
| 上游函数被 fork 替换过 | 上游用 `python3`，fork 已改成 `node -e` | prompt 里显式列保留项；移植前先 grep |
| fork 文件比上游多 hunk | fork 在某个函数里加了额外的 curl/check | prompt 里明确"fork 共有 N 处需包，比上游多 X 处" |
| 双语 changelog 漏一边 | 只写了 `docs/changelog.mdx`，没写 `docs/zh/changelog.mdx` | PR 检查清单里加双语断言 |
| `cac-dns-guard.js` 显示为 modified | build 后 CRLF 行末告警，实际 0 numstat | 跳过，不提交 |
| 生成文件冲突 | 直接合并上游 `cac` 文件 | 永远从本地 `bash build.sh` 重生 |
| CI 预存问题暴露 | 之前 PR 用 admin merge 绕过，新 PR 严格审视才挂红灯 | 每轮开工前先确保 master CI 绿 |

## 维护本指南

下次同步时：

1. 在 `history/` 加新一份计划文档
2. 如果发现新陷阱，更新本文档"常见陷阱"表
3. 如果 fork 又新增了专有文件/函数，更新 `preserve-list.md`
