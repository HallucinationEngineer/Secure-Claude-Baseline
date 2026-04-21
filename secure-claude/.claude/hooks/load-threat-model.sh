#!/usr/bin/env bash
# SessionStart hook — emits the project threat model into Claude's context so
# every session begins grounded in the team's security assumptions.
set -euo pipefail

THREAT_MODEL_PATHS=(
  "docs/threat-model.md"
  "docs/security/threat-model.md"
  "SECURITY.md"
  ".claude/THREAT_MODEL.md"
)

for path in "${THREAT_MODEL_PATHS[@]}"; do
  if [ -f "$path" ]; then
    echo "# Threat model loaded from ${path}"
    echo
    cat "$path"
    exit 0
  fi
done

# No threat model — prompt the team to create one.
cat <<'EOF'
# No threat model found

This project has no threat-model document. Consider running:

    /threat-model <component>

and saving the output to docs/threat-model.md so it loads automatically at session start.
EOF
exit 0
