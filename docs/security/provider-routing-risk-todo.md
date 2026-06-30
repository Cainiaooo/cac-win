# Provider Routing Risk TODO

> Status: TODO  
> Date: 2026-06-30  
> Scope: Windows-focused `cac-win` local environment management

## Purpose

Recent Claude Code versions appear to treat provider routing configuration and runtime locale/timezone as meaningful client-side signals. `cac-win` already manages several of these values, but the current behavior is spread across wrapper, env creation, runtime hooks, and check commands.

This document turns that scenario into an implementation TODO list. The goal is not to guarantee any account outcome or bypass any provider policy. The goal is to make local environment behavior explicit, auditable, and fail-safe:

- show whether a managed environment exposes custom provider routing values;
- warn when cloned settings carry provider routing or credential-like keys;
- verify that runtime timezone/locale settings match the environment configuration;
- avoid leaking secret values in logs or diagnostics;
- document the boundary between local environment management and server-side provider decisions.

## Current state

`cac-win` already has useful foundations:

- The wrapper uses proxy environment variables when a proxy is configured.
- In proxy mode, the wrapper currently removes `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and `ANTHROPIC_API_KEY` from the launched process.
- The environment stores `tz` and `lang`, then exports `TZ`, `CAC_TZ`, `LANG`, `LC_ALL`, `LC_MESSAGES`, `LC_TIME`, `CAC_LANG`, and `LANGUAGE` during launch.
- `fingerprint-hook.js` patches Node runtime locale/timezone APIs.
- `cac env check -d` already includes an Intl timezone/locale smoke test.
- `.claude` config is isolated per environment, but clone mode can still import host settings.

Gaps to close:

- No dedicated provider routing risk section in `cac env check`.
- No scan for provider routing keys inside `.claude/settings*.json` or cloned settings.
- No explicit user-facing policy for whether provider routing variables should be preserved, warned, or removed.
- No startup-level strict mode for high-risk local configuration combinations.
- No upgrade/audit reminder when Claude Code version changes.

## P0 tasks

### 1. Add an explicit provider routing policy

Add an environment setting:

```bash
cac env set [name] provider-routing <managed|warn|preserve>
```

Suggested behavior:

| Mode | Behavior |
|---|---|
| `managed` | The wrapper removes custom provider routing and credential-like variables before launching Claude Code. |
| `warn` | The wrapper preserves user configuration but `cac env check` reports visible provider routing keys. |
| `preserve` | The wrapper preserves user configuration and records that the user intentionally opted out of management. |

Suggested defaults:

- Proxy environment: `managed`.
- No-proxy environment: `warn`.

Files likely affected:

- `src/templates.sh`
- `src/cmd_env.sh`
- `src/cmd_check.sh`
- `README.md`

Acceptance criteria:

- Proxy environments continue to avoid exposing custom provider routing variables by default.
- No-proxy environments do not break existing user workflows, but visible provider routing is reported.
- Diagnostics show key names only, never values.
- Existing environments without this setting get a sane default.

### 2. Scan managed `.claude` settings for provider routing keys

Add a scanner used by `cac env check` and startup strict mode.

Files to scan:

```text
$env_dir/.claude/settings.json
$env_dir/.claude/settings.local.json
$env_dir/.claude/settings.override.json
$HOME/.claude/settings.json
$HOME/.claude/settings.local.json
$HOME/.claude.json
```

Keys to flag by name only:

```text
ANTHROPIC_BASE_URL
ANTHROPIC_API_KEY
ANTHROPIC_AUTH_TOKEN
CLAUDE_CODE_USE_BEDROCK
CLAUDE_CODE_USE_VERTEX
```

Acceptance criteria:

- `cac env check` shows a concise warning when risky keys are present.
- `cac env check -d` shows file paths and key names.
- Values are always redacted.
- Clone mode cannot silently import provider routing keys without a warning.

### 3. Add a `Signal guard` section to `cac env check`

Add a dedicated output block separate from telemetry and identity checks:

```text
Signal guard
  ✓ provider routing   managed
  ✓ settings scan      no provider routing keys
  ✓ runtime timezone   Intl probe ok
  ⚠ timezone           review manually when using custom provider routing
