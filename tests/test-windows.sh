#!/usr/bin/env bash
set -euo pipefail

# ── Windows 冒烟测试 (test-windows.sh) ──────────────────
# 在 Windows Git Bash (MINGW64) 环境下运行
# Linux 环境下自动跳过 Windows 专项测试，标记 SKIP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

# 检测平台
is_windows() { [[ "$(uname -s)" =~ MINGW*|MSYS*|CYGWIN* ]]; }
is_linux() { [[ "$(uname -s)" == Linux ]]; }

pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP+1)); echo "  ⏭️  $1"; }

echo "════════════════════════════════════════════════════════"
echo "  cac Windows 冒烟测试"
echo "  Platform: $(uname -s)"
echo "════════════════════════════════════════════════════════"

# source utils
source "$PROJECT_DIR/src/utils.sh" 2>/dev/null || { echo "FATAL: cannot source utils.sh"; exit 1; }
source "$PROJECT_DIR/src/cmd_claude.sh" 2>/dev/null || { echo "FATAL: cannot source cmd_claude.sh"; exit 1; }

# ── T01: 平台检测 ──
echo ""
echo "[T01] 平台检测"
p=$(_detect_platform)
if is_windows; then
    [[ "$p" =~ ^win32- ]] && pass "Windows 平台: $p" || fail "期望 win32-*, 实际: $p"
elif is_linux; then
    [[ "$p" =~ ^linux- ]] && pass "Linux 平台: $p" || fail "期望 linux-*, 实际: $p"
else
    pass "其他平台: $p"
fi

# ── T02: TCP 连通性检测 ──
echo ""
echo "[T02] TCP 连通性检测 (_tcp_check)"
if is_windows; then
    # Windows 下测试 _tcp_check 的 Node.js fallback
    node -e "const s=require('http').createServer(()=>{});s.listen(19883,'127.0.0.1',()=>console.log('READY'));setTimeout(()=>{s.close();process.exit(0)},3000);" &
    sleep 0.5
    _tcp_check 127.0.0.1 19883 && pass "开放端口可达" || fail "开放端口不可达"
    ! _tcp_check 127.0.0.1 19995 && pass "关闭端口不可达" || fail "关闭端口误报可达"
    wait
else
    skip "Windows 专项（Linux 下 _tcp_check 走原生 /dev/tcp）"
fi

# ── T03: python3 零残留 ──
echo ""
echo "[T03] python3 零残留 (src/*.sh)"
py=$(grep -rn 'python3' "$PROJECT_DIR/src/"*.sh 2>/dev/null || true)
if [[ -z "$py" ]]; then
    pass "src/*.sh 无 python3 引用"
else
    fail "python3 残留:"; echo "$py"
fi

# ── T04: /dev/tcp 仅在 utils.sh / 内联 helper ──
# templates.sh 的 wrapper 模板必须内联 _tcp_check（standalone 脚本无法 source utils.sh），
# 内联实现里同样使用 /dev/tcp 快路径 + node 兜底，与 utils.sh 行为对齐。
echo ""
echo "[T04] /dev/tcp 仅在 utils.sh / templates.sh 内联 helper"
dt=$(grep -rn '/dev/tcp' "$PROJECT_DIR/src/"*.sh 2>/dev/null | grep -vE 'src/(utils|templates)\.sh' || true)
if [[ -z "$dt" ]]; then
    pass "无外部 /dev/tcp 引用"
else
    fail "/dev/tcp 残留:"; echo "$dt"
fi

# ── T05: pgrep 仅在正确位置 ──
# 同样的原因，templates.sh 内联的 _count_claude_processes 在 Unix 分支使用 pgrep。
echo ""
echo "[T05] pgrep 仅在 Unix 分支 / utils.sh / templates.sh"
pg=$(grep -rn 'pgrep' "$PROJECT_DIR/src/"*.sh 2>/dev/null | grep -vE 'src/(utils|templates)\.sh' | grep -vi 'MINGW\|MSYS\|CYGWIN\|# ' || true)
if [[ -z "$pg" ]]; then
    pass "pgrep 仅在正确位置"
else
    fail "pgrep 残留:"; echo "$pg"
fi

# ── T06: 进程替换安全 ──
echo ""
echo "[T06] 进程替换 <(printf 已移除"
ps=$(grep -rn '<(printf' "$PROJECT_DIR/src/"*.sh 2>/dev/null || true)
if [[ -z "$ps" ]]; then
    pass "无 <(printf 进程替换"
else
    fail "进程替换残留:"; echo "$ps"
fi

