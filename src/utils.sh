# ── utils: colors, read/write, UUID, proxy parsing ───────────────────────

# shellcheck disable=SC2034  # used in build-concatenated cac script
CAC_VERSION="1.5.8-win.6"

_read()   { [[ -f "$1" ]] && tr -d '[:space:]' < "$1" || echo "${2:-}"; }
_die()    { printf '%b\n' "$(_red "error:") $*" >&2; exit 1; }

# Read a value from ~/.cac/settings.json
# Usage: _cac_setting "key" "default"
_cac_setting() {
    local key="$1" default="${2:-}"
    local settings="$CAC_DIR/settings.json"
    [[ -f "$settings" ]] || { echo "$default"; return; }
    local val
    val=$(node -e "
const fs = require('fs');
try {
  const d = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  const v = d[process.argv[2]];
  process.stdout.write(v == null ? '' : String(v));
} catch (_) {}
" "$settings" "$key" 2>/dev/null || true)
    val="${val:-$default}"
    # Sync hot-path keys as plain files (avoids node spawn in wrapper)
    [[ "$key" == "max_sessions" ]] && echo "$val" > "$CAC_DIR/max_sessions"
    echo "$val"
}
_bold()   { printf '\033[1m%s\033[0m' "$*"; }
_green()  { printf '\033[32m%s\033[0m' "$*"; }
_red()    { printf '\033[31m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }
_cyan()   { printf '\033[36m%s\033[0m' "$*"; }
_dim()    { printf '\033[2m%s\033[0m' "$*"; }
_green_bold() { printf '\033[1;32m%s\033[0m' "$*"; }
_log()    { printf '\033[32m✓\033[0m %b\n' "$*"; }

_detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

_native_path() {
    local path="$1"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            cygpath -w "$path" 2>/dev/null || printf '%s' "$path"
            ;;
        *)
            printf '%s' "$path"
            ;;
    esac
}

_display_path_with_home() {
    local path="$1" home_path="$2"
    [[ -n "$home_path" ]] || return 1
    if [[ "${path:0:${#home_path}}" == "$home_path" ]]; then
        printf '~%s' "${path:${#home_path}}"
        return 0
    fi
    return 1
}

_display_path() {
    local path="$1" home_path="${HOME:-}" home_native="" home_mixed=""
    _display_path_with_home "$path" "$home_path" && return 0
    if command -v cygpath >/dev/null 2>&1 && [[ -n "$home_path" ]]; then
        home_native=$(cygpath -w "$home_path" 2>/dev/null || true)
        _display_path_with_home "$path" "$home_native" && return 0
        home_mixed=$(cygpath -m "$home_path" 2>/dev/null || true)
        _display_path_with_home "$path" "$home_mixed" && return 0
    fi
    printf '%s' "$path"
}

# Path form for NODE_OPTIONS / BUN_OPTIONS only.
_node_require_path() {
    local path="$1"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            cygpath -m "$path" 2>/dev/null || printf '%s' "$path"
            ;;
        *)
            printf '%s' "$path"
            ;;
    esac
}

_provider_routing_keys() {
    cat <<'EOF'
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
EOF
}

_provider_routing_key_category() {
    case "$1" in
        ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_AWS_API_KEY)
            echo "credential"
            ;;
        CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST)
            echo "provider-mode"
            ;;
        CLAUDE_CODE_PROPAGATE_TRACEPARENT)
            echo "trace-propagation"
            ;;
        *)
            echo "routing"
            ;;
    esac
}

_provider_routing_policy() {
    local env_dir="$1" proxy="${2:-}" policy=""
    policy=$(_read "$env_dir/provider_routing" "")
    if [[ -z "$policy" ]]; then
        if [[ -n "$proxy" ]]; then
            policy="managed"
        else
            policy="warn"
        fi
    fi
    case "$policy" in
        managed|warn|preserve) echo "$policy" ;;
        *) echo "$([[ -n "$proxy" ]] && echo managed || echo warn)" ;;
    esac
}

_signal_guard_policy() {
    local env_dir="$1" policy=""
    policy=$(_read "$env_dir/signal_guard" "warn")
    case "$policy" in
        warn|strict) echo "$policy" ;;
        *) echo "warn" ;;
    esac
}

