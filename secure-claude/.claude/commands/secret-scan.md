---
description: Scan the repo (or a given path) for committed secrets using gitleaks
argument-hint: "[optional path, defaults to repo root]"
allowed-tools: Bash(gitleaks:*), Bash(git log:*), Read
---

# /secret-scan

Scan for secrets in: **${ARGUMENTS:-the entire repository}**

## Steps

1. Verify `gitleaks` is installed: !`command -v gitleaks || echo "gitleaks not installed — see https://github.com/gitleaks/gitleaks"`
2. Run detection against the working tree and history:
   - Working tree: !`gitleaks detect --source "${ARGUMENTS:-.}" --no-banner --redact --verbose || true`
   - Full git history: !`gitleaks detect --source . --log-opts="--all" --no-banner --redact --verbose || true`
3. For each finding, report:
   - File + line (or commit SHA for historical finds)
   - Rule that matched (e.g. `aws-access-token`, `generic-api-key`)
   - Recommended remediation:
     - Rotate the credential **immediately** at the provider
     - Remove from working tree and add to `.gitignore`
     - For historical leaks, rewrite history with `git filter-repo` and force-push (coordinate with the team)

## Notes

- `--redact` ensures actual secret values are never printed back into the conversation or logs.
- If gitleaks isn't available, fall back to `trufflehog` or the grep-based heuristics in `.claude/hooks/secret-scan.sh`.
- Treat any finding as PRE-INCIDENT and follow the team's secret-rotation runbook.
