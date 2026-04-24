# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is a **meta-project**: it ships a hardened `.claude/` baseline that is *installed into other projects* by `bootstrap.sh`. Nothing in this repo is the runtime application — the runtime is whatever target project the baseline gets copied into.

Two distinct CLAUDE.md files exist on purpose:

- **`/CLAUDE.md`** (this file) — guidance for working *on* the baseline itself (hooks, installer, CI).
- **`/secure-claude/CLAUDE.md`** — the *payload* that `bootstrap.sh` copies into target projects. It is loaded into Claude sessions in those projects, not this one. Edit it as a published artifact, not as instructions for this repo.

## Common commands

The Makefile mirrors CI exactly — `make test` locally is the same as a green CI run.

```bash
make test            # shellcheck + validate-json + validate-yaml + verify (full local CI)
make verify          # ./bootstrap.sh --verify — exercises every hook with synthetic events
make shellcheck      # lint bootstrap.sh + every hook script (severity=warning, excludes SC1091)
make validate-json   # jq empty on every *.json
make validate-yaml   # yq '.' on every *.yml / *.yaml
make gitleaks        # scan working tree (uses pinned GITLEAKS_VERSION)
make dry-run         # ./bootstrap.sh --local . --dry-run (preview an install)
make install-local   # install baseline into $PWD
make install-global  # install baseline into ~/.claude
make clean           # remove settings.json.bak.* files
```

To run a single hook test by hand, feed a synthetic event JSON on stdin:

```bash
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"AKIAIOSFODNN7EXAMPLE"}}' \
  | secure-claude/.claude/hooks/secret-scan.sh
echo $?   # rc=2 means the hook blocked, rc=0 means it allowed
```

`bootstrap.sh --verify` is the canonical "did I break anything?" check — it runs ~20 assertions across deps, hook syntax, hook behaviour, and `settings.json` merge semantics, and exits 1 if any fail. Run it after any change to `secure-claude/.claude/hooks/**`, `bootstrap.sh`, or `secure-claude/.claude/settings.json`.

## Architecture

### Source-of-truth layout

```
bootstrap.sh                      installer + --verify self-test (single file, ~700 lines)
secure-claude/                    the baseline payload (everything below ships to users)
  CLAUDE.md                       in-session conventions for target projects
  .mcp.json                       MCP servers (GH read-only, FS scoped to ${PROJECT_ROOT})
  .env.example, .gitignore        per-project files; copied on --local install only
  docs/threat-model.md.example    starter template; loaded by SessionStart hook
  .claude/
    settings.json                 hardened permissions + hook wiring + env
    commands/   *.md              slash commands (/security-review, /threat-model, /secret-scan)
    skills/     */SKILL.md        auto-loaded skill packs
    agents/     *.md              subagents (security-auditor, red-team)
    hooks/      *.sh              tripwires; share regex via lib/patterns.sh
      lib/patterns.sh             SECRET_TOKEN_PATTERNS, DESTRUCTIVE_COMMAND_PATTERNS,
                                  PERL_REDACTION, PROMPT_INJECTION_PATTERNS
.github/
  workflows/ci.yml                shellcheck / self-test / validate-configs / gitleaks
  CODEOWNERS                      maintainer-required review for high-trust paths
  dependabot.yml                  weekly SHA bumps for pinned actions
SECURITY.md                       Pwn-Request threat model + reporting policy
Makefile                          local equivalents of every CI job
```

### How the hooks fit together

Every hook reads the tool-call event as JSON on stdin and signals via exit code: `0` = allow, `2` = block (Claude sees the stderr message). The wiring lives in `secure-claude/.claude/settings.json` under `hooks.<event>` — that file is the only place that decides which hook runs on which event.

- **PreToolUse** (`Write|Edit|MultiEdit`) → `secret-scan.sh` (gitleaks, falls back to `SECRET_TOKEN_PATTERNS` regex)
- **PreToolUse** (`Bash`) → `block-destructive.sh` (matches `DESTRUCTIVE_COMMAND_PATTERNS`; `CLAUDE_BREAKGLASS` env var bypasses *with* an audit-log entry)
- **PreToolUse** (`Read|WebFetch|WebSearch`) → `prompt-injection-scan.sh` (`PROMPT_INJECTION_PATTERNS` + Unicode tag-block detection; modes: `warn`/`block`/`off`)
- **PostToolUse** (`Write|Edit|MultiEdit`) → `lint-and-typecheck.sh`
- **PostToolUse** (`.*`) → `audit-log.sh` (local SQLite or JSONL, optional Sumo / generic HTTPS forward; redacts via `PERL_REDACTION` before persist)
- **SessionStart** → `load-threat-model.sh` (injects `docs/threat-model.md` into context)
- **PreCompact** → `snapshot-session.sh`
- **Notification** → `notify-critical.sh` (Slack webhook if `SLACK_WEBHOOK_URL` set)

