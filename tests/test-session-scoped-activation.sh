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
echo "[S02] bash shell function handshake"
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
echo "[S03] PowerShell profile coverage"
if is_windows; then
    ps_home="$tmpdir/pshome"
    mkdir -p "$ps_home/Documents/WindowsPowerShell" "$ps_home/Documents/PowerShell"
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
else
    skip "PowerShell profile generation is Windows-only"
fi

echo
echo "════════════════════════════════════════════════════════"
echo "  Result: $PASS passed, $FAIL failed, $SKIP skipped"
echo "════════════════════════════════════════════════════════"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
