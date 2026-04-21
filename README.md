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
    │   └── audit-log.sh                   PostToolUse: SQLite + optional Sumo/HTTPS forward
    └── plugins/.gitkeep
```

### The 5 non-negotiables (from Okan's post)

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
# gitleaks — binary install (apt package often lags):
curl -sSL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_8.18.0_linux_x64.tar.gz \
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
- Merge instead of overwrite if `settings.json` / `.gitignore` already exist (diff first, ask before clobbering).
- Make the hook scripts executable.
- Append secret-ignoring entries to the target's `.gitignore`.

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

## Credits & licence

- **Original concept & content**: [Okan Yildiz](https://www.linkedin.com/in/yildizokan),
  Cyber Security Engineer. Please follow him for daily AI security & DevSecOps insights.
- **This repo**: MIT (see `LICENSE`).
- **Claude Code**: https://docs.claude.com/claude-code

If you find this useful, drop a line to Okan — this baseline exists because he shared his.