```

Acceptance criteria:

- The section appears in normal and detailed checks.
- Problems are included in the final summary.
- The output is useful even when no proxy is configured.

### 4. Add startup strict mode

Add an environment setting:

```bash
cac env set [name] signal-guard <warn|strict>
```

Suggested behavior:

| Mode | Behavior |
|---|---|
| `warn` | Print warnings but continue launching. |
| `strict` | Refuse to launch when high-risk local routing configuration is visible. |

Strict mode should block startup when:

- custom provider routing variables are visible to the child process;
- managed `.claude` settings contain provider routing keys;
- wrapper is not active but the user expects a managed environment.

Acceptance criteria:

- Strict mode fails closed with a clear message.
- Messages include repair commands.
- Secret values are never printed.

### 5. Update clone behavior

When cloning host `.claude` configuration, provider routing keys should not be silently carried into the managed environment.

Suggested options:

```bash
cac env create work --clone --sanitize-provider-routing
cac env create work --clone --preserve-provider-routing
```

Default recommendation: sanitize or warn by default; preserve only with explicit user intent.

Acceptance criteria:

- Clone output reports which key names were removed or preserved.
- Values remain redacted.
- Existing clone workflows remain usable.

## P1 tasks

### 6. Add a runtime inspection command

Add:

```bash
cac debug runtime
```

This should print a redacted summary of the actual runtime environment as launched through the cac wrapper:

```text
wrapper active: yes/no
provider-routing policy: managed/warn/preserve
ANTHROPIC_BASE_URL: hidden/present
ANTHROPIC_API_KEY: hidden/present
ANTHROPIC_AUTH_TOKEN: hidden/present
TZ: <timezone>
Intl timezone: <timezone>
locale: <locale>
```

Acceptance criteria:

- Works in PowerShell, CMD, and Git Bash.
- Uses the same wrapper path and env setup as real Claude launches as much as practical.
- Redacts all secret values.

### 7. Add Claude Code version audit hints

Add a lightweight command:

```bash
cac claude audit <current|version>
```

First implementation can be simple and conservative:

- identify installed Claude Code version;
- identify wrapper package vs platform binary;
- look for known marker strings only as a hint;
- report `known`, `unknown`, or `needs review` rather than pretending certainty.

Acceptance criteria:

- `cac claude audit current` works for managed versions.
- Unknown versions do not print a false green status.
- Auto-update flows suggest running `cac env check -d` after version changes.

### 8. Improve documentation

Update README with a section such as:

```text
Provider routing and signal guard
```

Include:

- what cac can manage locally;
- what cac cannot control, including account status, payment profile, OAuth state, IP reputation, and provider-side decisions;
- how to run `cac env check -d`;
- how to use `provider-routing` and `signal-guard` modes;
- how clone mode treats provider routing keys.

## P2 tasks

### 9. Add redacted environment report

Add:

```bash
cac env report --redact
```

Output should be safe to paste into issues:

```text
cac version
Claude Code version
OS and shell
wrapper active
provider-routing policy
signal-guard policy
proxy configured yes/no
runtime timezone
settings scan result
runtime probe result
```

### 10. Add automated tests

Suggested test files:

```text
tests/provider-routing-managed.bats
tests/provider-routing-warn.bats
tests/settings-provider-scan.bats
tests/signal-guard-strict.bats
tests/runtime-inspection.bats
```

Minimum cases:

- parent shell has provider routing variables and proxy env uses managed mode;
- no-proxy env uses warn mode and reports visible provider routing;
- settings file contains provider routing keys and check reports paths/key names;
- strict mode blocks unsafe local configuration;
- runtime timezone probe still passes after wrapper changes.

## Implementation order

1. Implement provider routing policy storage and defaults.
2. Add settings scanner.
3. Add `Signal guard` output to `cmd_check.sh`.
4. Add startup strict mode in wrapper generation.
5. Update clone sanitization behavior.
6. Update README.
7. Add tests.
8. Add version audit and redacted report commands.

## Definition of Done

- `cac env check -d` clearly shows whether custom provider routing is visible.
- Managed proxy environments do not expose provider routing variables by default.
- Cloned settings cannot silently import provider routing keys.
- Runtime timezone/locale checks stay visible and reliable.
- Startup strict mode fails closed on risky local configuration.
- No diagnostics print secret values.
- Documentation clearly states that cac manages local environment behavior only and cannot guarantee any provider-side account decision.
