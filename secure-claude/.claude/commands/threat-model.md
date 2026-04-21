---
description: Produce or update a STRIDE threat model for a feature or component
argument-hint: "<component or feature name>"
allowed-tools: Read, Grep, Glob
---

# /threat-model

Produce a STRIDE threat model for: **$ARGUMENTS**

## Process

1. **Identify the asset** — what are we protecting (data, capability, availability)?
2. **Map trust boundaries** — where does untrusted input cross into trusted code?
3. **Enumerate data flows** — producers, consumers, storage, transport.
4. **Apply STRIDE** per data flow / component:
   - **S**poofing — can an attacker impersonate a legitimate principal?
   - **T**ampering — can data in transit or at rest be modified?
   - **R**epudiation — can an actor deny having performed an action?
   - **I**nformation disclosure — can confidential data leak?
   - **D**enial of service — can the component be made unavailable?
   - **E**levation of privilege — can a low-priv actor gain higher privilege?
5. **Rate** likelihood × impact per threat (Low / Medium / High).
6. **Mitigation** — existing controls + proposed additions.

## Output format

```markdown
# Threat model: <component>

## Assets
- ...

## Trust boundaries
- ...

## Data flows
| # | Source | Sink | Data | Crosses boundary? |

## STRIDE table
| ID | Category | Threat | Likelihood | Impact | Mitigation | Status |

## Open risks / accepted risks
- ...
```

Save the result to `docs/threat-models/<slug>.md` if the user confirms.
