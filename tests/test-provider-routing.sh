#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
SKIP=0

pass() { PASS=$((PASS + 1)); echo "  OK  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ERR $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  SKIP $1"; }

source_clean() {
    local file="$1"
    source <(perl -pe 's/\r$//' "$file")
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label"
        printf '%s\n' "$haystack"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label"
        printf '%s\n' "$haystack"
    fi
}

source_clean "$PROJECT_DIR/src/utils.sh"
source_clean "$PROJECT_DIR/src/dns_block.sh"
source_clean "$PROJECT_DIR/src/mtls.sh"
source_clean "$PROJECT_DIR/src/templates.sh"
source_clean "$PROJECT_DIR/src/cmd_claude.sh"
source_clean "$PROJECT_DIR/src/cmd_relay.sh"
source_clean "$PROJECT_DIR/src/cmd_check.sh"
source_clean "$PROJECT_DIR/src/cmd_env.sh"

reset_sandbox() {
    sandbox="$(mktemp -d)"
    HOME="$sandbox/home"
    CAC_DIR="$HOME/.cac"
    ENVS_DIR="$CAC_DIR/envs"
    VERSIONS_DIR="$CAC_DIR/versions"
    mkdir -p "$HOME" "$CAC_DIR" "$ENVS_DIR" "$VERSIONS_DIR"
    make_fake_claude
    cp "$PROJECT_DIR/src/fingerprint-hook.js" "$CAC_DIR/fingerprint-hook.js"
    echo "$fake_claude" > "$CAC_DIR/real_claude"
    export HOME CAC_DIR ENVS_DIR VERSIONS_DIR
}

make_fake_claude() {
    fake_claude="$sandbox/fake-claude"
    cat > "$fake_claude" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    echo "Claude Code 2.1.196"
    exit 0
fi
for key in ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_USE_BEDROCK; do
    if [[ -n "${!key-}" ]]; then
        echo "$key=present"
    else
        echo "$key=hidden"
    fi
done
EOF
    chmod +x "$fake_claude"
}

make_env() {
    local name="$1"
    local env_dir="$ENVS_DIR/$name"
    mkdir -p "$env_dir/.claude" "$VERSIONS_DIR/2.1.196"
    echo "$name" > "$CAC_DIR/current"
    echo "2.1.196" > "$env_dir/version"
    echo "America/New_York" > "$env_dir/tz"
    echo "en_US.UTF-8" > "$env_dir/lang"
    echo "test-host" > "$env_dir/hostname"
    echo "02:00:00:00:00:01" > "$env_dir/mac_address"
    echo "00000000000000000000000000000001" > "$env_dir/machine_id"
    echo "test@example.invalid" > "$env_dir/git_email"
    echo "https://github.com/example/example.git" > "$env_dir/fake_git_remote"
    echo "token" > "$env_dir/device_token"
    echo "{}" > "$env_dir/.claude/settings.json"
    cp "$fake_claude" "$VERSIONS_DIR/2.1.196/claude"
    chmod +x "$VERSIONS_DIR/2.1.196/claude"
}

clear_provider_env() {
    local key
    while IFS= read -r key; do
        [[ -n "$key" ]] && unset "$key"
    done < <(_provider_routing_keys)
}

echo "Provider routing regression tests"

reset_sandbox
make_env managed
_write_wrapper
echo "managed" > "$ENVS_DIR/managed/provider_routing"
clear_provider_env
wrapper_out="$(ANTHROPIC_BASE_URL="https://secret.invalid" ANTHROPIC_API_KEY="test-secret-redacted" ANTHROPIC_AUTH_TOKEN="test-secret-redacted" "$CAC_DIR/bin/claude" 2>&1)"
assert_contains "$wrapper_out" "ANTHROPIC_BASE_URL=hidden" "managed hides ANTHROPIC_BASE_URL"
assert_contains "$wrapper_out" "ANTHROPIC_API_KEY=hidden" "managed hides ANTHROPIC_API_KEY"
assert_not_contains "$wrapper_out" "test-secret-redacted" "managed output redacts secret values"
rm -rf "$sandbox"

reset_sandbox
make_env warn
_write_wrapper
echo "warn" > "$ENVS_DIR/warn/provider_routing"
clear_provider_env
wrapper_out="$(ANTHROPIC_BASE_URL="https://secret.invalid" "$CAC_DIR/bin/claude" 2>&1)"
assert_contains "$wrapper_out" "ANTHROPIC_BASE_URL=present" "warn preserves provider env"
assert_contains "$wrapper_out" "provider routing env visible: ANTHROPIC_BASE_URL" "warn reports visible provider env"
assert_not_contains "$wrapper_out" "https://secret.invalid" "warn output redacts provider env value"
rm -rf "$sandbox"

