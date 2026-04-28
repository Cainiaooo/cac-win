# ── cmd: self (cac self-management, like "uv self") ──────────────

_self_cmd_update() {
    cat >&2 <<EOF

$(_yellow "warning:") $(_bold "cac self update") is disabled in cac-win.

This fork is install-by-local-clone, not npm. Running self-update would
overwrite your local cac with upstream nmhjklnm/cac and discard all
Windows-specific patches.

To update cac-win, from your cloned repository run:

    git pull origin master
    npm install
    powershell -ExecutionPolicy Bypass -File ./scripts/install-local-win.ps1

Then reopen your terminal.

EOF
    exit 1
}

cmd_self() {
    case "${1:-help}" in
        update)          _self_cmd_update ;;
        delete|remove)   cmd_delete ;;
        help|-h|--help)
            echo "$(_bold "cac self") — cac self-management"
            echo
            echo "  $(_bold "delete")    Uninstall cac completely"
            echo
            echo "  $(_dim "cac self update is disabled in cac-win.")"
            echo "  $(_dim "Update via 'git pull' + scripts/install-local-win.ps1 in your clone.")"
            ;;
        *) _die "unknown: cac self $1" ;;
    esac
}
