---
description: Complete a security review of the pending changes on the current branch
argument-hint: "[optional scope, e.g. 'auth module' or 'PR #123']"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*)
---

# /security-review

Perform a focused security review of pending changes against the project's threat model.

## Context

- Current branch diff: !`git diff origin/main...HEAD --stat`
- Changed files: !`git diff origin/main...HEAD --name-only`
- Scope: $ARGUMENTS

## Review checklist

Walk the diff and flag any of the following. For each finding, cite `file:line` and classify severity (Critical / High / Medium / Low / Info).

### Injection & untrusted input
- SQL injection (string concatenation into queries, unparameterised ORMs)
- Command injection (shell execution of user input, `exec`, `eval`, backticks)
- Path traversal (unsanitised paths passed to file I/O)
- XSS (unescaped output, `dangerouslySetInnerHTML`, `v-html`)
- SSRF (outbound requests to user-controlled URLs)
- Prompt injection (untrusted input concatenated into LLM prompts)

### Secrets & credentials
- Hardcoded API keys, tokens, passwords, private keys
- Secrets logged or echoed to stdout/stderr
- `.env` values committed or referenced in code

### AuthN / AuthZ
- Missing authentication on new endpoints
- Missing authorisation / IDOR (object references not scoped to the caller)
- Broken session handling, predictable tokens, missing CSRF

### Crypto
- Weak algorithms (MD5, SHA1 for signing, DES, RC4)
- Hardcoded IVs, reused nonces, insecure RNG (`Math.random` for crypto)

### Dependencies & supply chain
- New deps pinned? Any with known CVEs?
- Lockfile updated and committed?

### Output hygiene
- Sensitive data in error messages, stack traces, or logs
- PII leaving its intended boundary

## Report format

```
## Security review — <scope>

**Verdict**: PASS / PASS-WITH-FIXES / BLOCK

### Findings
1. **[SEVERITY]** <one-line title> — `path/to/file.ts:42`
   - Risk: <what an attacker can do>
   - Fix: <concrete remediation>

### Out of scope / not reviewed
- <anything the diff touches that you deliberately skipped>
```

Be concise. If there are no findings, say so plainly.