reset_sandbox
make_env scan
mkdir -p "$HOME/.claude"
echo '{"env":{"ANTHROPIC_BASE_URL":"test-secret-redacted","CLAUDE_CODE_USE_BEDROCK":"1"}}' > "$ENVS_DIR/scan/.claude/settings.json"
echo '{"env":{"ANTHROPIC_API_KEY":"test-secret-redacted"}}' > "$HOME/.claude/settings.json"
scan_out="$(_provider_routing_settings_scan "$ENVS_DIR/scan")"
assert_contains "$scan_out" "ANTHROPIC_BASE_URL" "settings scanner finds env settings key"
assert_contains "$scan_out" "ANTHROPIC_API_KEY" "settings scanner finds host settings key"
assert_contains "$scan_out" "credential" "settings scanner classifies credential"
assert_not_contains "$scan_out" "test-secret-redacted" "settings scanner redacts values"
check_out="$(cmd_check -d 2>&1 || true)"
assert_contains "$check_out" "Signal guard" "env check shows Signal guard section"
assert_contains "$check_out" "ANTHROPIC_BASE_URL" "env check details show provider key name"
assert_not_contains "$check_out" "test-secret-redacted" "env check redacts provider settings values"
rm -rf "$sandbox"

reset_sandbox
make_env strict
_write_wrapper
echo "warn" > "$ENVS_DIR/strict/provider_routing"
echo "strict" > "$ENVS_DIR/strict/signal_guard"
echo "Asia/Shanghai" > "$ENVS_DIR/strict/tz"
clear_provider_env
set +e
strict_out="$(ANTHROPIC_BASE_URL="https://secret.invalid" "$CAC_DIR/bin/claude" 2>&1)"
strict_rc=$?
set -e
[[ "$strict_rc" -ne 0 ]] && pass "strict blocks risky provider routing env" || fail "strict did not block risky provider routing env"
assert_contains "$strict_out" "signal-guard strict blocked Claude startup" "strict prints blocking error"
assert_not_contains "$strict_out" "https://secret.invalid" "strict output redacts provider env value"
rm -rf "$sandbox"

reset_sandbox
make_env strict_host_settings
_write_wrapper
mkdir -p "$HOME/.claude"
echo "strict" > "$ENVS_DIR/strict_host_settings/signal_guard"
echo '{"env":{"ANTHROPIC_API_KEY":"test-secret-redacted"}}' > "$HOME/.claude/settings.json"
clear_provider_env
set +e
strict_host_out="$("$CAC_DIR/bin/claude" 2>&1)"
strict_host_rc=$?
set -e
[[ "$strict_host_rc" -eq 0 ]] && pass "strict ignores host settings for isolated launch" || fail "strict incorrectly blocked isolated launch from host settings"
assert_not_contains "$strict_host_out" "signal-guard strict blocked Claude startup" "strict does not report host settings as effective"
assert_not_contains "$strict_host_out" "test-secret-redacted" "strict host settings output redacts secret values"
rm -rf "$sandbox"

reset_sandbox
mkdir -p "$HOME/.claude" "$VERSIONS_DIR/2.1.196"
echo '{"env":{"ANTHROPIC_BASE_URL":"test-secret-redacted"},"source":"value"}' > "$HOME/.claude/settings.json"
touch "$VERSIONS_DIR/2.1.196/claude" "$VERSIONS_DIR/2.1.196/claude.exe"
chmod +x "$VERSIONS_DIR/2.1.196/claude" "$VERSIONS_DIR/2.1.196/claude.exe"
_ensure_initialized() { mkdir -p "$CAC_DIR" "$ENVS_DIR" "$VERSIONS_DIR"; }
_ensure_version_installed() { echo "2.1.196"; }
_generate_client_cert() { return 0; }
clone_out="$(_env_cmd_create cloned --clone --no-link -c 2.1.196 2>&1)"
assert_contains "$clone_out" "provider routing removed from cloned settings: ANTHROPIC_BASE_URL" "clone reports sanitized provider key"
assert_not_contains "$(cat "$ENVS_DIR/cloned/.claude/settings.json")" "ANTHROPIC_BASE_URL" "clone sanitized provider key from settings"
assert_not_contains "$clone_out" "test-secret-redacted" "clone output redacts provider setting value"
rm -rf "$sandbox"

reset_sandbox
make_env runtime
node_probe="$(_runtime_intl_probe node "$CAC_DIR/fingerprint-hook.js" "America/New_York" "en_US.UTF-8")"
[[ "$node_probe" == "ok" ]] && pass "Node runtime probe passes" || fail "Node runtime probe failed: $node_probe"
bun_probe="$(_runtime_intl_probe bun "$CAC_DIR/fingerprint-hook.js" "America/New_York" "en_US.UTF-8")"
if [[ "$bun_probe" == "skip" ]]; then
    skip "Bun runtime not installed"
elif [[ "$bun_probe" == "ok" ]]; then
    pass "Bun runtime probe passes"
else
    fail "Bun runtime probe failed: $bun_probe"
fi
rm -rf "$sandbox"

echo "Result: $PASS passed, $FAIL failed, $SKIP skipped"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