When extending: add the regex once to `secure-claude/.claude/hooks/lib/patterns.sh`, not to individual hooks. `audit-log.sh` deliberately omits `set -e` because a sink failure must never propagate to the agent — read the comment block at the top before changing its error handling.

### `bootstrap.sh` install semantics

The installer never silently drops user state. The `merge_settings_json` jq program (lines ~88–124) is the contract:

| Field                       | Rule                                                  |
|-----------------------------|-------------------------------------------------------|
| `permissions.allow` (array) | Union, baseline order first, dedup                    |
| `permissions.deny`  (array) | Union, baseline order first, dedup — **never drop a user deny** |
| `permissions.defaultMode`   | User wins on conflict                                 |
| `hooks.<event>` (array)     | Union; baseline first, then user; dedup on equality   |
| `env.<key>`                 | User wins; user-only keys preserved                   |

The merge is idempotent and always writes a `settings.json.bak.<YYYYMMDDhhmmss>` before rewriting. The `settings.json merge` block in `run_verify` (in `bootstrap.sh`) is the test suite — if you change merge semantics, those assertions must change in lockstep. Pass `--no-merge` to bypass merging entirely (implies `--force`).

The `act` helper in `bootstrap.sh` uses `eval`. Read the SECURITY comment above it before adding a new caller — every existing call passes a *static* command string with only validated path variables interpolated.

### CI / supply-chain posture (don't regress these)

`SECURITY.md` is the canonical doc. Hard rules enforced in `.github/workflows/ci.yml`:

1. **Trigger is `pull_request`, never `pull_request_target`.** PR code runs sandboxed with no secrets.
2. **Every third-party action pinned by 40-char SHA**, with a `# vX.Y.Z` comment. Dependabot proposes weekly bumps; never repin to a tag.
3. **Workflow `permissions: {}` at the top**, each job opts in to exactly what it needs (`contents: read` is usually enough).
4. **Every checkout sets `persist-credentials: false`** so later steps can't read `GITHUB_TOKEN` from `.git/config`.
5. **Every job starts with `step-security/harden-runner`** (currently `egress-policy: audit`).
6. **No `secrets.*` in any PR-triggered `run:` block.**
7. **`GITLEAKS_VERSION` lives in one place** — the `env:` block at the top of `ci.yml`. The README, the Makefile, and the install instructions reference it; bump them together.

Anything under `/.github/**`, `/secure-claude/.claude/hooks/**`, `/secure-claude/.claude/settings.json`, `/bootstrap.sh`, or `/SECURITY.md` requires CODEOWNERS approval — coordinate with the maintainer before changing them.

## Conventions specific to this repo

- **Don't introduce a new `.json`/`.yml` file without the validate-configs job covering it** — `make validate-json` / `make validate-yaml` glob the whole tree, so new files are picked up automatically as long as they live outside `node_modules/` and `.git/`.
- **Hook fixtures use *example* tokens** (`AKIAIOSFODNN7EXAMPLE`, `github_pat_xxxxxxxx`, `sk-abcdefghijklmnopqrstuvwxyz1234567890`) — these are allow-listed by path in the `gitleaks` job. If you add a new fixture, add the value to the `regexes` allowlist or its file to the `paths` allowlist in `ci.yml`.
- **Shared README/CLAUDE.md content must stay in sync.** The 5 non-negotiables appear in both `README.md § The 5 non-negotiables` and `secure-claude/CLAUDE.md § Security posture`. Edit both or neither.
- **Conventional commits with a `sec:` type for security-relevant changes** (per `secure-claude/CLAUDE.md`). The repo's actual log uses `feat:` / `fix:` / `chore:` predominantly.
- **Hook scripts must pass `bash -n`**, be executable (`chmod +x`), and pass `shellcheck --severity=warning --exclude=SC1091`. SC1091 is excluded because `lib/patterns.sh` is sourced at runtime and shellcheck can't follow it statically.
