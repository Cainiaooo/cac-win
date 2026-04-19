#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

is_windows() { [[ "$(uname -s)" =~ MINGW*|MSYS*|CYGWIN* ]]; }
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP+1)); echo "  ⏭️  $1"; }

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    [[ "$actual" == "$expected" ]] && pass "$label" || fail "$label (expected '$expected', got '$actual')"
}

assert_file() {
    local path="$1" label="$2"
    [[ -e "$path" ]] && pass "$label" || fail "$label"
}

assert_no_file() {
    local path="$1" label="$2"
    [[ ! -e "$path" ]] && pass "$label" || fail "$label"
}

echo "════════════════════════════════════════════════════════"
echo "  Session-scoped activation smoke test"
echo "════════════════════════════════════════════════════════"

source "$PROJECT_DIR/src/utils.sh"
source "$PROJECT_DIR/src/cmd_env.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export CAC_DIR="$tmpdir/.cac"
export ENVS_DIR="$CAC_DIR/envs"
export VERSIONS_DIR="$CAC_DIR/versions"
mkdir -p "$CAC_DIR" "$ENVS_DIR" "$VERSIONS_DIR"

echo
echo "[S01] activation file writes"
touch "$CAC_DIR/stopped"
_env_record_activation work false
assert_eq "$(_read "$CAC_DIR/current")" "work" "persistent activation writes current"
assert_eq "$(_read "$CAC_DIR/.session_env")" "work" "persistent activation syncs current shell"
assert_no_file "$CAC_DIR/stopped" "persistent activation resumes cac"

printf 'work\n' > "$CAC_DIR/current"
touch "$CAC_DIR/stopped"
_env_record_activation dev true
assert_eq "$(_read "$CAC_DIR/current")" "work" "session activation leaves persistent current unchanged"
assert_eq "$(_read "$CAC_DIR/.session_env")" "dev" "session activation writes handshake"
assert_no_file "$CAC_DIR/stopped" "session activation resumes cac"

echo
echo "[S02] persistent active env removal guard"
mkdir -p "$ENVS_DIR/work" "$ENVS_DIR/dev"
printf 'work\n' > "$CAC_DIR/current"
export CAC_ACTIVE_ENV=dev
if ( _env_cmd_rm work >/dev/null 2>&1 ); then
    fail "cannot remove persistent active env during session"
else
    pass "cannot remove persistent active env during session"
fi
assert_file "$ENVS_DIR/work" "persistent active env still exists"
unset CAC_ACTIVE_ENV

echo
echo "[S03] bash shell function handshake"
shell_home="$tmpdir/home"
mkdir -p "$shell_home/.cac/bin" "$tmpdir/toolbin"
fake_cac="$tmpdir/toolbin/cac"
cat > "$fake_cac" <<'FAKECAC'
#!/usr/bin/env bash
mkdir -p "$HOME/.cac"
case "$*" in
    "dev --session")
        printf 'dev\n' > "$HOME/.cac/.session_env"
        ;;
    "work")
        printf 'work\n' > "$HOME/.cac/current"
        printf 'work\n' > "$HOME/.cac/.session_env"
        ;;
    "env ls")
        ;;
esac
FAKECAC
chmod +x "$fake_cac"

rc_file="$shell_home/.bashrc"
cat > "$rc_file" <<'OLDRC'
# >>> cac — Claude Code Cloak >>>
cac() {
    export CAC_ACTIVE_ENV=$(tr -d '[:space:]' < "$HOME/.cac/current")
}
# <<< cac — Claude Code Cloak <<<
OLDRC
HOME="$shell_home" _write_path_to_rc "$rc_file" >/dev/null
grep -q 'local _cac_next_env' "$rc_file" \
    && pass "bash function upgrades old session block" \
    || fail "bash function did not upgrade old session block"
if (
    export HOME="$shell_home"
    export PATH="$HOME/.cac/bin:$tmpdir/toolbin:$PATH"
    # shellcheck disable=SC1090
    source "$rc_file"
    printf 'work\n' > "$HOME/.cac/current"

    cac dev --session >/dev/null
    [[ "${CAC_ACTIVE_ENV:-}" == "dev" ]] || exit 10
    [[ ! -f "$HOME/.cac/.session_env" ]] || exit 11

    cac env ls >/dev/null
    [[ "${CAC_ACTIVE_ENV:-}" == "dev" ]] || exit 12

    cac work >/dev/null
    [[ "${CAC_ACTIVE_ENV:-}" == "work" ]] || exit 13
) then
    pass "bash function preserves session env across non-activation commands"
