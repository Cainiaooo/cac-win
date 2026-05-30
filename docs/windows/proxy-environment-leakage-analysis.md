# cac 代理环境泄露风险分析

> 记录时间：2026-05-22  
> 状态：Analysis  
> 范围：Windows fork 当前 `master` 的 env proxy、wrapper、relay、诊断输出与本机落盘状态  
> 关联：`docs/windows/proxy-mechanism-limitations.md`、`docs/windows/agent-view-proxy-bypass-analysis.md`

## 背景

近期对 Antigravity CLI、Proxinject、Proxifier、终端临时环境变量等方案的排障说明了一个核心事实：

- `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 只对愿意读取这些变量的程序有效。
- Go gRPC、长生命周期 daemon、IDE 插件、后台 worker 等路径可能绕过普通 env proxy。
- 进程级注入或系统级 TUN/规则分流才能对“不读 env 的网络栈”形成更硬的约束。

cac 的代理模型不是进程级注入。它通过 `~/.cac/bin/claude` wrapper 读取当前环境配置，向 Claude Code 进程树注入代理变量，并在有 `relay.js` 时启动本地 relay：

```text
claude command
  -> ~/.cac/bin/claude wrapper
     -> read ~/.cac/envs/<env>/proxy
     -> export HTTPS_PROXY / HTTP_PROXY / ALL_PROXY
     -> optionally start ~/.cac/relay.js
     -> exec real claude binary
```

典型本地 Clash/mihomo mixed port 路径：

```text
Claude Code -> cac relay -> 127.0.0.1:7897 -> Clash/mihomo -> remote exit
```

本文只分析两个问题：

1. 是否可能泄露真实出口 IP。
2. 是否可能泄露代理地址或代理账号密码。

## 当前实现路径

### 代理配置落盘

创建环境或修改代理时，代理地址会写入：

```text
~/.cac/envs/<env>/proxy
```

相关代码：

- `src/cmd_env.sh`：创建环境时 `echo "$proxy_url" > "$env_dir/proxy"`
- `src/cmd_env.sh`：`cac env set <env> proxy <value>` 时同样写入该文件
- `README.md`：明确记录 `~/.cac/envs/<name>/proxy` 是环境文件布局的一部分

支持的格式包括：

```text
host:port
host:port:user:pass
http://host:port
http://user:pass@host:port
socks5://host:port
socks5://user:pass@host:port
```

因此，如果用户配置了 `user:pass`，凭据会以明文形式保存。

### wrapper 注入代理环境

wrapper 启动时读取 `~/.cac/envs/<env>/proxy`，并设置：

```bash
export _CAC_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY" HTTP_PROXY="$PROXY" ALL_PROXY="$PROXY"
export NO_PROXY="localhost,127.0.0.1"
```

随后如果 relay 启动成功，wrapper 会把这些变量改写成本地 relay 地址：

```bash
export HTTPS_PROXY="http://127.0.0.1:$_relay_port"
export HTTP_PROXY="http://127.0.0.1:$_relay_port"
export ALL_PROXY="http://127.0.0.1:$_relay_port"
```

这意味着多数 Claude 子进程最终只能看到 `127.0.0.1:<relay-port>`，而不是上游代理凭据。但在 relay 启动前、wrapper 内部变量、进程命令行和状态文件中，真实上游代理仍然存在。

### relay 启动与状态文件

relay 启动方式：

```bash
node "$relay_js" "$port" "$proxy" "$pid_file" "$relay_token" </dev/null >"$CAC_DIR/relay.log" 2>&1 &
```

状态文件：

```text
~/.cac/relay.pid
~/.cac/relay.port
~/.cac/relay.proxy
~/.cac/relay.token
~/.cac/relay.log
~/.cac/relay.instances/
```

其中：

- `relay.proxy` 保存上游代理地址。
- relay Node 进程命令行参数包含上游代理地址。
- `relay.log` 目前只记录监听地址、上游 host:port、错误信息，不主动记录用户名密码。
- relay 只监听 `127.0.0.1`，并通过 token health endpoint 校验 cac 自有 relay，而不是信任任意 localhost listener。

## 真实 IP 泄露风险

### 已有保护

当前实现倾向于 fail-closed：

- 代理端口 TCP 不可达时，wrapper 拒绝启动 Claude。
- relay 死亡时，`HTTP_PROXY` 指向本地 dead port，请求会失败而不是自动直连。
- relay reuse 需要 `GET /__cac_relay_health__/<token>` 返回匹配 token，避免误用随机 localhost listener。
- 有代理时 wrapper 会清理 `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY`，避免 API key 跟随代理模式泄露。

因此，在“Claude Code 遵守 env proxy”的前提下，代理故障更可能表现为请求失败，而不是真实 IP 自动暴露。

### 不能覆盖的路径

cac 不是系统级网络拦截层，不能保证所有网络栈都经过 env proxy。

以下路径仍有真实 IP 泄露可能：

- Claude Code 或其依赖将来引入不读取 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 的网络栈。
- 某个子进程绕过 wrapper，以绝对路径直接启动真实 `claude.exe`。
- IDE 插件、后台服务、Agent View supervisor 由非 cac 路径启动。
- 长生命周期 supervisor 在代理配置变更前已经启动，并继续继承旧环境。
- gRPC、QUIC、原生 socket 或自带代理配置的库忽略标准 env proxy。

Agent View 的既有测试显示，当前版本中 `wrapper -> supervisor -> worker` 的 env 继承链能让后台 worker 走代理；但这是对当时版本和实现的验证，不等于系统级保证。

### 结论

真实 IP 泄露风险：**中低，但依赖前提明确**。

只要网络请求遵守 env proxy，cac 的 relay 设计大多 fail-closed；一旦目标程序绕过 env proxy，cac 没有 Proxinject、Proxifier、TUN、防火墙规则那样的强制拦截能力。

## 代理地址与凭据泄露风险

这是比真实 IP 泄露更现实的问题。

### 明文落盘

代理地址会明文写入：

```text
~/.cac/envs/<env>/proxy
~/.cac/relay.proxy
```

如果使用本地代理：

```text
http://127.0.0.1:7897
```

泄露价值较低。

如果使用远程代理凭据：

```text
http://user:pass@proxy.example.com:8080
socks5://user:pass@proxy.example.com:1080
```

则代理账号密码会直接落盘。

### 命令行参数暴露

relay 启动时上游代理 URL 是 Node 进程参数：

```text
node ~/.cac/relay.js <port> <upstream_proxy_url> <pid_file> <verify_token>
```

在 Windows 上，进程命令行通常可被同用户、管理员、部分安全软件、调试工具或日志采集工具读取。若 `<upstream_proxy_url>` 包含 `user:pass`，凭据可能通过进程列表泄露。

### 命令输出回显

`cac env create -p ...` 和 `cac env set proxy ...` 当前会输出完整 `proxy_url`。

`cac env ls` 已对 `://user:pass@` 做了脱敏处理，但创建和修改路径仍会直接回显完整代理。终端历史、CI 日志、录屏或共享终端输出都可能记录凭据。

