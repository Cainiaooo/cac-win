# ── cmd: check ─────────────────────────────────────────────────

# 检测本地代理软件冲突
_check_proxy_conflict() {
    local proxy="$1" proxy_ip="$2" verbose="$3"
    local proxy_hp; proxy_hp=$(_proxy_host_port "$proxy")
    local proxy_host="${proxy_hp%%:*}"

    local os; os=$(_detect_os)
    local conflicts=()

    # 检测 TUN 模式进程
    local tun_procs="clash|mihomo|sing-box|surge|shadowrocket|v2ray|xray|hysteria|tuic|nekoray"
    local running
    if [[ "$os" == "macos" ]]; then
        running=$(ps aux 2>/dev/null | grep -iE "$tun_procs" | grep -v grep || true)
    else
        running=$(ps -eo comm 2>/dev/null | grep -iE "$tun_procs" || true)
    fi
    if [[ -n "$running" ]]; then
        local proc_names
        proc_names=$(echo "$running" | grep -ioE "$tun_procs" | sort -u | head -3)
        [[ -n "$proc_names" ]] && conflicts+=("本地代理进程: $(echo "$proc_names" | tr '\n' ' ')")
    fi

    # 检测 TUN 网卡
    if [[ "$os" == "macos" ]]; then
        local tun_count
        tun_count=$(ifconfig 2>/dev/null | grep -cE '^utun[0-9]+' || echo 0)
        [[ "$tun_count" -gt 3 ]] && conflicts+=("TUN 网卡 ${tun_count} 个")
    elif [[ "$os" == "linux" ]]; then
        ip link show tun0 >/dev/null 2>&1 && conflicts+=("检测到 tun0")
    fi

    # 检测系统代理（macOS）
    if [[ "$os" == "macos" ]]; then
        local net_service
        net_service=$(networksetup -listallnetworkservices 2>/dev/null | grep -iE 'Wi-Fi|Ethernet|以太网' | head -1 || true)
        if [[ -n "$net_service" ]]; then
            local sys_http_proxy
            sys_http_proxy=$(networksetup -getwebproxy "$net_service" 2>/dev/null || true)
            if echo "$sys_http_proxy" | grep -qi "Enabled: Yes"; then
                local sys_host; sys_host=$(echo "$sys_http_proxy" | awk '/^Server:/{print $2}')
                local sys_port; sys_port=$(echo "$sys_http_proxy" | awk '/^Port:/{print $2}')
                [[ -n "$sys_host" ]] && conflicts+=("系统代理: ${sys_host}:${sys_port}")
            fi
        fi
    fi

    # 检测双重代理
    local direct_ip
    direct_ip=$(curl -s --noproxy '*' --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)
    if [[ -n "$direct_ip" ]] && [[ -n "$proxy_ip" ]] && [[ "$direct_ip" == "$proxy_ip" ]]; then
        conflicts+=("出口 IP 与直连相同，可能被拦截")
    fi

    # 无冲突
    if [[ ${#conflicts[@]} -eq 0 ]]; then
        return 0
    fi

    # 验证 relay 能否绕过
    local relay_ok=false
    if _relay_is_running 2>/dev/null; then
        local rport; rport=$(_read "$CAC_DIR/relay.port" "")
        local relay_ip
        relay_ip=$(curl -s --proxy "http://127.0.0.1:$rport" --connect-timeout 8 https://api.ipify.org 2>/dev/null || true)
        [[ -n "$relay_ip" ]] && relay_ok=true
    elif [[ -f "$CAC_DIR/relay.js" ]]; then
        local _test_env; _test_env=$(_current_env)
        if _relay_start "$_test_env" 2>/dev/null; then
            local rport; rport=$(_read "$CAC_DIR/relay.port" "")
            local relay_ip
            relay_ip=$(curl -s --proxy "http://127.0.0.1:$rport" --connect-timeout 8 https://api.ipify.org 2>/dev/null || true)
            _relay_stop 2>/dev/null || true
            [[ -n "$relay_ip" ]] && relay_ok=true
        fi
    fi

    if [[ "$relay_ok" == "true" ]]; then
        echo "$(_green "✓") relay 自动绕过"
        if [[ "$verbose" == "true" ]]; then
            for msg in "${conflicts[@]}"; do
                echo "    $(_dim "$msg")"
            done
        fi
        return 0
    fi

    # relay 失败
    echo "$(_red "✗") 代理冲突，需手动处理"
    for msg in "${conflicts[@]}"; do
        echo "    $(_yellow "•") $msg"
    done
    echo "    解决：在代理软件中为 $(_bold "$proxy_host") 添加 DIRECT 规则"
    return 1
}

cmd_check() {
    _require_setup

    local verbose=false
    [[ "${1:-}" == "-d" || "${1:-}" == "--detail" ]] && verbose=true

    local current; current=$(_current_env)

    if [[ -f "$CAC_DIR/stopped" ]]; then
        echo "$(_yellow "⚠") cac 已停用 — 运行 'cac <name>' 恢复"
        return
    fi
    if [[ -z "$current" ]]; then
        echo "错误：未激活任何环境，运行 'cac <name>'" >&2; exit 1
    fi

    local env_dir="$ENVS_DIR/$current"
    local proxy; proxy=$(_read "$env_dir/proxy" "")
    local ver; ver=$(_read "$env_dir/version" "system")

    # ── 基本信息 ──
    echo "$(_bold "$current") (claude: $(_cyan "$ver"))"

    if [[ "$verbose" == "true" ]]; then
        echo "  UUID      : $(_read "$env_dir/uuid")"
        echo "  stable_id : $(_read "$env_dir/stable_id")"
        echo "  user_id   : $(_read "$env_dir/user_id" "—")"
        echo "  TZ        : $(_read "$env_dir/tz" "—")"
        echo "  LANG      : $(_read "$env_dir/lang" "—")"
    fi

    # ── 网络 ──
    local proxy_ip=""
    if [[ -n "$proxy" ]]; then
        printf "  代理      : "
        if ! _proxy_reachable "$proxy"; then
            echo "$(_red "✗ 不通") ($proxy)"
            return
        fi
        proxy_ip=$(curl -s --proxy "$proxy" --connect-timeout 8 https://api.ipify.org 2>/dev/null || true)
        echo "$(_green "✓") ${proxy_ip:-?} $(_dim "via ${proxy%%@*}@...")"

        # 冲突检测
        printf "  冲突检测  : "
        _check_proxy_conflict "$proxy" "${proxy_ip:-}" "$verbose"
    else
        echo "  代理      : $(_dim "无（API Key 模式）")"
    fi

    # ── 安全防护（简洁模式只显示计数）──
    local wrapper_file="$CAC_DIR/bin/claude"
    local wrapper_content=""
    [[ -f "$wrapper_file" ]] && wrapper_content=$(<"$wrapper_file")
    local env_vars=(
        "CLAUDE_CODE_ENABLE_TELEMETRY" "DO_NOT_TRACK"
        "OTEL_SDK_DISABLED" "OTEL_TRACES_EXPORTER" "OTEL_METRICS_EXPORTER" "OTEL_LOGS_EXPORTER"
        "SENTRY_DSN" "DISABLE_ERROR_REPORTING" "DISABLE_BUG_COMMAND"
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "TELEMETRY_DISABLED" "DISABLE_TELEMETRY"
    )
    local env_ok=0 env_total=${#env_vars[@]}
    for var in "${env_vars[@]}"; do
        [[ "$wrapper_content" == *"$var"* ]] && (( env_ok++ )) || true
    done

    # DNS 拦截
    local dns_ok=false
    if [[ -f "$CAC_DIR/cac-dns-guard.js" ]]; then
        local dns_result
        dns_result=$(node -e '
            require(process.argv[1]);
            var dns = require("dns");
            dns.lookup(process.argv[2], function(err) {
                process.stdout.write(err && (err.code === "ECONNREFUSED" || err.code === "ENOTFOUND") ? "BLOCKED" : "OPEN");
            });
        ' "$CAC_DIR/cac-dns-guard.js" "statsig.anthropic.com" 2>/dev/null || echo "ERROR")
        [[ "$dns_result" == "BLOCKED" ]] && dns_ok=true
    fi

    # mTLS
    local mtls_ok=false
    local ca_cert="$CAC_DIR/ca/ca_cert.pem"
    local client_cert="$env_dir/client_cert.pem"
    [[ -f "$ca_cert" ]] && [[ -f "$client_cert" ]] && \
        openssl verify -CAfile "$ca_cert" "$client_cert" >/dev/null 2>&1 && mtls_ok=true

    if [[ "$verbose" == "true" ]]; then
        printf "  DNS 拦截  : "
        [[ "$dns_ok" == "true" ]] && echo "$(_green "✓")" || echo "$(_red "✗")"
        echo "  遥测屏蔽  : ${env_ok}/${env_total} 环境变量"
        for var in "${env_vars[@]}"; do
            printf "    %-36s" "$var"
            [[ "$wrapper_content" == *"$var"* ]] && echo "$(_green "✓")" || echo "$(_red "✗")"
        done
        printf "  mTLS      : "
        [[ "$mtls_ok" == "true" ]] && echo "$(_green "✓")" || echo "$(_yellow "—")"
    else
        local checks=() fails=()
        [[ "$dns_ok" == "true" ]] && checks+=("DNS 拦截") || fails+=("DNS 拦截")
        [[ "$env_ok" -eq "$env_total" ]] && checks+=("遥测屏蔽 ${env_ok}/${env_total}") || fails+=("遥测屏蔽 ${env_ok}/${env_total}")
        [[ "$mtls_ok" == "true" ]] && checks+=("mTLS") || true

        printf "  防护      : "
        if [[ ${#fails[@]} -eq 0 ]]; then
            echo "$(_green "✓") $(IFS=', '; echo "${checks[*]}")"
        else
            echo "$(_yellow "⚠") $(IFS=', '; echo "${fails[*]}")"
        fi
    fi
}
