# Session-Scoped Activation

## Motivation

By default, `cac <name>` writes the active environment to `~/.cac/current`, a persistent file. Activation survives across terminals and reboots. This is convenient but sometimes undesirable:

- **Multiple terminals, different envs**: You want `work` env in terminal A and `personal` in terminal B, without switching back and forth.
- **Temporary use**: You want to try an env briefly without changing the system-wide default.
- **Tooling conflicts**: Tools like cc-switch that manage `~/.claude/settings.json` should not leak changes into a session-scoped env.

## Usage

```bash
# Persistent activation (default, same as before)
cac work

# Session-scoped activation (this terminal only)
cac work --session
# or
cac work -s
```

With `--session`, activation lives only in the current terminal's environment variable (`$CAC_ACTIVE_ENV`). When the terminal closes, the activation disappears.

## How It Works

### Temp-file handshake

The core challenge: bash scripts run in subprocesses and cannot modify the parent shell's environment. The solution is an activation-only handshake via a temp file:

1. `cac <name> --session` writes the env name to `~/.cac/.session_env` (NOT `~/.cac/current`)
2. `cac <name>` writes `~/.cac/current` and also writes `~/.cac/.session_env` so the current shell follows the persistent activation
3. The shell function (in `.bashrc` or PowerShell profile) reads `.session_env`, exports `CAC_ACTIVE_ENV=<name>`, and deletes the temp file
4. Other `cac` commands do not write `.session_env`, so commands like `cac env ls` do not overwrite an existing session activation
5. The `~/.cac/bin/claude` wrapper checks `$CAC_ACTIVE_ENV` first, then falls back to `~/.cac/current`

### Activation priority

```
1. $CAC_ACTIVE_ENV  (session or persistent via shell function)
2. ~/.cac/current   (persistent file)
3. Error: no active environment
```

### `_current_env()` unification

The `_current_env()` helper (used by `cac env check`, relay management, etc.) checks `$CAC_ACTIVE_ENV` first, then `~/.cac/current`. This makes all existing callers session-aware with zero caller changes.

## Platform Support

| Terminal | Session Support | Mechanism |
|---|---|---|
| Git Bash (Windows) | Yes | `.bashrc` shell function |
| macOS/Linux bash/zsh | Yes | `.bashrc`/`.zshrc` shell function |
| PowerShell (Windows) | Yes | profile function in both `WindowsPowerShell` and `PowerShell` profile paths |
| CMD (Windows) | No | CMD has no shell function mechanism |

For CMD, persistent activation (`cac <name>` without `--session`) works as before via `~/.cac/current`.

## Upgrade Notes

Existing users do not need to recreate environments. Run any `cac` command after updating to let setup refresh the shell profile snippets, then open a new terminal or re-source your shell profile. On Windows, both Windows PowerShell and PowerShell Core profile paths are updated when available.

`cac self delete` already removes files under `~/.cac`; this feature only adds shell profile snippets outside that directory, using the existing marked `# >>> cac` / `# <<< cac` block.

## Interaction Matrix

| Operation | `~/.cac/current` | `$CAC_ACTIVE_ENV` | New terminal |
|---|---|---|---|
| `cac work` | "work" | "work" (fn) | Uses `work` (reads file) |
| `cac work --session` | unchanged | "work" (fn) | Unaffected |
| `cac work` then `cac dev --session` | "work" | "dev" | Other terminals use `work`, this terminal uses `dev` |
| Close session terminal | unchanged | gone | Unaffected |

## Files Changed

- `src/main.sh` — pass all args to `_env_cmd_activate`
- `src/cmd_env.sh` — `--session` flag in activate and create
- `src/utils.sh` — `_current_env()`, bash function in `_write_path_to_rc()`, new `_write_path_to_ps_profile()`
- `src/templates.sh` — wrapper env var priority, 4 shim functions
- `src/cmd_setup.sh` — call `_write_path_to_ps_profile()` on Windows
- `src/cmd_help.sh` — document `--session`
- `src/cmd_check.sh` — display session/persistent mode
