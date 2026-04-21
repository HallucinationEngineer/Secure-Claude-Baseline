#!/usr/bin/env bash
# PreToolUse hook — blocks Write/Edit/MultiEdit if the new content contains secret-looking patterns.
#
# Reads a JSON event on stdin per Claude Code hook protocol:
#   { "tool_name": "...", "tool_input": { "file_path": "...", "content": "...", "new_string": "..." } }
#
# Exit codes:
#   0 = allow the tool call
#   2 = block the tool call (stderr is surfaced to Claude)
#   other non-zero = non-blocking error (logged)
set -euo pipefail

# Read the event payload
EVENT_JSON="$(cat)"

# Extract fields we care about (jq is preferred; fall back to grep if jq is missing)
if command -v jq >/dev/null 2>&1; then
  FILE_PATH="$(printf '%s' "$EVENT_JSON" | jq -r '.tool_input.file_path // empty')"
  CONTENT="$(printf '%s' "$EVENT_JSON" | jq -r '.tool_input.content // .tool_input.new_string // empty')"
else
  FILE_PATH="$(printf '%s' "$EVENT_JSON" | grep -oE '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  CONTENT="$EVENT_JSON"
fi

# If gitleaks is available, prefer it. Otherwise use a portable regex fallback.
if command -v gitleaks >/dev/null 2>&1; then
  TMPFILE="$(mktemp)"
  trap 'rm -f "$TMPFILE"' EXIT
  printf '%s' "$CONTENT" > "$TMPFILE"
  if ! gitleaks detect --no-banner --redact --source "$TMPFILE" --no-git 2>/dev/null; then
    echo "BLOCKED: gitleaks detected a secret in the proposed write to '${FILE_PATH:-<unknown>}'." >&2
    echo "Hint: use an environment variable or the secrets manager instead." >&2
    exit 2
  fi
else
  # Minimal, portable fallback (not a substitute for gitleaks)
  PATTERNS=(
    'AKIA[0-9A-Z]{16}'                       # AWS access key id
    'ASIA[0-9A-Z]{16}'                       # AWS STS key id
    'AIza[0-9A-Za-z_-]{35}'                  # Google API key
    'ghp_[0-9A-Za-z]{36,}'                   # GitHub PAT
    'github_pat_[0-9A-Za-z_]{80,}'           # GitHub fine-grained PAT
    'xox[baprs]-[0-9A-Za-z-]{10,}'           # Slack
    'sk-[0-9A-Za-z]{32,}'                    # OpenAI / Anthropic-style
    '-----BEGIN (RSA |OPENSSH |EC |PGP )?PRIVATE KEY-----'
  )
  for p in "${PATTERNS[@]}"; do
    if printf '%s' "$CONTENT" | grep -Eq "$p"; then
      echo "BLOCKED: secret-like pattern matched (/${p}/) in proposed write to '${FILE_PATH:-<unknown>}'." >&2
      echo "Hint: use an environment variable or the secrets manager instead." >&2
      exit 2
    fi
  done
fi

exit 0
