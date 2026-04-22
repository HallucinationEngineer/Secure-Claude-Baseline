# Project conventions

This file is loaded into every Claude Code session for this project. Keep it short, factual, and opinionated.

## Security posture

This project follows the **Secure Claude Baseline**. The five non-negotiables
below are the in-session rules for Claude; the same list is summarised for
human readers in `README.md § The 5 non-negotiables` — keep both copies in
sync if you edit either.

1. **`.env` is never committed.** Secrets live in a secrets manager in prod and in `.env` (gitignored) locally. `.env.example` documents the keys.
2. **Filesystem MCP is scoped to the project root.** No access above.
3. **Every `Write`/`Edit` runs through `gitleaks`** via the PreToolUse hook at `.claude/hooks/secret-scan.sh`.
4. **Any database MCP must use a read-only role.** Writes go through normal CI, not through the agent.
5. **Every tool call is logged.** Local-first (SQLite `.claude/audit/tool-calls.db`, JSONL fallback) with optional remote forwarding to Sumo or any HTTPS endpoint (Splunk HEC, Datadog, ELK). High-confidence secret shapes are redacted before anything leaves the box.

If you need to relax a guardrail for a one-off task, document it in the PR description and revert before merging.

## Where things live

- `src/` — application code. The only path the agent can `Write` to without explicit approval.
- `docs/threat-model.md` — loaded at session start; keep it current.
- `.claude/commands/` — slash commands (`/security-review`, `/threat-model`, `/secret-scan`).
- `.claude/skills/` — skill-packs auto-loaded by task description.
- `.claude/agents/` — subagents (`security-auditor`, `red-team`).
- `.claude/hooks/` — security tripwires. **Don't disable these without a review.**

## Style

- Small diffs. Reviewable in one sitting.
- Tests alongside the change. "Will add tests later" means "never".
- No TODO comments without a linked ticket.
- No commented-out code. Delete it; git remembers.

## Commit / PR etiquette

- Conventional commits (`feat:`, `fix:`, `chore:`, `sec:`).
- `sec:` commits require a linked threat-model entry or security-review note.
- Force-push to `main`/`master` is denied at the tool level. If you need to rewrite shared history, coordinate in #eng-platform first.
