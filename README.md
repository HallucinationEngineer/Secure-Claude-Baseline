# Secure Claude Baseline

A ready-to-drop-in hardened `.claude/` folder for Claude Code, including slash commands,
skills, subagents, PreToolUse/PostToolUse hooks, a least-privilege `.mcp.json`, and an
installer that can target either a single project (local) or your user home (global).

> **Credit.** This baseline is a direct implementation of the field notes published by
> **[Okan Yildiz](https://www.linkedin.com/in/yildizokan)** — *"Claude Code, locked down.
> A security engineer's `.claude/` folder"*
> ([LinkedIn post, Jan 2025](https://www.linkedin.com/posts/yildizokan_aisecurity-claudecode-devsecops-activity-7451270082749517824-yMJ2)).
> All five non-negotiables, the hook layout, the MCP scoping approach, and the directory
> structure come from Okan's writeup. This repo packages them as runnable files and adds
> an installer so you can apply the baseline in one command. Thanks, Okan — go follow him
> for daily AI-security & DevSecOps insights.

---

## What you get

```
secure-claude/
├── CLAUDE.md                              project conventions loaded every session
├── .mcp.json                              MCP servers (GH read-only, scoped FS)
├── .env.example                           committed; .env never is
├── .gitignore                             ignores .env + settings.local.json + .claude/audit/
└── .claude/
    ├── settings.json                      hardened permissions + hooks + env
    ├── settings.local.json.example        dev-only override template
    ├── commands/
    │   ├── security-review.md             /security-review
    │   ├── threat-model.md                /threat-model
    │   └── secret-scan.md                 /secret-scan
    ├── skills/
    │   ├── code-review/SKILL.md
    │   ├── security-audit/SKILL.md
    │   └── secret-handler/SKILL.md
    ├── agents/
    │   ├── security-auditor.md            independent AppSec reviewer subagent
    │   └── red-team.md                    adversarial-review subagent
    ├── hooks/
    │   ├── secret-scan.sh                 PreToolUse: gitleaks on every Write/Edit
    │   ├── block-destructive.sh           PreToolUse: extra Bash guardrails (rm -rf, curl|sh, ...)
    │   ├── lint-and-typecheck.sh          PostToolUse: fast linter + type check on changed files
    │   ├── load-threat-model.sh           SessionStart: inject docs/threat-model.md into context
    │   ├── snapshot-session.sh            PreCompact: archive transcript before context is lost
    │   ├── notify-critical.sh             Notification: Slack webhook for high-signal events
    │   ├── audit-log.sh                   PostToolUse: SQLite + optional Sumo/HTTPS forward
    │   ├── prompt-injection-scan.sh       PreToolUse (Read/WebFetch/WebSearch): injection warnings
    │   └── lib/patterns.sh                shared regex library sourced by every hook
    └── plugins/.gitkeep
```

### The 5 non-negotiables (from Okan's post)

> Keep this list in sync with `secure-claude/CLAUDE.md § Security posture` —
> that file is the in-session version Claude reads on every load.

1. **Never commit `.env` or `settings.local.json`** — both are in `.gitignore`.
2. **Scope the filesystem MCP to the project root** — `.mcp.json` uses `${PROJECT_ROOT}`.
3. **PreToolUse hook runs gitleaks on every Write** — see `hooks/secret-scan.sh`.
4. **Read-only credentials for any database MCP** — if you add one, scope it to SELECT-only.
5. **Log every tool call** — `hooks/audit-log.sh` writes to a local SQLite DB (`.claude/audit/tool-calls.db`, JSONL fallback) and optionally forwards to Sumo Logic, Splunk HEC, Datadog, or any HTTPS endpoint. Secret shapes are redacted before leaving the box.

---

## Prerequisites

The hooks rely on a small set of common Unix tools. `jq`, `perl`, and `curl` are
usually preinstalled; `sqlite3` and `gitleaks` are the ones you'll typically
need to add.

| Tool       | Purpose                                 | Required? |
|------------|-----------------------------------------|-----------|
| `bash`     | Runs every hook in `.claude/hooks/`     | Yes       |
| `jq`       | Builds & redacts audit records          | Yes       |
| `perl`     | Redaction regex engine                  | Yes       |
| `curl`     | Remote audit forwarding + notifications | If remote |
| `sqlite3`  | Primary local audit sink                | Recommended (falls back to JSONL) |
| `gitleaks` | PreToolUse secret scan                  | Recommended (falls back to built-in regex) |

### macOS

```bash
brew install jq sqlite gitleaks   # curl + perl ship with macOS
```

### Linux

```bash
# Debian / Ubuntu
sudo apt-get install -y jq perl curl sqlite3
# gitleaks — binary install (apt package often lags). Keep this version in
# lockstep with .github/workflows/ci.yml's GITLEAKS_VERSION env var.
curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz \
  | tar -xz -C /tmp gitleaks && sudo mv /tmp/gitleaks /usr/local/bin/

# Fedora / RHEL
sudo dnf install -y jq perl curl sqlite

# Arch
sudo pacman -S jq perl curl sqlite gitleaks

# Alpine (Docker)
apk add bash jq perl curl sqlite
```

### Windows

Native PowerShell can't run the `.sh` hooks directly — Claude Code hooks are
bash scripts. Two supported paths:

**Option A: WSL (recommended)**
```powershell
wsl --install                 # one-time, then reboot
```
Open your project from inside WSL (`\\wsl$\Ubuntu\...` or `cd /mnt/c/...`)
and install prereqs using the Linux instructions above. Claude Code on
Windows detects and uses WSL bash automatically for `.sh` hooks.

**Option B: Git for Windows (Git Bash)**
```powershell
winget install --id Git.Git
winget install --id jqlang.jq
winget install --id SQLite.SQLite
winget install --id Gitleaks.Gitleaks
# curl + perl ship inside Git Bash's /usr/bin
```
Then run `bootstrap.sh` from a Git Bash shell (not PowerShell / cmd).
Claude Code will invoke hooks via the bundled bash.

**Option C: Scoop / Chocolatey**
```powershell
# scoop
scoop install git jq sqlite gitleaks

# chocolatey
choco install git jq sqlite gitleaks
```

> Windows users: if you want native PowerShell hooks instead of bash, open an
> issue — we can port the hooks to `.ps1` equivalents as a follow-up.

### FreeBSD / OpenBSD

```sh
pkg install bash jq perl5 curl sqlite3 gitleaks
```

---

## Install

The `bootstrap.sh` installer copies `secure-claude/` into either a project or your user home.
On Windows, run it from WSL or Git Bash — see **Prerequisites** above.

### Local install (into an existing project)

```bash
# macOS / Linux / WSL / Git Bash — from this repo's root:
./bootstrap.sh --local /path/to/your/project

# Or interactively from the target project:
cd /path/to/your/project
/path/to/Secure-Claude-Baseline/bootstrap.sh
```

The installer will:

- Copy `.claude/`, `.mcp.json`, `.env.example`, and `CLAUDE.md` into the target.
- Union-merge `settings.json` if one already exists (see **Merge semantics** below).
- Append missing entries to the target's `.gitignore`, `.env.example`, and `CLAUDE.md`.
- Make the hook scripts executable.

### Merge semantics (existing `settings.json`)

The installer performs a **union merge** — it never silently drops a user's
rule. A timestamped backup is saved as `settings.json.bak.<YYYYMMDDhhmmss>`
before the file is rewritten.

| Field                       | Rule                                                        |
|-----------------------------|-------------------------------------------------------------|
| `permissions.allow` (array) | **Union** — baseline rules first, then any user additions   |
| `permissions.deny`  (array) | **Union** — baseline + user; a user deny is NEVER dropped   |
| `permissions.defaultMode`   | **User wins** on conflict                                   |
| `hooks.<event>`     (array) | **Union** — baseline entries first, then user's; both run   |
| `env.<key>`                 | **User wins** on conflict (user-only keys preserved)        |
| `$schema`, other scalars    | **User wins** on conflict                                   |

Re-running the installer against an already-merged file is idempotent — the
same user+baseline input produces byte-identical output.

Pass `--force` to bypass the merge and overwrite with the raw baseline (the
backup is still written).

### Global install (user-level defaults)

```bash
./bootstrap.sh --global
```

This installs the baseline into `~/.claude/` so it applies to every project you open with
Claude Code that doesn't define its own `.claude/`. It will NOT copy `CLAUDE.md`, `.mcp.json`,
`.env.example`, or `.gitignore` (those are per-project by design).

### Dry run

```bash
./bootstrap.sh --local /path/to/project --dry-run
```

Prints every action without touching disk.

### Self-test (`--verify`)

Exercises every hook with synthetic events and asserts expected behaviour.
Run this after install (or in CI) to confirm the baseline is actually wired up:

```bash
./bootstrap.sh --verify
```

Outputs a pass/fail line per check:

- Required deps present (`bash`, `jq`, `perl`, `curl`) + optional (`sqlite3`, `gitleaks`)
- Every hook file exists, is executable, and passes `bash -n`
- `settings.json` / `.mcp.json` parse as valid JSON
- `secret-scan.sh` blocks an AWS token and allows benign content
- `block-destructive.sh` blocks `rm -rf /`, allows `ls -la`, and `CLAUDE_BREAKGLASS` bypass works with an audit entry
- `prompt-injection-scan.sh` warns on a canonical injection phrase and stays silent on benign content
- `audit-log.sh` writes a record and the redactor actually redacts

Exits 0 if all checks pass, 1 if any fail.

---

## Break-glass override

When a legitimately-needed command gets caught by `block-destructive.sh`,
instead of disabling the hook, set:

```bash
CLAUDE_BREAKGLASS="INC-4321: rotating old host, approved by $USER"
```

That single session will allow the normally-blocked command, but every
bypass is written to `.claude/audit/breakglass.log` with the reason, the
matching pattern, the exact command, and the user — so it's impossible
to use silently. `audit-log.sh` also tags every record in the session
with `breakglass_reason`, making forensic queries trivial:

```bash
sqlite3 .claude/audit/tool-calls.db \
  "SELECT ts, cwd, input_preview FROM tool_calls
    WHERE breakglass_reason != '' ORDER BY ts DESC;"
```

---

## Prompt-injection detection

`hooks/prompt-injection-scan.sh` runs on every `Read`, `WebFetch`, and
`WebSearch` and flags content that looks like it's trying to hijack the
agent — canonical "ignore previous instructions" phrasing, chat-markup
smuggling (`<|system|>`), tool-call shape smuggling (`<tool_use>`), and
Unicode tag-block invisible-text injection (U+E0000..U+E007F).

Modes:
- `CLAUDE_PROMPT_INJECTION=warn` (default) — warns on stderr, lets the read proceed
- `CLAUDE_PROMPT_INJECTION=block` — exits 2 and refuses the read
- `CLAUDE_PROMPT_INJECTION=off`   — disables the check

`warn` is the default because blocking reads on every README with the word
"instructions" is too disruptive; the warning surfaces through Claude's
context so the model knows to treat the content as untrusted.

---

## After install

1. `cp .env.example .env` and fill in real values (or better: source from your secrets manager).
2. Confirm prerequisites are installed — see **Prerequisites** above for your OS.
3. (Optional) Export `SLACK_WEBHOOK_URL` to enable the Notification hook.
4. (Optional) Configure the audit sink — see **Audit trail** below.
5. Open the project in Claude Code and run `/security-review` on your next diff.

---

## Audit trail

`hooks/audit-log.sh` runs on every `PostToolUse` event. It is:

- **Local-first** — records are written to disk before any remote POST, so a
  flaky SIEM or offline dev can't lose the trail.
- **Pluggable** — pick your sinks with env vars (no code edits needed).
- **Redacted** — high-confidence secret shapes (AWS / GitHub / Slack / OpenAI /
  private keys) and JSON credential keys (`password`, `api_key`, `token`, …)
  are stripped before anything is persisted or forwarded.

### Local sinks

| `CLAUDE_AUDIT_SINK` | Behaviour                                                           |
|---------------------|---------------------------------------------------------------------|
| `auto` (default)    | SQLite if `sqlite3` is on PATH, else JSONL                          |
| `sqlite`            | `.claude/audit/tool-calls.db` (indexed on ts, tool, session_id)     |
| `jsonl`             | `.claude/audit/tool-calls.jsonl` (one JSON record per line)         |
| `both`              | Write to both (useful during migration)                             |
| `none`              | Skip local sink — only makes sense with a remote sink configured    |

Query examples (SQLite):

```bash
# All blocked tool calls today
sqlite3 .claude/audit/tool-calls.db \
  "SELECT ts, tool, input_preview FROM tool_calls
    WHERE blocked != '' AND ts > date('now');"

# Top tools by call count for the current session
sqlite3 .claude/audit/tool-calls.db \
  "SELECT tool, count(*) FROM tool_calls GROUP BY tool ORDER BY 2 DESC;"
```

### Remote sinks (optional, fire-and-forget)

| Env var                   | Target                                                 |
|---------------------------|--------------------------------------------------------|
| `CLAUDE_AUDIT_SUMO_URL`   | Sumo Logic HTTP Source collector URL                   |
| `CLAUDE_AUDIT_HTTP_URL`   | Generic HTTPS endpoint (Splunk HEC, Datadog, ELK, …)   |
| `CLAUDE_AUDIT_HTTP_AUTH`  | `Authorization` header value for the generic HTTPS URL |

Both remote sinks can run in parallel. Each POST is detached via `disown` with
a 5s timeout, so slow endpoints never stall the agent.

### Customising retention / rotation

The hook doesn't rotate for you — pick one:

- **SQLite**: `DELETE FROM tool_calls WHERE ts < datetime('now', '-30 days'); VACUUM;` in a cron job.
- **JSONL**: drop `logrotate.d/claude-audit` with a `daily rotate 14 compress` policy.
- **Remote-only** (`CLAUDE_AUDIT_SINK=none`): retention is your SIEM's problem, not yours.

---

## Customising

- **Tighten the `allow` list** in `.claude/settings.json` — by default it allows `Read`,
  `Write(src/**)`, and a handful of safe `git`/`npm` subcommands. If your project doesn't
  use npm, remove those entries. If your source lives outside `src/`, update the glob.
- **Add project-specific deny rules** — e.g. `Write(infra/**)`, `Bash(terraform apply:*)`.
- **Extend the hooks** — `secret-scan.sh` falls back to a regex set if `gitleaks` isn't
  installed; replace with your team's detector of choice.
- **Add skills / commands / agents** — drop a new `.md` file into the relevant subdir.

---

## Verifying the install worked

```bash
# Inside the target project
ls -la .claude/hooks/       # hook scripts should be -rwxr-xr-x
claude --version            # the CLI picks up settings.json automatically
echo "test" > /tmp/fakesecret && claude -p "write 'AKIAIOSFODNN7EXAMPLE' to ./test.txt"
# → the PreToolUse secret-scan hook should BLOCK the write
```

---

## Troubleshooting

If something in the baseline isn't behaving, `./bootstrap.sh --verify` is the
fastest diagnostic — it exercises every hook and prints a pass/fail line per
check. The common failure modes below map to specific PASS/FAIL lines.

### `gitleaks: not found` or secret-scan hook times out

`hooks/secret-scan.sh` prefers `gitleaks` and falls back to a built-in regex
set when it's absent. If installation instructions for your OS above didn't
take, confirm `command -v gitleaks` prints a path. On Linux the apt package
often lags the latest release — use the binary install block under
**Prerequisites → Linux**.

If `gitleaks` is installed but the hook appears to hang, it's almost always
scanning a huge file (e.g. a committed `node_modules/` tarball). Add the
offending path to `.gitleaks.toml`'s `allowlist.paths`.

### `audit-log.sh` never writes to `.claude/audit/tool-calls.db`

The hook chooses SQLite only if `sqlite3` is on `PATH`; otherwise it silently
falls back to JSONL. Check `.claude/audit/tool-calls.jsonl` — if records are
there but not the DB, install sqlite3 and re-run (`brew install sqlite`,
`apt-get install sqlite3`, etc.). The hook is designed to never break the
session on a sink failure, so errors are swallowed by default; to debug, run
the hook by hand with a synthetic event:

```bash
printf '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"hello"}}' \
  | .claude/hooks/audit-log.sh
```

### `prompt-injection-scan.sh` fires on your own docs

The scanner is deliberately tuned for recall, so benign documents containing
phrases like "ignore the previous section" can trip the warn. Options:

- Keep the default (`CLAUDE_PROMPT_INJECTION=warn`) and let Claude see the
  warning — warns are informational, not blocking.
- Add a project-specific allowlist by editing the
  `PROMPT_INJECTION_PATTERNS` array in `.claude/hooks/lib/patterns.sh`.
- Set `CLAUDE_PROMPT_INJECTION=off` for a single session if you're reading
  many adversarial-example fixtures and the noise is overwhelming.

### `settings.json` merge produced a file I don't like

Every merge writes a timestamped backup at `settings.json.bak.<YYYYMMDDhhmmss>`
before rewriting. Restore with `mv settings.json.bak.<ts> settings.json`. If
you want to bypass the merge entirely on the next install, pass
`./bootstrap.sh --no-merge` (this also implies `--force`).

### Hook script has `Permission denied` / isn't executable

The installer runs `chmod +x` on everything in `.claude/hooks/*.sh`, but a
copy from Windows to WSL can drop the executable bit. Re-run
`chmod +x .claude/hooks/*.sh` or use `./bootstrap.sh --force`.

### Windows: hooks don't run at all

Claude Code detects WSL for `.sh` hooks, but only when invoked from inside a
WSL shell or from a Windows-native session where `wsl.exe` is on PATH. If
you're running Claude Code in PowerShell without WSL, install Git Bash (see
**Prerequisites → Windows Option B**) and launch Claude from that shell.

---

## Credits & licence

- **Original concept & content**: [Okan Yildiz](https://www.linkedin.com/in/yildizokan),
  Cyber Security Engineer. Please follow him for daily AI security & DevSecOps insights.
- **This repo**: MIT (see `LICENSE`).
- **Claude Code**: https://docs.claude.com/claude-code

If you find this useful, drop a line to Okan — this baseline exists because he shared his.