### 本机文件权限

本机实际检查中，当前 `~/.cac/envs/*/proxy` 只保存本地端口：

```text
~/.cac/envs/main/proxy      http://127.0.0.1:7897
~/.cac/envs/test-av/proxy   http://127.0.0.1:18999
```

当前没有代理账号密码，敏感泄露风险较低。

但 `~/.cac` ACL 继承允许 `CodexSandboxUsers` 读取。如果未来把带账号密码的代理 URL 写入 `~/.cac`，沙箱用户或同机辅助进程可能读到。

### relay.log 风险

当前 `relay.js` 日志只输出：

```text
[cac-relay] listening on 127.0.0.1:<port> -> <upstreamHost>:<upstreamPort> (http|socks5)
[cac-relay] upstream unreachable: <upstreamHost>:<upstreamPort>
[cac-relay] server error: ...
```

没有主动输出 username/password，也没有输出 `Proxy-Authorization` header。

但如果未来增加 debug 日志，必须避免记录：

- 完整 upstream URL
- `Proxy-Authorization`
- SOCKS5 username/password
- `_CAC_PROXY`
- `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` 的完整值

### 结论

代理地址与凭据泄露风险：**本地端口场景低；远程带认证代理场景高**。

当前实现适合保存 `http://127.0.0.1:<port>` 这类本地代理，不适合保存 `user:pass@host:port` 这类高敏感代理凭据。

## 本机当前状态

本次检查时：

```text
~/.cac/envs/main/proxy      http://127.0.0.1:7897
~/.cac/envs/test-av/proxy   http://127.0.0.1:18999
```

没有发现代理凭据落盘。

`~/.cac/relay.log` 中主要是：

```text
[cac-relay] server error: listen EADDRINUSE: address already in use 127.0.0.1:17891
```

这不是凭据泄露，但说明 relay/watchdog 生命周期仍有噪声。若 relay 进程泄漏或端口占用长期存在，会增加诊断难度，并可能让用户误判代理健康状态。

## 风险等级

| 风险 | 等级 | 说明 |
| --- | --- | --- |
| 本地 Clash 端口泄露 | Low | 只暴露 `127.0.0.1:<port>`，通常无远程价值 |
| 远程代理账号密码落盘 | High | `proxy` / `relay.proxy` 明文保存 |
| 远程代理账号密码进程命令行暴露 | High | relay argv 包含完整 upstream URL |
| 终端输出泄露代理凭据 | Medium | create/set 路径会回显完整 URL |
| relay.log 泄露凭据 | Low 当前 / Medium 未来 | 当前未记录凭据，未来 debug 日志需防回归 |
| 真实 IP 因 proxy 不可达而泄露 | Low | 当前大多 fail-closed |
| 真实 IP 因网络栈绕过 env proxy 泄露 | Medium | cac 无系统级强制拦截能力 |
| 本机其他进程复用 relay 出口 | Medium | relay 监听 localhost，无 per-request client auth |

## 建议修复

### P0：禁止凭据明文回显

所有用户可见输出都应使用脱敏代理：

```text
http://***@proxy.example.com:8080
socks5://***@proxy.example.com:1080
```

