---
name: security-audit
description: Use when the user asks for a security audit, vulnerability assessment, or wants to harden a component. Performs a deeper-than-review pass — threat surface, input validation, auth, crypto, dependencies, logging — and produces a prioritised remediation list.
---

# Security audit

A security audit is deeper than a code review. It reasons about the component as a whole, not just the diff.

## Phase 1 — Map the surface

- What does this component do, and for whom?
- Where does untrusted input enter? (HTTP params, webhooks, message queues, file uploads, LLM outputs)
- Where does trusted output leave? (DB writes, outbound HTTP, logs, emails)
- What secrets / privileged capabilities does it hold?

## Phase 2 — Walk the OWASP Top 10 (and more)

1. **Broken access control** — are authorisation checks present on every privileged path? IDOR?
2. **Cryptographic failures** — algorithms, key management, TLS config, password hashing (bcrypt/argon2/scrypt only).
3. **Injection** — SQL, command, LDAP, XSS, template injection, prompt injection.
4. **Insecure design** — missing rate limits, missing MFA on sensitive ops, default-allow patterns.
5. **Security misconfiguration** — verbose errors in prod, default creds, permissive CORS.
6. **Vulnerable components** — `npm audit` / `pip-audit` / `cargo audit` / SCA tool output.
7. **Authentication failures** — credential stuffing exposure, session fixation, weak password policy.
8. **Software / data integrity** — unsigned deserialisation, CI pipeline drift, unsigned artefacts.
9. **Logging & monitoring** — are security-relevant events logged? PII in logs? Log injection?
10. **SSRF** — outbound calls with user-controlled URL/host.

Plus the AI-era additions:
- **Prompt injection** — untrusted text reaching an LLM that has tools.
- **Insecure output handling** — LLM output passed to `eval`, shell, or rendered as HTML.
- **Model supply chain** — unpinned model names, unsigned weights, mutable prompt-template URLs.

## Phase 3 — Report

Produce a prioritised list. For each item:

```
[SEVERITY] <title>
Location: path/to/file.ts:42 (or "architectural, repo-wide")
Risk: <attacker capability if exploited>
Evidence: <code excerpt or reasoning>
Recommendation: <concrete fix>
Effort: S / M / L
```

Severity scale: Critical (fix now) / High (fix this sprint) / Medium (backlog) / Low / Info.

Close with a **one-paragraph executive summary** that a non-engineer can act on.
