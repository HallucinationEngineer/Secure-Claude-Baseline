# Project conventions

This file is loaded into every Claude Code session for this project. Keep it short, factual, and opinionated.

## Security posture

This project follows the **Secure Claude Baseline**. In practice that means:

1. **`.env` is never committed.** Secrets live in a secrets manager in prod and in `.env` (gitignored) locally. `.env.example` documents the keys.
2. **Filesystem MCP is scoped to the project root.** No access above.
3. **Every `Write`/`Edit` runs through `gitleaks`** via the PreToolUse hook at `.claude/hooks/secret-scan.sh`.
4. **Postgres MCP uses a read-only DB user.** Migrations happen through normal CI, not through the agent.
5. **Every tool call is logged** to `.claude/audit/tool-calls.jsonl` for post-hoc review.

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