需要覆盖：

- `cac env create -p ...`
- `cac env set <env> proxy ...`
- 错误输出
- relay 状态输出
- debug / verbose 输出

已有 `cac env ls` 的脱敏逻辑可抽成共享 helper，例如：

```bash
_mask_proxy() {
    sed 's|://[^@]*@|://***@|'
}
```

### P0：避免 relay argv 暴露完整代理 URL

不要把完整 `user:pass@host:port` 放进 Node 进程命令行。

可选方案：

1. relay 从只读临时文件读取 upstream URL，argv 只传文件路径。
2. relay 从环境变量读取 upstream URL，但注意进程环境也可能被同用户读取，安全性只比 argv 略好。
3. relay 从 Windows Credential Manager / DPAPI 读取凭据，磁盘文件只保存 host/port 和 credential id。
4. 拆分保存：argv 只传 host/port，凭据由本地 named pipe 或受限权限文件按需读取。

最低成本方案是“文件路径 + 严格 ACL + 输出脱敏”，但这仍不是强密钥管理。

### P1：代理文件权限收紧

创建或写入以下文件后，应尽量限制为当前用户可读：

```text
~/.cac/envs/<env>/proxy
~/.cac/relay.proxy
~/.cac/relay.token
```

Windows 上需要特别检查继承 ACL，避免 `Users`、`Authenticated Users`、`CodexSandboxUsers` 等宽泛主体读取代理凭据。

### P1：区分本地代理与远程认证代理

对以下配置给出不同策略：

| 类型 | 例子 | 策略 |
| --- | --- | --- |
| 本地无认证代理 | `http://127.0.0.1:7897` | 可以明文保存，低敏感 |
| LAN 无认证代理 | `http://192.168.1.2:7897` | 警告，仍可保存 |
| 远程无认证代理 | `http://proxy.example.com:8080` | 警告，说明进程 argv 暴露 |
| 认证代理 | `http://user:pass@host:port` | 强警告，建议使用凭据存储 |

### P1：`cac env check -d` 增加泄露面检查

建议新增诊断项：

- 当前代理是否包含凭据。
- `~/.cac/envs/<env>/proxy` 权限是否过宽。
- `~/.cac/relay.proxy` 是否包含凭据。
- relay 进程命令行是否包含 `://...@`。
- `relay.log` 是否出现疑似完整代理 URL 或 `Proxy-Authorization`。

输出示例：

```text
Security
  ✓ proxy      local loopback proxy
  ⚠ storage    proxy credentials stored in plaintext
  ⚠ argv       relay upstream URL visible in process command line
  ✓ log        no proxy credentials detected
```

### P2：文档明确安全边界

README 和 proxy setup 文档应明确：

- cac env proxy 是“环境变量代理 + 本地 relay”，不是进程级强制代理。
- 如果目标是防止任意网络栈直连，应使用 Proxinject、Proxifier、TUN 规则或防火墙策略。
- 不建议把远程代理账号密码直接写入 `cac env set proxy`。
- 推荐配置本地 Clash/mihomo mixed port，再由 Clash/mihomo 管理远程订阅和凭据。

## 推荐使用方式

当前最安全、最低维护成本的方式：

```powershell
cac env set main proxy http://127.0.0.1:7897
cac main
cac env check -d
```

远程代理账号密码应放在 Clash/mihomo/系统代理工具中，由 cac 只引用本地 loopback port：

```text
cac -> 127.0.0.1:7897 -> Clash/mihomo -> remote proxy with credentials
```

不推荐：

```powershell
cac env set main proxy http://user:pass@proxy.example.com:8080
```

如果必须这样做，应先完成：

- 输出脱敏
- relay argv 去敏
- proxy 文件 ACL 收紧
- `cac env check -d` 泄露面检查

## 验证清单

后续修复完成后，用以下清单验收：

- `cac env create -p http://user:pass@host:8080` 不在终端输出明文密码。
- `cac env set main proxy http://user:pass@host:8080` 不在终端输出明文密码。
- `cac env ls`、`cac env check -d`、`cac relay status` 均不输出明文密码。
- `relay.log` 不出现 `user:pass`、`Proxy-Authorization`、完整 upstream URL。
- Windows 进程命令行中看不到 `user:pass@host:port`。
- `~/.cac/envs/<env>/proxy` 和 `~/.cac/relay.proxy` ACL 仅当前用户和管理员可读。
- relay token 校验仍然通过，不能退化为“只要 localhost 端口可达就复用”。
- 代理不可达时 Claude 请求 fail-closed，不自动直连。

## 总结

cac 当前代理方案对本地 Clash/mihomo 端口是合理的：泄露的只是 `127.0.0.1:<port>`，真实 IP 路径也大多 fail-closed。

但它不应该被视为远程代理凭据管理器。只要用户把 `user:pass@host:port` 写进 cac，凭据就可能通过明文文件、relay 命令行、终端输出或宽松 ACL 泄露。

短期建议是文档明确“不保存远程代理凭据，只引用本地代理端口”。中期应实现输出脱敏、relay argv 去敏、文件权限收紧和 `cac env check -d` 泄露面诊断。
