# Security Policy

## Reporting a vulnerability

If you believe you've found a security issue in this repo — whether a bug in
the hooks, an install script footgun, a secret pattern that's slipping
through, or a supply-chain concern — please **do not** open a public issue.

Instead:

1. Use GitHub's private **Security → Report a vulnerability** form on this
   repo, or
2. Email the maintainer listed in `CODEOWNERS`.

We aim to triage within 5 business days.

---

## Supply-chain & CI (Pwn-Request threat model)

A "Pwn Request" is a GitHub Actions attack where a pull request causes
attacker-controlled code to run with repo privileges — either by exploiting
`pull_request_target`, by poisoning a tag on a third-party action, or by
modifying the workflow file itself and having a maintainer merge without
reading the diff. This repo defends against each vector explicitly:

### 1. We never use `pull_request_target`

Our workflow (`.github/workflows/ci.yml`) triggers on `pull_request` only.
That means:

- PR code runs in an **ephemeral**, sandboxed check-out of the PR commit.
- The runner has **no access to repository secrets**.
- `GITHUB_TOKEN` is restricted (see point 3).
- A malicious PR cannot push to the repo, publish a release, or touch any
  other GitHub resource.

`pull_request_target` is deliberately absent and must never be added without
a documented threat-model entry explaining why.

### 2. Every third-party action is pinned by full-length SHA

Tags like `@v4` are mutable — the action maintainer (or an attacker who
compromises them) can repoint the tag to a new commit. SHAs are immutable.
Every `uses:` line in the workflow references a 40-character commit SHA
with an inline comment showing the version it corresponds to:

```yaml
uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8   # v5.0.0
```

Dependabot (`.github/dependabot.yml`) opens a PR weekly proposing the new
SHA for each action; the PR shows the diff, and a maintainer review per
`CODEOWNERS` is required before merge.

### 3. Least-privilege `GITHUB_TOKEN`

The workflow-level `permissions:` block defaults to `{}` (no permissions).
Each job individually opts in to exactly what it needs — typically only
`contents: read`. No job has `write`, `id-token: write`, `packages: write`,
or any other scope that could be abused to push code, publish artefacts, or
impersonate the repo.

### 4. Runner egress is monitored

Every job starts with `step-security/harden-runner` (SHA-pinned) to audit
outbound network traffic from the runner. If a compromised dependency or a
malicious PR step tries to exfiltrate data or phone home, the call shows up
in the job summary. The policy is currently `audit`; once we have a stable
allowlist, we'll flip it to `block`.

### 5. `persist-credentials: false` on every checkout

We explicitly disable `actions/checkout`'s default behaviour of leaving the
`GITHUB_TOKEN` in `.git/config`. Even with the token already scoped to
`contents: read`, keeping it off the runner filesystem means a later step
that executes PR-controlled code (like our self-test, which runs the hook
scripts) cannot reach it.

### 6. CODEOWNERS + branch protection on high-trust paths

`.github/CODEOWNERS` requires maintainer review for any change to:

- `/.github/**` (workflows, Dependabot config, CODEOWNERS itself)
- `/secure-claude/.claude/hooks/**` (anything that runs on every tool call)
- `/secure-claude/.claude/settings.json` (the permission model)
- `/bootstrap.sh` (runs in the user's shell on install)
- `/SECURITY.md` (this document)

Combined with branch protection's **Require review from Code Owners** +
**Do not allow bypassing the above settings**, this prevents a merge that
bypasses review even by an admin.

### 7. No `secrets.*` in PR-triggered steps

No `run:` block references `secrets.*` in any PR-triggered job. If we ever
need to, we'll split the workflow so the secret-consuming step runs on
`workflow_run` after CI passes, reading the artefact from the sandboxed job
— never the raw PR code.

### 8. Self-scanning

The `gitleaks` job scans the whole repo (including history) on every PR
and push. Example tokens used in the hook test fixtures (`AKIAIOSFODNN7EXAMPLE`
from AWS docs, etc.) are explicitly allow-listed by path; anything new is
caught.

---

## Runtime hardening (what the baseline ships for users)

The threats above are CI-side. For the runtime protections the baseline
provides to users who install it — `PreToolUse` secret scanning,
destructive-command blocking, prompt-injection warnings, audit logging,
break-glass override — see `README.md`.

---

## Version

Last reviewed: 2026-04-21.
Revisit: on any CI workflow change, or quarterly, whichever comes first.
