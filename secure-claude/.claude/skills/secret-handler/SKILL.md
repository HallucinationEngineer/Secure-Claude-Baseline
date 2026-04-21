---
name: secret-handler
description: Use whenever secrets, credentials, API keys, tokens, or connection strings come up — storing, rotating, loading, or responding to a leak. Enforces the team's secret-handling policy and routes work through the right tools (vault, KMS, gitleaks).
---

# Secret handler

## Golden rules

1. **Never print a secret value.** Not in logs, not in error messages, not in the assistant's response, not in commit messages.
2. **Never commit a secret.** `.env` is always gitignored. `.env.example` is committed with placeholder values only.
3. **Never fetch a secret to inspect it.** Work with the *reference* (vault path, env var name) whenever possible.
4. **Rotate on suspicion.** If a secret touched an untrusted surface (clipboard, chat log, screenshot, public CI log), treat it as compromised.

## Where secrets live

| Type                     | Storage                         | Access pattern                 |
|--------------------------|---------------------------------|--------------------------------|
| Production runtime       | Secrets manager (AWS SM, Vault) | Injected as env at boot        |
| CI/CD                    | GitHub Actions / GitLab CI vars | Referenced by name in workflow |
| Local dev                | `.env` (gitignored)             | Loaded via `dotenv`            |
| Example / docs           | `.env.example`                  | Placeholder values only        |

## Adding a new secret — checklist

- [ ] Added as a key in `.env.example` with a placeholder (e.g. `STRIPE_API_KEY=sk_test_xxx`)
- [ ] Added to the secrets manager for each environment (dev, staging, prod)
- [ ] Wired into the runtime via env var, not hardcoded
- [ ] Consumer code reads via `process.env.X` / `os.environ["X"]` / equivalent
- [ ] `.gitignore` confirms `.env` is excluded
- [ ] Pre-commit hook (gitleaks) run locally

## Responding to a leaked secret

1. **Rotate immediately** at the provider — don't wait to clean history.
2. **Invalidate** any session/token issued with the compromised credential.
3. **Audit** provider logs for unauthorized use from the window of exposure.
4. **Remove from working tree**, add to `.gitignore`.
5. **Rewrite history** if the secret is still in git objects: `git filter-repo --replace-text secrets.txt` + coordinated force-push.
6. **File an incident ticket** — even if the blast radius was small.
7. **Post-mortem**: why did gitleaks miss it? Add a rule.

## Never do

- `console.log(process.env.SECRET)` even "just for debugging"
- Paste a secret into a chat, issue, PR comment, or screenshot
- Store secrets in frontend bundles, mobile apps, or any client-side code
- Use the same credential across environments
