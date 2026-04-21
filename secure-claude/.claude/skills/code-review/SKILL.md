---
name: code-review
description: Use when the user asks for a code review, PR review, or second opinion on a diff. Applies a senior-engineer lens — correctness, readability, test coverage, and security smells — and returns findings with file:line citations.
---

# Code review

Review the pending diff (or the files the user points to) and report findings grouped by severity.

## What to look for

1. **Correctness** — off-by-one, null/undefined paths, race conditions, incorrect error handling.
2. **Readability** — unclear names, dead code, over-abstraction, inconsistent style with the surrounding file.
3. **Test coverage** — new behaviour without tests, happy-path-only tests, tests that don't assert the thing the PR changes.
4. **Security smells** — see the `security-audit` skill for the full list; flag the obvious ones inline.
5. **Performance** — N+1 queries, allocations in hot paths, unnecessary re-renders.
6. **API design** — breaking changes, leaked internals, inconsistent naming with neighbours.

## Output

```
## Review

**Summary**: <one paragraph — what the PR does, verdict>

### Must fix
- [ ] `path:line` — <issue> — <fix>

### Should fix
- [ ] `path:line` — ...

### Nits
- [ ] `path:line` — ...

### Questions
- `path:line` — <clarifying question>
```

Skip categories with no findings. Don't invent problems — silence is a valid verdict.