_provider_routing_env_keys_present() {
    local key val found=()
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        val="${!key-}"
        [[ -n "$val" ]] && found+=("$key")
    done < <(_provider_routing_keys)
    ((${#found[@]} == 0)) && return 0
    printf '%s\n' "${found[@]}"
}

_provider_routing_settings_files() {
    local env_dir="$1"
    local files=(
        "$env_dir/.claude/settings.json"
        "$env_dir/.claude/settings.local.json"
        "$env_dir/.claude/settings.override.json"
        "$HOME/.claude/settings.json"
        "$HOME/.claude/settings.local.json"
        "$HOME/.claude.json"
    )
    local file
    for file in "${files[@]}"; do
        [[ -f "$file" ]] && printf '%s\n' "$file"
    done
}

_provider_routing_settings_scan_paths() {
    (($# == 0)) && return 0
    node -e '
const fs = require("fs");
const keys = new Set([
  "ANTHROPIC_BASE_URL",
  "ANTHROPIC_API_KEY",
  "ANTHROPIC_AUTH_TOKEN",
  "ANTHROPIC_AWS_BASE_URL",
  "ANTHROPIC_AWS_API_KEY",
  "ANTHROPIC_BEDROCK_BASE_URL",
  "ANTHROPIC_BEDROCK_MANTLE_BASE_URL",
  "ANTHROPIC_FOUNDRY_BASE_URL",
  "ANTHROPIC_VERTEX_BASE_URL",
  "CLAUDE_CODE_USE_BEDROCK",
  "CLAUDE_CODE_USE_VERTEX",
  "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
  "CLAUDE_CODE_PROPAGATE_TRACEPARENT",
]);
function category(key) {
  if (key === "ANTHROPIC_API_KEY" || key === "ANTHROPIC_AUTH_TOKEN" || key === "ANTHROPIC_AWS_API_KEY") return "credential";
  if (key === "CLAUDE_CODE_USE_BEDROCK" || key === "CLAUDE_CODE_USE_VERTEX" || key === "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST") return "provider-mode";
  if (key === "CLAUDE_CODE_PROPAGATE_TRACEPARENT") return "trace-propagation";
  return "routing";
}
function visit(value, file, seen) {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    value.forEach(function(item) { visit(item, file, seen); });
    return;
  }
  Object.keys(value).forEach(function(key) {
    if (keys.has(key)) {
      const id = file + "\t" + key;
      if (!seen.has(id)) {
        seen.add(id);
        process.stdout.write(file + "\t" + key + "\t" + category(key) + "\n");
      }
    }
    visit(value[key], file, seen);
  });
}
process.argv.slice(1).forEach(function(file) {
  try {
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    visit(data, file, new Set());
  } catch (_) {}
});
' "$@" 2>/dev/null || true
}

_provider_routing_settings_scan() {
    local env_dir="$1" file
    local files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(_provider_routing_settings_files "$env_dir")
    ((${#files[@]} == 0)) && return 0
    _provider_routing_settings_scan_paths "${files[@]}"
}

_provider_routing_sanitize_settings_file() {
    local input="$1" output="$2"
    node -e '
const fs = require("fs");
const keys = new Set([
  "ANTHROPIC_BASE_URL",
  "ANTHROPIC_API_KEY",
  "ANTHROPIC_AUTH_TOKEN",
  "ANTHROPIC_AWS_BASE_URL",
  "ANTHROPIC_AWS_API_KEY",
  "ANTHROPIC_BEDROCK_BASE_URL",
  "ANTHROPIC_BEDROCK_MANTLE_BASE_URL",
  "ANTHROPIC_FOUNDRY_BASE_URL",
  "ANTHROPIC_VERTEX_BASE_URL",
  "CLAUDE_CODE_USE_BEDROCK",
  "CLAUDE_CODE_USE_VERTEX",
  "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
  "CLAUDE_CODE_PROPAGATE_TRACEPARENT",
]);
function sanitize(value) {
  if (!value || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(sanitize);
  const result = {};
  Object.keys(value).forEach(function(key) {
    if (!keys.has(key)) result[key] = sanitize(value[key]);
  });
  return result;
}
const input = process.argv[1];
const output = process.argv[2];
const data = JSON.parse(fs.readFileSync(input, "utf8"));
fs.writeFileSync(output, JSON.stringify(sanitize(data), null, 2) + "\n");
' "$input" "$output"
}

_runtime_intl_probe() {
    local runtime="$1" hook_path="$2" expected_tz="$3" expected_lang="$4"
    [[ -r "$hook_path" ]] || { echo "missing hook"; return 1; }

    local hook_option; hook_option=$(_node_require_path "$hook_path")
    local probe_js='
function norm(v){v=String(v||"").trim();if(!v)return "";v=v.split(/[,:;]/)[0].trim().replace(/\.UTF-?8$/i,"").replace(/_/g,"-");const p=v.split("-").filter(Boolean);if(!p.length)return "";p[0]=p[0].toLowerCase();if(p[1]&&p[1].length===2)p[1]=p[1].toUpperCase();return p.join("-");}
function localeOk(actual, expected){return !expected || actual===expected || (actual||"").startsWith(expected + "-u-");}
function gmt(minutes){const sign=minutes<=0?"+":"-";const abs=Math.abs(minutes);return "GMT"+sign+String(Math.floor(abs/60)).padStart(2,"0")+String(abs%60).padStart(2,"0");}
const tz=process.env.CAC_TZ||"";
const locale=norm(process.env.CAC_LANG||"");
const d=new Date("2026-01-01T12:00:00Z");
const opts={hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:false};
const ro=Intl.DateTimeFormat().resolvedOptions();
const emptyRo=Intl.DateTimeFormat([]).resolvedOptions();
const actual=d.toLocaleTimeString(undefined,opts);
const emptyActual=d.toLocaleTimeString([],opts);
const expected=new Intl.DateTimeFormat(ro.locale||locale||undefined,Object.assign({},opts,{timeZone:tz||undefined})).format(d);
const ok=(!tz||ro.timeZone===tz)&&(!tz||emptyRo.timeZone===tz)&&localeOk(ro.locale||"",locale)&&localeOk(emptyRo.locale||"",locale)&&(!tz||actual===expected)&&(!tz||emptyActual===expected)&&(!tz||d.toString().includes(gmt(d.getTimezoneOffset())));
process.stdout.write(ok ? "ok" : JSON.stringify({timeZone:ro.timeZone||"",locale:ro.locale||"",emptyTimeZone:emptyRo.timeZone||"",emptyLocale:emptyRo.locale||"",actual,emptyActual,expected,stringValue:d.toString()}));
'

    case "$runtime" in
        node)
            command -v node >/dev/null 2>&1 || { echo "skip"; return 0; }
            NODE_OPTIONS="--require $hook_option" CAC_TZ="$expected_tz" CAC_LANG="$expected_lang" \
                node -e "$probe_js" 2>/dev/null || true
            ;;
        bun)
            command -v bun >/dev/null 2>&1 || { echo "skip"; return 0; }
            BUN_OPTIONS="--preload $hook_option" CAC_TZ="$expected_tz" CAC_LANG="$expected_lang" \
                bun -e "$probe_js" 2>/dev/null || true
            ;;
        *)
            echo "unknown runtime"
            return 1
            ;;
    esac
}

_gen_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        node -e "process.stdout.write(require('crypto').randomUUID())" || _die "node required for UUID generation"
    fi
}
_new_uuid()    { _gen_uuid | tr '[:lower:]' '[:upper:]'; }
_new_user_id() { node -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))" || _die "node required"; }
_new_machine_id() { _gen_uuid | tr -d '-' | tr '[:upper:]' '[:lower:]'; }
_new_hostname_suffix() { _gen_uuid | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-5; }
_detect_hostname_platform() {
    local os; os=$(_detect_os)
    if [[ "$os" == "linux" ]]; then
        if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]] || \
           grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null || \
           uname -r 2>/dev/null | grep -qi microsoft; then
            echo "windows"
            return
        fi
    fi
    echo "$os"
}
_new_hostname() {
    local -a _first_names=(
        "James" "John" "Robert" "Michael" "William" "David" "Richard" "Joseph"
        "Thomas" "Charles" "Daniel" "Matthew" "Anthony" "Donald" "Mark" "Paul"
        "Steven" "Andrew" "Kenneth" "Joshua" "Kevin" "Brian" "George" "Timothy"
        "Emma" "Olivia" "Sophia" "Isabella" "Mia" "Charlotte" "Amelia" "Harper"
        "Evelyn" "Abigail" "Emily" "Elizabeth" "Sofia" "Avery" "Ella" "Scarlett"
        "Liam" "Noah" "Oliver" "Elijah" "Lucas" "Mason" "Ethan" "Aiden"
        "Alex" "Ryan" "Tyler" "Jordan" "Taylor" "Morgan" "Casey" "Riley"
    )
    local _name="${_first_names[$((RANDOM % ${#_first_names[@]}))]}"
    local _platform; _platform=$(_detect_hostname_platform)
    case "$_platform" in
        macos)
            local -a _models=("MacBook-Pro" "MacBook-Air" "MacBook-Pro" "MacBook-Pro")
            local _model="${_models[$((RANDOM % ${#_models[@]}))]}"
            echo "${_name}s-${_model}.local"
            ;;
        windows)
            local -a _prefixes=("DESKTOP" "LAPTOP")
            local _prefix="${_prefixes[$((RANDOM % ${#_prefixes[@]}))]}"
            echo "${_prefix}-$(_new_hostname_suffix)"
            ;;
        *)
            local -a _devices=("desktop" "laptop" "workstation" "thinkpad")
            local _device="${_devices[$((RANDOM % ${#_devices[@]}))]}"
            echo "$(printf '%s' "$_name" | tr '[:upper:]' '[:lower:]')-${_device}"
            ;;
    esac
}
_new_mac() { printf '02:%02x:%02x:%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)); }
_new_git_remote() { echo "https://github.com/user-$(_gen_uuid | cut -d- -f1)/project-$(_gen_uuid | cut -d- -f2).git"; }
_new_git_email() { echo "user-$(_gen_uuid | cut -d- -f1 | tr '[:upper:]' '[:lower:]')@users.noreply.github.com"; }
_new_device_token() { _new_user_id; }

# Get real command path (bypass shim)
_get_real_cmd() {
    local cmd="$1"
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$CAC_DIR/shim-bin" | tr '\n' ':') \
        command -v "$cmd" 2>/dev/null || true
}

# host:port:user:pass → http://user:pass@host:port
# socks5://host:port:user:pass → socks5://user:pass@host:port
# or pass a standard URL directly (http://, https://, socks5://)
_parse_proxy() {
    local raw="$1"
    local proto rest

    [[ -n "$raw" ]] || return 0

    # Normalize protocol-prefixed legacy form:
    #   socks5://host:port:user:pass -> socks5://user:pass@host:port
    if [[ "$raw" =~ ^(http|https|socks5):// ]]; then
        proto="${raw%%://*}"
        rest="${raw#*://}"
        if [[ "$rest" != *"@"* ]] && [[ "$rest" == *:*:* ]]; then
            local host port user pass
            host=$(echo "$rest" | cut -d: -f1)
            port=$(echo "$rest" | cut -d: -f2)
            user=$(echo "$rest" | cut -d: -f3)
            pass=$(echo "$rest" | cut -d: -f4-)
            if [[ -n "$host" ]] && [[ -n "$port" ]] && [[ -n "$user" ]]; then
                echo "${proto}://${user}:${pass}@${host}:${port}"
                return
            fi
        fi
        echo "$raw"
        return
    fi
    # Parse host:port:user:pass format
    local host port user pass
    host=$(echo "$raw" | cut -d: -f1)
    port=$(echo "$raw" | cut -d: -f2)
    user=$(echo "$raw" | cut -d: -f3)
    pass=$(echo "$raw" | cut -d: -f4-)
    if [[ -z "$user" ]]; then
        echo "http://${host}:${port}"
    else
        echo "http://${user}:${pass}@${host}:${port}"
    fi
}

# curl-based health probes should use remote DNS for SOCKS5.
# Otherwise local DNS pollution can resolve probe domains to sinkhole/test
# addresses, causing false negatives even when the proxy itself is healthy.
_curl_proxy_url() {
    local normalized
    normalized=$(_parse_proxy "$1")
    if [[ "$normalized" =~ ^socks5:// ]]; then
        echo "socks5h://${normalized#socks5://}"
    else
        echo "$normalized"
    fi
}

# socks5://user:pass@host:port → host:port
_proxy_host_port() {
    local normalized
    normalized=$(_parse_proxy "$1")
    echo "$normalized" | sed 's|.*@||' | sed 's|.*://||'
}

_tcp_check() {
    local host="$1" port="$2" timeout_sec="${3:-2}"
    if (echo >"/dev/tcp/$host/$port") 2>/dev/null; then
        return 0
    fi
    node -e "
const net = require('net');
const host = process.argv[1];
const port = Number(process.argv[2]);
const timeoutMs = Number(process.argv[3]) * 1000;
const s = net.createConnection({ host, port, timeout: timeoutMs });
s.on('connect', () => { s.destroy(); process.exit(0); });
s.on('timeout', () => { s.destroy(); process.exit(1); });
s.on('error', () => process.exit(1));
" "$host" "$port" "$timeout_sec" >/dev/null 2>&1
}

_relay_new_token() {
    local token=""
    token=$(node -e "process.stdout.write(require('crypto').randomBytes(16).toString('hex'))" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
        printf '%s' "$token"
        return 0
    fi
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    if [[ -r /dev/urandom ]]; then
        od -An -tx1 -N16 /dev/urandom | tr -d ' \n'
        return 0
    fi
    printf '%08x%08x%08x%08x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" | tr '[:upper:]' '[:lower:]'
}

_relay_verify_listener() {
    local port="$1" token="$2" timeout_sec="${3:-2}"
    [[ -n "$port" ]] && [[ -n "$token" ]] || return 1
    node -e "
const http = require('http');
const port = Number(process.argv[1]);
const token = process.argv[2];
const timeoutMs = Number(process.argv[3]) * 1000;
const req = http.request({
  host: '127.0.0.1',
  port,
  path: '/__cac_relay_health__/' + token,
  method: 'GET',
  timeout: timeoutMs,
  headers: { Connection: 'close' }
}, function(res) {
  const replyToken = res.headers['x-cac-relay-token'];
  res.resume();
  res.on('end', function() {
    process.exit(res.statusCode === 204 && replyToken === token ? 0 : 1);
  });
});
req.on('timeout', function() { req.destroy(); process.exit(1); });
req.on('error', function() { process.exit(1); });
req.end();
" "$port" "$token" "$timeout_sec" >/dev/null 2>&1
}

_relay_instances_dir() {
    echo "$CAC_DIR/relay.instances"
}

_relay_instance_write() {
    local token="$1" port="$2" pid="$3"
    local dir; dir=$(_relay_instances_dir)
    [[ -n "$token" ]] && [[ -n "$port" ]] && [[ -n "$pid" ]] || return 1
    mkdir -p "$dir"
    echo "$pid" > "$dir/$token.pid"
    echo "$port" > "$dir/$token.port"
}

_relay_instance_remove() {
    local token="$1"
    local dir; dir=$(_relay_instances_dir)
    [[ -n "$token" ]] || return 0
    rm -f "$dir/$token.pid" "$dir/$token.port"
}

_relay_pid_is_cac_owned() {
    local pid="$1"
    local dir; dir=$(_relay_instances_dir)
    [[ -n "$pid" ]] || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    if [[ -d "$dir" ]]; then
        local pid_file token port saved_pid
        for pid_file in "$dir"/*.pid; do
            [[ -f "$pid_file" ]] || continue
            token=$(basename "$pid_file" .pid)
            saved_pid=$(tr -d '[:space:]' < "$pid_file" 2>/dev/null || true)
            [[ "$saved_pid" == "$pid" ]] || continue
            port=$(tr -d '[:space:]' < "$dir/$token.port" 2>/dev/null || true)
            _relay_verify_listener "$port" "$token" && return 0
        done
    fi
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            local relay_js relay_native relay_b64
            relay_js="$CAC_DIR/relay.js"
            [[ -f "$relay_js" ]] || return 1
            relay_native=$(_native_path "$relay_js")
            relay_b64=$(node -e "process.stdout.write(Buffer.from(process.argv[1], 'utf8').toString('base64'))" "$relay_native" 2>/dev/null) || return 1
            powershell.exe -NoProfile -Command "
                try {
                    \$relayPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$relay_b64'))
                    \$proc = Get-CimInstance Win32_Process -Filter \"ProcessId=$pid\" -ErrorAction Stop
                    if (\$proc -and \$proc.CommandLine -and \$proc.CommandLine.IndexOf(\$relayPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { exit 0 }
                } catch {}
                exit 1
            " >/dev/null 2>&1
            ;;
        *)
            local relay_js="$CAC_DIR/relay.js"
            [[ -f "$relay_js" ]] || return 1
            ps -p "$pid" -o args= 2>/dev/null | awk -v relay="$relay_js" 'index($0, relay) { found=1 } END { exit(found ? 0 : 1) }'
            ;;
    esac
}

_proxy_reachable() {
    local hp host port
    hp=$(_proxy_host_port "$1")
    host=$(echo "$hp" | cut -d: -f1)
    port=$(echo "$hp" | cut -d: -f2)
    _tcp_check "$host" "$port"
}

# Auto-detect proxy protocol (when user didn't specify http/socks5/https)
# Usage: _auto_detect_proxy "host:port:user:pass" → returns a working full URL
_auto_detect_proxy() {
    local raw="$1"
    # Has protocol prefix, return as-is
    if [[ "$raw" =~ ^(http|https|socks5):// ]]; then
        echo "$raw"
        return 0
    fi

    local host port user pass auth_part
    host=$(echo "$raw" | cut -d: -f1)
    port=$(echo "$raw" | cut -d: -f2)
    user=$(echo "$raw" | cut -d: -f3)
    pass=$(echo "$raw" | cut -d: -f4-)
    if [[ -n "$user" ]]; then
        auth_part="${user}:${pass}@"
    else
        auth_part=""
    fi

    # Try in order: http → socks5 → https
    local proto try_url
    for proto in http socks5 https; do
        try_url="${proto}://${auth_part}${host}:${port}"
        if curl --proxy "$try_url" -fsSL --connect-timeout 8 -o /dev/null https://api.ipify.org 2>/dev/null; then
            echo "$try_url"
            return 0
        fi
    done

    # All failed, fallback to http
    if [[ -n "$user" ]]; then
        echo "http://${auth_part}${host}:${port}"
    else
        echo "http://${host}:${port}"
    fi
    return 1
}

_current_env()  { _read "$CAC_DIR/current"; }
_env_dir()      { echo "$ENVS_DIR/$1"; }

# ── Version management helpers ────────────────────────────────────

# Find the highest installed version by semver sort
_update_latest() {
    local highest=""
    for d in "$VERSIONS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local v
        v=$(basename "$d")
        [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || continue
        if [[ -z "$highest" ]] || [[ "$(printf '%s\n%s\n' "$highest" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" == "$v" ]]; then
            highest="$v"
        fi
    done
    if [[ -n "$highest" ]]; then
        echo "$highest" > "$VERSIONS_DIR/.latest"
    else
        rm -f "$VERSIONS_DIR/.latest"
    fi
}

_resolve_version() {
    local v="$1"
    if [[ "$v" == "latest" || -z "$v" ]]; then
        _read "$VERSIONS_DIR/.latest" ""
    else
        echo "$v"
    fi
}

_version_binary() {
    local binary="claude"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) binary="claude.exe" ;;
    esac
    echo "$VERSIONS_DIR/$1/$binary"
}

_detect_platform() {
    local os arch platform
    case "$(uname -s)" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        MINGW*|MSYS*|CYGWIN*) os="win32" ;;
        *) echo "unsupported" ; return 1 ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)   arch="x64" ;;
        arm64|aarch64)  arch="arm64" ;;
        *) echo "unsupported" ; return 1 ;;
    esac
    if [[ "$os" == "darwin" && "$arch" == "x64" ]]; then
        [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" == "1" ]] && arch="arm64"
    fi
    if [[ "$os" == "linux" ]]; then
        if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
            platform="linux-${arch}-musl"
        else
            platform="linux-${arch}"
        fi
    else
        platform="${os}-${arch}"
    fi
    echo "$platform"
}

_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        node -e "
const fs = require('fs');
const crypto = require('crypto');
const b = fs.readFileSync(process.argv[1]);
process.stdout.write(crypto.createHash('sha256').update(b).digest('hex'));
" "$file"
    fi
}

_count_claude_processes() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            tasklist.exe //FO CSV //NH 2>/dev/null \
                | tr -d '\r' \
                | awk -F',' 'tolower($1) ~ /^"claude(\.exe)?"$/ { c++ } END { print c+0 }'
            ;;
        *)
            pgrep -x "claude" 2>/dev/null | wc -l | tr -d '[:space:]' || echo 0
            ;;
    esac
}

# Ensure a Claude Code version is installed (just-in-time, like uv)
# Usage: _ensure_version_installed <version>
# Resolves "latest", auto-downloads if missing, writes .latest
_ensure_version_installed() {
    local ver="$1"
    ver=$(_resolve_version "$ver")
    if [[ -z "$ver" ]]; then
        printf "Fetching latest version ... " >&2
        ver=$(_fetch_latest_version) || _die "failed to fetch latest version"
        echo "$(_cyan "$ver")" >&2
    fi
    if [[ ! -x "$(_version_binary "$ver")" ]]; then
        echo "Version $(_cyan "$ver") not installed, downloading ..." >&2
        mkdir -p "$VERSIONS_DIR"
        _download_version "$ver" >&2 || return 1
        _update_latest
        echo >&2
    fi
    echo "$ver"
}

# Count environments using a specific version
_envs_using_version() {
    local ver="$1" count=0
    for env_dir in "$ENVS_DIR"/*/; do
        [[ -d "$env_dir" ]] || continue
        [[ "$(_read "$env_dir/version" "")" == "$ver" ]] && (( count++ )) || true
    done
    echo "$count"
}

# Elapsed time helper: call _timer_start, then _timer_elapsed
_time_now() {
    local now
    now=$(date +%s%N 2>/dev/null || true)
    if [[ "$now" =~ ^[0-9]{11,}$ ]]; then
        echo "$now"
    else
        date +%s
    fi
}

_timer_start() { _TIMER_START=$(_time_now); }
_timer_elapsed() {
    local now; now=$(_time_now)
    if [[ "$now" =~ ^[0-9]{11,}$ && "${_TIMER_START:-}" =~ ^[0-9]{11,}$ ]]; then
        # nanoseconds available
        local ms=$(( (now - _TIMER_START) / 1000000 ))
        if [[ $ms -ge 1000 ]]; then
            printf '%d.%ds' $((ms/1000)) $(( (ms%1000)/100 ))
        else
            printf '%dms' "$ms"
        fi
    else
        printf '%ds' $(( now - _TIMER_START ))
    fi
}

_require_setup() {
    _ensure_initialized
}

_require_env() {
    [[ -d "$ENVS_DIR/$1" ]] || {
        echo "error: environment '$1' not found, use 'cac ls' to list" >&2; exit 1
    }
}

_find_real_claude() {
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$CAC_DIR/bin" | tr '\n' ':') \
        command -v claude 2>/dev/null || true
}

_detect_rc_file() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)
            [[ -f "$HOME/.zshrc" ]] && { echo "$HOME/.zshrc"; return; }
            ;;
        bash)
            [[ -f "$HOME/.bashrc" ]] && { echo "$HOME/.bashrc"; return; }
            [[ -f "$HOME/.bash_profile" ]] && { echo "$HOME/.bash_profile"; return; }
            ;;
    esac
    # Fallback: try common rc files
    [[ -f "$HOME/.bashrc" ]] && { echo "$HOME/.bashrc"; return; }
    [[ -f "$HOME/.zshrc" ]] && { echo "$HOME/.zshrc"; return; }
    [[ -f "$HOME/.bash_profile" ]] && { echo "$HOME/.bash_profile"; return; }
    echo ""
}

_install_method() {
    local self="$0"
    local resolved="$self"
    if [[ -L "$self" ]]; then
        resolved=$(readlink "$self" 2>/dev/null || echo "$self")
        # Handle relative symlinks
        if [[ "$resolved" != /* ]]; then
            resolved="$(dirname "$self")/$resolved"
        fi
    fi
    if [[ "$resolved" == *"node_modules"* ]] || [[ -f "$(dirname "$resolved")/package.json" ]]; then
        echo "npm"
    else
        echo "bash"
    fi
}

_write_path_to_rc() {
    local rc_file="${1:-$(_detect_rc_file)}"
    # Windows: Git Bash sources ~/.bashrc but it doesn't ship by default. Create it
    # so the cac PATH stanza below has a home — otherwise the wrapper is silently
    # bypassed by whatever else owns `claude` on PATH.
    if [[ -z "$rc_file" ]]; then
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*)
                rc_file="$HOME/.bashrc"
                touch "$rc_file" 2>/dev/null || true
                ;;
        esac
    fi
    if [[ -z "$rc_file" ]] || [[ ! -e "$rc_file" ]]; then
        echo "  $(_yellow '⚠') shell config file not found, please add PATH manually:"
        echo '    export PATH="$HOME/bin:$PATH"'
        echo '    export PATH="$HOME/.cac/bin:$PATH"'
        return 0
    fi

    if grep -q '# >>> cac >>>' "$rc_file" 2>/dev/null; then
        echo "  ✓ PATH already exists in $rc_file, skipping"
        return 0
    fi

    # Compat: remove old format if present
    if grep -q '\.cac/bin' "$rc_file" 2>/dev/null; then
        _remove_path_from_rc "$rc_file"
    fi

    cat >> "$rc_file" << 'CACEOF'

# >>> cac — Claude Code Cloak >>>
PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '\.cac/bin' | tr '\n' ':' | sed 's/:$//')
export PATH="$HOME/.cac/bin:$PATH"
cac() {
    local _cac_bin
    _cac_bin=$(PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '\.cac/bin' | tr '\n' ':') command -v cac 2>/dev/null)
    [[ -z "$_cac_bin" ]] && { echo "[cac] error: cac binary not found in PATH" >&2; return 1; }
    command "$_cac_bin" "$@"
    local _rc=$?
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '\.cac/bin' | tr '\n' ':' | sed 's/:$//')
    export PATH="$HOME/.cac/bin:$PATH"
    return $_rc
}
# <<< cac — Claude Code Cloak <<<
CACEOF
    echo "  ✓ PATH written to $rc_file"
    return 0
}

_remove_path_from_rc() {
    local rc_file="${1:-$(_detect_rc_file)}"
    [[ -z "$rc_file" ]] && return 0

    # Remove marked block (new format)
    if grep -q '# >>> cac' "$rc_file" 2>/dev/null; then
        local tmp="${rc_file}.cac-tmp"
        awk '/# >>> cac/{skip=1; next} /# <<< cac/{skip=0; next} !skip' "$rc_file" > "$tmp"
        cat -s "$tmp" > "$rc_file"
        rm -f "$tmp"
        echo "  ✓ Removed PATH config from $rc_file"
        return 0
    fi

    # Compat: old format
    if grep -qE '(\.cac/bin|# cac —)' "$rc_file" 2>/dev/null; then
        local tmp="${rc_file}.cac-tmp"
        grep -vE '(# cac — Claude Code Cloak|\.cac/bin|# cac 命令|# claude wrapper)' "$rc_file" > "$tmp" || true
        cat -s "$tmp" > "$rc_file"
        rm -f "$tmp"
        echo "  ✓ Removed PATH config from $rc_file (old format)"
        return 0
    fi
}

_update_claude_json_user_id() {
    local user_id="$1"
    local config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local claude_json="$config_dir/.claude.json"
    [[ -f "$claude_json" ]] || claude_json="$HOME/.claude.json"
    [[ -f "$claude_json" ]] || return 0

    # Find firstStartTime from current env
    local fst=""
    local current_env; current_env=$(_current_env)
    if [[ -n "$current_env" ]] && [[ -f "$ENVS_DIR/$current_env/first_start_time" ]]; then
        fst=$(tr -d '[:space:]' < "$ENVS_DIR/$current_env/first_start_time")
    fi

    node -e "
const fs = require('fs');
const crypto = require('crypto');
const fpath = process.argv[1];
const uid = process.argv[2];
const fst = process.argv[3] || '';
const d = JSON.parse(fs.readFileSync(fpath, 'utf8'));
d.userID=uid;
d.anonymousId='claudecode.v1.'+crypto.randomUUID();
delete d.numStartups;
if(fst){d.firstStartTime=fst;}else{delete d.firstStartTime;}
delete d.cachedGrowthBookFeatures;
delete d.cachedStatsigGates;
fs.writeFileSync(fpath, JSON.stringify(d, null, 2) + '\n');
" "$claude_json" "$user_id" "$fst"
    [[ $? -eq 0 ]] || echo "warning: failed to update claude.json userID" >&2
}

# ── Windows PATH helper ────────────────────────────────────
# Prepend (not append) so the cac wrapper wins over any other Claude install
# (e.g. ~/.local/bin/claude.exe). Idempotent: if already at the front, no-op;
# if present elsewhere, move to the front.
_add_to_user_path() {
    local dir="$1"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            local win_path
            win_path="$(cygpath -w "$dir" 2>/dev/null || echo "$dir")"
            local position
            position="$(powershell.exe -NoProfile -Command "
                \$target = '$win_path'
                \$current = [Environment]::GetEnvironmentVariable('Path','User')
                if (-not \$current) { 'missing'; exit }
                \$parts = @(\$current -split ';' | Where-Object { \$_ })
                if (\$parts.Count -gt 0 -and \$parts[0].TrimEnd('\\') -ieq \$target.TrimEnd('\\')) { 'first' }
                elseif (\$parts | Where-Object { \$_.TrimEnd('\\') -ieq \$target.TrimEnd('\\') }) { 'present' }
                else { 'missing' }
            " 2>/dev/null | tr -d '\r' | tail -n 1)"
            if [[ "$position" == "first" ]]; then
                _log "PATH already begins with $dir"
                return 0
            fi
            powershell.exe -NoProfile -Command "
                \$target = '$win_path'
                \$current = [Environment]::GetEnvironmentVariable('Path','User')
                \$parts = @(\$current -split ';' | Where-Object { \$_ -and \$_.TrimEnd('\\') -ine \$target.TrimEnd('\\') })
                \$new = (@(\$target) + \$parts) -join ';'
                [Environment]::SetEnvironmentVariable('Path', \$new, 'User')
            " 2>/dev/null
            if [[ $? -eq 0 ]]; then
                _log "Prepended $dir to User PATH (restart terminal to take effect)"
            else
                _warn "Failed to add $dir to User PATH"
            fi
            ;;
        *)
            _warn "PATH modification only supported on Windows"
            ;;
    esac
}
