# cac 代理机制缺陷记录

> 记录时间：2026-05-10
> 状态：Open
> 范围：Windows fork 当前 `master` 的代理、relay、`cac env check` 诊断机制

## 背景

当前 cac 的代理机制主要依赖环境变量和本地 wrapper：

1. 每个环境的代理地址保存于 `~/.cac/envs/<env>/proxy`
2. 启动 `claude` 时，`~/.cac/bin/claude` wrapper 读取当前环境
3. 如果配置了代理，wrapper 先做一次 TCP 端口可达性检查
4. wrapper 设置 `HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY`
5. 如果 `~/.cac/relay.js` 存在，wrapper 会启动本地 relay，并把代理变量改成 `http://127.0.0.1:<relay-port>`
6. relay 再转发到环境配置的上游代理

在本地 Clash Verge / mihomo 场景中，常见路径是：

```text
Claude Code -> cac relay -> 127.0.0.1:7897 -> Clash/mihomo -> remote exit
```

如果不启用 relay，路径可以简化为：

```text
Claude Code -> 127.0.0.1:7897 -> Clash/mihomo -> remote exit
```

## 已确认的安全边界

当前机制一般是 fail-closed，而不是 fail-open：

- 如果代理端口不可达，wrapper 会拒绝启动 Claude
- 如果端口可达但不是可用代理，请求会在 CONNECT 或上游转发阶段失败
- relay 失败时，Claude 连接到本地 relay 失败，不会因为 relay 失败自动直连远端 API
- `NO_PROXY=localhost,127.0.0.1` 只影响本机地址，不影响 Anthropic 远端 API

因此，配置了一个坏代理时，主要风险是 Claude 不可用或诊断失败，不是明显的真实 IP 自动直连。

但 cac 不是系统级防火墙，也不是网络命名空间。它依赖 Claude Code 及其子进程遵守 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`。如果未来 Claude 内部网络栈绕过这些环境变量，cac 不能从操作系统层面阻止直连。

## 当前缺陷

### 1. 启动预检只检查 TCP 可达

当前 wrapper 的启动前检查只验证 `host:port` 能否建立 TCP 连接。

这会导致：

- 端口开着但不是 HTTP/SOCKS 代理时，启动预检仍然通过
- 用户要等到实际请求或 `cac env check` 才能发现代理不可用
- 错误信息容易误导为 Claude 或上游服务故障

建议：

- 启动路径仍保留快速 TCP 检查，避免启动变慢
- `cac env check` 使用协议级检测：
  - HTTP proxy: 发送 `CONNECT api.ipify.org:443`
  - SOCKS5 proxy: 完整 SOCKS5 greeting + connect handshake
  - 只把协议级检测失败作为诊断问题，不一定阻塞日常启动

### 2. relay 对本地 HTTP 代理过度启用

当前 wrapper 注释和实现是“配置了 proxy 且存在 `relay.js` 就自动启 relay”。

对本地 Clash HTTP 代理，例如 `http://127.0.0.1:7897`，relay 通常没有明显收益：

- Claude 本来就能直接使用本地 HTTP proxy
- 多一层本地端口和 Node 进程
- 多一份 watchdog 生命周期状态
- 可能产生旧日志里的 `EADDRINUSE` 噪声
- 排障路径变复杂

建议：

- 默认不为本地 HTTP 代理启 relay
- relay 改为以下情况才启用：
  - 用户显式执行 `cac relay on`
  - 上游代理是 SOCKS5 且需要 HTTP proxy 兼容层
  - `cac env check` 明确检测到 TUN/VPN 冲突并提示用户启用

### 3. relay 状态是全局的

当前 relay 状态文件位于：

```text
~/.cac/relay.pid
~/.cac/relay.port
~/.cac/relay.proxy
~/.cac/relay.watchdog.pid
~/.cac/relay.log
```

这些文件是全局状态，不是按环境隔离。

问题：

- 多个环境使用不同代理时，切换环境会覆盖同一组 relay 状态
- 并发终端中不同环境可能互相影响
- 日志不能准确区分是哪一个环境触发的 relay 行为

建议：

- 如果继续保留自动 relay，改成 env-scoped 状态：

```text
~/.cac/envs/<env>/relay.pid
~/.cac/envs/<env>/relay.port
~/.cac/envs/<env>/relay.proxy
~/.cac/envs/<env>/relay.watchdog.pid
```