# ── T07: UUID / UserID 生成 ──
echo ""
echo "[T07] UUID / UserID 生成"
uuid=$(_gen_uuid)
[[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && pass "_gen_uuid: $uuid" || fail "_gen_uuid: $uuid"
uid=$(_new_user_id)
[[ ${#uid} -eq 64 ]] && [[ "$uid" =~ ^[0-9a-f]+$ ]] && pass "_new_user_id: ${uid:0:16}..." || fail "_new_user_id: $uid"

# ── T08: SHA256 计算 ──
echo ""
echo "[T08] SHA256 计算"
tmpf=$(mktemp)
echo "test-cac-windows" > "$tmpf"
r=$(_sha256 "$tmpf")
if is_linux; then
    e=$(sha256sum "$tmpf" | cut -d' ' -f1)
    [[ "$r" == "$e" ]] && pass "sha256 匹配" || fail "sha256 不匹配"
else
    # Windows: 验证输出格式（64 位十六进制）
    [[ "$r" =~ ^[0-9a-f]{64}$ ]] && pass "sha256 格式正确: ${r:0:16}..." || fail "sha256 格式错误: $r"
fi
rm -f "$tmpf"

# ── T09: claude.cmd / cac.cmd 入口 ──
echo ""
echo "[T09] .cmd 入口文件"
if is_windows; then
    [[ -f "$PROJECT_DIR/cac.cmd" ]] && pass "cac.cmd 存在" || fail "cac.cmd 缺失"
    grep -q 'bash' "$PROJECT_DIR/cac.cmd" && pass "cac.cmd 调用 bash" || fail "cac.cmd 未调用 bash"
    grep -q 'claude.cmd' "$PROJECT_DIR/src/templates.sh" && pass "templates.sh 生成 claude.cmd" || fail "未生成 claude.cmd"
    grep -q 'CLAUDE_CODE_GIT_BASH_PATH' "$PROJECT_DIR/src/templates.sh" && pass "claude wrapper 设置 Git Bash 路径" || fail "未设置 CLAUDE_CODE_GIT_BASH_PATH"
else
    skip "Windows 专项（.cmd 入口文件）"
fi

# ── T10: 语法完整性 ──
echo ""
echo "[T10] 全部 .sh 文件语法检查"
syntax_ok=true
for f in "$PROJECT_DIR/src/"*.sh; do
    if ! bash -n "$f" 2>/dev/null; then
        echo "    ❌ $(basename "$f") 语法错误"
        syntax_ok=false
    fi
done
$syntax_ok && pass "所有 .sh 文件语法正确" || fail "存在语法错误"

# ── T11: Node.js JSON 解析 ──
echo ""
echo "[T11] Node.js JSON 解析 (_cac_setting)"
tmpdir=$(mktemp -d)
echo '{"proxy":"socks5://1.2.3.4:1080","max_sessions":"5"}' > "$tmpdir/settings.json"
CAC_DIR="$tmpdir" r=$(_cac_setting "max_sessions" "3")
[[ "$r" == "5" ]] && pass "_cac_setting 读取: $r" || fail "_cac_setting: $r"
CAC_DIR="$tmpdir" r=$(_cac_setting "nonexistent" "default")
[[ "$r" == "default" ]] && pass "_cac_setting 默认值" || fail "_cac_setting 默认值: $r"
rm -rf "$tmpdir"

# ── T12: 版本二进制路径 ──
echo ""
echo "[T12] _version_binary 平台感知"
export VERSIONS_DIR="/tmp/.cac-versions-test"
b=$(_version_binary "2.1.97")
if is_windows; then
    [[ "$b" == *".exe" ]] && pass "Windows 路径: $b" || fail "Windows 路径缺 .exe: $b"
else
    [[ "$b" == "/tmp/.cac-versions-test/2.1.97/claude" ]] && pass "Linux 路径: $b" || fail "Linux 路径: $b"
fi

# ── T13: postinstall.js 语法和 win32 检查 ──
echo ""
echo "[T13] postinstall.js Windows 适配"
node -c "$PROJECT_DIR/scripts/postinstall.js" 2>/dev/null && pass "语法正确" || fail "语法错误"
grep -q 'claude.cmd' "$PROJECT_DIR/scripts/postinstall.js" && pass "claude.cmd 路径" || fail "缺 claude.cmd"
grep -q 'win32' "$PROJECT_DIR/scripts/postinstall.js" && pass "win32 平台检查" || fail "缺 win32"

# ── T13b: Windows PATH 日志函数 ──
echo ""
echo "[T13b] Windows PATH 日志函数"
grep -q '^_log()' "$PROJECT_DIR/src/utils.sh" && pass "_log 已定义" || fail "_log 未定义"

# ── T14: manifest 平台解析 ──
echo ""
echo "[T14] manifest 平台解析"
manifest='{"platforms":{"win32-x64":{"checksum":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}}}'
checksum=$(printf '%s' "$manifest" | _manifest_checksum "win32-x64" 2>/dev/null || true)
[[ "$checksum" == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" ]] \
    && pass "win32-x64 checksum 解析正确" \
    || fail "manifest checksum 解析失败: $checksum"

# ── T15: Windows 原生路径转换 ──
echo ""
echo "[T15] Windows 原生路径转换"
native_path=$(_native_path "$HOME/.cac/fingerprint-hook.js")
if is_windows; then
    [[ "$native_path" =~ ^[A-Za-z]:\\ ]] && pass "Windows 路径已转换: $native_path" || fail "未转换为 Windows 原生路径: $native_path"
else
    [[ "$native_path" == "$HOME/.cac/fingerprint-hook.js" ]] && pass "非 Windows 保持原路径" || fail "非 Windows 路径异常: $native_path"
fi

# ── T16: mTLS 自愈钩子 ──
echo ""
echo "[T16] mTLS 自愈钩子"
grep -q '_generate_ca_cert' "$PROJECT_DIR/src/cmd_setup.sh" && pass "初始化包含 CA 重试" || fail "初始化缺少 CA 重试"
grep -q '_generate_client_cert "$name"' "$PROJECT_DIR/src/cmd_env.sh" && pass "激活包含 client cert 回填" || fail "激活缺少 client cert 回填"

# ── T17: 出口 IP 检测源 ──
echo ""
echo "[T17] 出口 IP 检测源"
grep -q 'http://ip-api.com/json/?fields=query,timezone' "$PROJECT_DIR/src/cmd_check.sh" && pass "优先使用 ip-api 当前连接检测" || fail "缺少 ip-api 当前连接检测"
! grep -q 'ip.3322.net' "$PROJECT_DIR/src/cmd_check.sh" && pass "已移除 ip.3322.net" || fail "仍然使用 ip.3322.net"

# ── T18: Windows OpenSSL 选择 ──
echo ""
echo "[T18] Windows OpenSSL 选择"
grep -q '^_openssl()' "$PROJECT_DIR/src/mtls.sh" && pass "_openssl helper 已定义" || fail "_openssl helper 未定义"
grep -q '/c/Program Files/Git/mingw64/bin/openssl.exe' "$PROJECT_DIR/src/mtls.sh" && pass "优先 Git for Windows 标准 OpenSSL 路径" || fail "缺少 Git for Windows 标准 OpenSSL 路径"

# ── T19: env check read 兼容 set -e ──
echo ""
echo "[T19] env check read 兼容 set -e"
grep -q 'read -r proxy_ip ip_tz .*|| true' "$PROJECT_DIR/src/cmd_check.sh" && pass "proxy metadata read 已防止提前退出" || fail "proxy metadata read 仍可能提前退出"

# ── T20: --no-link settings 隔离 ──
echo ""
echo "[T20] --no-link settings 隔离"
source "$PROJECT_DIR/src/templates.sh" 2>/dev/null || { echo "FATAL: cannot source templates.sh"; exit 1; }
source "$PROJECT_DIR/src/cmd_env.sh" 2>/dev/null || { echo "FATAL: cannot source cmd_env.sh"; exit 1; }

tmp_home=$(mktemp -d)
tmp_cac=$(mktemp -d)
old_home="$HOME"
old_cac_dir="${CAC_DIR:-}"
old_envs_dir="${ENVS_DIR:-}"
old_versions_dir="${VERSIONS_DIR:-}"
HOME="$tmp_home"
CAC_DIR="$tmp_cac"
ENVS_DIR="$CAC_DIR/envs"
VERSIONS_DIR="$CAC_DIR/versions"
mkdir -p "$HOME/.claude" "$ENVS_DIR" "$VERSIONS_DIR/2.1.97"
echo '{"source":"value","env":{"SOURCE_ONLY":"1"}}' > "$HOME/.claude/settings.json"
touch "$VERSIONS_DIR/2.1.97/claude.exe" "$VERSIONS_DIR/2.1.97/claude"
chmod +x "$VERSIONS_DIR/2.1.97/claude.exe" "$VERSIONS_DIR/2.1.97/claude"

_ensure_initialized() { mkdir -p "$CAC_DIR" "$ENVS_DIR" "$VERSIONS_DIR"; }
_ensure_version_installed() { echo "2.1.97"; }
_generate_client_cert() { return 0; }

if ( _env_cmd_create copied --clone --no-link -c 2.1.97 ) >/dev/null 2>&1; then
    [[ -f "$ENVS_DIR/copied/clone_mode" ]] && [[ "$(_read "$ENVS_DIR/copied/clone_mode")" == "copied" ]] \
        && pass "copy 模式写入 clone_mode=copied" \
        || fail "copy 模式缺少 clone_mode=copied"
    [[ ! -f "$ENVS_DIR/copied/clone_source" ]] \
        && pass "copy 模式不写 clone_source" \
        || fail "copy 模式仍写入 clone_source"
    [[ ! -f "$ENVS_DIR/copied/.claude/settings.override.json" ]] \
        && pass "copy 模式不写 settings.override.json" \
        || fail "copy 模式仍写入 settings.override.json"
    grep -q '"source": "value"' "$ENVS_DIR/copied/.claude/settings.json" \
        && pass "copy 模式创建时完成一次性 settings merge" \
        || fail "copy 模式未完成一次性 settings merge"
else
    fail "_env_cmd_create --clone --no-link 失败"
fi

mkdir -p "$ENVS_DIR/legacy/.claude"
echo '{"legacy":"merged"}' > "$ENVS_DIR/legacy/.claude/settings.json"
echo '{"legacy":"override"}' > "$ENVS_DIR/legacy/.claude/settings.override.json"
echo "$HOME/.claude" > "$ENVS_DIR/legacy/clone_source"
if ( _env_cmd_detach legacy ) >/dev/null 2>&1; then
    [[ ! -f "$ENVS_DIR/legacy/clone_source" ]] && [[ ! -f "$ENVS_DIR/legacy/.claude/settings.override.json" ]] \
        && pass "detach 清理旧 merge 残留" \
        || fail "detach 未清理旧 merge 残留"
    [[ "$(_read "$ENVS_DIR/legacy/clone_mode")" == "copied" ]] \
        && pass "detach 写入 clone_mode=copied" \
        || fail "detach 未写入 clone_mode=copied"
else
    fail "_env_cmd_detach legacy 失败"
fi

grep -q '_clone_mode.*copied' "$PROJECT_DIR/src/templates.sh" \
    && pass "wrapper merge 受 clone_mode=copied 保护" \
    || fail "wrapper merge 缺少 clone_mode=copied 保护"

HOME="$old_home"
CAC_DIR="$old_cac_dir"
ENVS_DIR="$old_envs_dir"
VERSIONS_DIR="$old_versions_dir"
rm -rf "$tmp_home" "$tmp_cac"

# ── T21: fingerprint hook runtime locale/timezone spoof ──
echo ""
echo "[T21] fingerprint hook runtime locale/timezone spoof"
grep -q 'export CAC_TZ=' "$PROJECT_DIR/src/templates.sh" && pass "wrapper 导出 CAC_TZ" || fail "wrapper 未导出 CAC_TZ"
grep -q 'export LC_ALL=' "$PROJECT_DIR/src/templates.sh" && pass "wrapper 导出 LC_ALL" || fail "wrapper 未导出 LC_ALL"
hook_output=$(CAC_TZ="America/New_York" CAC_LANG="en_US.UTF-8" node -r "$PROJECT_DIR/src/fingerprint-hook.js" -e "
const d = new Date('2026-01-01T12:00:00Z');
const ro = Intl.DateTimeFormat().resolvedOptions();
const roEmpty = Intl.DateTimeFormat([]).resolvedOptions();
const actual = d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const actualEmpty = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const expected = new Intl.DateTimeFormat('en-US', {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
  timeZone: 'America/New_York',
}).format(d);
process.stdout.write(JSON.stringify({
  tz: ro.timeZone || '',
  locale: ro.locale || '',
  emptyTz: roEmpty.timeZone || '',
  emptyLocale: roEmpty.locale || '',
  actual,
  actualEmpty,
  expected,
  stringValue: d.toString(),
  timeString: d.toTimeString(),
}));
" 2>/dev/null || true)
hook_status=$(printf '%s' "$hook_output" | node -e "
const fs = require('fs');
try {
  const d = JSON.parse(fs.readFileSync(0, 'utf8'));
  const localeOk = (v) => v === 'en-US' || v.startsWith('en-US-');
  const stringOk = /GMT-0500/.test(d.stringValue) && /GMT-0500/.test(d.timeString);
  process.stdout.write(
    d.tz === 'America/New_York' &&
    localeOk(d.locale) &&
    d.emptyTz === 'America/New_York' &&
    localeOk(d.emptyLocale) &&
    d.actual === d.expected &&
    d.actualEmpty === d.expected &&
    stringOk
      ? 'ok'
      : JSON.stringify(d)
  );
} catch (_) {
  process.stdout.write('parse-fail');
}
" 2>/dev/null || true)
[[ "$hook_status" == "ok" ]] && pass "hook 覆盖默认与空 locale 参数并伪装 Date 字符串" || fail "hook 未完整覆盖 Intl/Date: $hook_status"

# ── 总结 ──
echo ""
echo "════════════════════════════════════════════════════════"
echo "  结果: $PASS 通过, $FAIL 失败, $SKIP 跳过"
echo "════════════════════════════════════════════════════════"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
