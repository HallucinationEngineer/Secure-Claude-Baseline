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
    │   └── audit-log.sh                   PostToolUse: append JSON-line audit record
    └── plugins/.gitkeep
```

### The 5 non-negotiables (from Okan's post)

1. **Never commit `.env` or `settings.local.json`** — both are in `.gitignore`.
2. **Scope the filesystem MCP to the project root** — `.mcp.json` uses `${PROJECT_ROOT}`.
3. **PreToolUse hook runs gitleaks on every Write** — see `hooks/secret-scan.sh`.
4. **Read-only credentials for any database MCP** — if you add one, scope it to SELECT-only.
5. **Log every tool call** — `hooks/audit-log.sh` appends to `.claude/audit/tool-calls.jsonl`.

---

## Install

The `bootstrap.sh` installer copies `secure-claude/` into either a project or your user home.

### Local install (into an existing project)

```bash
# From this repo's root:
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
2. Install [`gitleaks`](https://github.com/gitleaks/gitleaks) so `hooks/secret-scan.sh` has teeth:
   ```bash
   brew install gitleaks   # or: go install github.com/gitleaks/gitleaks/v8@latest
   ```
3. (Optional) Export `SLACK_WEBHOOK_URL` to enable the Notification hook.
4. Open the project in Claude Code and run `/security-review` on your next diff.

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