- 如果改成显式 relay，则全局状态可以保留，但需要在文档里说明同一时间只服务当前环境

### 4. 本地 relay 无认证

relay 监听 `127.0.0.1`，远程机器无法访问，但本机任意进程都可以连接它并复用当前代理出口。

这通常是可接受的本机信任边界，但严格来说仍是一个能力暴露：

- 本机恶意进程可借用 relay 出口
- relay 无法区分调用方是否是 Claude Code

建议：

- 保持只监听 `127.0.0.1`
- 如果未来要强化，可考虑随机本地 token 或仅在 wrapper 子进程生命周期内启用
- 目前优先级低于 relay 自动启用和全局状态问题

### 5. HTTPS upstream proxy 支持不完整

当前 relay 主要按 HTTP proxy 和 SOCKS5 upstream 设计。

风险：

- 环境代理如果被设置为 `https://host:port`，relay 可能不能正确与 HTTPS proxy 建立 TLS 连接
- 用户看到 `https://` 被 `_parse_proxy` 接受，容易误以为 relay 完整支持

建议：

- 文档明确推荐 Windows 本地代理使用 `http://127.0.0.1:<port>` 或 `socks5://127.0.0.1:<port>`
- 如果不准备支持 HTTPS upstream proxy，`cac env set proxy` 应给出警告
- 如果要支持，relay 需要增加 TLS upstream connect 分支和测试

### 6. `cac env check` 依赖 curl，Windows 上不稳定

本次调查中出现过 Windows `curl.exe` / Schannel 报错：

```text
schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS
```

同时，Node.js 手写 HTTP CONNECT + TLS 请求可以成功通过 `127.0.0.1:7897` 获取出口 IP。

这说明：

- Clash/mihomo 代理本身正常
- `curl` 后端可能受 Windows TLS、证书、凭据状态影响
- `cac env check` 可能产生误报

建议：

- 将 `cac env check` 的代理出口检测改为 Node.js 实现
- 避免依赖 Windows Schannel
- 统一支持 HTTP proxy 和 SOCKS5 proxy 的握手验证

### 7. TUN 冲突检测容易过度泛化

当前检测逻辑会扫描常见代理进程和 Windows 网络适配器名称。

问题：

- Clash/mihomo 开启 TUN 时，不一定代表 cac 路径有冲突
- 如果环境代理是 `127.0.0.1:<port>`，Claude 先连接 loopback，本身通常不受 TUN 影响
- 真正需要关注的是“连接远程代理服务器本身是否被 TUN 接管”

建议：

- 区分本地代理和远程代理：
  - `127.0.0.1` / `localhost` 上游：通常不提示 TUN 冲突
  - 远程代理 host：再提示 DIRECT rule 或 relay route
- `cac env check` 输出应说明检测依据，避免把“开了 TUN”直接等同于“有泄露风险”

## 建议的后续改造顺序

1. `cac env check` 改为 Node.js 代理诊断，减少 Windows curl 误报
2. 本地 HTTP proxy 默认不自动启 relay
3. relay 仅在显式开启或诊断建议后启用
4. relay 状态按 env 隔离，或明确改为全局单例并在文档中说明限制
5. 增加代理协议测试：
   - HTTP proxy 正常
   - HTTP 端口可连但不是 proxy
   - SOCKS5 proxy 正常
   - proxy 不可达
   - Windows Clash/mihomo TUN 开关场景
6. 明确 `https://` upstream proxy 的支持策略：要么完整支持，要么显式拒绝或警告

## 当前推荐使用方式

在修复前，Windows + Clash Verge / mihomo 用户建议：

```powershell
cac env set main proxy http://127.0.0.1:7897
cac main
cac env check -d
```

如果 `cac env check -d` 代理检查失败，但 Clash 端口确实监听，可以优先排查：

- `127.0.0.1:7897` 是否为 HTTP mixed port
- 是否误填成 SOCKS 端口
- 是否是 Windows curl / Schannel 误报
- `~/.cac/fingerprint-hook.js` / `relay.js` / `cac-dns-guard.js` 是否同步到最新构建产物

本地代理场景下，若没有明确 TUN 冲突，不建议优先启用 relay 作为排障手段。