else
    rc=$?
    case "$rc" in
        10) fail "bash function did not export session env" ;;
        11) fail "bash function did not remove handshake file" ;;
        12) fail "bash function overwrote session env on non-activation command" ;;
        13) fail "bash function did not sync persistent activation" ;;
        *) fail "bash function handshake failed unexpectedly" ;;
    esac
fi

echo
echo "[S04] PowerShell profile coverage"
if is_windows; then
    ps_home="$tmpdir/pshome"
    ps_toolbin="$tmpdir/pstoolbin"
    mkdir -p "$ps_home/Documents/WindowsPowerShell" "$ps_home/Documents/PowerShell"
    mkdir -p "$ps_home/.cac/bin" "$ps_toolbin"
    cat > "$ps_home/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1" <<'OLDPS'
# >>> cac — Claude Code Cloak >>>
function cac {
    $currentFile = Join-Path $env:USERPROFILE ".cac\current"
    $env:CAC_ACTIVE_ENV = (Get-Content $currentFile -Raw).Trim()
}
# <<< cac — Claude Code Cloak <<<
OLDPS
    USERPROFILE="$ps_home" _write_path_to_ps_profile >/dev/null
    assert_file "$ps_home/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1" "WindowsPowerShell profile written"
    assert_file "$ps_home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1" "PowerShell Core profile written"
    grep -q 'if (Test-Path $sessionFile)' "$ps_home/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1" \
        && pass "PowerShell profile uses activation handshake" \
        || fail "PowerShell profile missing activation handshake"
    ! grep -q 'currentFile' "$ps_home/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1" \
        && pass "PowerShell profile preserves session on non-activation commands" \
        || fail "PowerShell profile still resets from currentFile"
    cat > "$ps_toolbin/cac.ps1" <<'FAKEPS'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)
$cacDir = Join-Path $env:USERPROFILE ".cac"
New-Item -ItemType Directory -Force $cacDir | Out-Null
if (($Rest -join ' ') -eq 'dev --session') {
    Set-Content -Path (Join-Path $cacDir ".session_env") -Value "dev"
}
FAKEPS
    if command -v powershell.exe >/dev/null 2>&1; then
        ps_home_win=$(cygpath -w "$ps_home")
        ps_toolbin_win=$(cygpath -w "$ps_toolbin")
        ps_profile_win=$(cygpath -w "$ps_home/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1")
        if powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "\$env:USERPROFILE = '$ps_home_win'; \$env:Path = '$ps_toolbin_win;' + \$env:Path; . '$ps_profile_win'; cac dev --session; if (\$env:CAC_ACTIVE_ENV -ne 'dev') { exit 10 }; if (Test-Path (Join-Path \$env:USERPROFILE '.cac\.session_env')) { exit 11 }" >/dev/null 2>&1; then
            pass "PowerShell profile invokes cac from PATH and applies handshake"
        else
            rc=$?
            fail "PowerShell profile runtime handshake failed (exit $rc)"
        fi
    else
        skip "powershell.exe unavailable for profile runtime test"
    fi
else
    skip "PowerShell profile generation is Windows-only"
fi

echo
echo "[S05] relay state isolation"
grep -q '_relay_pid_file="$_env_dir/relay.pid"' "$PROJECT_DIR/src/templates.sh" \
    && pass "claude wrapper stores relay pid per env" \
    || fail "claude wrapper still uses global relay pid"
grep -q 'local pid_file="$env_dir/relay.pid"' "$PROJECT_DIR/src/cmd_relay.sh" \
    && pass "relay command stores relay pid per env" \
    || fail "relay command still uses global relay pid"
grep -q '_relay_stop_all' "$PROJECT_DIR/src/cmd_env.sh" \
    && pass "cac pause stops all env relays" \
    || fail "cac pause does not stop all env relays"

echo
echo "════════════════════════════════════════════════════════"
echo "  Result: $PASS passed, $FAIL failed, $SKIP skipped"
echo "════════════════════════════════════════════════════════"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
